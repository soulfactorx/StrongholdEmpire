class_name ScenarioManager
extends RefCounted

## 시나리오: data/scenarios/<id>/scenario.json 과 같은 폴더의 전용 데이터(events/, endings/, npcs/, sects/).
##
## scenario.json 필드
##   id, title, description, era_name(연호 표시, 예: "천하대란"), order(목록 순서)
##   start_roles   선택 가능한 시작 신분 id 목록 (StartingRoles). 생략하면 전부
##   player_sect   플레이어 문파 id. 생략하면 is_player_sect인 문파
##   sects         등장하는 강호 세력 id 목록. 생략하면 플레이어 문파를 뺀 전부
##   sect_overrides { 문파 id: { 수치 필드: 값 } } — 플레이어 문파도 가능
##   parameters    ScenarioRules 파라미터 덮어쓰기
##   victory_endings 이 시나리오에서 승리로 치는 결말 id 목록 (공용 결말 또는 endings/ 폴더의 전용 결말)
##   playables     고를 수 있는 등장인물 목록. 있으면 시작 신분 대신 인물을 골라 그 인물로 플레이한다 (PLAYABLE_KEYS)
##   common_events 공용 기연(data/events/) 가운데 읽을 하위 폴더 또는 파일 경로 앞부분 목록
##                 (예: ["bonds", "manuals"], ["bonds/bond_g_"]). 생략하면 전부
##   hidden_npcs   이 시나리오에 나오지 않는 공용 인물 id (다른 시대의 인물). 인연·기연 대상과 직책에서 빠진다
##   sect_overrides에는 수치 말고 sect_name(이름), leader_id(문주 인물 id)도 줄 수 있다
##   progressive   true면 기능 단계 개방: 등장인물의 features만 열고 시작해 이야기·신분으로 하나씩 연다 (FeatureGate)
##   goals         (선택) 강호 일지의 첫 목표 { 시작 신분 id 또는 "default": 목표 }. 등장인물의 goal이 있으면 그쪽이 먼저
##   common_endings false면 공용 결말(data/endings/)을 읽지 않고 이 시나리오의 결말만 쓴다 (기본 true)

const SCENARIO_DIR := "res://data/scenarios/"
const DEFAULT_ID := "cheonha"
## 등장인물(playables) 항목의 필드
##   npc        인물 id (공용 또는 이 시나리오 npcs/의 인물). 자질·무공·나이·도덕·초상화를 이 인물에게서 가져온다
##   start_role 시작 신분 id (StartingRoles). 신분과 신분 화면이 이것으로 정해진다
##   sect       소속 문파 id. "none"이면 무소속
##   summary    새 게임 화면에 보일 소개
##   level, morality, age  (선택) 인물 데이터 대신 쓸 값
##   bonds      { 인물 id: 관계 유형 키 } 시작 인연
##   flags      시작 이야기 플래그 (playing_<인물 id> 플래그는 저절로 켜진다)
##   region     (선택) 시작 지역 id
##   arts       (선택) 더 익히고 시작할 무공 id 목록
##   features   (선택) 기능 단계 개방 시나리오("progressive": true)에서 처음부터 열린 기능 (FeatureGate). 없으면 모두 열림
##   goal       (선택) 강호 일지의 첫 목표
const PLAYABLE_KEYS: PackedStringArray = [
	"npc", "start_role", "sect", "summary", "level", "morality", "age", "bonds", "flags", "region", "arts", "features", "goal",
]

static var current_id: String = ""
static var current: Dictionary = {}
## 새 게임 "세부 설정"에서 바꾼 파라미터 (저장본에 함께 저장)
static var user_overrides: Dictionary = {}
static var _scenarios: Dictionary = {}
static var _loaded: bool = false


static func list_scenarios() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for id in _scenarios:
		result.append(_scenarios[id])
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("order", 99) < b.get("order", 99)
	)
	return result


static func has_scenario(scenario_id: String) -> bool:
	_ensure_loaded()
	return _scenarios.has(scenario_id)


static func get_scenario(scenario_id: String) -> Dictionary:
	_ensure_loaded()
	return _scenarios.get(scenario_id, {})


static func get_dir(scenario_id: String) -> String:
	return SCENARIO_DIR.path_join(scenario_id)


## 시나리오를 켠다: 전용 결말·인물·문파·기연을 불러오고 파라미터를 적용한다.
static func activate(scenario_id: String, overrides: Dictionary = {}) -> PackedStringArray:
	_ensure_loaded()
	var errors: PackedStringArray = []
	if not _scenarios.has(scenario_id):
		errors.append("알 수 없는 시나리오: %s (기본 시나리오 사용)" % scenario_id)
		scenario_id = DEFAULT_ID
	current_id = scenario_id
	current = _scenarios.get(scenario_id, {})
	var dir: String = get_dir(scenario_id)

	NpcRoster.reload_data(NpcRoster.NPC_DIR, [dir.path_join("npcs")])
	SectRegistry.reload_data(SectRegistry.SECT_DIR, [dir.path_join("sects")])
	if current.get("common_endings", true) == false:
		EndingManager.reload_data(dir.path_join("endings"))
	else:
		EndingManager.reload_data(EndingManager.ENDING_DIR, [dir.path_join("endings")])
	CombatLibrary.reload_data(CombatLibrary.COMBAT_DIR, [dir.path_join("combats")])
	EventManager.reload_definitions(EventManager.EVENTS_DIR, [dir.path_join("events")], current.get("common_events", []))

	ScenarioRules.reset()
	errors.append_array(ScenarioRules.apply(current.get("parameters", {})))
	user_overrides = {}
	var override_errors: PackedStringArray = ScenarioRules.apply(overrides)
	if override_errors.is_empty():
		user_overrides = overrides.duplicate()
	errors.append_array(override_errors)
	for error in errors:
		push_warning("시나리오: %s" % error)
	return errors


static func get_era_name() -> String:
	return current.get("era_name", "천하대란")


## scenario를 주지 않으면 현재 시나리오 기준
static func get_start_role_ids(scenario: Dictionary = {}) -> Array:
	if scenario.is_empty():
		scenario = current
	var all_ids: Array = []
	for entry in StartingRoles.ROLES:
		all_ids.append(entry["id"])
	var allowed: Array = scenario.get("start_roles", [])
	return all_ids.filter(func(id: String) -> bool: return allowed.is_empty() or allowed.has(id))


## 고를 수 있는 등장인물 목록 (없으면 빈 배열 → 시작 신분을 고른다)
static func get_playables(scenario: Dictionary = {}) -> Array:
	if scenario.is_empty():
		scenario = current
	return scenario.get("playables", [])


## 현재 시나리오의 등장인물 항목 (없으면 {})
static func get_playable(npc_id: String) -> Dictionary:
	for entry in get_playables():
		if str(entry.get("npc", "")) == npc_id:
			return entry
	return {}


## 인물 데이터를 시나리오를 켜지 않고 본다: 명부에 있으면 그것, 없으면 그 시나리오의 npcs/ 폴더에서 찾는다.
static func peek_npc(npc_id: String, scenario: Dictionary = {}) -> Dictionary:
	if NpcRoster.has_npc(npc_id):
		return NpcRoster.get_npc(npc_id)
	var dir: String = get_dir(str(scenario.get("id", current_id))).path_join("npcs")
	if DirAccess.dir_exists_absolute(dir):
		for data in ModLoader.load_json_dir(dir):
			if data.get("id") == npc_id:
				return data
	return {}


## 시나리오에서 보이는 문파 이름 (sect_overrides의 sect_name이 있으면 그것)
static func sect_display_name(sect_id: String, scenario: Dictionary = {}) -> String:
	if scenario.is_empty():
		scenario = current
	var override: Dictionary = scenario.get("sect_overrides", {}).get(sect_id, {})
	return str(override.get("sect_name", SectRegistry.get_sect_info(sect_id).get("sect_name", sect_id)))


static func create_player_sect() -> SectData:
	var sect_id: String = current.get("player_sect", "")
	var overrides: Dictionary = current.get("sect_overrides", {})
	if sect_id.is_empty():
		sect_id = SectRegistry.get_player_sect_id()
	return SectRegistry.create_player_sect(sect_id, overrides.get(sect_id, {}))


static func create_rival_sects() -> Array[SectData]:
	return SectRegistry.create_rival_sects(current.get("sects", []), current.get("sect_overrides", {}))


static func is_victory_ending(ending_id: String) -> bool:
	return not ending_id.is_empty() and current.get("victory_endings", []).has(ending_id)


## 목록·새 게임 화면에 보여 줄 한 줄 요약 (길이와 세대)
static func describe_length(scenario: Dictionary, overrides: Dictionary = {}) -> String:
	var params: Dictionary = scenario.get("parameters", {}).duplicate()
	params.merge(overrides, true)
	var years: int = int(params.get("time_limit_years", ScenarioRules.DEFAULTS["time_limit_years"]))
	var legacy: bool = params.get("legacy_enabled", true)
	var generations: int = int(params.get("max_generations", 0))
	var length_text: String = "%d년" % years if years > 0 else "제한 없음"
	var legacy_text: String = "세대 전승 없음"
	if legacy:
		legacy_text = "최대 %d세대" % generations if generations > 0 else "세대 전승 무제한"
	return "%s · %s" % [length_text, legacy_text]


static func validate_scenario_dict(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in ["id", "title", "description"]:
		if not data.get(key) is String or String(data.get(key)).is_empty():
			errors.append("'%s'가 비어 있음" % key)
	errors.append_array(ScenarioRules.validate(data.get("parameters", {})))
	var role_ids: Array = []
	for entry in StartingRoles.ROLES:
		role_ids.append(entry["id"])
	for role_id in data.get("start_roles", []):
		if not role_ids.has(role_id):
			errors.append("알 수 없는 시작 신분: %s" % role_id)
	for entry in data.get("playables", []):
		errors.append_array(_validate_playable(entry, role_ids))
	var goals: Variant = data.get("goals", {})
	if not goals is Dictionary:
		errors.append("goals는 { 신분 id: 목표 } 객체여야 함")
	else:
		for role_id in goals:
			if role_id != "default" and not role_ids.has(role_id):
				errors.append("goals: 알 수 없는 시작 신분 %s" % role_id)
	var common_files: PackedStringArray = EventManager.collect_json_files(EventManager.EVENTS_DIR)
	for folder in data.get("common_events", []):
		if not Array(common_files).any(func(path: String) -> bool: return EventManager._in_folders(path, EventManager.EVENTS_DIR, [folder])):
			errors.append("공용 기연 폴더(앞부분)에 맞는 파일이 없음: %s" % folder)
	if data.has("endings"):
		errors.append("전용 결말은 scenario.json이 아니라 endings/ 폴더의 JSON으로 정의함")
	var own_endings: Array = _read_ids(SCENARIO_DIR.path_join(str(data.get("id", ""))).path_join("endings"))
	for ending_id in data.get("victory_endings", []):
		if not (_is_common_ending(ending_id) or own_endings.has(ending_id)):
			errors.append("알 수 없는 승리 결말: %s" % ending_id)
	# 문파 id는 공용 데이터 기준으로 확인한다. (시나리오 전용 문파는 활성화 후 확인)
	var scenario_sects_dir: String = SCENARIO_DIR.path_join(str(data.get("id", ""))).path_join("sects")
	if not DirAccess.dir_exists_absolute(scenario_sects_dir):
		var sect_ids: Array = data.get("sects", []).duplicate()
		if data.has("player_sect"):
			sect_ids.append(data["player_sect"])
		sect_ids.append_array(data.get("sect_overrides", {}).keys())
		for sect_id in sect_ids:
			if not SectRegistry.has_sect(sect_id):
				errors.append("알 수 없는 문파: %s" % sect_id)
	return errors


## 등장인물 항목 하나를 검사한다. 인물 id는 시나리오 전용 인물도 있으므로 활성화 뒤에 확인한다 (스모크 테스트).
static func _validate_playable(entry: Variant, role_ids: Array) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not entry is Dictionary or str(entry.get("npc", "")).is_empty():
		errors.append("등장인물에 npc가 없음: %s" % entry)
		return errors
	for key in entry:
		if not key in PLAYABLE_KEYS:
			errors.append("등장인물 %s: 알 수 없는 필드 %s" % [entry["npc"], key])
	if not role_ids.has(str(entry.get("start_role", ""))):
		errors.append("등장인물 %s: 알 수 없는 시작 신분 %s" % [entry["npc"], entry.get("start_role")])
	for feature_id in entry.get("features", []):
		if not FeatureGate.has_feature(str(feature_id)):
			errors.append("등장인물 %s: 알 수 없는 기능 %s" % [entry["npc"], feature_id])
	if str(entry.get("summary", "")).is_empty():
		errors.append("등장인물 %s: summary가 비어 있음" % entry["npc"])
	var bonds: Variant = entry.get("bonds", {})
	if not bonds is Dictionary:
		errors.append("등장인물 %s: bonds는 { 인물 id: 관계 유형 }" % entry["npc"])
	else:
		for target in bonds:
			if not RelationshipData.BondType.has(str(bonds[target])):
				errors.append("등장인물 %s: 알 수 없는 관계 유형 %s" % [entry["npc"], bonds[target]])
	return errors


## 공용 결말 폴더(data/endings/)에 있는 id인지. 현재 켜진 시나리오와 관계없이 확인한다.
static func _is_common_ending(ending_id: String) -> bool:
	return _read_ids(EndingManager.ENDING_DIR).has(ending_id)


static func _read_ids(dir_path: String) -> Array:
	var ids: Array = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return ids
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".json"):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir_path.path_join(file_name)))
			if data is Dictionary and data.has("id"):
				ids.append(data["id"])
	return ids


static func reload_data() -> void:
	_scenarios.clear()
	_loaded = true
	if not DirAccess.dir_exists_absolute(SCENARIO_DIR):
		push_warning("시나리오 폴더가 없습니다: %s" % SCENARIO_DIR)
		return
	var dirs: PackedStringArray = DirAccess.get_directories_at(SCENARIO_DIR)
	dirs.sort()
	for dir_name in dirs:
		var path: String = SCENARIO_DIR.path_join(dir_name).path_join("scenario.json")
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			push_warning("시나리오 JSON 파싱 실패: %s" % path)
			continue
		var errors: PackedStringArray = validate_scenario_dict(data)
		if data.get("id") != dir_name:
			errors.append("id(%s)와 폴더 이름(%s)이 다름" % [data.get("id"), dir_name])
		if not errors.is_empty():
			push_warning("시나리오 정의 오류 (%s): %s" % [path, "; ".join(errors)])
			continue
		_scenarios[dir_name] = data


static func _ensure_loaded() -> void:
	if not _loaded:
		reload_data()
