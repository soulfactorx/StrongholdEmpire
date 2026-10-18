extends Control

## 인연 팝업: 관계가 있는 인물마다 대화·선물·비무를 한다. 화면 구성은 코드로 만든다.
## 버튼은 모두 48px 이상이고, 목록은 끌어서 스크롤한다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 상호작용 결과 (success, message)
signal acted(result: Dictionary)

var _summary: Label
## 방금 오간 대사
var dialogue_label: Label
## 방금 한 일의 결과 (유대 변화, 할 수 없는 까닭)
var notice_label: Label
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
	# 세로 화면(휴대폰)에서는 화면 폭에 맞춘다
	LayoutMode.fit_width(panel, 900)
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
	notice_label = _UiTheme.make_notice()
	box.add_child(notice_label)
	dialogue_label = Label.new()
	dialogue_label.name = "DialogueLabel"
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.visible = false
	_UiTheme.set_font_size(dialogue_label, 16)
	box.add_child(dialogue_label)

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
	dialogue_label.visible = false
	notice_label.visible = false
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


## 가로: 초상화·이름표·버튼을 한 줄에. 세로(휴대폰): 초상화·이름표 아래에 버튼.
func _make_row(rel: RelationshipData, can_act: bool) -> Container:
	var parts: Array = LayoutMode.make_row()
	var row: Container = parts[0]
	var buttons: Container = parts[1]
	var head: Container = row
	if buttons != row:
		head = HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		row.add_child(head)
		row.add_child(buttons)
	# 초상화 (그림이 없으면 같은 크기의 빈칸으로 줄을 맞춘다)
	var picture: Control = ArtAssets.picture_rect(ArtAssets.portrait(rel.target_id), Vector2(64, 80))
	if picture == null:
		picture = Control.new()
		picture.custom_minimum_size = Vector2(64, 80)
	head.add_child(picture)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var npc: Dictionary = NpcRoster.get_npc(rel.target_id)
	var liked: PackedStringArray = []
	for like in NpcAgent.get_likes(rel.target_id):
		liked.append(NpcAgent.LIKE_NAMES[like])
	label.text = "%s — %s\n%s %d · %s · 좋아함: %s" % [
		rel.target_name, npc.get("title", ""), rel.get_bond_name(), rel.bond_strength, rel.get_stage_name(), ", ".join(liked),
	]
	head.add_child(label)
	# 길게 누르면(마우스는 올려 두면) 성향과 취향을 본다.
	var target_id: String = rel.target_id
	LongPressTip.attach(label, func() -> String: return "%s의 성향\n%s\n좋아하는 일을 하면 유대가 %d%% 더 오릅니다." % [
		NpcRoster.get_display_name(target_id), NpcAgent.describe(target_id), roundi((_Balance.LIKE_BOND_MULTIPLIER - 1.0) * 100),
	])
	for kind in RelationshipManager.INTERACTIONS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(130, 48)
		button.text = RelationshipManager.INTERACTIONS[kind]
		button.disabled = not can_act or (kind == "spar" and rel.bond_type == RelationshipData.BondType.HATRED)
		button.pressed.connect(_on_interact_pressed.bind(rel.target_id, kind))
		_UiTheme.style_button(button)
		buttons.add_child(button)
	return row


func _on_interact_pressed(target_id: String, kind: String) -> void:
	# 비무는 전투로 넘어가므로 바로 시작한다.
	if kind == "spar":
		_interact(target_id, kind)
		return
	var title: String = RelationshipManager.INTERACTIONS[kind]
	ActionPreview.confirm(self, title, _simulate_interact.bind(target_id, kind), _interact.bind(target_id, kind))


func _simulate_interact(target_id: String, kind: String) -> Dictionary:
	return RelationshipManager.interact(
		GameManager.player_relationships, target_id, kind, GameManager.player_character,
		GameManager.player_sect, GameManager.story_flags, GameManager._get_turn_index()
	)


func _interact(target_id: String, kind: String) -> void:
	var result: Dictionary = GameManager.interact_with(target_id, kind)
	_UiTheme.show_notice(notice_label, result)
	var lines: PackedStringArray = result.get("dialogue", PackedStringArray())
	dialogue_label.text = "\n".join(lines)
	dialogue_label.visible = not lines.is_empty()
	acted.emit(result)
	if is_inside_tree():
		refresh()
