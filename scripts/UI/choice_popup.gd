extends Control

## 목록에서 하나를 고르는 범용 팝업 (역할 행동의 대상 고르기 등). 화면 구성은 코드로 만든다.
## 항목마다 48px 이상 버튼을 만들어 터치로 고를 수 있다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

## 고른 항목의 id
signal chosen(option_id: String)

var _title: Label
var _description: Label
var _rows: VBoxContainer


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_title = Label.new()
	_UiTheme.style_label_title(_title, 24)
	box.add_child(_title)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_font_size_override("font_size", 14)
	box.add_child(_description)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)

	var close := Button.new()
	close.text = "취소"
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void: visible = false)
	box.add_child(close)
	_UiTheme.apply_to_control(panel)


## options: [{id, title, description, disabled(선택)}]
func open(title: String, description: String, options: Array[Dictionary]) -> void:
	_title.text = title
	_description.text = description
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for option in options:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 56)
		button.text = "%s\n%s" % [option["title"], option.get("description", "")]
		button.disabled = option.get("disabled", false)
		button.pressed.connect(_on_option_pressed.bind(option["id"]))
		_UiTheme.style_button(button)
		_rows.add_child(button)
	visible = true


func get_option_count() -> int:
	return _rows.get_child_count()


func _on_option_pressed(option_id: String) -> void:
	visible = false
	chosen.emit(option_id)
