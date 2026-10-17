class_name EndingManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

const ENDINGS: Dictionary = {
	"unify_righteous": {
		"title": "정파 통일",
		"description": "문주로서 청운검파를 이끌고 강호에 새 질서를 세웠습니다.\n정파가 연합하여 천하대란을 막을 수 있었습니다.",
	},
	"shadow_empire": {
		"title": "그림자 제패",
		"description": "암살과 음모로 강호를 장악했습니다.\n아무도 당신의 이름을 모르지만, 모두가 당신을 두려워합니다.",
	},
	"wanderer_legend": {
		"title": "낭인 전설",
		"description": "문파와 굴레를 벗어나 자유롭게 강호를 누볐습니다.\n당신의 이름은 전설이 되어 후대에 전해집니다.",
	},
	"tragic_execution": {
		"title": "비극적 처형",
		"description": "스파이 신분이 드러나 적문파에 체포되었습니다.\n이청풍의 이야기는 비극으로 끝났습니다.",
	},
	"new_sect_founder": {
		"title": "신파 창설",
		"description": "이중 스파이로 살아남아 새로운 문파를 세웠습니다.\n강호에 또 하나의 세력이 탄생했습니다.",
	},
}


## 게임오버: 이야기가 끝나며 세대 전승도 할 수 없다.
const GAME_OVERS: Dictionary = {
	"sect_disbanded": {
		"title": "문파 해산",
		"description": "마지막 제자마저 떠났습니다.\n텅 빈 연무장에 바람만 불고, 문파의 이름은 강호에서 잊혔습니다.",
	},
	"famine_collapse": {
		"title": "곳간이 비다",
		"description": "몇 계절째 이어진 궁핍을 견디지 못하고 문파가 무너졌습니다.\n남은 이들은 뿔뿔이 흩어졌습니다.",
	},
	"disgraced": {
		"title": "명성 실추",
		"description": "문파의 이름이 땅에 떨어졌습니다.\n더 이상 누구도 문하에 들어오려 하지 않습니다.",
	},
	## 시나리오 제한 연수가 끝났을 때. 실패가 아니라 시대의 마무리다.
	"era_end": {
		"title": "시대의 끝",
		"description": "정해진 시대가 저물었습니다. 강호는 당신이 남긴 자취를 기억할 것입니다.",
		"prefix": "시대 종결",
	},
	## 승리 엔딩으로 시나리오를 마쳤을 때 (end_on_victory)
	"scenario_complete": {
		"title": "시나리오 완수",
		"description": "이 시대에 주어진 사명을 이루었습니다.",
		"prefix": "승리",
	},
}

## 현재 시나리오가 데이터로 더한 엔딩 (ScenarioManager가 등록)
static var scenario_endings: Dictionary = {}


static func register_scenario_endings(endings: Dictionary) -> void:
	scenario_endings = endings.duplicate(true)


static func has_ending(ending_id: String) -> bool:
	return ENDINGS.has(ending_id) or scenario_endings.has(ending_id)


## 그 판의 평가. 점수와 등급, 항목별 내역을 돌려준다.
static func evaluate(
	character: CharacterData,
	sect: SectData,
	world_sects: Array[SectData],
	generation: int,
	ending_id: String,
	victory: bool
) -> Dictionary:
	var subjugated: int = 0
	for world_sect in world_sects:
		if world_sect.subjugated:
			subjugated += 1
	var parts: Array = [
		["문파 명성", sect.reputation],
		["주인공 경지 (Lv.%d)" % character.level, character.level * _Balance.SCORE_PER_LEVEL],
		["창조·습득 무공 %d개" % character.martial_arts.size(), character.martial_arts.size() * _Balance.SCORE_PER_ART],
		["굴복시킨 세력 %d곳" % subjugated, subjugated * _Balance.SCORE_PER_SUBJUGATION],
		["제자 %d명" % sect.disciple_count, sect.disciple_count * _Balance.SCORE_PER_DISCIPLE],
		["%d세대에 걸친 이야기" % generation, (generation - 1) * _Balance.SCORE_PER_GENERATION],
	]
	if not ending_id.is_empty():
		parts.append(["엔딩 「%s」" % get_ending(ending_id)["title"], _Balance.SCORE_ENDING])
	if victory:
		parts.append(["시나리오 승리", _Balance.SCORE_VICTORY])

	var score: int = 0
	var lines: PackedStringArray = []
	for part in parts:
		score += int(part[1])
		lines.append("%s: %+d" % [part[0], part[1]])
	var grade: String = "이름 없는 문파"
	for entry in _Balance.SCORE_GRADES:
		if score >= entry[0]:
			grade = entry[1]
			break
	return {"score": score, "grade": grade, "lines": lines}


static func check_game_over(sect: SectData) -> String:
	if sect.disciple_count <= 0:
		return "sect_disbanded"
	if sect.shortage_seasons >= _Balance.SHORTAGE_GAME_OVER_SEASONS:
		return "famine_collapse"
	if sect.reputation <= 0:
		return "disgraced"
	return ""


static func get_game_over(game_over_id: String) -> Dictionary:
	var info: Dictionary = {"title": "게임 오버", "description": "이야기가 끝났습니다.", "prefix": "게임 오버"}
	if GAME_OVERS.has(game_over_id):
		info.merge(GAME_OVERS[game_over_id], true)
	return info


static func check_endings(
	character: CharacterData,
	sect: SectData,
	story_flags: Dictionary
) -> String:
	if story_flags.get("spy_exposed", false):
		return "tragic_execution"

	if (
		character.role == CharacterData.Role.LEADER
		and sect.reputation >= _Balance.ENDING_REPUTATION_UNIFY
		and character.morality >= _Balance.ENDING_MORALITY_UNIFY
	):
		return "unify_righteous"

	if (
		character.role in [CharacterData.Role.ASSASSIN, CharacterData.Role.SPY]
		and character.morality <= _Balance.ENDING_MORALITY_SHADOW
		and sect.reputation >= _Balance.ENDING_REPUTATION_SHADOW
		and story_flags.get("assassin_path", false)
	):
		return "shadow_empire"

	if (
		character.role == CharacterData.Role.WANDERER
		and character.martial_arts.size() >= _Balance.ENDING_WANDERER_ARTS
		and character.level >= _Balance.ENDING_WANDERER_LEVEL
	):
		return "wanderer_legend"

	if (
		story_flags.get("spy_mission_complete", false)
		and character.role == CharacterData.Role.MANAGER
		and sect.reputation >= 85
	):
		return "new_sect_founder"

	return ""


static func get_ending(ending_id: String) -> Dictionary:
	if ENDINGS.has(ending_id):
		return ENDINGS[ending_id]
	if scenario_endings.has(ending_id):
		return scenario_endings[ending_id]
	return {"title": "미완의 서사", "description": "이야기가 아직 끝나지 않았습니다."}