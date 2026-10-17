class_name ArtAssets
extends RefCounted

## 그림 자원(배경·지형 타일·장기말·UI 텍스처·글꼴) 경로와 불러오기.
## 그림은 tools/art/ 생성기로 만든다. 같은 이름·크기의 파일로 덮어쓰면 그대로 바뀐다.

const ART_DIR := "res://assets/art/"
const FONT_BODY_PATH := "res://assets/fonts/NanumMyeongjo-Regular.ttf"
const FONT_BRUSH_PATH := "res://assets/fonts/NanumBrushScript-Regular.ttf"

## 화면 씬 파일 이름 → 배경 이름
const SCREEN_BACKGROUNDS: Dictionary = {
	"main": "main_menu",
	"management_screen": "hub",
	"world_screen": "world",
	"sect_war_screen": "war",
	"ending_screen": "ending",
	"martial_art_screen": "study",
	"help_screen": "scroll",
	"new_game_screen": "scroll",
	"combat_scene": "combat",
}

## 글이 배경 위에 바로 놓이는 화면은 한지 색 막을 덮어 그림을 옅게 한다. (막의 불투명도)
const SCREEN_VEILS: Dictionary = {
	"help_screen": 0.8,
	"martial_art_screen": 0.7,
}

## 지형 → 타일 이름
const TERRAIN_TILES: Dictionary = {
	CombatRules.Terrain.PLAIN: "plain",
	CombatRules.Terrain.FOREST: "forest",
	CombatRules.Terrain.WATER: "water",
	CombatRules.Terrain.HIGH: "high",
}

static var _cache: Dictionary = {}


## 텍스처를 불러온다. 없으면 null (그림 없이도 게임은 돌아간다).
static func texture(rel_path: String) -> Texture2D:
	var path: String = ART_DIR + rel_path
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


static func background(name: String) -> Texture2D:
	return texture("bg/%s.jpg" % name)


static func tile(name: String) -> Texture2D:
	return texture("tiles/%s.png" % name)


static func token(name: String) -> Texture2D:
	return texture("tokens/%s.png" % name)


static func ui(name: String) -> Texture2D:
	return texture("ui/%s.png" % name)


static func body_font() -> Font:
	return _font(FONT_BODY_PATH)


## 제목용 붓글씨 글꼴
static func brush_font() -> Font:
	return _font(FONT_BRUSH_PATH)


static func _font(path: String) -> Font:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## 화면의 Background 색 사각형 위에 그 화면의 배경 그림을 깐다. (한 번만)
static func apply_background(root: Node) -> void:
	var rect: ColorRect = root.get_node_or_null("Background") as ColorRect
	if rect == null or rect.has_node("Art"):
		return
	var screen: String = root.scene_file_path.get_file().get_basename()
	var tex: Texture2D = background(SCREEN_BACKGROUNDS.get(screen, "scroll"))
	if tex == null:
		return
	rect.color = UiTheme.COLORS["bg_dark"]
	var art := TextureRect.new()
	art.name = "Art"
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.add_child(art)
	var veil: float = SCREEN_VEILS.get(screen, 0.0)
	if veil > 0.0:
		var cover := ColorRect.new()
		cover.name = "Veil"
		cover.color = Color(UiTheme.COLORS["bg_panel"], veil)
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.add_child(cover)
