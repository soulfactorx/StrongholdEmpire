class_name ModLoader
extends RefCounted

const MOD_DIRS: Array[String] = [
	"res://data/martial_arts/",
	"res://data/events/",
]


## 폴더의 JSON 파일을 이름순으로 읽어 객체 목록으로 돌려준다.
## 파싱에 실패한 파일은 경고를 남기고 건너뛴다. 각 객체에 "_path"로 원본 경로를 넣는다.
static func load_json_dir(dir_path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		push_warning("데이터 폴더가 없습니다: %s" % dir_path)
		return result
	var files: PackedStringArray = DirAccess.get_files_at(dir_path)
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".json"):
			continue
		var path: String = dir_path.path_join(file_name)
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			push_warning("JSON 파싱 실패: %s" % path)
			continue
		data["_path"] = path
		result.append(data)
	return result


static func load_martial_arts_from_json() -> Array[MartialArtData]:
	var arts: Array[MartialArtData] = []
	var dir := DirAccess.open("res://data/martial_arts/")
	if dir == null:
		return arts

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var path: String = "res://data/martial_arts/%s" % file_name
			var art: MartialArtData = _parse_martial_art_json(path)
			if art:
				arts.append(art)
		file_name = dir.get_next()
	dir.list_dir_end()
	return arts


static func _parse_martial_art_json(path: String) -> MartialArtData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return null
	var data: Dictionary = json.data
	if not data.has("id") or not data.has("display_name"):
		return null

	var art := MartialArtData.new()
	art.id = data.get("id", "")
	art.display_name = data.get("display_name", "")
	art.category = data.get("category", MartialArtData.Category.SWORD)
	art.element = data.get("element", MartialArtData.FiveElement.NONE)
	art.yin_yang = data.get("yin_yang", MartialArtData.YinYang.BALANCED)
	art.research_cost = data.get("research_cost", 30)
	art.complexity = data.get("complexity", 2)
	art.damage = data.get("damage", 10)
	art.internal_cost = data.get("internal_cost", 15)
	art.action_cost = data.get("action_cost", 2)
	art.range = data.get("range", 1)
	art.heal_amount = data.get("heal_amount", 0)
	art.move_bonus = data.get("move_bonus", 0)
	art.card_type = str(data.get("card_type", ""))
	art.description = data.get("description", "")
	for effect in data.get("effects", []):
		art.special_effects.append(effect as MartialArtData.SpecialEffect)
	return art