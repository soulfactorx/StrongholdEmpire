extends Control

## 제자 명단 팝업: 제자마다 능력치·배치·출전을 보여 주고, 배치·출전 지정·개별 수련을 한다.
## 화면 구성은 코드로 만든다. 버튼은 모두 48px 이상이고, 목록은 끌어서 스크롤한다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")
const _ChoicePopup = preload("res://scripts/UI/choice_popup.gd")

## 명단을 바꾼 결과 (success, message)
signal changed(result: Dictionary)

var _summary: Label
## 방금 한 일(배치·출전·수련·전수)의 결과
var notice_label: Label
var _rows: VBoxContainer
## 전수할 무공을 고르는 팝업
var art_choice: Control
## 전수받을 제자 id
var _transmit_target: String = ""


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
	LayoutMode.fit_width(panel, 1040)
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
	_UiTheme.set_font_size(_summary, 14)
	box.add_child(_summary)
	notice_label = _UiTheme.make_notice()
	box.add_child(notice_label)

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
	art_choice = _ChoicePopup.new()
	add_child(art_choice)
	art_choice.chosen.connect(_on_art_chosen)


func open() -> void:
	notice_label.visible = false
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


## 가로: 한 줄에 이름표와 버튼. 세로(휴대폰): 이름표 아래에 버튼을 줄바꿈으로 둔다.
func _make_row(disciple: DiscipleData, turn: int) -> Container:
	var parts: Array = LayoutMode.make_row()
	var row: Container = parts[0]
	var buttons: Container = parts[1]
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s  Lv.%d (%d/%d) · %s\n무력 %d · 신법 %d · 지혜 %d · 참전 %d회" % [
		disciple.display_name, disciple.level, disciple.experience, disciple.get_next_level_experience(),
		"[%s]" % disciple.martial_art.display_name if disciple.martial_art else "무공 없음",
		disciple.strength, disciple.agility, disciple.wisdom, disciple.battles,
	]
	row.add_child(label)
	if buttons != row:
		row.add_child(buttons)

	var assign_button := Button.new()
	assign_button.custom_minimum_size = Vector2(150, 48)
	var assignment: String = disciple.assignment
	assign_button.text = "배치: %s" % (
		DiscipleRoster.ASSIGNMENTS[assignment]["name"] if DiscipleRoster.ASSIGNMENTS.has(assignment) else "없음"
	)
	assign_button.pressed.connect(_on_assign_pressed.bind(disciple.id))
	buttons.add_child(assign_button)

	var deploy_button := Button.new()
	deploy_button.custom_minimum_size = Vector2(130, 48)
	deploy_button.text = "출전 중 ○" if disciple.deployed else "출전 지정"
	deploy_button.pressed.connect(_on_deploy_pressed.bind(disciple.id))
	buttons.add_child(deploy_button)

	var train_button := Button.new()
	train_button.custom_minimum_size = Vector2(130, 48)
	train_button.text = "수련 (금화 %d)" % _Balance.DISCIPLE_TRAIN_GOLD
	train_button.disabled = (
		disciple.last_train_turn == turn
		or disciple.level >= _Balance.DISCIPLE_MAX_LEVEL
		or GameManager.player_sect.gold < _Balance.DISCIPLE_TRAIN_GOLD
	)
	train_button.pressed.connect(_on_train_pressed.bind(disciple.id))
	buttons.add_child(train_button)

	var transmit_button := Button.new()
	transmit_button.custom_minimum_size = Vector2(110, 48)
	transmit_button.text = "무공 전수"
	transmit_button.disabled = GameManager.player_character.martial_arts.is_empty()
	transmit_button.pressed.connect(_on_transmit_pressed.bind(disciple.id))
	buttons.add_child(transmit_button)
	for button in [assign_button, deploy_button, train_button, transmit_button]:
		_UiTheme.style_button(button)
	return row


func _on_assign_pressed(disciple_id: String) -> void:
	_apply(DiscipleRoster.cycle_assignment(GameManager.player_sect, disciple_id))


func _on_deploy_pressed(disciple_id: String) -> void:
	_apply(DiscipleRoster.toggle_deploy(GameManager.player_sect, disciple_id))


func _on_train_pressed(disciple_id: String) -> void:
	var train := func() -> Dictionary:
		return DiscipleRoster.train(GameManager.player_sect, disciple_id, GameManager._get_turn_index())
	var name: String = DiscipleRoster.get_disciple(GameManager.player_sect, disciple_id).display_name
	ActionPreview.confirm(self, "제자 개별 수련", train, func() -> void: _apply(train.call(), "disciple_train", name))


func _on_transmit_pressed(disciple_id: String) -> void:
	var sect: SectData = GameManager.player_sect
	var disciple: DiscipleData = DiscipleRoster.get_disciple(sect, disciple_id)
	var options: Array[Dictionary] = []
	for art in GameManager.player_character.martial_arts:
		var tags: PackedStringArray = []
		if sect.secret_art and sect.secret_art.id == art.id:
			tags.append("문파 비전")
		var need: int = DiscipleRoster.get_transmit_level(art)
		var cost: int = DiscipleRoster.get_transmit_cost(sect, art)
		# 전수할 수 없는 무공은 까닭을 적고 고를 수 없게 한다 (눌러도 아무 일이 없는 것처럼 보이지 않게)
		var blocked: String = ""
		if disciple.martial_art and disciple.martial_art.id == art.id:
			blocked = "이미 익힘"
		elif disciple.level < need:
			blocked = "제자 Lv.%d 필요 (지금 Lv.%d)" % [need, disciple.level]
		elif sect.research_points < cost:
			blocked = "연구점 부족 (%d / %d)" % [sect.research_points, cost]
		if not blocked.is_empty():
			tags.append(blocked)
		options.append({
			"id": art.id,
			"title": "%s%s" % [art.display_name, " (%s)" % ", ".join(tags) if not tags.is_empty() else ""],
			"description": "연구점 %d · %s" % [cost, art.get_stats_text()],
			"disabled": not blocked.is_empty(),
		})
	_transmit_target = disciple_id
	art_choice.open("%s에게 무공 전수" % disciple.display_name, "전수한 무공은 방어전에서 그 제자가 씁니다. 제자는 무공을 하나만 익힙니다.", options)


func _on_art_chosen(art_id: String) -> void:
	var chosen: MartialArtData = null
	for art in GameManager.player_character.martial_arts:
		if art.id == art_id:
			chosen = art
	var target: String = _transmit_target
	var transmit := func() -> Dictionary: return DiscipleRoster.transmit(GameManager.player_sect, target, chosen)
	var name: String = DiscipleRoster.get_disciple(GameManager.player_sect, target).display_name
	ActionPreview.confirm(self, "무공 전수", transmit, func() -> void: _apply(transmit.call(), "transmit", name, chosen.display_name))


## 결과를 알린다. scene_action이 있으면 경영 화면이 그 행동의 대화 장면을 띄운다 (제자 이름·무공 이름과 함께)
func _apply(result: Dictionary, scene_action: String = "", disciple_name: String = "", art_name: String = "") -> void:
	if not scene_action.is_empty():
		result["scene_action"] = scene_action
		result["disciple_name"] = disciple_name
		result["art_name"] = art_name
	_UiTheme.show_notice(notice_label, result)
	if result.get("success", false):
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	changed.emit(result)
	refresh()
