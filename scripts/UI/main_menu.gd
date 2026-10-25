extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _ChoicePopup = preload("res://scripts/UI/choice_popup.gd")
const _ConfirmPopup = preload("res://scripts/UI/confirm_popup.gd")
const _OptionsPopup = preload("res://scripts/UI/options_popup.gd")

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var status_label: Label = %StatusLabel
@onready var continue_button: Button = %ContinueButton
@onready var load_button: Button = %LoadButton
@onready var dev_toggle_button: Button = %DevToggleButton
@onready var dev_panel: Control = %DevPanel
## 불러올 슬롯을 고르는 팝업
var load_popup: Control
var confirm_popup: Control
var options_popup: Control


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	load_popup = _ChoicePopup.new()
	add_child(load_popup)
	load_popup.chosen.connect(_on_load_slot_chosen)
	confirm_popup = _ConfirmPopup.new()
	add_child(confirm_popup)
	options_popup = _OptionsPopup.new()
	add_child(options_popup)
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
	if GameManager.is_game_active:
		confirm_popup.open(
			"새 게임", "진행 중인 판이 있습니다. 새로 시작할까요?\n지금 판은 자동 저장에서 이어 할 수 있지만, 새 판의 계절이 바뀌면 자동 저장을 덮어씁니다.",
			_goto_new_game, "새로 시작", "취소"
		)
		return
	_goto_new_game()


func _goto_new_game() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.NEW_GAME)


func _on_options_pressed() -> void:
	AudioManager.play_click()
	options_popup.open()


func _on_load_pressed() -> void:
	AudioManager.play_click()
	var options: Array[Dictionary] = []
	for slot in range(SaveManager.AUTO_SLOT, SaveManager.SLOT_COUNT + 1):
		var summary: Dictionary = SaveManager.get_slot_summary(slot)
		options.append({
			"id": str(slot), "title": summary["title"], "description": summary["detail"], "disabled": not summary["exists"],
		})
	load_popup.open("불러오기", "불러올 세이브를 고르세요.", options)


func _on_load_slot_chosen(slot: String) -> void:
	var result: Dictionary = GameManager.load_game(int(slot))
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

