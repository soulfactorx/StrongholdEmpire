extends Control

## 초식 배치 대결 화면. 판정은 DuelEngine이 하고, 이 화면은 배치와 진행을 보여 준다.
## 위: 전투 이름·목표·양쪽 줄 / 가운데: 지금 겨루는 두 사람(체력·내공·기세)과 보이는 상대 배치·버릇 /
## 아래: 내 칸(탭하면 고르기·다시 탭하면 비우기)과 손패(탭하면 고른 칸이나 빈 칸에 놓기), 겨루기·자동·결과만·후퇴, 기록.
## 모든 버튼은 48px 이상이고 터치만으로 쓸 수 있다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _ConfirmPopup = preload("res://scripts/UI/confirm_popup.gd")
const TYPE_COLORS: Dictionary = {
	DuelCard.Type.STRIKE: Color("#b23a2b"), DuelCard.Type.QUICK: Color("#94701a"), DuelCard.Type.GUARD: Color("#2f6b5e"),
	DuelCard.Type.EVADE: Color("#4a6f8a"), DuelCard.Type.FOCUS: Color("#7a5a8c"), DuelCard.Type.TRICK: Color("#5a5a5a"),
}
const LOG_LINES := 60

var engine: DuelEngine
## 이번 합의 내 배치 (칸 수만큼, 빈 칸은 null)
var plan: Array = []
var selected_slot: int = -1
var auto_mode: bool = false
var _busy: bool = false
var _skipping: bool = false
var _finished: bool = false

var title_label: Label
var goal_label: Label
var lineup_label: Label
var friend_label: Label
var foe_label: Label
var friend_bar: ProgressBar
var foe_bar: ProgressBar
var friend_portrait: TextureRect
var foe_portrait: TextureRect
var intent_label: Label
var slot_row: HBoxContainer
var hand_grid: GridContainer
var fight_button: Button
var auto_fill_button: Button
var auto_button: Button
var skip_button: Button
var order_button: Button
var back_button: Button
var log_label: Label
var log_scroll: ScrollContainer
var result_label: Label
## 배치 사전 점검 (빈틈·상성 불리를 겨루기 전에 알려 준다)
var warning_label: Label
var confirm_popup: Control


func _ready() -> void:
	ArtAssets.apply_background(self)
	var setup: CombatSetup = GameManager.get_or_create_combat_setup()
	var region: String = setup.region_id if not setup.region_id.is_empty() else GameManager.player_region
	if WorldMap.has_region(region):
		ArtAssets.set_background(self, ArtAssets.region_background(region))
	engine = DuelEngine.new(setup, GameManager.player_character, GameManager.duel_memory, GameManager.art_mastery, GameManager.player_relationships)
	_build_ui()
	_UiTheme.apply_to_control(self)
	AudioManager.play_battle_start()
	_new_bout()


# ── 화면 구성 ──

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)

	# 결과는 맨 위 패널에 (끝나면 보인다)
	var result_box := _panel(root)
	result_label = _label(result_box, 20)
	result_box.get_parent().visible = false
	result_label.visibility_changed.connect(func() -> void: result_box.get_parent().visible = result_label.visible)
	result_label.visible = false
	var head := _panel(root)
	title_label = _label(head, 22)
	title_label.text = engine.setup.title
	_UiTheme.style_label_title(title_label, 22)
	goal_label = _label(head, 14)
	goal_label.text = Battlefield.describe(engine.setup) + "\n상성: 강공 > 막기 > 속공 > 강공 · 회피는 강공·속공을 흘리고 술에 약함 · 기(운기)는 무방비"
	lineup_label = _label(head, 14)

	# 지금 겨루는 두 사람
	var versus := _panel(root)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	versus.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	friend_portrait = _portrait(left)
	friend_label = _label(left, 15)
	friend_bar = _bar(left)
	var mid := Label.new()
	mid.text = "대"
	mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_UiTheme.style_label_title(mid, 28)
	row.add_child(mid)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	foe_portrait = _portrait(right)
	foe_label = _label(right, 15)
	foe_bar = _bar(right)
	intent_label = _label(versus, 15)

	# 내 칸과 손패
	var board := _panel(root)
	var slot_title := _label(board, 16)
	slot_title.text = "내 배치 — 칸을 눌러 고르고, 아래 초식을 눌러 놓습니다 (고른 칸을 다시 누르면 비움)"
	slot_row = HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	board.add_child(slot_row)
	warning_label = _label(board, 15)
	warning_label.name = "WarningLabel"
	warning_label.add_theme_color_override("font_color", Color("#9b2c1f"))
	var hand_title := _label(board, 16)
	hand_title.text = "손패 — 무공 초식은 한 합에 한 번, 기본 동작은 여러 번"
	hand_grid = GridContainer.new()
	hand_grid.columns = 2 if LayoutMode.is_portrait() else 3
	hand_grid.add_theme_constant_override("h_separation", 6)
	hand_grid.add_theme_constant_override("v_separation", 6)
	board.add_child(hand_grid)

	# 행동
	var actions := GridContainer.new()
	actions.columns = 2 if LayoutMode.is_portrait() else 3
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	root.add_child(actions)
	fight_button = _button(actions, "겨루기 ▶", _on_fight_pressed)
	fight_button.name = "FightButton"
	auto_fill_button = _button(actions, "자동 배치", auto_fill)
	auto_fill_button.name = "AutoFillButton"
	auto_button = _button(actions, "자동 전투", func() -> void: set_auto(not auto_mode))
	auto_button.name = "AutoButton"
	auto_button.toggle_mode = true
	skip_button = _button(actions, "결과만 보기", skip_to_result)
	skip_button.name = "SkipButton"
	order_button = _button(actions, "주인공을 선봉으로", _toggle_order)
	order_button.name = "OrderButton"
	back_button = _button(actions, "후퇴", _on_back_pressed)
	back_button.name = "BackButton"

	var log_panel := _panel(root)
	var log_title := _label(log_panel, 15)
	log_title.text = "전투 기록"
	log_scroll = ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(0, 260)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_panel.add_child(log_scroll)
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_UiTheme.set_font_size(log_label, 14)
	log_scroll.add_child(log_label)


func _panel(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


func _label(parent: Node, size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_UiTheme.set_font_size(label, size)
	parent.add_child(label)
	return label


func _bar(parent: Node) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	parent.add_child(bar)
	return bar


func _portrait(parent: Node) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(64, 80)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(rect)
	return rect


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


# ── 상태 그리기 ──

func _new_bout() -> void:
	if engine.over:
		_finish_combat()
		return
	engine.prepare_bout()
	plan.clear()
	plan.resize(engine.current_friend().slot_count())
	selected_slot = 0
	_refresh()
	if auto_mode and not _skipping:
		_auto_bout.call_deferred()


func _refresh() -> void:
	var friend: CombatUnit = engine.current_friend()
	var foe: CombatUnit = engine.current_foe()
	lineup_label.text = "우리 줄: %s\n상대 줄: %s" % [_lineup(engine.friends, engine.friend_index), _lineup(engine.foes, engine.foe_index)]
	if friend and foe:
		friend_label.text = _unit_text(friend)
		foe_label.text = _unit_text(foe)
		friend_bar.max_value = friend.max_hp
		friend_bar.value = friend.hp
		foe_bar.max_value = foe.max_hp
		foe_bar.value = foe.hp
		friend_portrait.texture = _portrait_of(friend)
		foe_portrait.texture = _portrait_of(foe)
		var shown: PackedStringArray = []
		var revealed: PackedStringArray = engine.revealed_plan()
		for i in revealed.size():
			shown.append("%d %s" % [i + 1, revealed[i]])
		var habit: String = engine.habit_text()
		intent_label.text = "상대 배치 (지혜로 보임): %s%s\n이번 대결 %d/%d합" % [
			"  ".join(shown), "\n버릇: " + habit if not habit.is_empty() else "", engine.bout_in_duel + 1, engine.max_bouts,
		]
		if engine.setup.objective == "escape":
			intent_label.text += " · 흘린 공격 %d/%d" % [engine.evades, DuelEngine.ESCAPE_EVADES]
		elif engine.setup.objective == "survive":
			intent_label.text += " · 버틴 합 %d/%d" % [engine.bout_total, engine.setup.objective_rounds]
		elif engine.ward:
			intent_label.text += " · 지킬 %s 체력 %d/%d" % [engine.ward.display_name, engine.ward.hp, engine.ward.max_hp]
	_fill_slots()
	_fill_hand()
	var idle: bool = not engine.over and not _busy
	fight_button.disabled = not idle or auto_mode
	auto_fill_button.disabled = not idle or auto_mode
	skip_button.disabled = engine.over or _skipping
	auto_button.disabled = engine.over
	auto_button.set_pressed_no_signal(auto_mode)
	order_button.visible = engine.friends.size() > 1 and engine.bout_total == 0 and not engine.over
	order_button.text = "주인공을 대장으로" if engine.friends[0].is_player else "주인공을 선봉으로"
	back_button.text = "돌아가기" if engine.over else "후퇴"
	_show_log()


## 초상화: 주인공은 주인공 초상화, 인물은 그 인물, 그림이 없는 제자 등은 역할 초상화
func _portrait_of(unit: CombatUnit) -> Texture2D:
	if unit.is_player:
		return ArtAssets.player_portrait(unit.character)
	var found: Texture2D = ArtAssets.portrait(DuelEngine._npc_id(unit))
	return found if found else ArtAssets.role_portrait(unit.character.role)


func _lineup(units: Array[CombatUnit], index: int) -> String:
	var parts: PackedStringArray = []
	for i in units.size():
		var unit: CombatUnit = units[i]
		var mark: String = "▶" if i == index and not engine.over else ""
		var state: String = " (쓰러짐)" if not unit.is_alive() else (" (물러남)" if engine.retired.has(unit) else "")
		parts.append("%s%s%s" % [mark, unit.display_name, state])
	return " · ".join(parts)


func _unit_text(unit: CombatUnit) -> String:
	var status: String = unit.get_status_text()
	return "%s\n체력 %d/%d · 내공 %d · 기세 %s%s" % [
		unit.display_name, unit.hp, unit.max_hp, unit.character.internal_energy_current,
		"★".repeat(unit.momentum) if unit.momentum > 0 else "0", " [%s]" % status if not status.is_empty() else "",
	]


func _fill_slots() -> void:
	for child in slot_row.get_children():
		slot_row.remove_child(child)
		child.queue_free()
	var warnings: Array[Dictionary] = plan_warnings()
	var lines: PackedStringArray = []
	for warning in warnings:
		lines.append("! " + warning["text"])
	warning_label.text = "\n".join(lines)
	warning_label.visible = not lines.is_empty() and not engine.over
	for i in plan.size():
		var card: DuelCard = plan[i]
		var warned: bool = warnings.any(func(w: Dictionary) -> bool: return w["slot"] == i and card != null)
		var button := Button.new()
		button.name = "Slot%d" % i
		button.text = "%d%s\n%s" % [i + 1, " !" if warned else "", "%s\n%s" % [card.display_name, card.get_type_name()] if card else "비어 있음"]
		button.custom_minimum_size = Vector2(0, 72)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.set_pressed_no_signal(i == selected_slot)
		button.pressed.connect(select_slot.bind(i))
		_UiTheme.style_button(button)
		if card:
			button.add_theme_color_override("font_color", TYPE_COLORS[card.type])
		slot_row.add_child(button)


func _fill_hand() -> void:
	for child in hand_grid.get_children():
		hand_grid.remove_child(child)
		child.queue_free()
	var friend: CombatUnit = engine.current_friend()
	if friend == null:
		return
	for card in friend.cards:
		var button := Button.new()
		button.name = "Card_" + card.id
		button.text = card.describe() + _hand_hint(card)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 60)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not DuelAI.can_place(card, plan) or engine.over or _busy
		button.pressed.connect(place_card.bind(card))
		_UiTheme.style_button(button)
		button.add_theme_color_override("font_color", TYPE_COLORS[card.type])
		hand_grid.add_child(button)


func _show_log() -> void:
	var lines: PackedStringArray = engine.history
	log_label.text = "\n".join(lines.slice(maxi(0, lines.size() - LOG_LINES)))
	await get_tree().process_frame
	if is_inside_tree():
		log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


# ── 배치 ──

## 칸을 고른다. 이미 고른 칸을 다시 누르면 비운다.
func select_slot(index: int) -> void:
	if _busy or engine.over:
		return
	if index == selected_slot and plan[index] != null:
		plan[index] = null
	selected_slot = index
	_refresh()


## 초식을 고른 칸(없으면 첫 빈 칸)에 놓고, 다음 빈 칸을 고른다.
func place_card(card: DuelCard) -> void:
	if _busy or engine.over:
		return
	var others: Array = plan.duplicate()
	if selected_slot >= 0 and selected_slot < others.size():
		others[selected_slot] = null
	if not DuelAI.can_place(card, others):
		return
	var index: int = selected_slot if selected_slot >= 0 else plan.find(null)
	if index < 0:
		return
	plan[index] = card
	selected_slot = plan.find(null)
	_refresh()


func auto_fill() -> void:
	if _busy or engine.over:
		return
	plan = engine.auto_plan()
	selected_slot = -1
	_refresh()


func _toggle_order() -> void:
	engine.set_player_first(not engine.friends[0].is_player)
	engine.prepare_bout()
	plan.resize(engine.current_friend().slot_count())
	plan.fill(null)
	selected_slot = 0
	_refresh()


## 지금 배치의 사전 점검 (DuelRules.plan_warnings)
func plan_warnings() -> Array[Dictionary]:
	var friend: CombatUnit = engine.current_friend()
	if friend == null or engine.over:
		return []
	return DuelRules.plan_warnings(friend, plan, engine.visible_enemy_types())


## 손패 초식을 고른 칸에 놓으면 내공·기세가 모자라는지 미리 알려 준다
func _hand_hint(card: DuelCard) -> String:
	if selected_slot < 0 or selected_slot >= plan.size() or engine.current_friend() == null:
		return ""
	var trial: Array = plan.duplicate()
	trial[selected_slot] = card
	for warning in DuelRules.plan_warnings(engine.current_friend(), trial.slice(0, selected_slot + 1)):
		if warning["slot"] != selected_slot:
			continue
		if warning["text"].contains("내공이 모자라"):
			return "\n(%d칸에선 내공 부족)" % (selected_slot + 1)
		if warning["text"].contains("기세"):
			return "\n(%d칸에선 기세가 모자랄 수 있음)" % (selected_slot + 1)
	return ""


# ── 교전 ──

## [겨루기]: 확실한 빈틈이 있으면 한 번 묻는다
func _on_fight_pressed() -> void:
	if _busy or engine.over:
		return
	var serious: Array = plan_warnings().filter(func(w: Dictionary) -> bool: return w["serious"])
	if serious.is_empty():
		fight()
		return
	if confirm_popup == null:
		confirm_popup = _ConfirmPopup.new()
		add_child(confirm_popup)
	var lines: PackedStringArray = []
	for warning in serious:
		lines.append("· " + warning["text"])
	confirm_popup.open("빈틈이 있습니다", "\n".join(lines) + "\n\n그래도 겨룰까요?", fight, "그래도 겨룬다", "다시 배치")


## 지금 배치로 한 합을 겨룬다. 빈 칸은 빈틈이 된다.
func fight() -> void:
	if _busy or engine.over:
		return
	_busy = true
	_refresh()
	var used_art: bool = plan.any(func(c: Variant) -> bool: return c != null and not c.art_id.is_empty())
	var lines: PackedStringArray = engine.run_bout(plan)
	if not _skipping:
		if used_art:
			AudioManager.play_art()
		else:
			AudioManager.play_hit()
	if GameSettings.combat_delay > 0.0 and not _skipping:
		# 한 줄씩 보여 준다 (기록은 이미 엔진에 있다)
		for i in lines.size():
			if not is_inside_tree():
				return
			await get_tree().create_timer(minf(GameSettings.combat_delay, 0.25)).timeout
	_busy = false
	_new_bout()


func set_auto(on: bool) -> void:
	auto_mode = on
	_refresh()
	if on and not _busy and not engine.over:
		_auto_bout()


func _auto_bout() -> void:
	if not auto_mode or _busy or engine.over or _skipping:
		return
	plan = engine.auto_plan()
	await fight()


## 끝까지 바로 치르고 결과만 본다
func skip_to_result() -> void:
	if engine.over or _skipping:
		return
	_skipping = true
	while _busy and is_inside_tree():
		await get_tree().process_frame
	engine.play_to_end()
	_skipping = false
	_finish_combat()


func _finish_combat() -> void:
	if _finished:
		return
	_finished = true
	auto_mode = false
	var level_before: int = GameManager.player_character.level
	GameManager.last_combat_history = engine.history
	var fallen: Array = engine.fallen_ally_ids()
	var result: Dictionary = GameManager.finish_combat(engine.outcome, fallen.size(), fallen)
	if GameManager.player_character.level > level_before:
		AudioManager.play_level_up()
	elif engine.outcome == CombatManager.Outcome.VICTORY:
		AudioManager.play_victory()
	elif engine.outcome == CombatManager.Outcome.DEFEAT:
		AudioManager.play_defeat()
	result_label.text = str(result.get("message", ""))
	result_label.visible = true
	engine.history.append(str(result.get("message", "")))
	_refresh()


# ── 나가기 ──

func _on_back_pressed() -> void:
	if engine.over:
		leave_combat()
		return
	if confirm_popup == null:
		confirm_popup = _ConfirmPopup.new()
		add_child(confirm_popup)
	confirm_popup.open("후퇴", "전투에서 물러납니다. 패배 손실의 절반을 받습니다.\n정말 후퇴할까요?", leave_combat, "후퇴", "계속 싸운다")


## 전투를 떠난다. 끝나지 않았으면 후퇴로 처리한다.
func leave_combat() -> void:
	if not engine.over:
		engine.retreat()
		_finish_combat()
	SceneRouter.goto(get_tree(), SceneRouter.HUB)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match event.keycode:
		KEY_SPACE, KEY_ENTER:
			_on_fight_pressed()
		KEY_A:
			auto_fill()
		KEY_ESCAPE:
			_on_back_pressed()
		_:
			return
	get_viewport().set_input_as_handled()
