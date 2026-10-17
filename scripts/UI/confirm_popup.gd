extends Control

## 확인 대화상자. 예/아니오(또는 확인 하나)를 고른다. 화면 구성은 코드로 만든다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

## 예를 누르면 true, 아니오면 false
signal answered(confirmed: bool)

var _title: Label
var _message: Label
var _yes: Button
var _no: Button
## 예를 눌렀을 때 실행할 일 (open에서 넘긴다)
var _on_yes: Callable


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
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = Label.new()
	_UiTheme.style_label_title(_title, 24)
	box.add_child(_title)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_yes = Button.new()
	_no = Button.new()
	for button in [_yes, _no]:
		button.custom_minimum_size = Vector2(0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(button)
	_yes.pressed.connect(_answer.bind(true))
	_no.pressed.connect(_answer.bind(false))
	_UiTheme.apply_to_control(panel)


## no_text가 비어 있으면 확인 버튼 하나만 보인다 (알림).
func open(title: String, message: String, on_yes: Callable = Callable(), yes_text: String = "예", no_text: String = "아니오") -> void:
	_title.text = title
	_message.text = message
	_yes.text = yes_text
	_no.text = no_text
	_no.visible = not no_text.is_empty()
	_on_yes = on_yes
	visible = true
	_yes.grab_focus()


func _answer(confirmed: bool) -> void:
	visible = false
	answered.emit(confirmed)
	if confirmed and _on_yes.is_valid():
		_on_yes.call()
