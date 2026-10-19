class_name DragScroll
extends Node

## 목록(ItemList)을 손가락으로 끌어 스크롤한다 (휴대폰). 마우스로 끌어도 같다.
## ItemList는 누르는 순간 항목을 고르므로 끌어도 목록이 움직이지 않는다. 그래서 누름을 잠시 붙잡아 두고
## 조금 이상 움직이면 스크롤로, 그대로 떼면 그 자리의 항목을 고른 것으로 친다.
## 목록이 끝까지 스크롤되면 남은 움직임은 바깥 ScrollContainer로 넘긴다 (화면 전체가 이어서 움직임).
## 화면마다 UiTheme.apply_to_control이 모든 ItemList에 붙인다.

## 이만큼(px) 움직이면 고르기가 아니라 스크롤이다
const DRAG_THRESHOLD := 12.0
## 손을 뗀 뒤 미끄러지는 감속 (초당 남는 비율)
const FLING_DECAY := 0.02
const FLING_MIN_SPEED := 30.0

var _list: ItemList
var _pressed: bool = false
var _dragging: bool = false
var _press_pos: Vector2
var _velocity: float = 0.0


static func attach(list: ItemList) -> DragScroll:
	if list.has_node("DragScroll"):
		return list.get_node("DragScroll")
	var helper := DragScroll.new()
	helper.name = "DragScroll"
	helper._list = list
	list.add_child(helper)
	list.gui_input.connect(helper._on_gui_input)
	return helper


func _ready() -> void:
	set_process(false)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_dragging = false
			_press_pos = event.position
			_velocity = 0.0
			set_process(false)
		elif _pressed:
			_pressed = false
			if _dragging:
				set_process(absf(_velocity) > FLING_MIN_SPEED)
			else:
				_select_at(event.position)
		# 목록이 누르자마자 고르지 않도록 기본 처리를 막는다
		_list.accept_event()
	elif event is InputEventMouseMotion and _pressed:
		if not _dragging and event.position.distance_to(_press_pos) >= DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			var dy: float = -event.relative.y
			_scroll_by(dy)
			_velocity = dy / maxf(get_process_delta_time(), 1.0 / 120.0)
		_list.accept_event()


func _process(delta: float) -> void:
	_scroll_by(_velocity * delta)
	_velocity *= pow(FLING_DECAY, delta)
	if absf(_velocity) < FLING_MIN_SPEED:
		set_process(false)


## 목록을 dy만큼 스크롤하고, 끝에 닿아 남은 만큼은 바깥 스크롤 칸으로 넘긴다.
func _scroll_by(dy: float) -> void:
	var bar: VScrollBar = _list.get_v_scroll_bar()
	var before: float = bar.value
	bar.value = clampf(bar.value + dy, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
	var rest: float = dy - (bar.value - before)
	if absf(rest) < 0.5:
		return
	var outer: ScrollContainer = _outer_scroll()
	if outer:
		outer.scroll_vertical += int(round(rest))


func _outer_scroll() -> ScrollContainer:
	var node: Node = _list.get_parent()
	while node:
		if node is ScrollContainer:
			return node
		node = node.get_parent()
	return null


## 그 자리의 항목을 고른다 (ItemList를 직접 누른 것과 같은 신호)
func _select_at(pos: Vector2) -> void:
	var index: int = _list.get_item_at_position(pos, true)
	if index < 0 or not _list.is_item_selectable(index) or _list.is_item_disabled(index):
		return
	var was_selected: bool = _list.is_selected(index)
	_list.select(index)
	_list.item_clicked.emit(index, pos, MOUSE_BUTTON_LEFT)
	# 이미 고른 항목을 다시 누르면 ItemList처럼 다시 알리지 않는다 (allow_reselect면 알림)
	if not was_selected or _list.allow_reselect:
		_list.item_selected.emit(index)
