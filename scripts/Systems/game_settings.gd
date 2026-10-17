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
## 공격·무공 전에 예상 결과를 보여 주고 확인받는다
static var combat_preview: bool = true
## 경영 행동(수련·영약·시설·유대 등) 전에 수치 변화를 보여 주고 확인받는다
static var action_preview: bool = true
## 계절을 넘기면 강호 세력이 무엇을 했는지 보고 창을 띄운다
static var faction_report: bool = true


static func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", 0.8)), 0.0, 1.0)
		music_volume = clampf(float(config.get_value("audio", "music_volume", 0.6)), 0.0, 1.0)
		fullscreen = config.get_value("display", "fullscreen", false) == true
		text_scale = float(config.get_value("display", "text_scale", 1.0))
		combat_delay = float(config.get_value("combat", "delay", 0.3))
		combat_preview = config.get_value("combat", "preview", true) == true
		action_preview = config.get_value("game", "action_preview", true) == true
		faction_report = config.get_value("game", "faction_report", true) == true
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
	config.set_value("combat", "preview", combat_preview)
	config.set_value("game", "action_preview", action_preview)
	config.set_value("game", "faction_report", faction_report)
	config.save(settings_path)


## 설정을 엔진에 적용한다. tree가 있으면 화면 전체의 기본 글자 크기도 바꾼다.
static func apply(tree: SceneTree = null) -> void:
	_set_bus_volume(SFX_BUS, sfx_volume)
	_set_bus_volume(MUSIC_BUS, music_volume)
	UiTheme.text_scale = text_scale
	if tree and tree.root:
		if tree.root.theme == null:
			tree.root.theme = Theme.new()
			UiTheme.apply_root_theme(tree.root.theme)
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
		"music_volume":
			music_volume = clampf(float(value), 0.0, 1.0)
		"fullscreen":
			fullscreen = value == true
		"text_scale":
			text_scale = float(value)
		"combat_delay":
			combat_delay = float(value)
		"combat_preview":
			combat_preview = value == true
		"action_preview":
			action_preview = value == true
		"faction_report":
			faction_report = value == true
	save_settings()
	apply(tree)


## 이름으로 버스 번호를 찾는다. 없으면 새로 만든다.
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
