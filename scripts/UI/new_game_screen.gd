extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

@onready var name_edit: LineEdit = %NameEdit
@onready var role_list: ItemList = %RoleList
@onready var role_desc_label: Label = %RoleDescLabel

var _selected_role_id: String = StartingRoles.DEFAULT_ID


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	role_list.clear()
	for entry in StartingRoles.ROLES:
		role_list.add_item(entry["title"])
	role_list.select(0)
	_on_role_selected(0)
	name_edit.grab_focus()


func _on_role_selected(index: int) -> void:
	var entry: Dictionary = StartingRoles.ROLES[index]
	# 이름을 직접 입력하지 않았다면 역할별 기본 이름을 보여준다.
	var previous: Dictionary = StartingRoles.get_by_id(_selected_role_id)
	if name_edit.text.is_empty() or name_edit.text == previous["default_name"]:
		name_edit.text = entry["default_name"]
	_selected_role_id = entry["id"]
	role_desc_label.text = entry["description"]


func _on_name_submitted(_text: String) -> void:
	_on_start_pressed()


func _on_start_pressed() -> void:
	AudioManager.play_click()
	GameManager.start_new_game(name_edit.text, _selected_role_id)
	SceneRouter.goto(get_tree(), SceneRouter.HUB)


func _on_back_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.MAIN_MENU)
