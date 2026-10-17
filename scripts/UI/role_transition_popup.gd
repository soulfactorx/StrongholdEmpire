extends Control

@onready var title_label: Label = %RoleTitleLabel
@onready var desc_label: Label = %RoleDescLabel
@onready var option_list: ItemList = %RoleOptionList


func show_options(options: Array[Dictionary]) -> void:
	title_label.text = "역할 전환"
	desc_label.text = "조건을 충족한 새 역할이 있습니다. 하나를 선택하세요."
	option_list.clear()
	for option in options:
		option_list.add_item("%s — %s" % [option["title"], option["description"]])
	if not options.is_empty():
		option_list.select(0)
	visible = true


func _on_confirm_pressed() -> void:
	var selected: PackedInt32Array = option_list.get_selected_items()
	if selected.is_empty():
		return
	var options: Array[Dictionary] = GameManager.pending_role_transitions
	if selected[0] >= options.size():
		return
	var option: Dictionary = options[selected[0]]
	GameManager.apply_role_transition(option["role"], option)
	visible = false


func _on_close_pressed() -> void:
	visible = false