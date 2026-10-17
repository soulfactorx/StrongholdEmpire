class_name CombatManager
extends RefCounted

## 전투 구성 생성과 전투 결과 반영을 담당한다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

enum Outcome { VICTORY, DEFEAT, RETREAT }

const RIVAL_ID := "npc_rival"


## 경영 화면에서 언제든 할 수 있는 남궁휘와의 비무. 계절당 한 번.
static func create_sparring(player: CharacterData) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "sparring"
	setup.title = "비무 — 남궁휘"
	setup.relationship_target_id = RIVAL_ID
	setup.blocked_tiles = _central_wall()
	setup.add_enemy(_create_rival(player), Vector2i(13, 5))
	setup.rewards = {"experience": _Balance.SPAR_EXP, "bond": 5}
	setup.defeat_penalty = {"injury_ratio": 0.5, "bond": 2}
	return setup


## 기연 「라이벌의 도전」에서 시작되는 진검 승부.
static func create_rival_duel(player: CharacterData) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "rival_duel"
	setup.title = "결투 — 남궁휘의 도전"
	setup.relationship_target_id = RIVAL_ID
	setup.blocked_tiles = _central_wall()
	var rival: CharacterData = _create_rival(player)
	rival.strength += 2
	rival.internal_energy_max += 20
	rival.restore_internal_energy()
	setup.add_enemy(rival, Vector2i(13, 5))
	setup.rewards = {"experience": 40, "reputation": 5, "strength": 1, "bond": 10}
	setup.defeat_penalty = {"reputation": 5, "injury_ratio": 0.3, "bond": -5}
	setup.victory_flag = "won_rival_duel"
	return setup


## 기연 「야습 도적」에서 시작되는 다대일 전투.
static func create_night_bandits(player: CharacterData) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "night_bandits"
	setup.title = "야습 — 도적 무리"
	setup.player_position = Vector2i(3, 5)
	setup.blocked_tiles = [
		Vector2i(6, 2), Vector2i(6, 3), Vector2i(9, 6), Vector2i(9, 7), Vector2i(10, 7),
	]
	var positions: Array[Vector2i] = [Vector2i(12, 3), Vector2i(13, 5), Vector2i(12, 7)]
	for i in positions.size():
		setup.add_enemy(_create_bandit(player, i), positions[i])
	setup.enemy_hp_scale = 0.5
	setup.enemy_damage_scale = 0.6
	setup.rewards = {"experience": 30, "gold": 30, "reputation": 3, "strength": 1}
	setup.defeat_penalty = {"gold": 40, "reputation": 3, "injury_ratio": 0.3}
	return setup


## 전투 결과를 캐릭터·문파·관계에 반영하고 결과 메시지를 돌려준다.
static func apply_outcome(
	setup: CombatSetup,
	outcome: Outcome,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary
) -> Dictionary:
	var parts: PackedStringArray = []
	var bond: RelationshipData = null
	if not setup.relationship_target_id.is_empty():
		bond = RelationshipManager.get_bond_with(relationships, setup.relationship_target_id)

	if outcome == Outcome.VICTORY:
		var r: Dictionary = setup.rewards
		var exp_gain: int = r.get("experience", 0)
		if exp_gain > 0:
			character.gain_experience(exp_gain)
			parts.append("경험치 +%d" % exp_gain)
		if r.get("gold", 0) > 0:
			sect.gold += r["gold"]
			parts.append("금화 +%d" % r["gold"])
		if r.get("reputation", 0) > 0:
			sect.reputation += r["reputation"]
			parts.append("명성 +%d" % r["reputation"])
		if r.get("strength", 0) > 0:
			character.strength += r["strength"]
			parts.append("무력 +%d" % r["strength"])
		_change_bond(bond, r.get("bond", 0), parts)
		if not setup.victory_flag.is_empty():
			story_flags[setup.victory_flag] = true
		return {
			"success": true,
			"outcome": outcome,
			"message": "승리! " + ", ".join(parts) if not parts.is_empty() else "승리!",
		}

	# 후퇴는 패배 손실의 절반만 받는다.
	var scale: float = 0.5 if outcome == Outcome.RETREAT else 1.0
	var p: Dictionary = setup.defeat_penalty
	var gold_loss: int = mini(sect.gold, int(p.get("gold", 0) * scale))
	if gold_loss > 0:
		sect.gold -= gold_loss
		parts.append("금화 -%d" % gold_loss)
	var rep_loss: int = mini(sect.reputation, int(p.get("reputation", 0) * scale))
	if rep_loss > 0:
		sect.reputation -= rep_loss
		parts.append("명성 -%d" % rep_loss)
	var injury_ratio: float = p.get("injury_ratio", 1.0)
	if outcome == Outcome.RETREAT:
		injury_ratio = (1.0 + injury_ratio) / 2.0
	var max_left: int = int(character.internal_energy_max * injury_ratio)
	if character.internal_energy_current > max_left:
		character.internal_energy_current = max_left
		parts.append("부상으로 내공 %d까지 감소" % max_left)
	if outcome == Outcome.DEFEAT:
		_change_bond(bond, p.get("bond", 0), parts)

	var head: String = "후퇴했습니다." if outcome == Outcome.RETREAT else "패배했습니다."
	return {
		"success": false,
		"outcome": outcome,
		"message": head + (" " + ", ".join(parts) if not parts.is_empty() else ""),
	}


static func _change_bond(bond: RelationshipData, amount: int, parts: PackedStringArray) -> void:
	if bond == null or amount == 0:
		return
	if amount > 0:
		bond.increase_bond(amount)
	else:
		bond.decrease_bond(-amount)
	parts.append("%s 유대 %+d" % [bond.target_name, amount])


static func _central_wall() -> Array[Vector2i]:
	return [
		Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6),
		Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7),
	]


## 남궁휘는 플레이어 레벨에 맞춰 함께 성장하는 라이벌이다.
static func _create_rival(player: CharacterData) -> CharacterData:
	var rival := CharacterData.new()
	rival.id = RIVAL_ID
	rival.display_name = "남궁휘"
	rival.role = CharacterData.Role.YOUNG_DISCIPLE
	rival.level = maxi(2, player.level)
	var growth: int = rival.level - 2
	rival.strength = 14 + growth
	rival.agility = 13 + growth
	rival.wisdom = 10 + growth
	rival.charisma = 9
	rival.internal_energy_max = 100 + growth * 10
	rival.restore_internal_energy()
	return rival


static func _create_bandit(player: CharacterData, index: int) -> CharacterData:
	var bandit := CharacterData.new()
	bandit.id = "npc_bandit_%d" % index
	bandit.display_name = "도적 %s" % ["갑", "을", "병"][index % 3]
	bandit.role = CharacterData.Role.WANDERER
	bandit.level = maxi(1, player.level - 1)
	bandit.strength = 7 + bandit.level
	bandit.agility = 9 + bandit.level
	bandit.wisdom = 5
	bandit.charisma = 5
	bandit.internal_energy_max = 60
	bandit.restore_internal_energy()
	return bandit
