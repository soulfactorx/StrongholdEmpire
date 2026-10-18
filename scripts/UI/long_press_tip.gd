class_name LongPressTip
extends Node

## 길게 눌러(터치) 또는 마우스를 올려 두면(PC) 설명 말풍선을 보여 준다. 다시 누르면 닫힌다.
## 라벨 등 정보 표시에는 attach, 버튼에는 attach_button을 쓴다.
## 버튼은 길게 눌러 설명이 뜨면 손을 떼도 눌리지 않는다 (설명만 보고 취소).

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
## 길게 누르기·마우스 올림 판정 시간(초)
const HOLD_TIME := 0.45
const BUBBLE_WIDTH := 420.0

## 말풍선 내용을 돌려주는 함수 (그때그때 최신 수치를 보여 주려고 함수로 받는다)
var provider: Callable
var _target: Control
var _pending: bool = false
var _hold_id: int = 0
## 버튼에 붙었는지, 지금 누르고 있는 중인지 (마우스 올림과 구분)
var _is_button: bool = false
var _pressing: bool = false


## control에 설명을 붙인다. 라벨은 입력을 받도록 mouse_filter를 바꾼다.
static func attach(control: Control, text_provider: Callable) -> LongPressTip:
	var tip := LongPressTip.new()
	tip.provider = text_provider
	tip._target = control
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.add_child(tip)
	control.gui_input.connect(tip._on_gui_input)
	control.mouse_entered.connect(tip._on_hover.bind(true))
	control.mouse_exited.connect(tip._on_hover.bind(false))
	return tip


## 버튼에 설명을 붙인다. 버튼의 입력 설정은 그대로 두고, 길게 누르면 누름을 취소한다.
static func attach_button(button: BaseButton, text_provider: Callable) -> LongPressTip:
	var tip := LongPressTip.new()
	tip.provider = text_provider
	tip._target = button
	tip._is_button = true
	button.add_child(tip)
	button.gui_input.connect(tip._on_gui_input)
	button.mouse_entered.connect(tip._on_hover.bind(true))
	button.mouse_exited.connect(tip._on_hover.bind(false))
	return tip


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_start_hold()
		else:
			_pressing = false
			_pending = false


func _on_hover(entered: bool) -> void:
	if entered:
		_start_hold()
	else:
		_pending = false
		hide_bubble(_target)


func _start_hold() -> void:
	_pending = true
	_hold_id += 1
	var my_id: int = _hold_id
	await get_tree().create_timer(HOLD_TIME).timeout
	if _pending and my_id == _hold_id and is_inside_tree():
		# 마우스 올림은 터치 화면이 아니고 마우스가 실제로 위에 있을 때만 (터치는 탭만 해도 올림으로 잡힌다)
		if not _pressing and not _hover_allowed():
			return
		show_now()
		if _is_button and _pressing:
			_cancel_press()


func _hover_allowed() -> bool:
	if DisplayServer.is_touchscreen_available():
		return false
	return _target.get_global_rect().has_point(_target.get_global_mouse_position())


## 길게 눌러 설명을 연 버튼은 손을 떼도 눌리지 않게 누름 상태를 지운다.
## (비활성으로 바꾸면 BaseButton이 누르던 중이던 상태를 초기화한다)
func _cancel_press() -> void:
	var button := _target as BaseButton
	if button == null or button.disabled:
		return
	button.disabled = true
	button.disabled = false
	_pressing = false


## 바로 말풍선을 연다 (테스트·키보드용)
func show_now() -> void:
	var text: String = provider.call() if provider.is_valid() else ""
	if text.is_empty():
		return
	var bubble: PanelContainer = _get_bubble(_target)
	var label: Label = bubble.get_child(0)
	label.text = text
	bubble.reset_size()
	bubble.visible = true
	# 대상 아래쪽에, 화면을 넘지 않게 둔다.
	var view: Vector2 = _target.get_viewport_rect().size
	var rect: Rect2 = _target.get_global_rect()
	var size: Vector2 = bubble.get_combined_minimum_size()
	var pos := Vector2(rect.position.x, rect.end.y + 6)
	if pos.y + size.y > view.y:
		pos.y = rect.position.y - size.y - 6
	pos.x = clampf(pos.x, 8, view.x - size.x - 8)
	pos.y = clampf(pos.y, 8, view.y - size.y - 8)
	bubble.global_position = pos


## 화면마다 말풍선 하나를 같이 쓴다. 맨 위 층(CanvasLayer)에 둔다.
static func _get_bubble(anchor: Control) -> PanelContainer:
	var scene: Node = anchor.get_tree().current_scene if anchor.get_tree().current_scene else anchor.get_tree().root
	var layer: CanvasLayer = scene.get_node_or_null("TipLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "TipLayer"
		layer.layer = 100
		scene.add_child(layer)
		var bubble := PanelContainer.new()
		bubble.name = "Bubble"
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# CanvasLayer 아래는 창 테마를 이어받지 않으므로 직접 준다 (글꼴이 깨지지 않게)
		bubble.theme = anchor.get_tree().root.theme
		bubble.add_theme_stylebox_override("panel", _UiTheme.create_panel_style())
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)
		_UiTheme.set_font_size(label, 15)
		label.add_theme_color_override("font_color", _UiTheme.COLORS["text_primary"])
		bubble.add_child(label)
		bubble.visible = false
		layer.add_child(bubble)
	return layer.get_node("Bubble")


static func hide_bubble(anchor: Control) -> void:
	if anchor == null or not anchor.is_inside_tree():
		return
	var scene: Node = anchor.get_tree().current_scene
	if scene and scene.has_node("TipLayer/Bubble"):
		scene.get_node("TipLayer/Bubble").visible = false


static func is_bubble_visible(anchor: Control) -> bool:
	var scene: Node = anchor.get_tree().current_scene
	return scene != null and scene.has_node("TipLayer/Bubble") and scene.get_node("TipLayer/Bubble").visible


## 아무 곳이나 다시 누르면 닫는다.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and is_bubble_visible(_target):
		hide_bubble(_target)
