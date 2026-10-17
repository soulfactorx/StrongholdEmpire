extends Control

## 인연 팝업: 관계가 있는 인물마다 대화·선물·비무를 한다. 화면 구성은 코드로 만든다.
## 버튼은 모두 48px 이상이고, 목록은 끌어서 스크롤한다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 상호작용 결과 (success, message)
signal acted(result: Dictionary)

var _summary: Label
var _rows: VBoxContainer


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "인연"
	_UiTheme.style_label_title(title, 24)
	box.add_child(title)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(_summary, 14)
	box.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)

	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void: visible = false)
	box.add_child(close)
	_UiTheme.apply_to_control(panel)


func open() -> void:
	refresh()
	visible = true


func get_row_count() -> int:
	return _rows.get_child_count()


func refresh() -> void:
	var left: int = RelationshipManager.get_interactions_left(GameManager.story_flags, GameManager._get_turn_index())
	_summary.text = "이번 계절 남은 상호작용 %d/%d · 대화: 유대 +%d(매력에 따라 더) · 선물: 금화 %d로 유대 +%d · 비무: 이기면 유대 +%d\n원한이 있는 상대와 대화·선물하면 원한이 누그러집니다. 유대 %d 이상인 사제·혈맹·연인은 방어전에 함께 싸웁니다." % [
		left, _Balance.INTERACTIONS_PER_SEASON, _Balance.TALK_BOND, _Balance.GIFT_GOLD, _Balance.GIFT_BOND,
		_Balance.SPAR_BOND_WIN, _Balance.BOND_ALLY_MIN,
	]
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for rel in GameManager.player_relationships:
		_rows.add_child(_make_row(rel, left > 0))


func _make_row(rel: RelationshipData, can_act: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	# 초상화 (그림이 없으면 같은 크기의 빈칸으로 줄을 맞춘다)
	var picture: Control = ArtAssets.picture_rect(ArtAssets.portrait(rel.target_id), Vector2(64, 80))
	if picture == null:
		picture = Control.new()
		picture.custom_minimum_size = Vector2(64, 80)
	row.add_child(picture)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var npc: Dictionary = NpcRoster.get_npc(rel.target_id)
	label.text = "%s — %s\n%s %d · %s" % [
		rel.target_name, npc.get("title", ""), rel.get_bond_name(), rel.bond_strength, rel.get_stage_name(),
	]
	row.add_child(label)
	for kind in RelationshipManager.INTERACTIONS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(130, 48)
		button.text = RelationshipManager.INTERACTIONS[kind]
		button.disabled = not can_act or (kind == "spar" and rel.bond_type == RelationshipData.BondType.HATRED)
		button.pressed.connect(_on_interact_pressed.bind(rel.target_id, kind))
		_UiTheme.style_button(button)
		row.add_child(button)
	return row


func _on_interact_pressed(target_id: String, kind: String) -> void:
	var result: Dictionary = GameManager.interact_with(target_id, kind)
	acted.emit(result)
	if is_inside_tree():
		refresh()
