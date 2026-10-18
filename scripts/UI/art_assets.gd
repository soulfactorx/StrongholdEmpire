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
	"map_screen": "world",
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


## 불러 둔 그림·글꼴 캐시를 비운다.
static func clear_cache() -> void:
	_cache.clear()


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


## 인물 초상화: NPC 데이터의 "portrait"(assets/art/ 아래 경로)가 있으면 그것, 없으면 portraits/<npc_id>.jpg
static func portrait(npc_id: String) -> Texture2D:
	var npc: Dictionary = NpcRoster.get_npc(npc_id)
	return texture(str(npc.get("portrait", "portraits/%s.jpg" % npc_id)))


## 주인공 역할 초상화 (portraits/role_<역할>.jpg)
static func role_portrait(role: CharacterData.Role) -> Texture2D:
	return texture("portraits/role_%s.jpg" % CharacterData.Role.keys()[role].to_lower())


## 세력 문장: 문파 데이터의 "emblem"이 있으면 그것, 없으면 emblems/<sect_id>.png
static func emblem(sect_id: String) -> Texture2D:
	var info: Dictionary = SectRegistry.get_sect_info(sect_id)
	return texture(str(info.get("emblem", "emblems/%s.png" % sect_id)))


## 그림을 담은 TextureRect (그림이 없으면 null). 비율을 지켜 size 안에 맞춘다.
static func picture_rect(tex: Texture2D, size: Vector2) -> TextureRect:
	if tex == null:
		return null
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func body_font() -> Font:
	return _font(FONT_BODY_PATH)


## 제목용 붓글씨 글꼴. 붓글씨 글꼴에 없는 문장부호(— · → ★ 「」 등)는 본문 글꼴로 그린다.
static func brush_font() -> Font:
	var brush: Font = _font(FONT_BRUSH_PATH)
	var body: Font = body_font()
	if brush and body and not brush.fallbacks.has(body):
		brush.fallbacks = [body]
	return brush


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
