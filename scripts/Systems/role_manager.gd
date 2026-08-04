class_name RoleManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

static func get_available_transitions(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []

	if character.role == CharacterData.Role.YOUNG_DISCIPLE:
		if _can_become_manager(character, sect, relationships):
			options.append(_transition_option(
				CharacterData.Role.MANAGER,
				"중간관리자 승진",
				"문파 내 신뢰를 얻어 중간관리자가 됩니다."
			))
		if _can_become_spy(character, story_flags):
			options.append(_transition_option(
				CharacterData.Role.SPY,
				"스파이 임무 수락",
				"적 문파에 잠입해 정보를 수집합니다."
			))
		if character.level >= 2:
			options.append(_transition_option(
				CharacterData.Role.WANDERER,
				"문파를 떠나 낭인이 된다",
				"자유로운 강호 행을 시작합니다."
			))

	elif character.role == CharacterData.Role.MANAGER:
		if _can_become_leader(character, sect, relationships):
			options.append(_transition_option(
				CharacterData.Role.LEADER,
				"문주 승계",
				"청운검파의 새 문주가 됩니다."
			))

	elif character.role == CharacterData.Role.SPY:
		if _can_become_assassin(character, story_flags):
			options.append(_transition_option(
				CharacterData.Role.ASSASSIN,
				"암살자로 전향",
				"은밀한 제거 임무를 전담합니다."
			))
		if story_flags.get("spy_mission_complete", false):
			options.append(_transition_option(
				CharacterData.Role.MANAGER,
				"임무 완료 후 복귀",
				"스파이 임무를 마치고 문파로 돌아옵니다."
			))

	return options


static func apply_transition(
	character: CharacterData,
	sect: SectData,
	new_role: CharacterData.Role
) -> Dictionary:
	var old_name: String = character.get_role_name()
	character.role = new_role
	_apply_role_bonuses(character, new_role)

	if new_role == CharacterData.Role.LEADER:
		sect.leader_name = character.display_name

	var new_name: String = character.get_role_name()
	return {
		"success": true,
		"message": "%s에서 %s(으)로 역할이 전환되었습니다." % [old_name, new_name],
		"new_role": new_role,
	}


static func get_role_combat_bonus(role: CharacterData.Role) -> float:
	match role:
		CharacterData.Role.LEADER:
			return 1.15
		CharacterData.Role.SPY, CharacterData.Role.ASSASSIN:
			return 1.1
		CharacterData.Role.MANAGER:
			return 1.05
		CharacterData.Role.WANDERER:
			return 1.08
		_:
			return 1.0


static func get_role_management_bonus(role: CharacterData.Role) -> float:
	match role:
		CharacterData.Role.LEADER:
			return 1.2
		CharacterData.Role.MANAGER:
			return 1.15
		_:
			return 1.0


static func _transition_option(
	role: CharacterData.Role,
	title: String,
	description: String
) -> Dictionary:
	return {"role": role, "title": title, "description": description}


static func _can_become_manager(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData]
) -> bool:
	var master: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_master")
	var master_bond: int = master.bond_strength if master else 0
	return (
		character.level >= _Balance.MANAGER_LEVEL_REQ
		and character.wisdom >= _Balance.MANAGER_WISDOM_REQ
		and sect.reputation >= _Balance.MANAGER_REPUTATION_REQ
		and master_bond >= 25
	)


static func _can_become_spy(
	character: CharacterData,
	story_flags: Dictionary
) -> bool:
	return (
		character.agility >= 15
		and character.charisma >= 13
	) or story_flags.get("spy_recruitment", false)


static func _can_become_leader(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData]
) -> bool:
	var master: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_master")
	var master_bond: int = master.bond_strength if master else 0
	return (
		character.level >= _Balance.LEADER_LEVEL_REQ
		and sect.reputation >= _Balance.LEADER_REPUTATION_REQ
		and sect.disciple_count >= _Balance.LEADER_DISCIPLE_REQ
		and master_bond >= 50
	)


static func _can_become_assassin(
	character: CharacterData,
	story_flags: Dictionary
) -> bool:
	return character.morality <= 45 and character.strength >= 13 and story_flags.get("assassin_path", false)


static func _apply_role_bonuses(character: CharacterData, role: CharacterData.Role) -> void:
	match role:
		CharacterData.Role.LEADER:
			character.charisma += 2
			character.internal_energy_max += 20
		CharacterData.Role.MANAGER:
			character.wisdom += 2
		CharacterData.Role.SPY:
			character.agility += 2
		CharacterData.Role.ASSASSIN:
			character.strength += 2
			character.morality -= 10
		CharacterData.Role.WANDERER:
			character.agility += 1
			character.charisma += 1
	character.internal_energy_current = mini(
		character.internal_energy_current,
		character.internal_energy_max
	)