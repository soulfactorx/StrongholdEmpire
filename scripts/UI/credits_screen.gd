extends Control

## 만든 이들 화면: 게임의 저작권·라이선스와 함께 쓴 글꼴·Godot 엔진의 고지를 보인다.
## Godot 엔진(MIT)과 그 구성 요소의 저작권 고지는 내보낸 빌드에 반드시 들어가야 하므로
## 엔진이 제공하는 Engine.get_license_text()·get_copyright_info()·get_license_info()를 그대로 보인다.
## 탭과 라이선스 이름은 모두 버튼(48px 이상)이라 터치만으로 다 볼 수 있다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

const COPYRIGHT_HOLDER := "이준혁 (soulfactorx)"
const COPYRIGHT_YEAR := "2026"
## 내보낸 빌드에도 들어가는 라이선스 파일 (export_presets.cfg의 include_filter)
const CODE_LICENSE_PATH := "res://LICENSE"
const FONT_LICENSE_PATH := "res://assets/fonts/OFL.txt"

const TAB_GAME := "game"
const TAB_FONTS := "fonts"
const TAB_ENGINE := "engine"
const TAB_LICENSES := "licenses"
## 탭 id → 버튼 글자 (보이는 순서)
const TABS: Array = [
	[TAB_GAME, "강호제패"],
	[TAB_FONTS, "글꼴"],
	[TAB_ENGINE, "Godot 엔진"],
	[TAB_LICENSES, "라이선스 전문"],
]
const BUTTON_HEIGHT := 48

@onready var tab_bar: HFlowContainer = %TabBar
@onready var license_bar: HFlowContainer = %LicenseBar
@onready var scroll: ScrollContainer = %Scroll
@onready var body_label: Label = %BodyLabel

var current_tab: String = ""
var current_license: String = ""
## 탭 id → 버튼
var _tab_buttons: Dictionary = {}
## 라이선스 이름 → 버튼
var _license_buttons: Dictionary = {}


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	var tab_group := ButtonGroup.new()
	for tab in TABS:
		var button: Button = _make_button(tab[1], tab_group)
		button.pressed.connect(_on_tab_pressed.bind(tab[0]))
		tab_bar.add_child(button)
		_tab_buttons[tab[0]] = button
	var license_group := ButtonGroup.new()
	for license_name in license_names():
		var button: Button = _make_button(license_name, license_group)
		button.pressed.connect(_on_license_pressed.bind(license_name))
		license_bar.add_child(button)
		_license_buttons[license_name] = button
	show_tab(TAB_GAME)


func _make_button(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(120, BUTTON_HEIGHT)
	_UiTheme.style_button(button)
	return button


func show_tab(tab: String) -> void:
	current_tab = tab
	_mark_pressed(_tab_buttons, tab)
	license_bar.visible = tab == TAB_LICENSES
	match tab:
		TAB_GAME:
			body_label.text = game_text()
		TAB_FONTS:
			body_label.text = font_text()
		TAB_ENGINE:
			body_label.text = engine_text()
		TAB_LICENSES:
			show_license(current_license if not current_license.is_empty() else license_names()[0])
			return
	scroll.scroll_vertical = 0


func show_license(license_name: String) -> void:
	current_license = license_name
	_mark_pressed(_license_buttons, license_name)
	body_label.text = license_text(license_name)
	scroll.scroll_vertical = 0


## 고른 버튼만 눌린 모양으로 둔다 (코드로 탭을 바꿀 때도 같게).
func _mark_pressed(buttons: Dictionary, selected: String) -> void:
	for key in buttons:
		buttons[key].set_pressed_no_signal(key == selected)


func _on_tab_pressed(tab: String) -> void:
	AudioManager.play_click()
	show_tab(tab)


func _on_license_pressed(license_name: String) -> void:
	AudioManager.play_click()
	show_license(license_name)


func _on_back_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.back(get_tree(), SceneRouter.MAIN_MENU)


## 파일 내용. 없으면 빈 문자열.
static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()


## 게임 자체의 저작권·라이선스와 만든 이들
static func game_text() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var mit: String = _read_text(CODE_LICENSE_PATH)
	if mit.is_empty():
		mit = "(라이선스 파일을 찾지 못했습니다. https://github.com/soulfactorx/StrongholdEmpire 의 LICENSE를 보세요.)"
	return """강호제패 v%s
© %s %s

■ 라이선스
  코드: MIT 라이선스 (아래 전문)
  그림·음악·효과음·아이콘, 이야기와 데이터, 기획 문서, 게임 제목과 로고: All Rights Reserved
    저작권자의 허락 없이 복제·수정·배포·2차 창작·상업적 이용을 할 수 없습니다.
  글꼴과 Godot 엔진은 각자의 라이선스를 따릅니다 ([글꼴]·[Godot 엔진] 탭).

■ 만든 이들
  기획·제작: %s
  그림: 수묵담채 그림 세트 — %s
  음악·효과음: 직접 합성
  글꼴: 나눔명조·나눔손글씨 붓 — NAVER (SIL Open Font License 1.1)
  엔진: Godot Engine (MIT) — Godot Engine contributors

■ MIT 라이선스 (코드)
%s""" % [version, COPYRIGHT_YEAR, COPYRIGHT_HOLDER, COPYRIGHT_HOLDER, COPYRIGHT_HOLDER, mit]


## 나눔 글꼴의 저작권과 SIL OFL 전문
static func font_text() -> String:
	var ofl: String = _read_text(FONT_LICENSE_PATH)
	if ofl.is_empty():
		ofl = "(OFL.txt를 찾지 못했습니다. https://openfontlicense.org 를 보세요.)"
	return """■ 나눔명조 (본문), 나눔손글씨 붓 (제목·장기말 글자)
  NAVER Corporation — SIL Open Font License 1.1

%s""" % ofl


## Godot 엔진 라이선스와 엔진에 든 구성 요소마다의 저작권·라이선스
static func engine_text() -> String:
	var lines: PackedStringArray = [
		"이 게임은 Godot 엔진으로 만들었습니다. Godot 엔진은 아래 라이선스를 따릅니다.",
		"This game uses Godot Engine, available under the following license:",
		"",
		Engine.get_license_text().strip_edges(),
		"",
		"■ 엔진에 든 구성 요소 (Godot Engine third-party components)",
		"  라이선스마다 전문은 [라이선스 전문] 탭에 있습니다.",
	]
	for component in Engine.get_copyright_info():
		lines.append("")
		lines.append(str(component.get("name", "")))
		# 파일 목록은 빼고, 같은 저작권·라이선스가 되풀이되면 한 번만 쓴다.
		var seen: Dictionary = {}
		for part in component.get("parts", []):
			var copyright: PackedStringArray = PackedStringArray(part.get("copyright", []))
			var license: String = str(part.get("license", ""))
			var key: String = "|".join(copyright) + "#" + license
			if seen.has(key):
				continue
			seen[key] = true
			for holder in copyright:
				lines.append("  © %s" % holder)
			lines.append("  License: %s" % license)
	return "\n".join(lines)


## 엔진 구성 요소가 쓰는 라이선스 이름 (가나다·ABC 순)
static func license_names() -> Array:
	var names: Array = Engine.get_license_info().keys()
	names.sort()
	return names


static func license_text(license_name: String) -> String:
	var info: Dictionary = Engine.get_license_info()
	if not info.has(license_name):
		return ""
	return "■ %s\n\n%s" % [license_name, str(info[license_name]).strip_edges()]
