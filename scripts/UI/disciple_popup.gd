extends Control

## 제자 명단 팝업: 제자마다 능력치·배치·출전을 보여 주고, 배치·출전 지정·개별 수련을 한다.
## 화면 구성은 코드로 만든다. 버튼은 모두 48px 이상이고, 목록은 끌어서 스크롤한다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 명단을 바꾼 결과 (success, message)
signal changed(result: Dictionary)

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
	title.text = "제자 명단"
	_UiTheme.style_label_title(title, 24)
	box.add_child(title)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size", 14)
	box.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 440)
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
	var sect: SectData = GameManager.player_sect
	var slot_texts: PackedStringArray = []
	for facility in DiscipleRoster.ASSIGNMENTS:
		slot_texts.append("%s %d/%d" % [
			DiscipleRoster.ASSIGNMENTS[facility]["name"],
			DiscipleRoster.get_assigned(sect, facility).size(),
			DiscipleRoster.get_slots(sect, facility),
		])
	_summary.text = "제자 %d명 · 배치 %s · 출전 지정 %d/%d\n%s\n개별 수련: 금화 %d로 경험치 +%d (제자마다 계절에 한 번)" % [
		sect.disciples.size(), ", ".join(slot_texts),
		DiscipleRoster.get_deployed_count(sect), _Balance.DEFENSE_ALLY_COUNT,
		" / ".join(DiscipleRoster.ASSIGNMENTS.values().map(func(a: Dictionary) -> String: return "%s: %s" % [a["name"], a["effect"]])),
		_Balance.DISCIPLE_TRAIN_GOLD, _Balance.DISCIPLE_TRAIN_EXP,
	]
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var ordered: Array[DiscipleData] = sect.disciples.duplicate()
	ordered.sort_custom(func(a: DiscipleData, b: DiscipleData) -> bool: return a.get_power() > b.get_power())
	var turn: int = GameManager._get_turn_index()
	for disciple in ordered:
		_rows.add_child(_make_row(disciple, turn))


func _make_row(disciple: DiscipleData, turn: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s  Lv.%d (%d/%d)\n무력 %d · 신법 %d · 지혜 %d · 참전 %d회" % [
		disciple.display_name, disciple.level, disciple.experience, disciple.get_next_level_experience(),
		disciple.strength, disciple.agility, disciple.wisdom, disciple.battles,
	]
	row.add_child(label)

	var assign_button := Button.new()
	assign_button.custom_minimum_size = Vector2(150, 48)
	var assignment: String = disciple.assignment
	assign_button.text = "배치: %s" % (
		DiscipleRoster.ASSIGNMENTS[assignment]["name"] if DiscipleRoster.ASSIGNMENTS.has(assignment) else "없음"
	)
	assign_button.pressed.connect(_on_assign_pressed.bind(disciple.id))
	row.add_child(assign_button)

	var deploy_button := Button.new()
	deploy_button.custom_minimum_size = Vector2(130, 48)
	deploy_button.text = "출전 ✔" if disciple.deployed else "출전 지정"
	deploy_button.pressed.connect(_on_deploy_pressed.bind(disciple.id))
	row.add_child(deploy_button)

	var train_button := Button.new()
	train_button.custom_minimum_size = Vector2(130, 48)
	train_button.text = "수련 (금화 %d)" % _Balance.DISCIPLE_TRAIN_GOLD
	train_button.disabled = (
		disciple.last_train_turn == turn
		or disciple.level >= _Balance.DISCIPLE_MAX_LEVEL
		or GameManager.player_sect.gold < _Balance.DISCIPLE_TRAIN_GOLD
	)
	train_button.pressed.connect(_on_train_pressed.bind(disciple.id))
	row.add_child(train_button)
	for button in [assign_button, deploy_button, train_button]:
		_UiTheme.style_button(button)
	return row


func _on_assign_pressed(disciple_id: String) -> void:
	_apply(DiscipleRoster.cycle_assignment(GameManager.player_sect, disciple_id))


func _on_deploy_pressed(disciple_id: String) -> void:
	_apply(DiscipleRoster.toggle_deploy(GameManager.player_sect, disciple_id))


func _on_train_pressed(disciple_id: String) -> void:
	_apply(DiscipleRoster.train(GameManager.player_sect, disciple_id, GameManager._get_turn_index()))


func _apply(result: Dictionary) -> void:
	changed.emit(result)
	refresh()
