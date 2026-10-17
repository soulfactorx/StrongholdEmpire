class_name MartialArtLibrary
extends RefCounted

## id로 무공을 찾는 목록. resources/MartialArts/의 프리셋과 data/martial_arts/의 모드 무공을 모은다.

const PRESET_DIR := "res://resources/MartialArts/"

static var _arts: Dictionary = {}
static var _loaded: bool = false


static func has_art(art_id: String) -> bool:
	_ensure_loaded()
	return _arts.has(art_id)


## 원본을 보호하기 위해 복제본을 돌려준다.
static func create_art(art_id: String) -> MartialArtData:
	_ensure_loaded()
	var art: MartialArtData = _arts.get(art_id)
	return art.duplicate(true) if art else null


static func reload_data() -> void:
	_arts.clear()
	_loaded = true
	for file_name in DirAccess.get_files_at(PRESET_DIR):
		# 내보낸 빌드에서는 .tres가 .tres.remap으로 보인다.
		var resource_name: String = file_name.trim_suffix(".remap")
		if not resource_name.ends_with(".tres"):
			continue
		var art: MartialArtData = load(PRESET_DIR.path_join(resource_name)) as MartialArtData
		if art and not art.id.is_empty():
			_arts[art.id] = art
	for art in ModLoader.load_martial_arts_from_json():
		_arts[art.id] = art


static func _ensure_loaded() -> void:
	if not _loaded:
		reload_data()
