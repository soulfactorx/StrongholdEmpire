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


static func apply_to_control(root: Control) -> void:
	if root is ColorRect:
		pass
	_style_recursive(root)


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
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLORS["accent_gold"])


static func _style_recursive(node: Node) -> void:
	if node is Button:
		style_button(node as Button)
	elif node is PanelContainer:
		(node as PanelContainer).add_theme_stylebox_override("panel", create_panel_style())
	elif node is Label:
		var label := node as Label
		if label.get_theme_font_size("font_size") >= 20:
			label.add_theme_color_override("font_color", COLORS["accent_gold"])
		else:
			label.add_theme_color_override("font_color", COLORS["text_primary"])
	for child in node.get_children():
		_style_recursive(child)