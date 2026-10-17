extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

@onready var title_label: Label = %EventTitleLabel
@onready var desc_label: Label = %EventDescLabel
@onready var choice_box: VBoxContainer = %ChoiceBox


func show_event(event_data: Dictionary) -> void:
	title_label.text = event_data.get("title", "기연")
	desc_label.text = event_data.get("description", "")
	for child in choice_box.get_children():
		choice_box.remove_child(child)
		child.queue_free()

	var choices: Array = Array(event_data.get("choices", []))
	if choices.is_empty():
		choices = ["확인"]
	# 선택지 수는 기연 데이터에 따라 달라지므로 버튼을 매번 새로 만든다.
	for i in choices.size():
		var button := Button.new()
		button.text = choices[i]
		_UiTheme.style_button(button)
		button.custom_minimum_size = Vector2(0, 48)
		button.pressed.connect(_on_choice_pressed.bind(i))
		choice_box.add_child(button)
	visible = true
	# 키보드·게임패드로 바로 고를 수 있게 첫 선택지에 포커스를 둔다.
	if choice_box.get_child_count() > 0:
		(choice_box.get_child(0) as Button).grab_focus()


func _on_choice_pressed(index: int) -> void:
	visible = false
	GameManager.resolve_pending_event(index)
