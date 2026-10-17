class_name RoleManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

static func get_available_transitions(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary,
	role_state: Dictionary = {},
	world_sects: Array[SectData] = []
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if role_state.is_empty():
		role_state = RoleActions.create_state()

	if character.role == CharacterData.Role.YOUNG_DISCIPLE:
		# 스토리 아크 「승계와 배신」에서 후계자로 지명되면 승진 조건을 따지지 않는다.
		if _can_become_manager(character, sect, relationships) or story_flags.get("arc_succession_heir", false):
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
		var named_heir: bool = story_flags.get("arc_succession_heir", false) and character.level >= _Balance.MANAGER_LEVEL_REQ
		if (
			(_can_become_leader(character, sect, relationships) or named_heir)
			and role_state["trust"] >= _Balance.MANAGER_TRUST_FOR_LEADER
		):
			options.append(_transition_option(
				CharacterData.Role.LEADER,
				"문주 승계",
				"%s의 새 문주가 됩니다." % sect.sect_name
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
		# 배신: 잠입한 세력에 붙는다.
		var infiltrated: SectData = _find_sect(world_sects, str(role_state["spy_target"]))
		if infiltrated and not infiltrated.subjugated:
			options.append(_sect_option(
				infiltrated, "betray",
				"%s(으)로 전향" % infiltrated.sect_name,
				"잠입한 세력에 붙어 옛 문파를 배신합니다. 그곳의 중간관리자가 됩니다."
			))

	elif character.role == CharacterData.Role.WANDERER:
		if character.level >= _Balance.MERCENARY_LEVEL_REQ:
			options.append(_transition_option(
				CharacterData.Role.MERCENARY,
				"의뢰인이 된다",
				"세력들의 임무를 계약으로 맡는 청부업을 시작합니다."
			))

	elif character.role == CharacterData.Role.MERCENARY:
		options.append(_transition_option(
			CharacterData.Role.WANDERER,
			"청부를 접는다",
			"계약에서 손을 떼고 다시 떠돌이 낭인이 됩니다."
		))

	# 이적: 신용을 쌓은 세력에 객경으로 들어간다.
	if character.role in [CharacterData.Role.WANDERER, CharacterData.Role.MERCENARY]:
		for world_sect in world_sects:
			if world_sect.subjugated:
				continue
			if RoleActions.get_credit(role_state, world_sect.id) >= _Balance.DEFECT_CREDIT_REQ:
				options.append(_sect_option(
					world_sect, "defect",
					"%s에 객경으로 들어간다" % world_sect.sect_name,
					"신용을 쌓은 세력에 몸을 의탁합니다. 그곳의 중간관리자가 됩니다."
				))

	# 배신: 도덕이 낮은 제자·관리자는 가장 적대적인 비정파 세력으로 넘어갈 수 있다.
	if character.role in [CharacterData.Role.YOUNG_DISCIPLE, CharacterData.Role.MANAGER]:
		if character.morality <= _Balance.BETRAY_MORALITY_REQ:
			var enemy: SectData = _most_hostile_unorthodox(world_sects)
			if enemy:
				options.append(_sect_option(
					enemy, "betray",
					"%s(으)로 투항" % enemy.sect_name,
					"문파를 배신하고 적에게 넘어갑니다. 그곳의 중간관리자가 됩니다."
				))

	return options


static func _sect_option(sect: SectData, kind: String, title: String, description: String) -> Dictionary:
	var option: Dictionary = _transition_option(CharacterData.Role.MANAGER, title, description)
	option["sect_id"] = sect.id
	option["kind"] = kind
	return option


static func _find_sect(world_sects: Array[SectData], sect_id: String) -> SectData:
	for sect in world_sects:
		if sect.id == sect_id:
			return sect
	return null


static func _most_hostile_unorthodox(world_sects: Array[SectData]) -> SectData:
	var result: SectData = null
	for sect in world_sects:
		if sect.subjugated or sect.alignment == SectData.Alignment.RIGHTEOUS:
			continue
		if result == null or sect.attitude < result.attitude:
			result = sect
	return result


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
		CharacterData.Role.WANDERER, CharacterData.Role.MERCENARY:
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
		CharacterData.Role.MERCENARY:
			character.strength += 1
			character.charisma += 1
	character.internal_energy_current = mini(
		character.internal_energy_current,
		character.internal_energy_max
	)