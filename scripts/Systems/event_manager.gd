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

const EVENTS_DIR := "res://data/events/"

const CHARACTER_FIELDS: PackedStringArray = [
	"strength", "agility", "wisdom", "charisma", "morality",
	"internal_energy_current", "internal_energy_max", "level", "age",
]
const CHARACTER_COMPUTED_FIELDS: PackedStringArray = ["martial_arts_count"]
const SECT_FIELDS: PackedStringArray = [
	"gold", "food", "reputation", "research_points", "disciple_count", "max_disciples",
	"library_level", "training_ground_level", "treasury_level",
]
const WORLD_SECT_FIELDS: PackedStringArray = ["attitude", "reputation", "disciple_count"]
const OPERATORS: PackedStringArray = [">=", "<=", ">", "<", "==", "!="]
const SEASON_NAMES: PackedStringArray = ["봄", "여름", "가을", "겨울"]

static var _definitions: Array[EventData] = []
static var _loaded: bool = false


## 조건·효과에서 강호 세력을 찾을 때 쓰는 목록. GameManager가 새 게임·불러오기 때 지정한다.
static var world_sects: Array[SectData] = []


static func check_turn_events(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	triggered_ids: Array[String],
	story_flags: Dictionary
) -> Dictionary:
	var pool: Array[EventData] = []
	for event in get_definitions():
		if not event.can_repeat and triggered_ids.has(event.id):
			continue
		if _conditions_met(event, character, sect, relationships, season, story_flags):
			pool.append(event)
	if pool.is_empty():
		return {}

	var chosen: EventData = pool[randi() % pool.size()]
	if not chosen.can_repeat:
		triggered_ids.append(chosen.id)
	return chosen.to_popup_dict()


static func resolve_choice(
	event_id: String,
	choice_index: int,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary
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
		"message": message,
	}
	for effect in effects:
		_apply_effect(effect, character, sect, relationships, story_flags, result)
	return result


static func get_definitions() -> Array[EventData]:
	if not _loaded:
		reload_definitions()
	return _definitions


static func get_event(event_id: String) -> EventData:
	for event in get_definitions():
		if event.id == event_id:
			return event
	return null


## 기연 폴더를 다시 읽는다. 잘못된 파일은 경고를 남기고 건너뛴다.
static func reload_definitions(dir_path: String = EVENTS_DIR) -> void:
	_definitions.clear()
	_loaded = true
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("기연 폴더를 열 수 없습니다: %s" % dir_path)
		return
	var files: PackedStringArray = dir.get_files()
	files.sort()
	var seen_ids: Dictionary = {}
	for file_name in files:
		if not file_name.ends_with(".json"):
			continue
		var path: String = dir_path.path_join(file_name)
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


## 기연 정의 하나를 검사해 오류 메시지 목록을 돌려준다. 비어 있으면 정상이다.
static func validate_event_dict(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in ["id", "title", "description"]:
		if not data.get(key) is String or String(data.get(key)).is_empty():
			errors.append("'%s'가 비어 있음" % key)
	if not data.get("conditions", []) is Array:
		errors.append("conditions는 배열이어야 함")
	else:
		for condition in data.get("conditions", []):
			_validate_condition(condition, errors)
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
			_validate_world_sect(c, errors)
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
		_:
			errors.append("알 수 없는 효과 type: %s" % e.get("type"))


static func _validate_world_sect(entry: Dictionary, errors: PackedStringArray) -> void:
	var sect_id: String = str(entry.get("sect", ""))
	if not SectRegistry.has_sect(sect_id) or SectRegistry.get_sect_info(sect_id).get("is_player_sect", false):
		errors.append("알 수 없는 강호 세력: %s" % sect_id)
	if not entry.get("field") in WORLD_SECT_FIELDS:
		errors.append("알 수 없는 세력 필드: %s" % entry.get("field"))


static func _find_world_sect(sect_id: String) -> SectData:
	for sect in world_sects:
		if sect.id == sect_id:
			return sect
	return null


static func _to_event_data(data: Dictionary) -> EventData:
	var event := EventData.new()
	event.id = data["id"]
	event.title = data["title"]
	event.description = data["description"]
	event.can_repeat = data.get("can_repeat", false)
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
	for c in event.conditions:
		if not _condition_met(c, character, sect, relationships, season, story_flags):
			return false
	return true


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
			return _compare(sect.get(c["field"]), c["op"], c["value"])
		"bond":
			var bond: RelationshipData = RelationshipManager.get_bond_with(relationships, c["target"])
			return bond != null and _compare(bond.bond_strength, c["op"], c["value"])
		"role":
			return str(CharacterData.Role.find_key(character.role)) in c["in"]
		"season":
			return season in c["in"]
		"flag":
			return story_flags.get(c["flag"], false) == c.get("value", true)
		"world_sect":
			var world_sect: SectData = _find_world_sect(c["sect"])
			return world_sect != null and _compare(world_sect.get(c["field"]), c["op"], c["value"])
	return false


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
			sect.set(field, maxi(0, int(sect.get(field)) + int(e.get("add", 0))))
		"experience":
			character.gain_experience(int(e["amount"]))
		"bond":
			var bond: RelationshipData = RelationshipManager.get_bond_with(relationships, e["target"])
			if bond:
				bond.increase_bond(int(e.get("add", 0)))
		"flag":
			story_flags[e["flag"]] = e.get("value", true)
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
