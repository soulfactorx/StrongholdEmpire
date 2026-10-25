extends Control

## 신분 전환 창: 지금 고를 수 있는 전환(위 목록)과, 지금 신분에서 갈 수 있는 모든 길의 조건 안내(아래).
## 조건마다 채웠는지를 색으로 보인다 (채움: 옥색, 못 채움: 붉은색). 고를 전환이 없어도 안내를 보려고 열 수 있다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

@onready var title_label: Label = %RoleTitleLabel
@onready var desc_label: Label = %RoleDescLabel
@onready var option_list: ItemList = %RoleOptionList
@onready var confirm_button: Button = $Center/Panel/VBox/ConfirmButton

## 조건 안내 (테스트에서 줄 수를 본다)
var guide_box: VBoxContainer
## 고른 전환의 설명
var option_desc_label: Label


func _ready() -> void:
	var panel: Control = $Center/Panel
	LayoutMode.fit_width(panel, 760)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 목록에는 이름만, 고른 전환의 설명은 아래 글로 (휴대폰에서 잘리지 않게)
	option_list.auto_height = true
	# 줄 높이를 터치하기 좋게 (48px 안팎)
	option_list.add_theme_constant_override("v_separation", 24)
	option_list.custom_minimum_size.y = 0
	option_desc_label = Label.new()
	option_desc_label.name = "OptionDescLabel"
	option_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(option_desc_label, 15)
	option_list.get_parent().add_child(option_desc_label)
	option_list.get_parent().move_child(option_desc_label, option_list.get_index() + 1)
	option_list.item_selected.connect(_show_option_desc)
	var guide_title := Label.new()
	guide_title.text = "신분 전환 안내 — 갈 수 있는 길과 조건"
	_UiTheme.style_label_title(guide_title, 18)
	var scroll := ScrollContainer.new()
	scroll.name = "GuideScroll"
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	guide_box = VBoxContainer.new()
	guide_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_box.add_theme_constant_override("separation", 4)
	scroll.add_child(guide_box)
	var box: Node = option_list.get_parent()
	box.add_child(guide_title)
	box.move_child(guide_title, confirm_button.get_index())
	box.add_child(scroll)
	box.move_child(scroll, confirm_button.get_index())


func show_options(options: Array[Dictionary]) -> void:
	var character: CharacterData = GameManager.player_character
	title_label.text = "신분 전환 — 지금: %s" % character.get_role_name()
	desc_label.text = (
		"조건을 채운 새 신분이 있습니다. 하나를 골라 [전환 확정]을 누르세요." if not options.is_empty()
		else "아직 조건을 채운 전환이 없습니다. 아래 안내에서 필요한 조건을 확인하세요."
	)
	option_list.clear()
	for option in options:
		option_list.add_item(option["title"])
	option_list.visible = not options.is_empty()
	option_desc_label.visible = not options.is_empty()
	confirm_button.disabled = options.is_empty()
	if not options.is_empty():
		option_list.select(0)
		_show_option_desc(0)
	_fill_guide()
	visible = true


## 지금 신분에서 갈 수 있는 길마다 조건을 한 줄씩. 채운 조건은 옥색, 못 채운 조건은 붉은색.
func _fill_guide() -> void:
	for child in guide_box.get_children():
		guide_box.remove_child(child)
		child.queue_free()
	var paths: Array[Dictionary] = RoleManager.get_transition_guide(GameManager)
	if paths.is_empty():
		_add_line("이 신분에서 갈 수 있는 길이 없습니다.", _UiTheme.COLORS["text_muted"], 15)
	for path in paths:
		var head: String = "%s — %s" % [path["title"], "지금 가능" if path["available"] else "조건 부족"]
		_add_line(head, _UiTheme.COLORS["accent_gold"] if path["available"] else _UiTheme.COLORS["text_primary"], 16)
		for condition in path["conditions"]:
			_add_line("    · " + condition["text"], _UiTheme.COLORS["accent_jade"] if condition["ok"] else _UiTheme.COLORS["accent_red"], 14)
		if path.has("alt"):
			_add_line("    · " + path["alt"]["text"], _UiTheme.COLORS["accent_jade"] if path["alt"]["ok"] else _UiTheme.COLORS["text_muted"], 14)
	_add_line("자동 전환: 총관은 실책 %d회나 신임도 0이면 막내 제자로 강등, 문주는 불만도 %d이면 쫓겨납니다." % [
		_Balance.DEMOTION_FAILURES, _Balance.DISCONTENT_OUSTED,
	], _UiTheme.COLORS["text_muted"], 13)


func _show_option_desc(index: int) -> void:
	var options: Array[Dictionary] = GameManager.pending_role_transitions
	option_desc_label.text = str(options[index]["description"]) if index < options.size() else ""


func get_guide_line_count() -> int:
	return guide_box.get_child_count()


func _add_line(text: String, color: Color, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	_UiTheme.set_font_size(label, size)
	guide_box.add_child(label)


func _on_confirm_pressed() -> void:
	var selected: PackedInt32Array = option_list.get_selected_items()
	if selected.is_empty():
		return
	var options: Array[Dictionary] = GameManager.pending_role_transitions
	if selected[0] >= options.size():
		return
	var option: Dictionary = options[selected[0]]
	GameManager.apply_role_transition(option["role"], option)
	visible = false


func _on_close_pressed() -> void:
	visible = false
