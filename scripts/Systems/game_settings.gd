class_name GameSettings
extends RefCounted

## 옵션: 효과음 음량, 전체 화면, 글자 크기, 전투 속도. user://settings.cfg에 저장하고 바로 적용한다.

const TEXT_SCALES: Array = [["보통", 1.0], ["크게", 1.15], ["아주 크게", 1.3]]
## 전투에서 적 행동 사이의 간격(초)
const COMBAT_DELAYS: Array = [["빠르게", 0.0], ["보통", 0.3], ["느리게", 0.6]]

## 설정 파일 경로. 테스트는 다른 경로를 써서 실제 설정을 건드리지 않는다.
static var settings_path: String = "user://settings.cfg"
static var sfx_volume: float = 0.8
static var fullscreen: bool = false
static var text_scale: float = 1.0
static var combat_delay: float = 0.3


static func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", 0.8)), 0.0, 1.0)
		fullscreen = config.get_value("display", "fullscreen", false) == true
		text_scale = float(config.get_value("display", "text_scale", 1.0))
		combat_delay = float(config.get_value("combat", "delay", 0.3))
	if not TEXT_SCALES.any(func(entry: Array) -> bool: return is_equal_approx(entry[1], text_scale)):
		text_scale = 1.0
	if not COMBAT_DELAYS.any(func(entry: Array) -> bool: return is_equal_approx(entry[1], combat_delay)):
		combat_delay = 0.3


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "text_scale", text_scale)
	config.set_value("combat", "delay", combat_delay)
	config.save(settings_path)


## 설정을 엔진에 적용한다. tree가 있으면 화면 전체의 기본 글자 크기도 바꾼다.
static func apply(tree: SceneTree = null) -> void:
	var bus: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(bus, sfx_volume <= 0.0)
	UiTheme.text_scale = text_scale
	if tree and tree.root:
		if tree.root.theme == null:
			tree.root.theme = Theme.new()
		tree.root.theme.default_font_size = UiTheme.font_size(UiTheme.BASE_FONT_SIZE)
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
		"fullscreen":
			fullscreen = value == true
		"text_scale":
			text_scale = float(value)
		"combat_delay":
			combat_delay = float(value)
	save_settings()
	apply(tree)
