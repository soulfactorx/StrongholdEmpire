extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

@onready var title_label: Label = %EventTitleLabel
@onready var desc_label: Label = %EventDescLabel
@onready var choice_box: VBoxContainer = %ChoiceBox
## 기연에 얽힌 인물의 초상화 (없으면 숨긴다)
var portrait: TextureRect


## 내용 왼쪽에 초상화 자리를 만든다. (한 번만)
func _ensure_portrait() -> void:
	if portrait:
		return
	var content: Control = title_label.get_parent()
	var panel: Node = content.get_parent()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	row.owner = content.owner
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(192, 240)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(portrait)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# reparent는 owner를 지켜 %이름 찾기가 계속 된다.
	content.reparent(row, false)


func show_event(event_data: Dictionary) -> void:
	_ensure_portrait()
	var npc_id: String = str(event_data.get("npc", ""))
	portrait.texture = ArtAssets.portrait(npc_id) if not npc_id.is_empty() else null
	portrait.visible = portrait.texture != null
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
