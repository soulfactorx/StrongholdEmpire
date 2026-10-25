class_name GameSettings
extends RefCounted

## 옵션: 배경음악·효과음 음량, 전체 화면, 글자 크기, 전투 속도. user://settings.cfg에 저장하고 바로 적용한다.

const TEXT_SCALES: Array = [["보통", 1.0], ["크게", 1.15], ["아주 크게", 1.3]]
## 전투에서 적 행동 사이의 간격(초)
const COMBAT_DELAYS: Array = [["빠르게", 0.0], ["보통", 0.3], ["느리게", 0.6]]

## 음량을 따로 조절하는 오디오 버스 (없으면 만들어 Master로 보낸다)
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

## 설정 파일 경로. 테스트는 다른 경로를 써서 실제 설정을 건드리지 않는다.
static var settings_path: String = "user://settings.cfg"
static var sfx_volume: float = 0.8
static var music_volume: float = 0.6
static var fullscreen: bool = false
static var text_scale: float = 1.0
static var combat_delay: float = 0.3
## 경영 행동(수련·영약·시설·유대 등) 전에 수치 변화를 보여 주고 확인받는다
static var action_preview: bool = true
## 계절을 넘기면 강호 세력이 무엇을 했는지 보고 창을 띄운다
static var faction_report: bool = true
## 경영 행동을 하면 결과 알림 대신 인물과의 대화 장면을 띄운다 (ActionScenes)
static var action_scenes: bool = true
## 전투에서 합마다 무대 연출(달려들기·피해 숫자·흔들림)을 보여 준다 (DuelStage)
static var combat_effects: bool = true
## 화면 배치: LayoutMode.Mode (자동·가로·세로)
static var layout_mode: int = 0


static func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", 0.8)), 0.0, 1.0)
		music_volume = clampf(float(config.get_value("audio", "music_volume", 0.6)), 0.0, 1.0)
		fullscreen = config.get_value("display", "fullscreen", false) == true
		text_scale = float(config.get_value("display", "text_scale", 1.0))
		combat_delay = float(config.get_value("combat", "delay", 0.3))
		action_preview = config.get_value("game", "action_preview", true) == true
		faction_report = config.get_value("game", "faction_report", true) == true
		action_scenes = config.get_value("game", "action_scenes", true) == true
		combat_effects = config.get_value("combat", "effects", true) == true
		layout_mode = clampi(int(config.get_value("display", "layout_mode", 0)), 0, 2)
	if not TEXT_SCALES.any(func(entry: Array) -> bool: return is_equal_approx(entry[1], text_scale)):
		text_scale = 1.0
	if not COMBAT_DELAYS.any(func(entry: Array) -> bool: return is_equal_approx(entry[1], combat_delay)):
		combat_delay = 0.3


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "text_scale", text_scale)
	config.set_value("combat", "delay", combat_delay)
	config.set_value("game", "action_preview", action_preview)
	config.set_value("game", "faction_report", faction_report)
	config.set_value("game", "action_scenes", action_scenes)
	config.set_value("combat", "effects", combat_effects)
	config.set_value("display", "layout_mode", layout_mode)
	config.save(settings_path)


## 설정을 엔진에 적용한다. tree가 있으면 화면 전체의 기본 글자 크기도 바꾼다.
static func apply(tree: SceneTree = null) -> void:
	_set_bus_volume(SFX_BUS, sfx_volume)
	_set_bus_volume(MUSIC_BUS, music_volume)
	UiTheme.text_scale = text_scale
	if tree and tree.root:
		LayoutMode.apply(tree, layout_mode)
		if tree.root.theme == null:
			tree.root.theme = Theme.new()
			UiTheme.apply_root_theme(tree.root.theme)
		tree.root.theme.default_font_size = UiTheme.font_size(UiTheme.BASE_FONT_SIZE)
		# 화면 위 층(CanvasLayer)의 말풍선·확인창은 창 테마를 이어받지 못하므로 엔진 기본 글꼴도 한글 글꼴로 둔다.
		if ArtAssets.body_font():
			ThemeDB.fallback_font = ArtAssets.body_font()
	# 헤드리스(테스트)에서는 창 모드를 바꾸지 않는다.
	if DisplayServer.get_name() != "headless":
		var mode: DisplayServer.WindowMode = (
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


static func set_and_save(key: String, value: Variant, tree: SceneTree = null) -> void:
	match key:
		"sfx_volume":
			sfx_volume = clampf(float(value), 0.0, 1.0)
		"music_volume":
			music_volume = clampf(float(value), 0.0, 1.0)
		"fullscreen":
			fullscreen = value == true
		"text_scale":
			text_scale = float(value)
		"combat_delay":
			combat_delay = float(value)
		"action_preview":
			action_preview = value == true
		"faction_report":
			faction_report = value == true
		"action_scenes":
			action_scenes = value == true
		"combat_effects":
			combat_effects = value == true
		"layout_mode":
			layout_mode = clampi(int(value), 0, 2)
	save_settings()
	apply(tree)


## 이름으로 버스 번호를 찾는다. 없으면 새로 만든다.
## 버스는 default_bus_layout.tres에 미리 정해 둔다. 웹(샘플 재생)은 시작할 때의 버스 구성만 브라우저 쪽에 만들기 때문에
## 실행 중에 add_bus로 만든 버스로 보낸 소리는 들리지 않는다. 아래는 레이아웃 파일이 없을 때를 위한 대비다.
static func bus_index(bus_name: String) -> int:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	return index


static func _set_bus_volume(bus_name: String, volume: float) -> void:
	var index: int = bus_index(bus_name)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(index, volume <= 0.0)
