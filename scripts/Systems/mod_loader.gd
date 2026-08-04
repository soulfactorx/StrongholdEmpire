class_name ModLoader
extends RefCounted

const MOD_DIRS: Array[String] = [
	"res://data/martial_arts/",
	"res://data/events/",
]


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
	art.description = data.get("description", "")
	for effect in data.get("effects", []):
		art.special_effects.append(effect as MartialArtData.SpecialEffect)
	return art