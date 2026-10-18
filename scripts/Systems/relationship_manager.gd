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
	RelationshipData.BondType.SPOUSE,
	RelationshipData.BondType.PUPIL,
	RelationshipData.BondType.FRIEND,
]
## 청혼 (인연 팝업의 따로 된 버튼. 상호작용 한 번을 쓴다)
const PROPOSE := "propose"
## 새 게임에서 직접 정한 관계의 시작 유대 (관계 유형 키 → 유대)
const START_STRENGTH: Dictionary = {
	"MASTER_DISCIPLE": 35, "ROMANCE": 45, "BLOOD_OATH": 45, "RIVALRY": 15, "HATRED": 30, "ACQUAINTANCE": 15,
	"SPOUSE": 60, "FRIEND": 35, "FELLOW": 25, "PUPIL": 30, "BENEFACTOR": 30, "IN_LAW": 25,
}
## 문파 데이터에 initial_bonds가 없을 때 문주(사부)와의 시작 유대
const DEFAULT_MASTER_STRENGTH := 30


## 소속 문파의 시작 인연: [{target, type, strength}]. 무소속("none"·"")이면 없다.
## 문파 데이터의 initial_bonds를 쓰고, 없으면 문주를 사부로 모신다.
static func get_sect_start_bonds(sect_id: String) -> Array:
	if sect_id.is_empty() or sect_id == NpcRoster.NO_SECT or not SectRegistry.has_sect(sect_id):
		return []
	var info: Dictionary = SectRegistry.get_sect_info(sect_id)
	if info.has("initial_bonds"):
		return info["initial_bonds"]
	return [{"target": info.get("leader_id", ""), "type": "MASTER_DISCIPLE", "strength": DEFAULT_MASTER_STRENGTH}]


## 새 게임 시작 관계: 소속 문파의 시작 인연. 인자를 주지 않으면 시나리오의 기본 플레이어 문파.
static func create_default_relationships(sect_id: String = "default") -> Array[RelationshipData]:
	if sect_id == "default":
		sect_id = SectRegistry.get_player_sect_id()
	var relationships: Array[RelationshipData] = []
	for bond in get_sect_start_bonds(sect_id):
		var rel: RelationshipData = make_relationship(str(bond.get("target", "")), str(bond.get("type", "")), int(bond.get("strength", 10)))
		if rel and get_bond_with(relationships, rel.target_id) == null:
			relationships.append(rel)
	return relationships


## 새 게임에서 직접 정한 시작 관계: {인물 id: 관계 유형 키}. 빈 값이면 관계 없음.
static func create_from_setup(setup: Dictionary) -> Array[RelationshipData]:
	var relationships: Array[RelationshipData] = []
	for target_id in setup:
		var type_key: String = str(setup[target_id])
		if type_key.is_empty():
			continue
		var rel: RelationshipData = make_relationship(str(target_id), type_key, int(START_STRENGTH.get(type_key, 20)))
		if rel:
			relationships.append(rel)
	return relationships


## 명부 인물과의 관계 하나를 만든다. 인물이나 유형이 잘못되면 null
static func make_relationship(target_id: String, type_key: String, strength: int) -> RelationshipData:
	if not NpcRoster.has_npc(target_id) or not RelationshipData.BondType.has(type_key):
		return null
	var rel := RelationshipData.new()
	rel.target_id = target_id
	rel.target_name = NpcRoster.get_display_name(target_id)
	rel.bond_type = RelationshipData.BondType.get(type_key)
	rel.increase_bond(strength)
	return rel


## 관계 유형별 인원
static func count_type(relationships: Array[RelationshipData], bond_type: RelationshipData.BondType) -> int:
	var count: int = 0
	for rel in relationships:
		if rel.bond_type == bond_type:
			count += 1
	return count


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
			RelationshipData.BondType.SPOUSE,
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
## sect: 금화를 내는 곳 (개인 재산을 쓰는 역할이면 주머니). 청혼의 명성은 GameManager가 문파에 더한다.
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
	if rel == null or not (INTERACTIONS.has(kind) or kind == PROPOSE):
		return {"success": false, "message": "할 수 없는 일입니다."}
	if get_interactions_left(story_flags, turn) <= 0:
		return {"success": false, "message": "이번 계절에는 더 인연을 돌볼 여유가 없습니다. (계절마다 %d번)" % _Balance.INTERACTIONS_PER_SEASON}
	if kind == PROPOSE:
		var reason: String = get_propose_block(rel)
		if not reason.is_empty():
			return {"success": false, "message": reason}
		if not sect.spend_resources(_Balance.WEDDING_GOLD):
			return {"success": false, "message": "혼례 비용이 모자랍니다. (금화 %d 필요)" % _Balance.WEDDING_GOLD}
		_use_interaction(story_flags, turn)
		var wedding: String = marry(relationships, rel, EventManager.world_sects)
		EventManager.set_flag(story_flags, "married")
		return {"success": true, "married": target_id, "message": "%s에게 청혼해 혼례를 올렸습니다. (금화 -%d, 명성 +%d) %s" % [
			rel.target_name, _Balance.WEDDING_GOLD, _Balance.WEDDING_REPUTATION, wedding,
		]}
	var hatred: bool = rel.bond_type == RelationshipData.BondType.HATRED
	var stage_before: int = rel.stage
	var message: String
	match kind:
		"talk":
			var amount: int = _like_bonus(target_id, kind, _Balance.TALK_BOND + character.charisma / _Balance.TALK_CHARISMA_DIVISOR)
			message = _change(rel, amount, hatred, "%s와(과) 이야기를 나누었습니다.%s" % [rel.target_name, _like_text(target_id, kind)])
		"gift":
			if not sect.spend_resources(_Balance.GIFT_GOLD):
				return {"success": false, "message": "금화가 부족합니다. (%d 필요)" % _Balance.GIFT_GOLD}
			message = _change(rel, _like_bonus(target_id, kind, _Balance.GIFT_BOND), hatred, "%s에게 선물을 보냈습니다. (금화 -%d)%s" % [
				rel.target_name, _Balance.GIFT_GOLD, _like_text(target_id, kind),
			])
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


## 취향: 좋아하는 상호작용(인물의 likes)이면 유대가 더 오른다.
static func _like_bonus(target_id: String, kind: String, amount: int) -> int:
	return roundi(amount * _Balance.LIKE_BOND_MULTIPLIER) if NpcAgent.likes(target_id, kind) else amount


static func _like_text(target_id: String, kind: String) -> String:
	return " 마음에 드는 일이라 크게 반깁니다." if NpcAgent.likes(target_id, kind) else ""


## 원한이면 유대(원한의 깊이)가 줄어 누그러지고, 아니면 유대가 오른다.
static func _change(rel: RelationshipData, amount: int, hatred: bool, head: String) -> String:
	if hatred:
		rel.decrease_bond(amount)
		return "%s 원한이 조금 누그러졌습니다. (원한 %d)" % [head, rel.bond_strength]
	rel.increase_bond(amount)
	return "%s 유대 +%d (%d)" % [head, amount, rel.bond_strength]


# ── 혼인 ──

## 청혼할 수 없는 까닭 (할 수 있으면 "")
static func get_propose_block(rel: RelationshipData) -> String:
	if rel.bond_type == RelationshipData.BondType.SPOUSE:
		return "이미 배우자입니다."
	if rel.bond_type != RelationshipData.BondType.ROMANCE:
		return "연인에게만 청혼할 수 있습니다."
	if rel.bond_strength < _Balance.MARRIAGE_MIN_BOND:
		return "유대가 %d 이상이어야 청혼할 수 있습니다. (지금 %d)" % [_Balance.MARRIAGE_MIN_BOND, rel.bond_strength]
	return ""


## 배우자로 맞는다. 배우자는 여럿일 수 있다. 이미 있던 배우자는 서운해 유대가 줄고,
## 배우자가 몸담은 세력의 문주와는 인척이 되며 그 세력의 태도가 오른다. 일어난 일을 글로 돌려준다.
static func marry(relationships: Array[RelationshipData], rel: RelationshipData, world_sects: Array[SectData] = []) -> String:
	var notes: PackedStringArray = []
	var others: PackedStringArray = []
	for other in relationships:
		if other != rel and other.bond_type == RelationshipData.BondType.SPOUSE:
			other.decrease_bond(_Balance.SPOUSE_JEALOUSY_BOND)
			others.append(other.target_name)
	rel.bond_type = RelationshipData.BondType.SPOUSE
	rel.increase_bond(_Balance.WEDDING_BOND)
	notes.append("%s와(과) 부부가 되었습니다. (유대 +%d)" % [rel.target_name, _Balance.WEDDING_BOND])
	if not others.is_empty():
		notes.append("%s이(가) 서운해합니다. (유대 -%d)" % [", ".join(others), _Balance.SPOUSE_JEALOUSY_BOND])
	var sect_id: String = str(NpcRoster.get_npc(rel.target_id).get("sect_id", ""))
	for world_sect in world_sects:
		if world_sect.id != sect_id:
			continue
		world_sect.attitude = clampi(world_sect.attitude + _Balance.WEDDING_ATTITUDE, -100, 100)
		notes.append("%s 태도 +%d" % [world_sect.sect_name, _Balance.WEDDING_ATTITUDE])
	var leader_id: String = str(SectRegistry.get_sect_info(sect_id).get("leader_id", "")) if SectRegistry.has_sect(sect_id) else ""
	if not leader_id.is_empty() and leader_id != rel.target_id and get_bond_with(relationships, leader_id) == null:
		var in_law: RelationshipData = make_relationship(leader_id, "IN_LAW", START_STRENGTH["IN_LAW"])
		if in_law:
			relationships.append(in_law)
			notes.append("%s와(과) 인척이 되었습니다." % in_law.target_name)
	return " ".join(notes)


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
