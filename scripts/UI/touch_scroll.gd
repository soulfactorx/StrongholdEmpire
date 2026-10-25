class_name TouchScroll
extends Node

## 스크롤 칸(ScrollContainer)을 손가락으로 끌어 위아래로 움직인다 (휴대폰). 마우스로 끌어도 같다.
## ScrollContainer는 버튼·판(PanelContainer)이 누름을 받아 버리면 끌어도 움직이지 않는다.
## 그래서 화면 입력을 GUI보다 먼저(_input) 보고, 스크롤 칸 안에서 조금 이상 움직이면 스크롤로 친다.
## 끄는 동안 누르고 있던 버튼은 손을 떼도 눌리지 않게 막는다. 그대로 떼면 평소처럼 버튼이 눌린다.
## 목록(ItemList)이나 안쪽 스크롤 칸 위에서 끈 것은 그쪽이 맡고(DragScroll·안쪽 TouchScroll),
## 위에 덮인 창이 있으면 뒤의 화면은 움직이지 않는다.
## 누른 자리가 이 칸 몫인지는 누르는 순간 노드 트리로 직접 따진다. (휴대폰은 마우스 올림이 없어
## Viewport의 "올려 둔 컨트롤"이 지난번 누른 자리에 머물러 있으므로 그것에 기대지 않는다)
## 화면마다 UiTheme.apply_to_control이 모든 ScrollContainer에 붙인다.

## 이만큼(px) 움직이면 누르기가 아니라 스크롤이다
const DRAG_THRESHOLD := 12.0
## 손을 뗀 뒤 미끄러지는 감속 (초당 남는 비율)
const FLING_DECAY := 0.02
const FLING_MIN_SPEED := 30.0

var _scroll: ScrollContainer
var _pressed: bool = false
var _dragging: bool = false
var _press_pos: Vector2
var _velocity: float = 0.0
## 정수 스크롤 값에 담기지 않은 나머지
var _remainder: float = 0.0
## 끄는 동안 눌림을 막아 둔 버튼과 그 버튼의 원래 눌림 상태
var _held: BaseButton = null
var _held_pressed: bool = false


static func attach(scroll: ScrollContainer) -> TouchScroll:
	if scroll.has_node("TouchScroll"):
		return scroll.get_node("TouchScroll")
	var helper := TouchScroll.new()
	helper.name = "TouchScroll"
	helper._scroll = scroll
	scroll.add_child(helper)
	return helper


func _ready() -> void:
	set_process(false)


func is_dragging() -> bool:
	return _dragging


func _input(event: InputEvent) -> void:
	if _scroll == null or not _scroll.is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = owns_point(event.position)
			_dragging = false
			_press_pos = event.position
			_velocity = 0.0
			set_process(false)
		elif _pressed:
			_pressed = false
			if _dragging:
				_dragging = false
				# 버튼이 떼는 입력을 처리한 뒤에 막아 둔 것을 푼다
				_release_button.call_deferred()
				set_process(absf(_velocity) > FLING_MIN_SPEED)
	elif event is InputEventMouseMotion and _pressed:
		if not _dragging and event.position.distance_to(_press_pos) >= DRAG_THRESHOLD:
			if not _can_scroll():
				_pressed = false
				return
			_dragging = true
			_hold_button()
		if _dragging:
			var dy: float = -event.relative.y
			_scroll_by(dy)
			_velocity = dy / maxf(get_process_delta_time(), 1.0 / 120.0)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_scroll_by(_velocity * delta)
	_velocity *= pow(FLING_DECAY, delta)
	if absf(_velocity) < FLING_MIN_SPEED:
		set_process(false)


func _scroll_by(dy: float) -> void:
	_remainder += dy
	var step: int = int(_remainder)
	_remainder -= step
	_scroll.scroll_vertical += step


func _can_scroll() -> bool:
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	return bar.max_value - bar.page > 1.0


## 누른 자리가 이 스크롤 칸 몫인지: 칸 안이고, 안쪽 목록·스크롤 칸 위가 아니며, 위에 덮인 것이 없다.
func owns_point(point: Vector2) -> bool:
	if not _scroll.get_global_rect().has_point(point):
		return false
	if _inner_takes(_scroll, point):
		return false
	# 트리에서 이 칸보다 뒤에 오는 것(위에 그려지는 것)이 그 자리를 덮는지
	var node: Node = _scroll
	while node.get_parent():
		var parent: Node = node.get_parent()
		for i in range(node.get_index() + 1, parent.get_child_count()):
			if _blocks(parent.get_child(i), point):
				return false
		node = parent
	return true


## 안쪽의 목록이나 스크롤되는 안쪽 스크롤 칸이 그 자리에 있으면 그쪽이 맡는다
func _inner_takes(node: Node, point: Vector2) -> bool:
	for child in node.get_children():
		if not child is Control or not (child as Control).is_visible_in_tree():
			continue
		var control := child as Control
		if (control is ItemList or (control is ScrollContainer and control.has_node("TouchScroll") and control.get_node("TouchScroll")._can_scroll())) \
				and control.get_global_rect().has_point(point):
			return true
		if _inner_takes(control, point):
			return true
	return false


## node(또는 그 안의 것)가 그 자리의 누름을 받는지 (보이고, 마우스를 무시하지 않고, 자리를 덮음)
func _blocks(node: Node, point: Vector2) -> bool:
	if node is CanvasLayer:
		if not (node as CanvasLayer).visible:
			return false
	elif node is Control:
		var control := node as Control
		if not control.visible:
			return false
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE and control.get_global_rect().has_point(point):
			return true
	else:
		return false
	for child in node.get_children():
		if _blocks(child, point):
			return true
	return false


## 누르고 있던 버튼(누른 자리의 버튼)이 떼는 순간 눌리지 않게 신호를 막아 둔다
func _hold_button() -> void:
	var button: BaseButton = _button_at(_scroll, _press_pos)
	if button:
		_held = button
		_held_pressed = button.button_pressed
		button.set_block_signals(true)


func _button_at(node: Node, point: Vector2) -> BaseButton:
	for child in node.get_children():
		if not child is Control or not (child as Control).is_visible_in_tree():
			continue
		if not (child as Control).get_global_rect().has_point(point):
			continue
		var inner: BaseButton = _button_at(child, point)
		if inner:
			return inner
		if child is BaseButton:
			return child
	return null


func _release_button() -> void:
	if _held and is_instance_valid(_held):
		if _held.toggle_mode:
			_held.set_pressed_no_signal(_held_pressed)
		_held.set_block_signals(false)
	_held = null
