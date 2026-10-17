class_name RelationshipManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 인물과의 상호작용 (계절마다 INTERACTIONS_PER_SEASON번, 서로 공유)
const INTERACTIONS: Dictionary = {
	"talk": "대화",
	"gift": "선물 (금화 %d)" % _Balance.GIFT_GOLD,
	"spar": "비무 신청",
}
## 방어전에 아군으로 합류하고, 함께 싸울 때 서로를 지켜 주는 관계
const PROTECTIVE_BONDS: Array = [
	RelationshipData.BondType.MASTER_DISCIPLE,
	RelationshipData.BondType.BLOOD_OATH,
	RelationshipData.BondType.ROMANCE,
]

## 새 게임 시작 관계. NPC 명부에서 initial_bond가 있는 인물로 만든다.
static func create_default_relationships() -> Array[RelationshipData]:
	var relationships: Array[RelationshipData] = []
	for npc in NpcRoster.get_all():
		var bond: Dictionary = npc.get("initial_bond", {})
		if bond.is_empty():
			continue
		var rel := RelationshipData.new()
		rel.target_id = npc["id"]
		rel.target_name = npc["display_name"]
		rel.bond_type = RelationshipData.BondType.get(bond["type"])
		rel.bond_strength = int(bond.get("strength", 0))
		rel.stage = int(bond.get("stage", 0))
		relationships.append(rel)
	return relationships


static func get_bond_with(
	relationships: Array[RelationshipData],
	target_id: String
) -> RelationshipData:
	for rel in relationships:
		if rel.target_id == target_id:
			return rel
	return null


static func get_combat_damage_bonus(
	relationships: Array[RelationshipData],
	target_id: String
) -> float:
	var rel := get_bond_with(relationships, target_id)
	if rel == null:
		return 1.0
	return rel.get_combat_damage_modifier()


static func get_ally_buff_multiplier(relationships: Array[RelationshipData]) -> float:
	var multiplier := 1.0
	for rel in relationships:
		if rel.bond_type in [
			RelationshipData.BondType.MASTER_DISCIPLE,
			RelationshipData.BondType.BLOOD_OATH,
		]:
			multiplier += rel.bond_strength * 0.001
	return multiplier


static func format_relationships(relationships: Array[RelationshipData]) -> String:
	if relationships.is_empty():
		return "관계 없음"
	var lines: PackedStringArray = []
	for rel in relationships:
		lines.append(
			"%s (%s Lv.%d, %d)" % [
				rel.target_name,
				rel.get_bond_name(),
				rel.stage,
				rel.bond_strength,
			]
		)
	return "\n".join(lines)


# ── 상호작용 ──

## 이번 계절에 남은 상호작용 횟수 (스토리 플래그에 계절과 횟수를 기록)
static func get_interactions_left(story_flags: Dictionary, turn: int) -> int:
	if int(story_flags.get("interaction_turn", -1)) != turn:
		return _Balance.INTERACTIONS_PER_SEASON
	return maxi(0, _Balance.INTERACTIONS_PER_SEASON - int(story_flags.get("interactions_used", 0)))


static func _use_interaction(story_flags: Dictionary, turn: int) -> void:
	var used: int = int(story_flags.get("interactions_used", 0)) if int(story_flags.get("interaction_turn", -1)) == turn else 0
	EventManager.set_flag(story_flags, "interaction_turn", turn)
	EventManager.set_flag(story_flags, "interactions_used", used + 1)


## 인물과 대화·선물·비무를 한다. 비무면 결과에 combat(CombatSetup)이 담긴다 (GameManager가 전투를 시작한다).
static func interact(
	relationships: Array[RelationshipData],
	target_id: String,
	kind: String,
	character: CharacterData,
	sect: SectData,
	story_flags: Dictionary,
	turn: int
) -> Dictionary:
	var rel: RelationshipData = get_bond_with(relationships, target_id)
	if rel == null or not INTERACTIONS.has(kind):
		return {"success": false, "message": "할 수 없는 일입니다."}
	if get_interactions_left(story_flags, turn) <= 0:
		return {"success": false, "message": "이번 계절에는 더 인연을 돌볼 여유가 없습니다. (계절마다 %d번)" % _Balance.INTERACTIONS_PER_SEASON}
	var hatred: bool = rel.bond_type == RelationshipData.BondType.HATRED
	var stage_before: int = rel.stage
	var message: String
	match kind:
		"talk":
			var amount: int = _Balance.TALK_BOND + character.charisma / _Balance.TALK_CHARISMA_DIVISOR
			message = _change(rel, amount, hatred, "%s와(과) 이야기를 나누었습니다." % rel.target_name)
		"gift":
			if not sect.spend_resources(_Balance.GIFT_GOLD):
				return {"success": false, "message": "금화가 부족합니다. (%d 필요)" % _Balance.GIFT_GOLD}
			message = _change(rel, _Balance.GIFT_BOND, hatred, "%s에게 선물을 보냈습니다. (금화 -%d)" % [rel.target_name, _Balance.GIFT_GOLD])
		"spar":
			if hatred:
				return {"success": false, "message": "원한이 있는 상대와는 비무가 아니라 목숨을 건 싸움이 됩니다."}
			if not NpcRoster.has_npc(target_id):
				return {"success": false, "message": "겨룰 수 없는 상대입니다."}
			_use_interaction(story_flags, turn)
			return {
				"success": true,
				"combat": CombatManager.create_sparring_with(target_id, character),
				"message": "%s에게 비무를 청했습니다." % rel.target_name,
			}
	_use_interaction(story_flags, turn)
	if rel.stage > stage_before:
		message += " 관계가 깊어졌습니다: %s" % rel.get_stage_name()
	return {"success": true, "message": message}


## 원한이면 유대(원한의 깊이)가 줄어 누그러지고, 아니면 유대가 오른다.
static func _change(rel: RelationshipData, amount: int, hatred: bool, head: String) -> String:
	if hatred:
		rel.decrease_bond(amount)
		return "%s 원한이 조금 누그러졌습니다. (원한 %d)" % [head, rel.bond_strength]
	rel.increase_bond(amount)
	return "%s 유대 +%d (%d)" % [head, amount, rel.bond_strength]


# ── 전투 ──

## 방어전에 합류할 인연: 유대 BOND_ALLY_MIN 이상인 사제·혈맹·연인. 적 세력 소속은 제외, 유대 높은 순
static func get_bond_allies(relationships: Array[RelationshipData], enemy_sect_id: String = "") -> Array[RelationshipData]:
	var result: Array[RelationshipData] = []
	for rel in relationships:
		if not rel.bond_type in PROTECTIVE_BONDS or rel.bond_strength < _Balance.BOND_ALLY_MIN:
			continue
		if not NpcRoster.has_npc(rel.target_id):
			continue
		if not enemy_sect_id.is_empty() and NpcRoster.get_npc(rel.target_id).get("sect_id") == enemy_sect_id:
			continue
		result.append(rel)
	result.sort_custom(func(a: RelationshipData, b: RelationshipData) -> bool: return a.bond_strength > b.bond_strength)
	return result


## 받는 피해를 나누는 값: 인연이 있는 아군 인물은 그 인연으로, 주인공은 함께 싸우는 인연 중 가장 깊은 것으로 버틴다.
static func get_defense_modifier(relationships: Array[RelationshipData], ally_ids: Array) -> float:
	var best: float = 1.0
	for ally_id in ally_ids:
		var rel: RelationshipData = get_bond_with(relationships, ally_id)
		if rel:
			best = maxf(best, rel.get_combat_defense_modifier())
	return best
