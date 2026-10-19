class_name FeatureGate
extends RefCounted

## 기능 단계 개방: 처음에는 몇 가지 일만 하고, 이야기와 역할이 바뀌면서 할 수 있는 일이 하나씩 열린다.
## 시나리오가 단계 개방(scenario.json "progressive": true)이고 등장인물이 시작 기능("features")을 정했을 때만 쓴다.
## 그 밖의 게임은 처음부터 모두 열려 있다.
## 기능은 기연 효과 unlock으로 열리거나, 역할이 바뀔 때 그 역할의 기능(ROLE_FEATURES)이 함께 열린다.
## 열린 순간 짧은 소개 장면을 띄운다 (GameManager.pending_intros).

## 기능 id → 이름, 소개 글
const FEATURES: Dictionary = {
	"role_action": {"title": "역할 행동", "intro": "계절마다 지금 신분에 맞는 일을 한 번 할 수 있습니다.\n막내 제자라면 스승께 배우거나 외출해 기연을 찾고, 낭인이라면 의뢰를 맡습니다."},
	"bond": {"title": "인연 돌보기", "intro": "강호는 사람의 일입니다. 계절마다 인연 있는 사람과 이야기를 나누고 마음을 쌓으세요.\n유대가 깊어지면 대화가 달라지고, 새로운 이야기가 열립니다."},
	"spar": {"title": "비무", "intro": "인연 있는 무인과 검을 겨룰 수 있습니다. 이기면 경험을 얻고, 서로를 더 잘 알게 됩니다.\n[인물] 쪽의 [비무] 버튼으로 겨룹니다."},
	"martial": {"title": "무공 연구소", "intro": "익힌 무공을 살펴보고, 얻은 비급을 연구하고, 나만의 초식을 만들 수 있습니다."},
	"travel": {"title": "강호 지도", "intro": "강호 지도를 펼쳐 지역을 살피고 다른 곳으로 떠날 수 있습니다.\n머무는 곳에 따라 만나는 사람과 들리는 소문이 달라집니다."},
	"elixir": {"title": "영약", "intro": "금화를 들여 영약을 구하면 내공의 그릇을 키울 수 있습니다."},
	"role_change": {"title": "역할 전환", "intro": "때가 되면 신분을 바꿀 수 있습니다. 문파를 떠나 낭인이 되거나, 문파의 살림을 맡거나, 문주가 될 수도 있습니다.\n[역할 전환]에서 가능한 길과 조건을 봅니다."},
	"sect": {"title": "문파 경영", "intro": "이제 문파의 살림이 당신의 몫입니다. 제자를 수련시키고, 시설을 짓고, 연회를 열어 문파를 키우세요.\n[문파] 쪽에서 경영합니다."},
	"diplomacy": {"title": "외교·정세", "intro": "강호 세력과 사절을 주고받고, 동맹을 맺거나 굴복을 요구할 수 있습니다."},
	"sect_war": {"title": "문파전·평정", "intro": "문파의 이름을 걸고 다른 세력과 겨루거나, 맞닿은 땅을 평정해 세를 넓힐 수 있습니다."},
}

## 경영 화면 버튼 → 그 버튼을 여는 기능
const BUTTON_FEATURES: Dictionary = {
	"BondButton": "bond", "CombatButton": "spar", "MartialArtButton": "martial", "MapButton": "travel",
	"ElixirButton": "elixir", "RoleButton": "role_change", "TrainButton": "sect", "FacilityButton": "sect",
	"FeastButton": "sect", "DiscipleButton": "sect", "WorldButton": "diplomacy", "SectWarButton": "sect_war",
}

## 이번 계절 할 일 단계(RoleDashboard.get_season_steps의 id) → 기능
const STEP_FEATURES: Dictionary = {
	"role_action": "role_action", "bond": "bond", "elixir": "elixir", "feast": "sect", "spar": "spar",
	"disciple_train": "sect", "sect_war": "sect_war", "pacify": "sect_war",
}

## 역할이 되면 함께 열리는 기능 (역할 이름 → 기능 목록)
const ROLE_FEATURES: Dictionary = {
	"LEADER": ["sect", "diplomacy", "sect_war", "role_change"],
	"MANAGER": ["sect", "role_change"],
	"WANDERER": ["travel", "role_change"],
	"MERCENARY": ["travel", "role_change"],
	"SPY": ["role_change"],
	"ASSASSIN": ["role_change"],
}

## 단계 개방 중인지 (false면 모두 열림), 열린 기능 (GameManager의 배열을 그대로 가리킨다)
static var progressive: bool = false
static var unlocked: Array[String] = []


static func sync(is_progressive: bool, unlocked_list: Array[String]) -> void:
	progressive = is_progressive
	unlocked = unlocked_list


static func has_feature(feature_id: String) -> bool:
	return FEATURES.has(feature_id)


static func is_open(feature_id: String) -> bool:
	return not progressive or unlocked.has(feature_id)


## 경영 화면 버튼이 열려 있는지 (기능과 상관없는 버튼은 늘 열림)
static func is_button_open(button_name: String) -> bool:
	return not BUTTON_FEATURES.has(button_name) or is_open(BUTTON_FEATURES[button_name])


static func is_step_open(step_id: String) -> bool:
	return not STEP_FEATURES.has(step_id) or is_open(STEP_FEATURES[step_id])


static func get_title(feature_id: String) -> String:
	return str(FEATURES.get(feature_id, {}).get("title", feature_id))


## 기능이 열릴 때 띄우는 소개 장면 (GameManager.pending_event 형식). 한꺼번에 열린 기능은 한 장면에 모은다.
static func intro_popup(feature_ids: Array) -> Dictionary:
	var titles: PackedStringArray = []
	var parts: PackedStringArray = []
	for feature_id in feature_ids:
		var info: Dictionary = FEATURES.get(feature_id, {})
		titles.append(str(info.get("title", feature_id)))
		parts.append("【%s】\n%s" % [info.get("title", feature_id), info.get("intro", "")])
	return {
		"id": "feature_intro", "intro": true,
		"title": "새로 열린 길 — %s" % "·".join(titles),
		"description": "\n\n".join(parts),
		"choices": ["알겠습니다"], "choice_map": [0], "npc": "", "subject": "",
	}
