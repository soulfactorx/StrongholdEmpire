class_name EndingManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 엔딩은 data/endings/*.json (시나리오 전용은 data/scenarios/<id>/endings/)에 데이터로 정의한다.
##
## 필드: id, title, description
##   priority  자동 판정 순서. 높은 것부터 확인한다 (auto 엔딩은 필수, 서로 달라야 함)
##   auto      true(기본)면 계절마다 conditions로 자동 판정. false면 기연의 end_game으로만 도달
##   final     true면 이 엔딩으로 주인공의 생이 끝난다. 전승할 수 있으면 곧바로 후계자를 정하고,
##             없으면 이야기가 끝난다 (story_end)
##   tone      victory / tragedy / neutral — 화면 표시용
##   conditions 기연과 같은 조건 문법 (docs/기연_데이터_형식.md)

const ENDING_DIR := "res://data/endings/"
const TONES: PackedStringArray = ["victory", "tragedy", "neutral"]

static var _endings: Dictionary = {}
static var _loaded: bool = false


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
	## 생을 마치는 엔딩(final)에 도달했는데 전승할 수 없을 때
	"story_end": {
		"title": "이야기의 끝",
		"description": "주인공의 생이 다했고, 그 뒤를 이을 사람은 없습니다.",
		"prefix": "결말",
	},
	## 승리 엔딩으로 시나리오를 마쳤을 때 (end_on_victory)
	"scenario_complete": {
		"title": "시나리오 완수",
		"description": "이 시대에 주어진 사명을 이루었습니다.",
		"prefix": "승리",
	},
}

static func has_ending(ending_id: String) -> bool:
	_ensure_loaded()
	return _endings.has(ending_id)


## 로드된 엔딩 목록 (자동 판정 엔딩은 우선순위 높은 순)
static func get_all_endings() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for id in _endings:
		result.append(_endings[id])
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)
	return result


static func is_final(ending_id: String) -> bool:
	return get_ending(ending_id).get("final", false)


static func validate_ending_dict(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in ["id", "title", "description"]:
		if not data.get(key) is String or String(data.get(key)).is_empty():
			errors.append("'%s'가 비어 있음" % key)
	var auto: Variant = data.get("auto", true)
	if not auto is bool:
		errors.append("auto는 true/false여야 함")
	elif auto:
		if not (data.get("priority") is float or data.get("priority") is int):
			errors.append("자동 판정 엔딩에는 priority(숫자)가 필요함")
		if data.get("conditions", []).is_empty():
			errors.append("자동 판정 엔딩에는 조건이 하나 이상 필요함")
	if data.has("final") and not data["final"] is bool:
		errors.append("final은 true/false여야 함")
	if data.has("tone") and not data["tone"] in TONES:
		errors.append("알 수 없는 tone: %s" % data["tone"])
	if data.has("id") and GAME_OVERS.has(data["id"]):
		errors.append("게임오버 id와 겹침: %s" % data["id"])
	EventManager.validate_conditions(data.get("conditions", []), errors)
	return errors


## 엔딩 폴더를 다시 읽는다. extra_dirs(시나리오 전용 엔딩)가 있으면 이어서 읽는다.
## 잘못된 파일, 중복 id, 다른 자동 엔딩과 겹치는 priority는 경고 후 건너뛴다.
static func reload_data(dir_path: String = ENDING_DIR, extra_dirs: Array = []) -> void:
	_endings.clear()
	_loaded = true
	var entries: Array[Dictionary] = ModLoader.load_json_dir(dir_path)
	for extra in extra_dirs:
		if DirAccess.dir_exists_absolute(str(extra)):
			entries.append_array(ModLoader.load_json_dir(str(extra)))
	var priorities: Dictionary = {}
	for data in entries:
		var errors: PackedStringArray = validate_ending_dict(data)
		if _endings.has(data.get("id")):
			errors.append("중복된 id")
		var auto: bool = data.get("auto", true) == true
		if auto and errors.is_empty() and priorities.has(int(data["priority"])):
			errors.append("priority %d가 %s와 겹침" % [int(data["priority"]), priorities[int(data["priority"])]])
		if not errors.is_empty():
			push_warning("엔딩 정의 오류 (%s): %s" % [data["_path"], "; ".join(errors)])
			continue
		if auto:
			priorities[int(data["priority"])] = data["id"]
		_endings[data["id"]] = data


static func _ensure_loaded() -> void:
	if not _loaded:
		reload_data()


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
	# 무소속(낭인)은 제자가 없어도 이야기가 이어진다.
	if sect.disciple_count <= 0 and sect.id != "none":
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


## 자동 판정 엔딩 중 조건을 만족하는 가장 높은 우선순위 엔딩 id (없으면 "")
static func check_endings(
	character: CharacterData,
	sect: SectData,
	story_flags: Dictionary,
	relationships: Array[RelationshipData] = [],
	season: String = "봄"
) -> String:
	for ending in get_all_endings():
		if not ending.get("auto", true):
			continue
		# 엔딩의 문파 조건은 개인 재산이 아니라 문파 자체를 본다 (금권 강호 = 문파 금고)
		var wallet: SectData = EventManager.wallet
		EventManager.wallet = null
		var met: bool = EventManager.conditions_met(ending["conditions"], character, sect, relationships, season, story_flags)
		EventManager.wallet = wallet
		if met:
			return ending["id"]
	return ""


static func get_ending(ending_id: String) -> Dictionary:
	_ensure_loaded()
	if _endings.has(ending_id):
		return _endings[ending_id]
	return {"title": "미완의 서사", "description": "이야기가 아직 끝나지 않았습니다."}