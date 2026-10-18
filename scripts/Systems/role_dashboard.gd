class_name RoleDashboard
extends RefCounted

## 역할별 경영 화면 구성: 보일 행동 버튼, 문파 칸 제목, 역할 안내.
## 역할마다 할 수 있는 일이 달라서, 할 일이 없는 버튼은 숨기고 그 역할의 목표를 위에 적는다.
## 역할 고유 행동(문파 회의·정보 수집 등)은 RoleActions가 따로 버튼을 만든다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 경영 화면의 행동 버튼 (노드 이름)
const ACTION_BUTTONS: PackedStringArray = [
	"AdvanceTurnButton", "TrainButton", "FacilityButton", "ElixirButton", "FeastButton", "MartialArtButton",
	"RoleButton", "CombatButton", "SectWarButton", "WorldButton", "DiscipleButton", "MapButton",
]

## 역할별 구성. hidden: 숨길 버튼, sect: 문파 일에 몸담는지(아니면 시설 칸을 숨기고 금화·식량을 개인 재산으로 보인다),
## focus: 역할 안내
const LAYOUTS: Dictionary = {
	CharacterData.Role.LEADER: {
		"hidden": [],
		"sect": true,
		"focus": "문파 경영·영토 정복·외교·문파전을 모두 지휘합니다.",
	},
	CharacterData.Role.MANAGER: {
		"hidden": ["FeastButton"],
		"sect": true,
		"focus": "부서를 정해 살림을 꾸리고 제자를 기릅니다. 신임을 쌓아 문주 자리를 노리세요.",
	},
	CharacterData.Role.YOUNG_DISCIPLE: {
		"hidden": ["TrainButton", "FacilityButton", "FeastButton", "SectWarButton", "DiscipleButton"],
		"sect": true,
		"focus": "스승께 배우고 외출에서 기연을 찾습니다. 문파 운영은 아직 윗사람의 몫입니다.",
	},
	CharacterData.Role.WANDERER: {
		"hidden": ["TrainButton", "FacilityButton", "FeastButton", "SectWarButton", "DiscipleButton"],
		"sect": false,
		"focus": "의뢰로 이름을 떨치고 강호를 떠돕니다. 지도에서 다른 세력의 땅으로 옮겨 갈 수 있습니다.",
	},
	CharacterData.Role.MERCENARY: {
		"hidden": ["TrainButton", "FacilityButton", "FeastButton", "SectWarButton", "DiscipleButton"],
		"sect": false,
		"focus": "세력의 계약을 맡아 신용과 금화를 쌓습니다. 이행할지 배신할지는 당신의 몫입니다.",
	},
	CharacterData.Role.SPY: {
		"hidden": ["TrainButton", "FacilityButton", "FeastButton", "SectWarButton", "DiscipleButton"],
		"sect": false,
		"focus": "세력의 전력과 작전을 캐고 사보타주로 흔듭니다. 노출도를 조심하세요.",
	},
	CharacterData.Role.ASSASSIN: {
		"hidden": ["TrainButton", "FacilityButton", "FeastButton", "SectWarButton", "DiscipleButton", "WorldButton"],
		"sect": false,
		"focus": "표적 의뢰로 돈을 벌고, 현상금이 쌓이면 은신합니다. 강호의 그림자를 지배하세요.",
	},
}


static func get_layout(role: CharacterData.Role) -> Dictionary:
	return LAYOUTS.get(role, LAYOUTS[CharacterData.Role.LEADER])


static func is_button_visible(role: CharacterData.Role, button_name: String) -> bool:
	return not button_name in get_layout(role)["hidden"]


## 문파 칸 제목: 문파를 운영하는 역할은 문파 이름, 아니면 몸담은 곳과 개인 재산
static func get_sect_title(role: CharacterData.Role, sect: SectData) -> String:
	if sect.id == "none":
		return "무소속 (떠돌이 · 금화·식량은 내 몫)"
	if get_layout(role)["sect"]:
		return sect.sect_name
	return "%s (몸담은 곳 · 금화·식량은 내 몫)" % sect.sect_name


## 새 게임 화면에 보일 역할 소개: 할 수 있는 일 목록
static func describe_role(role: CharacterData.Role) -> String:
	var layout: Dictionary = get_layout(role)
	var actions: PackedStringArray = []
	for action in RoleActions.get_actions(role):
		actions.append(action["title"])
	var hidden: Array = layout["hidden"]
	var common: PackedStringArray = []
	for pair in [
		["TrainButton", "제자 수련"], ["FacilityButton", "시설"], ["FeastButton", "연회"],
		["SectWarButton", "문파전"], ["DiscipleButton", "제자 명단"], ["WorldButton", "외교·정세"], ["MapButton", "지도"],
	]:
		if not pair[0] in hidden:
			common.append(pair[1])
	return "%s\n고유 행동: %s\n경영 화면: %s" % [
		layout["focus"], ", ".join(actions) if not actions.is_empty() else "없음", ", ".join(common),
	]


## 이번 계절에 지금 역할로 아직 할 수 있는 일 (계절 넘기기 미리보기 안내). 역할에 없는 일과 자원이 모자란 일은 뺀다.
## gm은 GameManager 노드다.
static func get_unused_actions(gm: Node) -> PackedStringArray:
	var result: PackedStringArray = []
	for step in get_season_steps(gm):
		result.append(step["title"])
	return result


## 이번 계절 할 일 단계: [{id, title, detail}] (휴대폰 경영 화면의 "할 일" 목록, 계절 넘기기 안내)
## id: role_action · bond · elixir · feast · spar · disciple_train · sect_war · pacify
static func get_season_steps(gm: Node) -> Array[Dictionary]:
	var role: CharacterData.Role = gm.player_character.role
	var sect: SectData = gm.player_sect
	var turn: int = gm._get_turn_index()
	var result: Array[Dictionary] = []
	if RoleActions.can_act(gm.role_state, turn) and not RoleActions.get_actions(role).is_empty():
		var titles: PackedStringArray = []
		for action in RoleActions.get_actions(role):
			titles.append(action["title"])
		result.append({"id": "role_action", "title": "고유 행동(%s)" % "·".join(titles), "detail": "계절에 한 번, 역할만의 일"})
	var interactions: int = RelationshipManager.get_interactions_left(gm.story_flags, turn)
	if interactions > 0 and not gm.player_relationships.is_empty():
		result.append({"id": "bond", "title": "인연 돌보기 %d번" % interactions, "detail": "대화·선물·비무로 유대를 쌓습니다"})
	if is_button_visible(role, "ElixirButton") and gm.can_do_seasonal("last_elixir_turn") and sect.gold >= _Balance.ELIXIR_GOLD:
		result.append({"id": "elixir", "title": "영약 구매", "detail": "금화 %d로 최대 내공 +%d" % [_Balance.ELIXIR_GOLD, _Balance.ELIXIR_INTERNAL_GAIN]})
	if is_button_visible(role, "FeastButton") and gm.can_do_seasonal("last_feast_turn") and sect.gold >= _Balance.FEAST_GOLD and sect.food >= _Balance.FEAST_FOOD:
		result.append({"id": "feast", "title": "문파 연회", "detail": "금화 %d·식량 %d로 명성 +%d" % [_Balance.FEAST_GOLD, _Balance.FEAST_FOOD, _Balance.FEAST_REPUTATION]})
	if is_button_visible(role, "CombatButton") and gm.can_spar():
		result.append({"id": "spar", "title": "연습 비무", "detail": "이기면 경험치 +%d" % _Balance.SPAR_EXP})
	if is_button_visible(role, "DiscipleButton") and sect.gold >= _Balance.DISCIPLE_TRAIN_GOLD and sect.disciples.any(
		func(d: DiscipleData) -> bool: return d.last_train_turn != turn and d.level < _Balance.DISCIPLE_MAX_LEVEL
	):
		result.append({"id": "disciple_train", "title": "제자 개별 수련", "detail": "금화 %d로 제자 경험치 +%d" % [_Balance.DISCIPLE_TRAIN_GOLD, _Balance.DISCIPLE_TRAIN_EXP]})
	if is_button_visible(role, "SectWarButton") and gm.can_wage_war() and not gm.get_war_targets().is_empty():
		result.append({"id": "sect_war", "title": "문파전", "detail": "강호 세력과 겨뤄 꺾습니다"})
	if gm.can_command_conquest() and gm.can_do_seasonal("last_pacify_turn"):
		for region_id in WorldMap.frontier(gm.map_state, sect.id, true):
			if gm.get_region_action(region_id)["reason"].is_empty():
				result.append({"id": "pacify", "title": "땅 평정", "detail": "맞닿은 빈 땅을 차지합니다 (강호 지도)"})
				break
	return result
