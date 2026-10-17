class_name SectRegistry
extends RefCounted

## 문파 데이터. data/sects/*.json 한 파일이 한 문파다.
## is_player_sect가 true인 문파 하나가 플레이어 문파가 되고, 나머지는 강호의 다른 세력이 된다.
##
## 필드: id, sect_name, alignment(SectData.Alignment 이름), leader_id(NPC id), description,
##       is_player_sect(선택), 그리고 SectData의 수치 필드(reputation, disciple_count 등)
##       war_tactics(선택) { 명령: 가중치 }, war_formation(선택) CRANE/FISH/CIRCLE/NONE
##       — 없으면 성향별 기본값(GameBalance.WAR_TACTICS, WAR_FORMATIONS)

const SECT_DIR := "res://data/sects/"
const NUMERIC_FIELDS: PackedStringArray = [
	"gold", "food", "reputation", "research_points", "disciple_count", "max_disciples",
	"library_level", "training_ground_level", "treasury_level",
	"apothecary_level", "meditation_hall_level", "attitude",
]

static var _sects: Dictionary = {}
static var _loaded: bool = false


static func has_sect(sect_id: String) -> bool:
	_ensure_loaded()
	return _sects.has(sect_id)


static func get_sect_info(sect_id: String) -> Dictionary:
	_ensure_loaded()
	return _sects.get(sect_id, {})


static func get_description(sect_id: String) -> String:
	return get_sect_info(sect_id).get("description", "")


## is_player_sect인 문파 id (없으면 빈 문자열)
static func get_player_sect_id() -> String:
	_ensure_loaded()
	for id in _sects:
		if _sects[id].get("is_player_sect", false):
			return id
	return ""


## sect_id가 비어 있으면 is_player_sect인 문파를 쓴다. overrides로 수치를 덮어쓴다.
static func create_player_sect(sect_id: String = "", overrides: Dictionary = {}) -> SectData:
	_ensure_loaded()
	if sect_id.is_empty():
		sect_id = get_player_sect_id()
	if not _sects.has(sect_id):
		push_warning("플레이어 문파 데이터가 없습니다. 기본값을 씁니다.")
		return SectData.new()
	return create_sect(sect_id, overrides)


## 강호의 세력들. ids가 비어 있으면 플레이어 문파를 뺀 전부.
## overrides: { 문파 id: { 필드: 값 } }
static func create_rival_sects(ids: Array = [], overrides: Dictionary = {}) -> Array[SectData]:
	_ensure_loaded()
	var result: Array[SectData] = []
	var sect_ids: Array = ids.duplicate()
	if sect_ids.is_empty():
		for id in _sects:
			if not _sects[id].get("is_player_sect", false):
				sect_ids.append(id)
	for id in sect_ids:
		if _sects.has(id):
			result.append(create_sect(id, overrides.get(id, {})))
	return result


static func create_sect(sect_id: String, overrides: Dictionary = {}) -> SectData:
	var data: Dictionary = get_sect_info(sect_id)
	var sect := SectData.new()
	sect.id = sect_id
	sect.sect_name = data.get("sect_name", sect.sect_name)
	sect.alignment = SectData.Alignment.get(data.get("alignment", ""), SectData.Alignment.RIGHTEOUS)
	sect.leader_id = data.get("leader_id", "")
	sect.leader_name = NpcRoster.get_display_name(sect.leader_id)
	for key in NUMERIC_FIELDS:
		if data.has(key):
			sect.set(key, int(data[key]))
	for key in overrides:
		if key in NUMERIC_FIELDS:
			sect.set(key, int(overrides[key]))
	return sect


static func validate_sect_dict(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in ["id", "sect_name", "leader_id"]:
		if not data.get(key) is String or String(data.get(key)).is_empty():
			errors.append("'%s'가 비어 있음" % key)
	if not SectData.Alignment.has(data.get("alignment", "")):
		errors.append("알 수 없는 성향: %s" % data.get("alignment"))
	if not NpcRoster.has_npc(data.get("leader_id", "")):
		errors.append("명부에 없는 문주: %s" % data.get("leader_id"))
	for key in data:
		if not (key in NUMERIC_FIELDS or key in [
			"id", "sect_name", "alignment", "leader_id", "description", "is_player_sect", "_path",
			"war_tactics", "war_formation",
		]):
			errors.append("알 수 없는 필드: %s" % key)
	var tactics: Variant = data.get("war_tactics", {})
	if not tactics is Dictionary:
		errors.append("war_tactics는 { 명령: 가중치 } 형식이어야 함")
	else:
		for command in tactics:
			if not command in ["CHARGE", "DEFEND", "FLANK", "RETREAT"]:
				errors.append("알 수 없는 문파전 명령: %s" % command)
			elif not ((tactics[command] is float or tactics[command] is int) and tactics[command] >= 0):
				errors.append("war_tactics 가중치는 0 이상의 숫자여야 함")
	if data.has("war_formation") and not data["war_formation"] in ["NONE", "CRANE", "FISH", "CIRCLE"]:
		errors.append("알 수 없는 진형: %s" % data["war_formation"])
	return errors


## extra_dirs(시나리오 전용 문파 등)가 있으면 이어서 읽는다.
static func reload_data(dir_path: String = SECT_DIR, extra_dirs: Array = []) -> void:
	_sects.clear()
	_loaded = true
	var entries: Array[Dictionary] = ModLoader.load_json_dir(dir_path)
	for extra in extra_dirs:
		if DirAccess.dir_exists_absolute(str(extra)):
			entries.append_array(ModLoader.load_json_dir(str(extra)))
	for data in entries:
		var errors: PackedStringArray = validate_sect_dict(data)
		if _sects.has(data.get("id")):
			errors.append("중복된 id")
		if not errors.is_empty():
			push_warning("문파 정의 오류 (%s): %s" % [data["_path"], "; ".join(errors)])
			continue
		_sects[data["id"]] = data


static func _ensure_loaded() -> void:
	if not _loaded:
		reload_data()
