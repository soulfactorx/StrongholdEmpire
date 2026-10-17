class_name UiTheme
extends RefCounted

## 수묵담채 색: 한지 바탕에 먹 글씨, 주홍·옥색·황토를 포인트로 쓴다.
static var COLORS: Dictionary = {
	"bg_dark": Color("#2a2620"),
	"bg_panel": Color("#f2ead8"),
	"accent_red": Color("#b23a2b"),
	"accent_gold": Color("#8c6420"),
	"accent_jade": Color("#2f6b5e"),
	"text_primary": Color("#1e1e1e"),
	"text_muted": Color("#6b655b"),
	"text_on_ink": Color("#f2ead8"),
}


## 본문 기본 글자 크기와 옵션의 글자 크기 배율 (GameSettings가 정한다)
const BASE_FONT_SIZE := 16
## 작은 글자(보조 설명)도 이보다 작게 하지 않는다
const MIN_FONT_SIZE := 14
## 이 크기 이상인 라벨은 제목으로 보고 붓글씨 글꼴을 쓴다.
const TITLE_FONT_SIZE := 22
static var text_scale: float = 1.0


## 글자 크기 배율을 적용한 크기
static func font_size(base: int) -> int:
	return roundi(maxi(base, MIN_FONT_SIZE) * text_scale)


static func apply_to_control(root: Control) -> void:
	ArtAssets.apply_background(root)
	_style_recursive(root)
	apply_safe_area(root)


## 창 전체 테마: 글꼴과 기본 글자색·버튼·패널 모양.
## 코드로 만든 라벨·버튼도 한지 화면에 맞는 모양이 되게 한다.
static func apply_root_theme(theme: Theme) -> void:
	var font: Font = ArtAssets.body_font()
	if font:
		theme.default_font = font
	for type in ["Label", "CheckBox", "CheckButton", "LinkButton"]:
		theme.set_color("font_color", type, COLORS["text_primary"])
	theme.set_color("default_color", "RichTextLabel", COLORS["text_primary"])
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_color("font_color", type, COLORS["text_primary"])
		theme.set_color("font_focus_color", type, COLORS["text_primary"])
		theme.set_color("font_hover_color", type, COLORS["accent_gold"])
		theme.set_color("font_pressed_color", type, COLORS["text_on_ink"])
		theme.set_color("font_hover_pressed_color", type, COLORS["text_on_ink"])
		theme.set_color("font_disabled_color", type, COLORS["text_muted"])
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type, _button_style(state))
	# 목록·입력칸·펼침 메뉴도 한지 바탕에 먹 글씨로
	var field := _field_style(COLORS["bg_panel"].lightened(0.3), COLORS["text_muted"])
	var selected := _field_style(COLORS["accent_jade"], COLORS["accent_jade"])
	theme.set_stylebox("panel", "ItemList", field)
	theme.set_stylebox("focus", "ItemList", _field_style(Color.TRANSPARENT, COLORS["accent_gold"]))
	for state in ["selected", "selected_focus", "cursor", "cursor_unfocused"]:
		theme.set_stylebox(state, "ItemList", selected if state.begins_with("selected") else _field_style(Color.TRANSPARENT, COLORS["accent_gold"]))
	theme.set_stylebox("hovered", "ItemList", _field_style(Color("#e9d9b4"), Color("#e9d9b4")))
	theme.set_color("font_color", "ItemList", COLORS["text_primary"])
	theme.set_color("font_hovered_color", "ItemList", COLORS["text_primary"])
	theme.set_color("font_selected_color", "ItemList", COLORS["text_on_ink"])
	theme.set_color("font_hovered_selected_color", "ItemList", COLORS["text_on_ink"])
	for type in ["LineEdit", "TextEdit", "SpinBox"]:
		theme.set_stylebox("normal", type, field)
		theme.set_stylebox("focus", type, _field_style(Color.TRANSPARENT, COLORS["accent_gold"]))
		theme.set_stylebox("read_only", type, field)
		theme.set_color("font_color", type, COLORS["text_primary"])
		theme.set_color("font_placeholder_color", type, COLORS["text_muted"])
		theme.set_color("caret_color", type, COLORS["text_primary"])
		theme.set_color("selection_color", type, Color(COLORS["accent_jade"], 0.4))
	theme.set_stylebox("panel", "PopupMenu", create_panel_style())
	theme.set_stylebox("hover", "PopupMenu", _field_style(Color("#e9d9b4"), Color("#e9d9b4")))
	theme.set_color("font_color", "PopupMenu", COLORS["text_primary"])
	theme.set_color("font_hover_color", "PopupMenu", COLORS["text_primary"])
	theme.set_color("font_disabled_color", "PopupMenu", COLORS["text_muted"])
	theme.set_stylebox("panel", "PanelContainer", create_panel_style())
	theme.set_stylebox("panel", "TooltipPanel", create_panel_style())
	theme.set_color("font_color", "TooltipLabel", COLORS["text_primary"])


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


## 패널: 한지 9분할 텍스처. 그림이 없으면 단색으로 대신한다.
static func create_panel_style() -> StyleBox:
	var tex: Texture2D = ArtAssets.ui("panel")
	if tex == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = COLORS["bg_panel"]
		flat.border_color = COLORS["text_primary"]
		flat.set_border_width_all(1)
		flat.set_corner_radius_all(6)
		_set_content_margins(flat, 12, 10)
		return flat
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.set_texture_margin_all(16)
	_set_content_margins(style, 16, 14)
	return style


## 목록·입력칸 바탕: 밝은 한지에 가는 테두리
static func _field_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_set_content_margins(style, 8, 6)
	return style


static func _set_content_margins(style: StyleBox, horizontal: float, vertical: float) -> void:
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical


## 버튼 상태별 모양: 한지 바탕에 먹 테두리, 가리키면 황토 테, 누르면 주홍.
static func _button_style(state: String) -> StyleBox:
	if state == "focus":
		var focus := StyleBoxFlat.new()
		focus.draw_center = false
		focus.border_color = COLORS["accent_gold"]
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(6)
		return focus
	var tex: Texture2D = ArtAssets.ui("button_%s" % state)
	if tex == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = {
			"normal": COLORS["bg_panel"], "hover": Color("#f5e2b8"),
			"pressed": COLORS["accent_red"], "disabled": Color("#d6cdbb"),
		}[state]
		flat.border_color = COLORS["text_muted"] if state == "disabled" else COLORS["text_primary"]
		flat.set_border_width_all(1)
		flat.set_corner_radius_all(4)
		_set_content_margins(flat, 10, 8)
		return flat
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.set_texture_margin_all(10)
	_set_content_margins(style, 12, 8)
	return style


static func style_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _button_style(state))
	button.add_theme_color_override("font_disabled_color", COLORS["text_muted"])
	button.add_theme_color_override("font_color", COLORS["text_primary"])
	# 키보드·게임패드 포커스가 있을 때도 먹 글씨로 (기본값은 흰 글씨라 한지 바탕에서 안 보인다)
	button.add_theme_color_override("font_focus_color", COLORS["text_primary"])
	button.add_theme_color_override("font_hover_color", COLORS["accent_gold"])
	button.add_theme_color_override("font_pressed_color", COLORS["text_on_ink"])
	button.add_theme_color_override("font_hover_pressed_color", COLORS["text_on_ink"])


static func style_label_title(label: Label, size: int = 24) -> void:
	set_font_size(label, size)
	label.add_theme_color_override("font_color", COLORS["accent_gold"])
	_use_brush_font(label)


## 제목 라벨에 붓글씨 글꼴을 쓴다. 붓글씨는 획이 가늘어 조금 크게 한다. (한 번만)
static func _use_brush_font(label: Label) -> void:
	var font: Font = ArtAssets.brush_font()
	if font == null or label.has_meta("brush_font"):
		return
	label.set_meta("brush_font", true)
	label.add_theme_font_override("font", font)
	set_font_size(label, roundi(label.get_meta("base_font_size", BASE_FONT_SIZE) * 1.25))


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
		var base: int = label.get_meta("base_font_size", 0)
		if base >= TITLE_FONT_SIZE:
			label.add_theme_color_override("font_color", COLORS["accent_gold"])
			_use_brush_font(label)
		elif base >= 20:
			label.add_theme_color_override("font_color", COLORS["accent_gold"])
		else:
			label.add_theme_color_override("font_color", COLORS["text_primary"])
	for child in node.get_children():
		_style_recursive(child)
