extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var status_label: Label = %StatusLabel
@onready var continue_button: Button = %ContinueButton
@onready var load_button: Button = %LoadButton
@onready var dev_toggle_button: Button = %DevToggleButton
@onready var dev_panel: Control = %DevPanel


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	_UiTheme.style_label_title(title_label, 48)
	title_label.text = "강호제패"
	subtitle_label.text = "무협 전략 시뮬레이션 RPG"
	continue_button.visible = GameManager.is_game_active
	load_button.disabled = not GameManager.has_save_file()
	# 각 화면 바로가기는 개발 빌드에서만 노출한다.
	dev_toggle_button.visible = OS.is_debug_build()
	dev_panel.visible = false
	status_label.text = _build_status_text()


func _build_status_text() -> String:
	var mod_count: int = GameManager.mod_martial_arts.size()
	var save_text: String = "저장됨" if GameManager.has_save_file() else "저장 없음"
	return "모드 무공 %d개 로드 | %s" % [mod_count, save_text]


func _on_continue_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.HUB)


func _on_new_game_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.NEW_GAME)


func _on_load_pressed() -> void:
	AudioManager.play_click()
	var result: Dictionary = GameManager.load_game()
	status_label.text = result["message"]
	if result["success"]:
		AudioManager.play_success()
		SceneRouter.goto(get_tree(), SceneRouter.HUB)
	else:
		AudioManager.play_failure()


func _on_help_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.HELP)


func _on_quit_pressed() -> void:
	AudioManager.play_click()
	get_tree().quit()


func _on_dev_toggle_pressed() -> void:
	dev_panel.visible = not dev_panel.visible
	dev_toggle_button.text = "개발자 메뉴 ▲" if dev_panel.visible else "개발자 메뉴 ▼"


func _dev_goto(path: String) -> void:
	AudioManager.play_click()
	GameManager.is_game_active = true
	SceneRouter.goto(get_tree(), path)


func _on_dev_management_pressed() -> void:
	_dev_goto(SceneRouter.HUB)


func _on_dev_martial_art_pressed() -> void:
	_dev_goto(SceneRouter.MARTIAL_ART)


func _on_dev_combat_pressed() -> void:
	_dev_goto(SceneRouter.COMBAT)


func _on_dev_sect_war_pressed() -> void:
	_dev_goto(SceneRouter.SECT_WAR)


func _on_dev_ending_pressed() -> void:
	_dev_goto(SceneRouter.ENDING)


func _on_dev_grid_pressed() -> void:
	_dev_goto(SceneRouter.GRID_DEMO)
