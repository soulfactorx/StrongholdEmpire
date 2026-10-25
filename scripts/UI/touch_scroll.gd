class_name TouchScroll
extends Node

## 스크롤 칸(ScrollContainer)을 손가락으로 끌어 위아래로 움직인다 (휴대폰). 마우스로 끌어도 같다.
## ScrollContainer는 버튼·판(PanelContainer)이 누름을 받아 버리면 끌어도 움직이지 않는다.
## 그래서 화면 입력을 GUI보다 먼저(_input) 보고, 스크롤 칸 안에서 조금 이상 움직이면 스크롤로 친다.
## 끄는 동안 누르고 있던 버튼은 손을 떼도 눌리지 않게 막는다. 그대로 떼면 평소처럼 버튼이 눌린다.
## 목록(ItemList)이나 안쪽 스크롤 칸 위에서 끈 것은 그쪽이 맡는다 (DragScroll·안쪽 TouchScroll).
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
			_pressed = _scroll.get_global_rect().has_point(event.position)
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
			if not _can_scroll() or not _owns_point():
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


## 지금 손가락 밑의 것이 이 스크롤 칸 몫인지: 이 칸 안에 있고, 사이에 목록·다른 스크롤 칸이 없다.
## (위에 덮인 팝업이나 안쪽 목록을 끌 때 뒤의 화면이 같이 움직이지 않게)
func _owns_point() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return true
	var node: Node = hovered
	while node:
		if node == _scroll:
			return true
		if node is ItemList or node is ScrollContainer:
			return false
		node = node.get_parent()
	return false


## 누르고 있던 버튼이 떼는 순간 눌리지 않게 신호를 막아 둔다
func _hold_button() -> void:
	var node: Node = get_viewport().gui_get_hovered_control()
	while node and node != _scroll and not node is BaseButton:
		node = node.get_parent()
	if node is BaseButton:
		_held = node
		_held_pressed = _held.button_pressed
		_held.set_block_signals(true)


func _release_button() -> void:
	if _held and is_instance_valid(_held):
		if _held.toggle_mode:
			_held.set_pressed_no_signal(_held_pressed)
		_held.set_block_signals(false)
	_held = null
