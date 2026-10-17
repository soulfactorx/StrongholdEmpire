class_name SectRegistry
extends RefCounted

## 문파 데이터. data/sects/*.json 한 파일이 한 문파다.
## is_player_sect가 true인 문파 하나가 플레이어 문파가 되고, 나머지는 강호의 다른 세력이 된다.
##
## 필드: id, sect_name, alignment(SectData.Alignment 이름), leader_id(NPC id), description,
##       is_player_sect(선택), 그리고 SectData의 수치 필드(reputation, disciple_count 등)

const SECT_DIR := "res://data/sects/"
const NUMERIC_FIELDS: PackedStringArray = [
	"gold", "food", "reputation", "research_points", "disciple_count", "max_disciples",
	"library_level", "training_ground_level", "treasury_level", "attitude",
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


static func create_player_sect() -> SectData:
	_ensure_loaded()
	for id in _sects:
		if _sects[id].get("is_player_sect", false):
			return create_sect(id)
	push_warning("플레이어 문파 데이터가 없습니다. 기본값을 씁니다.")
	return SectData.new()


## 플레이어 문파를 제외한 강호의 세력들
static func create_rival_sects() -> Array[SectData]:
	_ensure_loaded()
	var result: Array[SectData] = []
	for id in _sects:
		if not _sects[id].get("is_player_sect", false):
			result.append(create_sect(id))
	return result


static func create_sect(sect_id: String) -> SectData:
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
		]):
			errors.append("알 수 없는 필드: %s" % key)
	return errors


static func reload(dir_path: String = SECT_DIR) -> void:
	_sects.clear()
	_loaded = true
	for data in ModLoader.load_json_dir(dir_path):
		var errors: PackedStringArray = validate_sect_dict(data)
		if _sects.has(data.get("id")):
			errors.append("중복된 id")
		if not errors.is_empty():
			push_warning("문파 정의 오류 (%s): %s" % [data["_path"], "; ".join(errors)])
			continue
		_sects[data["id"]] = data


static func _ensure_loaded() -> void:
	if not _loaded:
		reload()
