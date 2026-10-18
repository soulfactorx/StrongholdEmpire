class_name Toast
extends RefCounted

## 화면 아래쪽에 잠깐 떠서 행동 결과를 알리는 안내(토스트).
## 안내 줄(log_label)이 보이지 않는 곳(세로 경영 화면의 다른 탭, 무공·지도·외교·문파전 화면)에서도 결과를 바로 알 수 있게 한다.
## 화면마다 하나를 같이 쓰고 맨 위 층(CanvasLayer)에 둔다. 누르기를 막지 않으며 잠시 뒤 저절로 사라진다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

const LAYER := 90
## 보이는 시간: 기본 + 글자 수만큼, 최대값까지
const BASE_TIME := 2.5
const PER_CHAR_TIME := 0.04
const MAX_TIME := 7.0
const FADE_TIME := 0.25


## 안내를 띄운다. 같은 화면에 이미 떠 있으면 내용을 바꾸고 시간을 다시 잰다.
static func notify(host: Node, text: String, is_error: bool = false) -> void:
	if host == null or not host.is_inside_tree() or text.strip_edges().is_empty():
		return
	var panel: PanelContainer = _get_panel(host)
	var label: Label = panel.get_child(0)
	label.text = text.strip_edges()
	label.add_theme_color_override("font_color", _UiTheme.COLORS["accent_red"] if is_error else _UiTheme.COLORS["text_primary"])
	panel.visible = true
	panel.modulate.a = 0.0
	var old: Tween = panel.get_meta("tween", null)
	if old != null and old.is_valid():
		old.kill()
	var tween: Tween = panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, FADE_TIME)
	tween.tween_interval(minf(BASE_TIME + PER_CHAR_TIME * text.length(), MAX_TIME))
	tween.tween_property(panel, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(func() -> void: panel.visible = false)
	panel.set_meta("tween", tween)


## 결과 {success, message}를 띄운다. 실패는 붉은 글씨
static func notify_result(host: Node, result: Dictionary) -> void:
	notify(host, str(result.get("message", "")), not result.get("success", true))


## 지금 떠 있는 안내 글 (없으면 빈 문자열, 테스트용)
static func get_text(host: Node) -> String:
	var scene: Node = _scene_of(host)
	if scene == null or not scene.has_node("ToastLayer/Toast"):
		return ""
	var panel: PanelContainer = scene.get_node("ToastLayer/Toast")
	return panel.get_child(0).text if panel.visible else ""


static func _scene_of(host: Node) -> Node:
	if host == null or not host.is_inside_tree():
		return null
	var tree: SceneTree = host.get_tree()
	return tree.current_scene if tree.current_scene else tree.root


static func _get_panel(host: Node) -> PanelContainer:
	var scene: Node = _scene_of(host)
	var layer: CanvasLayer = scene.get_node_or_null("ToastLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "ToastLayer"
		layer.layer = LAYER
		scene.add_child(layer)
		var panel := PanelContainer.new()
		panel.name = "Toast"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# CanvasLayer 아래는 창 테마를 이어받지 않으므로 직접 준다 (글꼴이 깨지지 않게)
		panel.theme = host.get_tree().root.theme
		panel.add_theme_stylebox_override("panel", _UiTheme.create_panel_style())
		# 화면 아래쪽 폭 가득 (양옆 16), 글이 길면 위로 늘어난다
		panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		panel.offset_left = 16
		panel.offset_right = -16
		panel.offset_bottom = -(140 if LayoutMode.is_portrait() else 90)
		panel.offset_top = panel.offset_bottom
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_UiTheme.set_font_size(label, 18)
		panel.add_child(label)
		panel.visible = false
		layer.add_child(panel)
	return layer.get_node("Toast")
