class_name EventManager
extends RefCounted

## 기연(이벤트) 시스템. 기연 내용은 data/events/*.json에 데이터로 정의하고,
## 이 클래스는 불러오기·검증·조건 판정·효과 적용만 담당한다.
##
## ■ 파일 형식
##   { "id", "title", "description", "can_repeat": bool,
##     "conditions": [조건...], "choices": [선택지...] }
##   선택지: { "label", "message", "effects": [효과...],
##            "branches": [{ "chance": 1~100, "message", "effects" }] (선택),
##            "success": bool (선택, 기본 true) }
##   branches는 위에서부터 확률을 굴려 처음 걸린 것을 쓰고, 모두 빗나가면 기본 효과를 쓴다.
##
## ■ 조건 (type별 필드)
##   character  field, op, value   — CHARACTER_FIELDS (martial_arts_count는 습득 무공 수)
##   sect       field, op, value   — SECT_FIELDS
##   bond       target, op, value  — 관계 대상의 유대 수치. 관계가 없으면 거짓
##   role       in: [역할 이름]     — CharacterData.Role 이름 (예: "SPY")
##   season     in: [계절]          — "봄" "여름" "가을" "겨울"
##   flag       flag, value        — 스토리 플래그 값 비교 (없으면 false로 간주)
##   world_sect sect, field, op, value — 강호 세력 수치 비교 (WORLD_SECT_FIELDS)
##   year       op, value          — 현재 연차 비교
##   turns_since_flag flag, op, value — 플래그가 켜진 뒤 지난 계절 수 비교 (켜진 적 없으면 거짓)
##   relationship_type target, bond_type — 해당 인물과의 관계 유형이 일치
##   role_history role, value       — 그 역할을 거쳐 왔는지 (value 생략 시 true)
##   scenario   in: [시나리오 id]   — 현재 시나리오가 목록에 있음
##   years_left op, value          — 시나리오 제한까지 남은 연수 (제한 없으면 9999)
##   subjugated_count op, value    — 굴복시킨 강호 세력 수
##   regions_owned op, value       — 강호 지도에서 우리 문파가 가진 땅 수 (본거지 포함)
##   generation op, value          — 현재 세대 (1세대부터)
##   role_state field, op, value   — 역할 자원 비교 (RoleActions.NUMERIC_FIELDS: discontent, trust, exposure, bounty ...)
##   (world_sect의 field에는 subjugated(0/1)도 쓸 수 있다)
##   op: ">=" "<=" ">" "<" "==" "!="
##
## ■ 효과 (type별 필드)
##   character   field, add        — 능력치 증감. 내공은 0~최대치로 제한
##   sect        field, add        — 문파 자원 증감. 0 미만으로 내려가지 않음
##   experience  amount            — 경험치 (레벨업 포함)
##   bond        target, add       — 유대 증감
##   flag        flag, value       — 스토리 플래그 설정
##   combat      combat            — 전투 시작 (CombatManager.create_by_id, 방어전이면 제자 합류)
##   world_sect  sect, field, add  — 강호 세력 수치 증감 (태도는 -100~100)
##   set_bond_type target, bond_type — 기존 관계의 유형을 바꾼다
##   add_relationship target, bond_type, strength — 명부 인물과 새 관계를 맺는다 (이미 있으면 무시)
##   learn_art   art               — 무공 습득 (MartialArtLibrary id)
##   end_game    ending            — 지정한 엔딩 또는 게임오버로 이야기를 끝낸다
##   role_state  field, add        — 역할 자원 증감 (0~100으로 제한)
##
## ■ 관계 대상 기연 (subject)
##   최상위 "subject"가 있으면 기연이 일어날 때 조건에 맞는 인물 하나를 고른다.
##   조건·효과의 target "$subject"가 그 인물이고, 제목·설명·선택지·결과 글의 {name}·{title}이 그 인물의 이름·호칭으로 바뀐다.
##   subject { bond_types: [관계 유형] — 그 관계인 인물 중에서,
##             stranger: true — 아직 관계가 없는 이름 있는 인물 중에서 (문주 제외),
##             min, max — 유대 범위 (bond_types일 때), sect: "same"|"other"|"none"|"any" — 인물의 소속,
##             min_age, max_age — 인물의 나이 }
##   bond_count bond_type, op, value — 그 관계인 인물 수 비교 (조건)
##   marry target                    — 연인(또는 누구든)을 배우자로 맞는다. 배우자는 여럿 둘 수 있다 (효과)
##   end_relationship target         — 관계를 끝낸다 (이별·사별, 효과)
##
## ■ 비급
##   gain_manual art — 비급을 얻는다 (무공 연구소에서 연구할 수 있게 됨). art가 "random"이면 아직 연구할 수 없고
##                     익히지도 않은 비급 중 하나 (효과)
##
## ■ 가중치
##   최상위 "weight"(기본 1): 발생 후보 중에서 뽑힐 상대적 확률. 스토리 핵심 기연은 높게 준다.
##   최상위 "priority"(기본 false): true면 조건을 채운 계절에 기연 발생 확률과 관계없이 먼저 일어난다.
##
## ■ 초상화
##   최상위 "npc"(선택): 팝업에 초상화를 보일 인물 id. 없으면 조건·효과에서 처음 나오는 명부 인물(target)을 쓴다.

const EVENTS_DIR := "res://data/events/"

const CHARACTER_FIELDS: PackedStringArray = [
	"strength", "agility", "wisdom", "charisma", "morality",
	"internal_energy_current", "internal_energy_max", "level", "age",
]
const CHARACTER_COMPUTED_FIELDS: PackedStringArray = ["martial_arts_count"]
const SECT_FIELDS: PackedStringArray = [
	"gold", "food", "reputation", "research_points", "disciple_count", "max_disciples",
	"library_level", "training_ground_level", "treasury_level",
	"apothecary_level", "meditation_hall_level",
]
const WORLD_SECT_FIELDS: PackedStringArray = ["attitude", "reputation", "disciple_count"]
## 조건에서만 쓰는 세력 필드 (효과로는 바꿀 수 없음)
const WORLD_SECT_CONDITION_FIELDS: PackedStringArray = ["subjugated"]
const OPERATORS: PackedStringArray = [">=", "<=", ">", "<", "==", "!="]
const SEASON_NAMES: PackedStringArray = ["봄", "여름", "가을", "겨울"]

static var _definitions: Array[EventData] = []
static var _loaded: bool = false


## 기연 판정에 쓰는 진행 상황. GameManager가 새 게임·불러오기·계절 진행 때 갱신한다.
static var world_sects: Array[SectData] = []
static var current_year: int = 1
## 연차 × 4 + 계절 순번
static var current_turn: int = 0
static var current_generation: int = 1
## 거쳐 온 역할 이름 (CharacterData.Role 키)
static var role_history: Array[String] = []
## 플래그 이름 → 켜진 계절(current_turn)
static var flag_turns: Dictionary = {}
## 역할 자원 (GameManager.role_state와 같은 객체)
static var role_state: Dictionary = {}
## 강호 지도 상태 (GameManager.map_state)와 플레이어 문파 id — regions_owned 조건
static var map_state: Dictionary = {}
static var player_sect_id: String = ""
## 금화·식량을 내고 받는 곳 (GameManager.get_wallet). 개인 재산을 쓰는 역할이면 주머니다.
## sect 조건·효과의 gold·food는 여기를 본다. null이면 문파.
static var wallet: SectData = null
## 가진 비급 (GameManager.owned_manuals와 같은 배열) — gain_manual 효과
static var owned_manuals: Array[String] = []
## 관계 대상 기연에서 지금 판정·적용 중인 대상 인물 ("$subject")
static var _subject: String = ""
## get_candidates가 관계 대상 기연마다 고른 대상 (기연 id → 인물 id)
static var _picked_subjects: Dictionary = {}

const SUBJECT_KEYS: PackedStringArray = ["bond_types", "stranger", "min", "max", "sect", "min_age", "max_age"]
const SUBJECT_SECTS: PackedStringArray = ["same", "other", "none", "any"]


## 스토리 플래그를 설정하고 켜진 계절을 기록한다. 플래그는 항상 이 함수로 설정한다.
static func set_flag(story_flags: Dictionary, flag: String, value: Variant = true) -> void:
	story_flags[flag] = value
	flag_turns[flag] = current_turn


## 지금 발생할 수 있는 기연 후보 전체 (가중치 추첨 전)
static func get_candidates(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	triggered_ids: Array[String],
	story_flags: Dictionary
) -> Array[EventData]:
	var pool: Array[EventData] = []
	_picked_subjects.clear()
	for event in get_definitions():
		if not event.can_repeat and triggered_ids.has(event.id):
			continue
		if event.subject.is_empty():
			if _conditions_met(event, character, sect, relationships, season, story_flags):
				pool.append(event)
			continue
		# 관계 대상 기연: 조건을 채우는 대상 중 하나를 고른다.
		var fits: Array[String] = []
		for subject_id in _subject_candidates(event.subject, relationships):
			_subject = subject_id
			if _conditions_met(event, character, sect, relationships, season, story_flags):
				fits.append(subject_id)
		_subject = ""
		if not fits.is_empty():
			_picked_subjects[event.id] = fits.pick_random()
			pool.append(event)
	return pool


## 관계 대상 기연의 대상 후보 인물 id
static func _subject_candidates(spec: Dictionary, relationships: Array[RelationshipData]) -> Array[String]:
	var result: Array[String] = []
	if spec.get("stranger", false) == true:
		for npc in NpcRoster.get_all():
			if not NpcRoster.is_listed(npc) or npc.get("role", "") == "LEADER":
				continue
			if RelationshipManager.get_bond_with(relationships, npc["id"]) == null and _subject_fits(spec, npc):
				result.append(npc["id"])
		return result
	var types: Array = spec.get("bond_types", [])
	for rel in relationships:
		if not types.is_empty() and not RelationshipData.BondType.keys()[rel.bond_type] in types:
			continue
		if rel.bond_strength < int(spec.get("min", 0)) or rel.bond_strength > int(spec.get("max", 100)):
			continue
		if NpcRoster.has_npc(rel.target_id) and _subject_fits(spec, NpcRoster.get_npc(rel.target_id)):
			result.append(rel.target_id)
	return result


static func _subject_fits(spec: Dictionary, npc: Dictionary) -> bool:
	var npc_sect: String = str(npc.get("sect_id", ""))
	match str(spec.get("sect", "any")):
		"same":
			if npc_sect != player_sect_id or npc_sect == NpcRoster.NO_SECT:
				return false
		"other":
			if npc_sect == player_sect_id or npc_sect == NpcRoster.NO_SECT:
				return false
		"none":
			if npc_sect != NpcRoster.NO_SECT:
				return false
	var age: int = int(npc.get("stats", {}).get("age", 30))
	return age >= int(spec.get("min_age", 0)) and age <= int(spec.get("max_age", 999))


## 조건·효과의 target: "$subject"면 지금 대상 인물
static func _target(entry: Dictionary) -> String:
	var target: String = str(entry.get("target", ""))
	return _subject if target == "$subject" else target


static func check_turn_events(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	triggered_ids: Array[String],
	story_flags: Dictionary
) -> Dictionary:
	var pool: Array[EventData] = get_candidates(character, sect, relationships, season, triggered_ids, story_flags)
	# 우선 기연이 있으면 그중에서만 고른다.
	var urgent: Array[EventData] = []
	for event in pool:
		if event.priority:
			urgent.append(event)
	if not urgent.is_empty():
		pool = urgent
		# 인물을 콕 집은 이야기 기연이 누구에게나 일어나는 관계 기연보다 먼저다.
		var named: Array[EventData] = urgent.filter(func(e: EventData) -> bool: return e.subject.is_empty())
		if not named.is_empty():
			pool = named
	if pool.is_empty():
		return {}

	var chosen: EventData = _pick_weighted(pool)
	if not chosen.can_repeat:
		triggered_ids.append(chosen.id)
	return chosen.to_popup_dict(str(_picked_subjects.get(chosen.id, "")))


static func resolve_choice(
	event_id: String,
	choice_index: int,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary,
	subject_id: String = ""
) -> Dictionary:
	var event: EventData = get_event(event_id)
	if event == null or choice_index < 0 or choice_index >= event.choices.size():
		return {"success": false, "message": "알 수 없는 기연입니다."}

	var choice: Dictionary = event.choices[choice_index]
	var effects: Array = choice.get("effects", [])
	var message: String = choice.get("message", "")
	for branch in choice.get("branches", []):
		if randi_range(1, 100) <= int(branch.get("chance", 0)):
			effects = branch.get("effects", [])
			message = branch.get("message", message)
			break

	var result: Dictionary = {
		"success": choice.get("success", true),
		"message": EventData.fill_text(message, subject_id),
	}
	_subject = subject_id
	for effect in effects:
		_apply_effect(effect, character, sect, relationships, story_flags, result)
	_subject = ""
	return result


static func _pick_weighted(pool: Array[EventData]) -> EventData:
	var total: float = 0.0
	for event in pool:
		total += event.weight
	var roll: float = randf() * total
	for event in pool:
		roll -= event.weight
		if roll < 0.0:
			return event
	return pool[-1]


static func get_definitions() -> Array[EventData]:
	if not _loaded:
		reload_definitions()
	return _definitions


static func get_event(event_id: String) -> EventData:
	for event in get_definitions():
		if event.id == event_id:
			return event
	return null


## 기연 폴더를 다시 읽는다. extra_dirs(시나리오 전용 기연 등)가 있으면 이어서 읽는다.
## 잘못된 파일과 중복 id는 경고를 남기고 건너뛴다.
static func reload_definitions(dir_path: String = EVENTS_DIR, extra_dirs: Array = []) -> void:
	_definitions.clear()
	_loaded = true
	var seen_ids: Dictionary = {}
	for i in extra_dirs.size() + 1:
		var current_dir: String = dir_path if i == 0 else str(extra_dirs[i - 1])
		if i > 0 and not DirAccess.dir_exists_absolute(current_dir):
			continue
		if not DirAccess.dir_exists_absolute(current_dir):
			push_warning("기연 폴더를 열 수 없습니다: %s" % current_dir)
			continue
		for path in collect_json_files(current_dir):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not data is Dictionary:
				push_warning("기연 JSON 파싱 실패: %s" % path)
				continue
			var errors: PackedStringArray = validate_event_dict(data)
			if seen_ids.has(data.get("id")):
				errors.append("중복된 id: %s" % data.get("id"))
			if not errors.is_empty():
				push_warning("기연 정의 오류 (%s): %s" % [path, "; ".join(errors)])
				continue
			seen_ids[data["id"]] = true
			_definitions.append(_to_event_data(data))


## 폴더와 하위 폴더(스토리 아크 등)의 JSON 파일 경로를 이름순으로 모은다.
static func collect_json_files(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var files: PackedStringArray = DirAccess.get_files_at(dir_path)
	files.sort()
	for file_name in files:
		if file_name.ends_with(".json"):
			result.append(dir_path.path_join(file_name))
	var dirs: PackedStringArray = DirAccess.get_directories_at(dir_path)
	dirs.sort()
	for sub_dir in dirs:
		result.append_array(collect_json_files(dir_path.path_join(sub_dir)))
	return result


## 기연 정의 하나를 검사해 오류 메시지 목록을 돌려준다. 비어 있으면 정상이다.
static func validate_event_dict(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in ["id", "title", "description"]:
		if not data.get(key) is String or String(data.get(key)).is_empty():
			errors.append("'%s'가 비어 있음" % key)
	if data.has("npc") and not NpcRoster.has_npc(str(data["npc"])):
		errors.append("명부에 없는 인물(npc): %s" % data["npc"])
	if data.has("priority") and not data["priority"] is bool:
		errors.append("priority는 true/false여야 함")
	if data.has("weight") and not ((data["weight"] is float or data["weight"] is int) and data["weight"] > 0):
		errors.append("weight는 0보다 큰 숫자여야 함")
	if data.has("subject"):
		_validate_subject(data["subject"], errors)
	elif JSON.stringify(data).contains("$subject"):
		errors.append("$subject를 쓰려면 subject가 필요함")
	validate_conditions(data.get("conditions", []), errors)
	var choices: Variant = data.get("choices")
	if not choices is Array or (choices as Array).is_empty():
		errors.append("choices가 비어 있음")
		return errors
	for i in (choices as Array).size():
		var choice: Variant = choices[i]
		if not choice is Dictionary or not choice.get("label") is String:
			errors.append("선택지 %d: label 필요" % i)
			continue
		for effect in choice.get("effects", []):
			_validate_effect(effect, errors)
		for branch in choice.get("branches", []):
			if not branch is Dictionary or not branch.has("chance"):
				errors.append("선택지 %d: branch에 chance 필요" % i)
				continue
			for effect in branch.get("effects", []):
				_validate_effect(effect, errors)
	return errors


static func _validate_subject(spec: Variant, errors: PackedStringArray) -> void:
	if not spec is Dictionary:
		errors.append("subject는 객체여야 함")
		return
	for key in spec:
		if not key in SUBJECT_KEYS:
			errors.append("알 수 없는 subject 필드: %s" % key)
	for type_key in spec.get("bond_types", []):
		if not RelationshipData.BondType.has(str(type_key)):
			errors.append("알 수 없는 관계 유형: %s" % type_key)
	if spec.has("sect") and not str(spec["sect"]) in SUBJECT_SECTS:
		errors.append("알 수 없는 subject sect: %s" % spec["sect"])
	if spec.get("stranger", false) != true and not spec.has("bond_types"):
		errors.append("subject에 bond_types나 stranger 필요")


static func _validate_condition(condition: Variant, errors: PackedStringArray) -> void:
	if not condition is Dictionary:
		errors.append("조건은 객체여야 함")
		return
	var c: Dictionary = condition
	match c.get("type", ""):
		"character":
			if not (c.get("field") in CHARACTER_FIELDS or c.get("field") in CHARACTER_COMPUTED_FIELDS):
				errors.append("알 수 없는 캐릭터 필드: %s" % c.get("field"))
			_validate_compare(c, errors)
		"sect":
			if not c.get("field") in SECT_FIELDS:
				errors.append("알 수 없는 문파 필드: %s" % c.get("field"))
			_validate_compare(c, errors)
		"bond":
			if not c.get("target") is String:
				errors.append("bond 조건에 target 필요")
			_validate_compare(c, errors)
		"role":
			for role_name in c.get("in", []):
				if not CharacterData.Role.has(role_name):
					errors.append("알 수 없는 역할: %s" % role_name)
		"season":
			for season in c.get("in", []):
				if not season in SEASON_NAMES:
					errors.append("알 수 없는 계절: %s" % season)
		"flag":
			if not c.get("flag") is String:
				errors.append("flag 조건에 flag 필요")
		"world_sect":
			_validate_world_sect(c, errors, true)
			_validate_compare(c, errors)
		"year":
			_validate_compare(c, errors)
		"turns_since_flag":
			if not c.get("flag") is String:
				errors.append("turns_since_flag 조건에 flag 필요")
			_validate_compare(c, errors)
		"relationship_type":
			if not c.get("target") is String:
				errors.append("relationship_type 조건에 target 필요")
			_validate_bond_type(c, errors)
		"bond_count":
			_validate_bond_type(c, errors)
			_validate_compare(c, errors)
		"role_history":
			if not CharacterData.Role.has(c.get("role", "")):
				errors.append("알 수 없는 역할: %s" % c.get("role"))
		"scenario":
			if not c.get("in") is Array or (c.get("in") as Array).is_empty():
				errors.append("scenario 조건에 in 목록 필요")
		"years_left", "subjugated_count", "generation", "regions_owned":
			_validate_compare(c, errors)
		"role_state":
			if not c.get("field") in RoleActions.NUMERIC_FIELDS:
				errors.append("알 수 없는 역할 자원: %s" % c.get("field"))
			_validate_compare(c, errors)
		_:
			errors.append("알 수 없는 조건 type: %s" % c.get("type"))


static func _validate_compare(c: Dictionary, errors: PackedStringArray) -> void:
	if not c.get("op") in OPERATORS:
		errors.append("알 수 없는 비교 연산자: %s" % c.get("op"))
	if not (c.get("value") is float or c.get("value") is int):
		errors.append("비교 값은 숫자여야 함")


static func _validate_effect(effect: Variant, errors: PackedStringArray) -> void:
	if not effect is Dictionary:
		errors.append("효과는 객체여야 함")
		return
	var e: Dictionary = effect
	match e.get("type", ""):
		"character":
			if not e.get("field") in CHARACTER_FIELDS:
				errors.append("알 수 없는 캐릭터 필드: %s" % e.get("field"))
		"sect":
			if not e.get("field") in SECT_FIELDS:
				errors.append("알 수 없는 문파 필드: %s" % e.get("field"))
		"experience":
			if not e.has("amount"):
				errors.append("experience 효과에 amount 필요")
		"bond":
			if not e.get("target") is String:
				errors.append("bond 효과에 target 필요")
		"flag":
			if not e.get("flag") is String:
				errors.append("flag 효과에 flag 필요")
		"combat":
			if not CombatManager.has_combat(e.get("combat", "")):
				errors.append("알 수 없는 전투: %s" % e.get("combat"))
		"world_sect":
			_validate_world_sect(e, errors)
		"set_bond_type":
			if not e.get("target") is String:
				errors.append("set_bond_type 효과에 target 필요")
			_validate_bond_type(e, errors)
		"add_relationship":
			if not NpcRoster.has_npc(str(e.get("target", ""))) and e.get("target") != "$subject":
				errors.append("명부에 없는 인물: %s" % e.get("target"))
			_validate_bond_type(e, errors)
		"gain_manual":
			var manual: String = str(e.get("art", ""))
			if manual != "random" and not MartialArtLibrary.has_art(manual):
				errors.append("알 수 없는 비급: %s" % manual)
		"marry", "end_relationship":
			if not e.get("target") is String:
				errors.append("%s 효과에 target 필요" % e.get("type"))
		"learn_art":
			if not MartialArtLibrary.has_art(str(e.get("art", ""))):
				errors.append("알 수 없는 무공: %s" % e.get("art"))
		"role_state":
			if not e.get("field") in RoleActions.NUMERIC_FIELDS:
				errors.append("알 수 없는 역할 자원: %s" % e.get("field"))
		"end_game":
			var ending: String = str(e.get("ending", ""))
			if not (EndingManager.has_ending(ending) or EndingManager.GAME_OVERS.has(ending)):
				errors.append("알 수 없는 엔딩: %s" % ending)
		_:
			errors.append("알 수 없는 효과 type: %s" % e.get("type"))


static func _validate_bond_type(entry: Dictionary, errors: PackedStringArray) -> void:
	if not RelationshipData.BondType.has(entry.get("bond_type", "")):
		errors.append("알 수 없는 관계 유형: %s" % entry.get("bond_type"))


static func _validate_world_sect(entry: Dictionary, errors: PackedStringArray, is_condition: bool = false) -> void:
	var sect_id: String = str(entry.get("sect", ""))
	if not SectRegistry.has_sect(sect_id) or SectRegistry.get_sect_info(sect_id).get("is_player_sect", false):
		errors.append("알 수 없는 강호 세력: %s" % sect_id)
	var allowed: bool = entry.get("field") in WORLD_SECT_FIELDS
	if is_condition:
		allowed = allowed or entry.get("field") in WORLD_SECT_CONDITION_FIELDS
	if not allowed:
		errors.append("알 수 없는 세력 필드: %s" % entry.get("field"))


static func _find_world_sect(sect_id: String) -> SectData:
	for sect in world_sects:
		if sect.id == sect_id:
			return sect
	return null


## 초상화를 보일 인물: 조건·효과에서 처음 나오는 명부의 인물 (target·npc 값). 없으면 ""
static func _infer_npc(data: Dictionary) -> String:
	var found: Array[String] = []
	_collect_npc_ids(data.get("conditions", []), found)
	_collect_npc_ids(data.get("choices", []), found)
	return found[0] if not found.is_empty() else ""


static func _collect_npc_ids(value: Variant, found: Array[String]) -> void:
	if not found.is_empty():
		return
	if value is Dictionary:
		for key in ["target", "npc"]:
			if value.get(key) is String and NpcRoster.has_npc(value[key]):
				found.append(value[key])
				return
		for key in value:
			_collect_npc_ids(value[key], found)
	elif value is Array:
		for item in value:
			_collect_npc_ids(item, found)


static func _to_event_data(data: Dictionary) -> EventData:
	var event := EventData.new()
	event.id = data["id"]
	event.title = data["title"]
	event.description = data["description"]
	event.can_repeat = data.get("can_repeat", false)
	event.weight = float(data.get("weight", 1.0))
	event.priority = data.get("priority", false) == true
	event.npc = str(data.get("npc", _infer_npc(data)))
	event.subject = data.get("subject", {})
	for condition in data.get("conditions", []):
		event.conditions.append(condition)
	for choice in data["choices"]:
		event.choices.append(choice)
	return event


static func _conditions_met(
	event: EventData,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	story_flags: Dictionary
) -> bool:
	return conditions_met(event.conditions, character, sect, relationships, season, story_flags)


## 조건 목록을 모두 만족하는지. 기연 외에 엔딩 판정에서도 쓴다.
static func conditions_met(
	conditions: Array,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	story_flags: Dictionary
) -> bool:
	for c in conditions:
		if not _condition_met(c, character, sect, relationships, season, story_flags):
			return false
	return true


## 조건 목록을 검사해 오류를 errors에 더한다. 기연 외에 엔딩 정의 검증에서도 쓴다.
static func validate_conditions(conditions: Variant, errors: PackedStringArray) -> void:
	if not conditions is Array:
		errors.append("conditions는 배열이어야 함")
		return
	for condition in conditions:
		_validate_condition(condition, errors)


static func _condition_met(
	c: Dictionary,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	story_flags: Dictionary
) -> bool:
	match c["type"]:
		"character":
			var value: int
			if c["field"] == "martial_arts_count":
				value = character.martial_arts.size()
			else:
				value = character.get(c["field"])
			return _compare(value, c["op"], c["value"])
		"sect":
			return _compare(_money_target(sect, c["field"]).get(c["field"]), c["op"], c["value"])
		"bond":
			var bond: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(c))
			return bond != null and _compare(bond.bond_strength, c["op"], c["value"])
		"bond_count":
			return _compare(RelationshipManager.count_type(relationships, RelationshipData.BondType.get(c["bond_type"])), c["op"], c["value"])
		"role":
			return str(CharacterData.Role.find_key(character.role)) in c["in"]
		"season":
			return season in c["in"]
		"flag":
			return story_flags.get(c["flag"], false) == c.get("value", true)
		"world_sect":
			var world_sect: SectData = _find_world_sect(c["sect"])
			return world_sect != null and _compare(int(world_sect.get(c["field"])), c["op"], c["value"])
		"year":
			return _compare(current_year, c["op"], c["value"])
		"turns_since_flag":
			if not flag_turns.has(c["flag"]) or not story_flags.get(c["flag"], false):
				return false
			return _compare(current_turn - int(flag_turns[c["flag"]]), c["op"], c["value"])
		"relationship_type":
			var rel: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(c))
			return rel != null and rel.bond_type == RelationshipData.BondType.get(c["bond_type"])
		"role_history":
			return role_history.has(c["role"]) == c.get("value", true)
		"scenario":
			return ScenarioManager.current_id in c["in"]
		"years_left":
			return _compare(ScenarioRules.years_left(current_year), c["op"], c["value"])
		"regions_owned":
			return _compare(WorldMap.count(map_state, player_sect_id), c["op"], c["value"])
		"subjugated_count":
			var count: int = 0
			for world_sect in world_sects:
				if world_sect.subjugated:
					count += 1
			return _compare(count, c["op"], c["value"])
		"generation":
			return _compare(current_generation, c["op"], c["value"])
		"role_state":
			return _compare(int(role_state.get(c["field"], 0)), c["op"], c["value"])
	return false


## 금화·식량은 지갑(개인 재산이면 주머니), 그 밖의 문파 수치는 문파
static func _money_target(sect: SectData, field: String) -> SectData:
	return wallet if wallet != null and field in ["gold", "food"] else sect


## 얻을 비급이 남지 않았을 때 대신 주는 연구점
const NO_MANUAL_RESEARCH := 20


## 비급을 owned에 더한다. "random"이면 available(이미 연구할 수 있는 것)·owned·익힌 무공이 아닌 것 중 하나.
## 얻은 비급 이름을 돌려준다 (이미 있거나 남은 것이 없으면 "").
static func gain_manual(art_id: String, owned: Array[String], character: CharacterData, available: Array = []) -> String:
	if art_id == "random":
		var pool: Array[String] = []
		for art in MartialArtLibrary.get_all():
			if not owned.has(art.id) and not available.has(art.id) and not character.knows_martial_art(art.id):
				pool.append(art.id)
		if pool.is_empty():
			return ""
		art_id = pool.pick_random()
	if not MartialArtLibrary.has_art(art_id) or owned.has(art_id):
		return ""
	owned.append(art_id)
	return MartialArtLibrary.create_art(art_id).display_name


static func _compare(actual: float, op: String, expected: float) -> bool:
	match op:
		">=":
			return actual >= expected
		"<=":
			return actual <= expected
		">":
			return actual > expected
		"<":
			return actual < expected
		"==":
			return is_equal_approx(actual, expected)
		"!=":
			return not is_equal_approx(actual, expected)
	return false


static func _apply_effect(
	e: Dictionary,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary,
	result: Dictionary
) -> void:
	match e["type"]:
		"character":
			var field: String = e["field"]
			var new_value: int = int(character.get(field)) + int(e.get("add", 0))
			if field == "internal_energy_current":
				new_value = clampi(new_value, 0, character.internal_energy_max)
			character.set(field, new_value)
		"sect":
			var field: String = e["field"]
			var target: SectData = _money_target(sect, field)
			target.set(field, maxi(0, int(target.get(field)) + int(e.get("add", 0))))
		"experience":
			character.gain_experience(int(e["amount"]))
		"bond":
			var bond: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(e))
			if bond:
				bond.increase_bond(int(e.get("add", 0)))
		"flag":
			set_flag(story_flags, e["flag"], e.get("value", true))
		"combat":
			result["combat"] = CombatManager.create_by_id(e["combat"], character, sect)
		"world_sect":
			var world_sect: SectData = _find_world_sect(e["sect"])
			if world_sect:
				var value: int = int(world_sect.get(e["field"])) + int(e.get("add", 0))
				if e["field"] == "attitude":
					value = clampi(value, -100, 100)
				else:
					value = maxi(0, value)
				world_sect.set(e["field"], value)
		"set_bond_type":
			var rel: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(e))
			if rel:
				rel.bond_type = RelationshipData.BondType.get(e["bond_type"])
		"add_relationship":
			var target_id: String = _target(e)
			if NpcRoster.has_npc(target_id) and RelationshipManager.get_bond_with(relationships, target_id) == null:
				relationships.append(RelationshipManager.make_relationship(target_id, e["bond_type"], int(e.get("strength", 10))))
		"marry":
			var rel: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(e))
			if rel and rel.bond_type != RelationshipData.BondType.SPOUSE:
				var wedding: String = RelationshipManager.marry(relationships, rel, world_sects)
				result["message"] = (str(result.get("message", "")) + " " + wedding).strip_edges()
				set_flag(story_flags, "married")
		"end_relationship":
			var rel: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(e))
			if rel:
				relationships.erase(rel)
		"gain_manual":
			var library: Array = SectRegistry.get_sect_info(sect.id).get("manuals", []) if SectRegistry.has_sect(sect.id) else []
			var gained: String = gain_manual(str(e["art"]), owned_manuals, character, library)
			var note: String = "비급 [%s]을(를) 얻었습니다. 무공 연구소에서 연구할 수 있습니다." % gained if not gained.is_empty() \
				else "새로 얻을 비급이 없었습니다. 대신 연구점 +%d" % NO_MANUAL_RESEARCH
			if gained.is_empty():
				sect.research_points += NO_MANUAL_RESEARCH
			result["message"] = (str(result.get("message", "")) + " " + note).strip_edges()
		"learn_art":
			var art: MartialArtData = MartialArtLibrary.create_art(e["art"])
			if art:
				character.learn_martial_art(art)
		"end_game":
			result["end_game"] = e["ending"]
		"role_state":
			if role_state.has(e["field"]):
				role_state[e["field"]] = clampi(int(role_state[e["field"]]) + int(e.get("add", 0)), 0, 100)
