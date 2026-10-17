class_name UiTheme
extends RefCounted

static var COLORS: Dictionary = {
	"bg_dark": Color(0.08, 0.1, 0.14),
	"bg_panel": Color(0.12, 0.14, 0.18),
	"accent_red": Color(0.85, 0.3, 0.25),
	"accent_gold": Color(0.9, 0.75, 0.35),
	"accent_jade": Color(0.3, 0.65, 0.5),
	"text_primary": Color(0.92, 0.9, 0.85),
	"text_muted": Color(0.6, 0.62, 0.68),
}


## 본문 기본 글자 크기와 옵션의 글자 크기 배율 (GameSettings가 정한다)
const BASE_FONT_SIZE := 16
## 작은 글자(보조 설명)도 이보다 작게 하지 않는다
const MIN_FONT_SIZE := 14
static var text_scale: float = 1.0


## 글자 크기 배율을 적용한 크기
static func font_size(base: int) -> int:
	return roundi(maxi(base, MIN_FONT_SIZE) * text_scale)


static func apply_to_control(root: Control) -> void:
	_style_recursive(root)
	apply_safe_area(root)


## 휴대폰 노치·홈 바를 피하도록 화면의 바깥 여백(Margin)에 안전 영역을 더한다.
static func apply_safe_area(root: Control) -> void:
	var margin: MarginContainer = root.get_node_or_null("Margin") as MarginContainer
	if margin == null or margin.has_meta("safe_area_applied"):
		return
	margin.set_meta("safe_area_applied", true)
	var screen: Vector2i = DisplayServer.screen_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if screen.x <= 0 or safe.size.x <= 0 or safe.size == screen:
		return
	# 화면 픽셀을 뷰포트 좌표로 바꾼다.
	var scale: float = root.get_viewport_rect().size.x / float(screen.x)
	var insets: Dictionary = {
		"margin_left": safe.position.x,
		"margin_top": safe.position.y,
		"margin_right": screen.x - safe.end.x,
		"margin_bottom": screen.y - safe.end.y,
	}
	for side in insets:
		var base: int = margin.get_theme_constant(side)
		margin.add_theme_constant_override(side, base + roundi(maxi(0, insets[side]) * scale))


static func create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLORS["bg_panel"]
	style.border_color = COLORS["accent_gold"]
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func style_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.2, 0.26)
	normal.border_color = COLORS["accent_gold"]
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8

	var hover := normal.duplicate()
	hover.bg_color = Color(0.25, 0.22, 0.18)

	var pressed := normal.duplicate()
	pressed.bg_color = COLORS["accent_red"]

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.13, 0.14, 0.17)
	disabled.border_color = COLORS["text_muted"]

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", COLORS["text_muted"])
	button.add_theme_color_override("font_color", COLORS["text_primary"])
	button.add_theme_color_override("font_hover_color", COLORS["accent_gold"])


static func style_label_title(label: Label, size: int = 24) -> void:
	set_font_size(label, size)
	label.add_theme_color_override("font_color", COLORS["accent_gold"])


## 글자 크기를 정한다. 기준 크기를 기록해 두어 배율이 두 번 곱해지지 않게 한다.
static func set_font_size(control: Control, base: int) -> void:
	control.set_meta("base_font_size", base)
	control.add_theme_font_size_override("font_size", font_size(base))


## 따로 정한 글자 크기가 있는 라벨에도 글자 크기 배율과 최소 크기를 적용한다. (한 번만)
static func _scale_font(control: Control) -> void:
	if not control.has_theme_font_size_override("font_size"):
		return
	var base: int = control.get_meta("base_font_size", control.get_theme_font_size("font_size"))
	control.set_meta("base_font_size", base)
	control.add_theme_font_size_override("font_size", font_size(base))


static func _style_recursive(node: Node) -> void:
	if node is Button:
		style_button(node as Button)
	elif node is PanelContainer:
		(node as PanelContainer).add_theme_stylebox_override("panel", create_panel_style())
	elif node is Label:
		var label := node as Label
		_scale_font(label)
		if label.get_theme_font_size("font_size") >= 20:
			label.add_theme_color_override("font_color", COLORS["accent_gold"])
		else:
			label.add_theme_color_override("font_color", COLORS["text_primary"])
	for child in node.get_children():
		_style_recursive(child)