class_name DiplomacyManager
extends RefCounted

## 외교: 사절 파견, 동맹(제안·파기), 혼담, 도전장, 공물(요구·면제). 세력마다 계절에 한 번.
## 문파를 대표하는 문주·중간관리자만 할 수 있다. gm은 GameManager 노드다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

const ACTIONS: Dictionary = {
	"envoy": "사절 파견",
	"alliance": "동맹 제안",
	"break_alliance": "동맹 파기",
	"marriage": "혼담",
	"challenge": "도전장",
	"tribute": "공물 요구",
	"release_tribute": "공물 면제",
}
## 외교를 할 수 있는 역할
const DIPLOMAT_ROLES: Array = [CharacterData.Role.LEADER, CharacterData.Role.MANAGER]


static func can_negotiate(character: CharacterData) -> bool:
	return character.role in DIPLOMAT_ROLES


## 이 세력에 지금 할 수 있는 외교 행동과 비용·조건 설명: [{id, title, description, available}]
static func get_options(gm: Node, sect: SectData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action_id in ACTIONS:
		var check: String = _check(gm, sect, action_id)
		if check == "hidden":
			continue
		result.append({
			"id": action_id,
			"title": ACTIONS[action_id],
			"description": check if not check.is_empty() else _describe(gm, sect, action_id),
			"available": check.is_empty(),
		})
	return result


## 행동을 할 수 없는 이유. 할 수 있으면 "", 이 세력에는 해당 없는 행동이면 "hidden"
static func _check(gm: Node, sect: SectData, action_id: String) -> String:
	match action_id:
		"envoy":
			return "" if not sect.subjugated else "hidden"
		"alliance":
			if sect.subjugated or sect.allied:
				return "hidden"
			if sect.attitude < _Balance.ALLIANCE_MIN_ATTITUDE:
				return "태도 %d 이상이어야 동맹을 받아들입니다. (지금 %d)" % [_Balance.ALLIANCE_MIN_ATTITUDE, sect.attitude]
		"break_alliance":
			return "" if sect.allied else "hidden"
		"marriage":
			if sect.subjugated or sect.married:
				return "hidden"
			if get_marriage_partner(gm, sect) == null:
				return "이 세력 인물과 유대 %d 이상인 연인이 있어야 합니다." % _Balance.MARRIAGE_MIN_BOND
		"challenge":
			if sect.subjugated or sect.allied:
				return "hidden"
			if gm.challenge_target == sect.id:
				return "이미 도전장을 보냈습니다. 문파전으로 결판을 내세요."
		"tribute":
			return "" if sect.subjugated and not sect.tribute else "hidden"
		"release_tribute":
			return "" if sect.tribute else "hidden"
	return ""


static func _describe(gm: Node, sect: SectData, action_id: String) -> String:
	match action_id:
		"envoy":
			return "금화 %d · 태도 +%d" % [_Balance.DIPLOMAT_ENVOY_GOLD, _Balance.DIPLOMAT_ENVOY_ATTITUDE]
		"alliance":
			return "동맹 세력은 문파전에 전력 %d%%의 원군을 보냅니다. 동맹은 공격할 수 없습니다." % int(_Balance.ALLY_WAR_SUPPORT_RATIO * 100)
		"break_alliance":
			return "태도 -%d, 명성 -%d" % [_Balance.ALLIANCE_BREAK_ATTITUDE, _Balance.ALLIANCE_BREAK_REPUTATION]
		"marriage":
			var partner: RelationshipData = get_marriage_partner(gm, sect)
			return "%s와(과)의 혼인 · 금화 %d · 태도 +%d, 명성 +%d, 동맹" % [
				partner.target_name, _Balance.MARRIAGE_GOLD, _Balance.MARRIAGE_ATTITUDE, _Balance.MARRIAGE_REPUTATION,
			]
		"challenge":
			return "명성 +%d, 태도 -%d. 이 세력과의 문파전에서 이기면 명성 +%d, 지면 -%d" % [
				_Balance.CHALLENGE_REPUTATION, _Balance.CHALLENGE_ATTITUDE,
				_Balance.CHALLENGE_WIN_REPUTATION, _Balance.CHALLENGE_LOSS_REPUTATION,
			]
		"tribute":
			return "계절마다 금화 +%d. 바칠 때마다 태도 -%d, 태도 %d 이하면 끊습니다." % [
				_Balance.TRIBUTE_GOLD, _Balance.TRIBUTE_ATTITUDE_PER_SEASON, _Balance.TRIBUTE_REVOLT_ATTITUDE,
			]
		"release_tribute":
			return "공물을 거둬들이지 않습니다. 태도 +%d" % _Balance.TRIBUTE_RELEASE_ATTITUDE
	return ""


## 혼담 상대: 그 세력 소속이고 유대 MARRIAGE_MIN_BOND 이상인 연인
static func get_marriage_partner(gm: Node, sect: SectData) -> RelationshipData:
	for rel in gm.player_relationships:
		if rel.bond_type != RelationshipData.BondType.ROMANCE or rel.bond_strength < _Balance.MARRIAGE_MIN_BOND:
			continue
		if NpcRoster.get_npc(rel.target_id).get("sect_id") == sect.id:
			return rel
	return null


static func _fail(message: String) -> Dictionary:
	return {"success": false, "message": message}


## 외교 행동을 한다.
static func perform(gm: Node, sect_id: String, action_id: String) -> Dictionary:
	if not can_negotiate(gm.player_character):
		return _fail("외교는 문파를 대표하는 문주나 중간관리자만 할 수 있습니다.")
	var sect: SectData = gm.get_world_sect(sect_id)
	if sect == null or not ACTIONS.has(action_id):
		return _fail("할 수 없는 외교입니다.")
	var reason: String = _check(gm, sect, action_id)
	if reason == "hidden":
		return _fail("%s에는 %s을(를) 할 수 없습니다." % [sect.sect_name, ACTIONS[action_id]])
	if not reason.is_empty():
		return _fail(reason)
	var turn: int = gm._get_turn_index()
	if sect.last_diplomacy_turn == turn:
		return _fail("이번 계절에는 이미 %s와(과) 외교를 했습니다." % sect.sect_name)
	var player_sect: SectData = gm.player_sect
	var message: String
	match action_id:
		"envoy":
			if not player_sect.spend_resources(_Balance.DIPLOMAT_ENVOY_GOLD):
				return _fail("금화가 부족합니다. (%d 필요)" % _Balance.DIPLOMAT_ENVOY_GOLD)
			_change_attitude(sect, _Balance.DIPLOMAT_ENVOY_ATTITUDE)
			message = "%s에 사절을 보냈습니다. 태도 %s(%d)" % [sect.sect_name, sect.get_attitude_text(), sect.attitude]
		"alliance":
			sect.allied = true
			_change_attitude(sect, _Balance.ALLIANCE_ATTITUDE_GAIN)
			EventManager.set_flag(gm.story_flags, "allied_%s" % sect.id)
			message = "%s와(과) 동맹을 맺었습니다. 문파전에 원군을 보내 줍니다." % sect.sect_name
		"break_alliance":
			sect.allied = false
			_change_attitude(sect, -_Balance.ALLIANCE_BREAK_ATTITUDE)
			player_sect.reputation = maxi(0, player_sect.reputation - _Balance.ALLIANCE_BREAK_REPUTATION)
			EventManager.set_flag(gm.story_flags, "allied_%s" % sect.id, false)
			message = "%s와(과)의 동맹을 깼습니다. 태도 %d, 명성 -%d" % [sect.sect_name, sect.attitude, _Balance.ALLIANCE_BREAK_REPUTATION]
		"marriage":
			if not player_sect.spend_resources(_Balance.MARRIAGE_GOLD):
				return _fail("금화가 부족합니다. (%d 필요)" % _Balance.MARRIAGE_GOLD)
			var partner: RelationshipData = get_marriage_partner(gm, sect)
			sect.married = true
			sect.allied = true
			_change_attitude(sect, _Balance.MARRIAGE_ATTITUDE)
			player_sect.reputation += _Balance.MARRIAGE_REPUTATION
			EventManager.set_flag(gm.story_flags, "married_%s" % sect.id)
			EventManager.set_flag(gm.story_flags, "allied_%s" % sect.id)
			# 연애 아크(남궁설)의 혼례와 같은 결말로 친다.
			if partner.target_id == "npc_namgung_lady":
				EventManager.set_flag(gm.story_flags, "arc_love_married")
			message = "%s와(과)의 혼담이 성사되었습니다. %s와(과) 사돈이자 동맹이 되었습니다. 명성 +%d" % [
				partner.target_name, sect.sect_name, _Balance.MARRIAGE_REPUTATION,
			]
		"challenge":
			gm.challenge_target = sect.id
			player_sect.reputation += _Balance.CHALLENGE_REPUTATION
			_change_attitude(sect, -_Balance.CHALLENGE_ATTITUDE)
			message = "%s에 도전장을 보냈습니다. 강호의 이목이 쏠립니다. 명성 +%d" % [sect.sect_name, _Balance.CHALLENGE_REPUTATION]
		"tribute":
			sect.tribute = true
			message = "%s에 공물을 요구했습니다. 계절마다 금화 %d를 바칩니다." % [sect.sect_name, _Balance.TRIBUTE_GOLD]
		"release_tribute":
			sect.tribute = false
			_change_attitude(sect, _Balance.TRIBUTE_RELEASE_ATTITUDE)
			message = "%s의 공물을 면제했습니다. 태도 %d" % [sect.sect_name, sect.attitude]
	sect.last_diplomacy_turn = turn
	return {"success": true, "message": message}


static func _change_attitude(sect: SectData, amount: int) -> void:
	sect.attitude = clampi(sect.attitude + amount, -100, 100)


## 문파전 원군: 동맹 세력 전력의 일부
static func get_ally_support(world_sects: Array[SectData]) -> int:
	var support: int = 0
	for sect in world_sects:
		if sect.allied and not sect.subjugated:
			support += roundi(SectWarManager.get_sect_power(sect) * _Balance.ALLY_WAR_SUPPORT_RATIO)
	return support


## 계절 처리: 공물을 받는다. 원망이 쌓여 태도가 너무 낮으면 공물을 끊는다. 보고 문구를 돌려준다.
static func on_season(player_sect: SectData, world_sects: Array[SectData]) -> String:
	var gold: int = 0
	var parts: PackedStringArray = []
	for sect in world_sects:
		if not sect.tribute:
			continue
		if not sect.subjugated or sect.attitude <= _Balance.TRIBUTE_REVOLT_ATTITUDE:
			sect.tribute = false
			parts.append("%s이(가) 공물을 끊었습니다" % sect.sect_name)
			continue
		gold += _Balance.TRIBUTE_GOLD
		_change_attitude(sect, -_Balance.TRIBUTE_ATTITUDE_PER_SEASON)
	if gold > 0:
		player_sect.gold += gold
		parts.insert(0, "공물 금화 +%d" % gold)
	return ", ".join(parts)
