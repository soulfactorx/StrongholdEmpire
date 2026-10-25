class_name LayoutMode
extends RefCounted

## 화면 배치: 가로(PC) 또는 세로(휴대폰). 세로에서는 기준 크기를 720×1280으로 바꾸고,
## 화면마다 두 칸을 위아래로 쌓거나(stack) 휴대폰용 구성(경영 화면 탭)을 쓴다.
## 설정의 "화면 배치"(GameSettings.layout_mode)가 자동이면 휴대폰(안드로이드·iOS·휴대폰 웹)은 세로, 그 밖은 가로다.

enum Mode { AUTO, LANDSCAPE, PORTRAIT }

const LANDSCAPE_SIZE := Vector2i(1280, 720)
const PORTRAIT_SIZE := Vector2i(720, 1280)
const MODE_NAMES: Array[String] = ["자동 (휴대폰은 세로)", "가로 (PC)", "세로 (휴대폰)"]

## 지금 세로 배치인지. apply()가 정한다. 테스트는 직접 바꿔 세로 화면을 시험한다.
static var portrait: bool = false


static func is_portrait() -> bool:
	return portrait


## 설정값으로 세로 배치 여부를 정한다.
static func decide(mode: int) -> bool:
	match mode:
		Mode.LANDSCAPE:
			return false
		Mode.PORTRAIT:
			return true
	return is_phone()


## 휴대폰인지 (안드로이드·iOS 앱, 휴대폰 브라우저)
static func is_phone() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## 세로·가로에 맞춰 기준 크기와 (휴대폰이면) 화면 방향을 바꾼다.
static func apply(tree: SceneTree, mode: int) -> void:
	portrait = decide(mode)
	if tree == null or tree.root == null:
		return
	tree.root.content_scale_size = PORTRAIT_SIZE if portrait else LANDSCAPE_SIZE
	if OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		DisplayServer.screen_set_orientation(
			DisplayServer.SCREEN_PORTRAIT if portrait else DisplayServer.SCREEN_SENSOR_LANDSCAPE
		)


## 가로로 놓인 상자(HBox)를 세로 상자(VBox)로 바꿔 칸을 위아래로 쌓는다. 세로 배치가 아니면 그대로 둔다.
## (HBoxContainer는 vertical을 바꿔도 가로로 놓으므로 같은 이름의 VBox로 바꿔 끼운다. 자식은 그대로 옮긴다)
## ratios를 주면 칸마다 높이 비율(size_flags_stretch_ratio)로 쓴다. 바꿔 끼운 상자를 돌려준다.
static func stack(box: BoxContainer, ratios: Array = []) -> BoxContainer:
	if not portrait or box == null:
		return box
	var column: VBoxContainer = _swap_to_vbox(box)
	var index: int = 0
	for child in column.get_children():
		if child is Control:
			child.size_flags_vertical = Control.SIZE_EXPAND_FILL
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if index < ratios.size():
				child.size_flags_stretch_ratio = float(ratios[index])
			index += 1
	return column


## 세로로 쌓은 내용이 화면보다 길면 끌어서 보도록 스크롤 안에 넣는다.
static func stack_scroll(box: BoxContainer) -> ScrollContainer:
	if not portrait or box == null:
		return null
	var parent: Node = box.get_parent()
	var index: int = box.get_index()
	var column: VBoxContainer = _swap_to_vbox(box)
	var scroll := ScrollContainer.new()
	scroll.name = column.name + "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	parent.move_child(scroll, index)
	column.reparent(scroll)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in column.get_children():
		if child is Control:
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			child.size_flags_vertical = Control.SIZE_FILL
	return scroll


static func _swap_to_vbox(box: BoxContainer) -> VBoxContainer:
	if box is VBoxContainer:
		return box
	var parent: Node = box.get_parent()
	var index: int = box.get_index()
	var column := VBoxContainer.new()
	var box_name: StringName = box.name
	box.name = box_name + "_old"
	column.name = box_name
	column.size_flags_horizontal = box.size_flags_horizontal
	column.size_flags_vertical = box.size_flags_vertical
	column.add_theme_constant_override("separation", box.get_theme_constant("separation"))
	parent.add_child(column)
	parent.move_child(column, index)
	column.owner = box.owner
	for child in box.get_children():
		child.reparent(column)
	box.queue_free()
	return column


## 창 판의 폭: 원하는 폭과 화면 폭(양옆 여백 12) 중 작은 쪽
static func fit_width(control: Control, desired: float) -> void:
	var view: float = control.get_viewport_rect().size.x if control.is_inside_tree() else float(PORTRAIT_SIZE.x if portrait else LANDSCAPE_SIZE.x)
	control.custom_minimum_size.x = minf(desired, view - 24.0)


## 한 줄(이름표 + 버튼들). 세로면 이름표 아래에 버튼을 줄바꿈으로 놓는다.
## 돌려주는 값: [줄(부모에 넣을 것), 버튼을 넣을 상자]
static func make_row() -> Array:
	if not portrait:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		return [row, row]
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 6)
	return [column, buttons]
