extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var status_label: Label = %StatusLabel
@onready var load_button: Button = %LoadButton


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	_UiTheme.style_label_title(title_label, 48)
	title_label.text = "강호제패"
	subtitle_label.text = "무협 전략 시뮬레이션 RPG"
	load_button.disabled = not GameManager.has_save_file()
	status_label.text = _build_status_text()


func _build_status_text() -> String:
	var mod_count: int = GameManager.mod_martial_arts.size()
	var save_text: String = "저장됨" if GameManager.has_save_file() else "저장 없음"
	return "모드 무공 %d개 로드 | %s" % [mod_count, save_text]


func _on_management_pressed() -> void:
	AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/UI/management_screen.tscn")


func _on_martial_art_pressed() -> void:
	AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/UI/martial_art_screen.tscn")


func _on_combat_pressed() -> void:
	AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/Combat/combat_scene.tscn")


func _on_sect_war_pressed() -> void:
	AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/UI/sect_war_screen.tscn")


func _on_ending_pressed() -> void:
	AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/UI/ending_screen.tscn")


func _on_help_pressed() -> void:
	AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/UI/help_screen.tscn")


func _on_save_pressed() -> void:
	AudioManager.play_click()
	var result: Dictionary = GameManager.save_game()
	status_label.text = result["message"]
	if result["success"]:
		AudioManager.play_success()
		load_button.disabled = false


func _on_load_pressed() -> void:
	AudioManager.play_click()
	var result: Dictionary = GameManager.load_game()
	status_label.text = result["message"]
	if result["success"]:
		AudioManager.play_success()


func _on_grid_demo_pressed() -> void:
	AudioManager.play_click()
	get_tree().change_scene_to_file("res://scenes/Combat/grid_demo.tscn")


func _on_quit_pressed() -> void:
	AudioManager.play_click()
	get_tree().quit()