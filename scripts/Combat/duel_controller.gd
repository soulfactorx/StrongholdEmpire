extends Control

## 초식 배치 대결 화면. 판정은 DuelEngine이 하고, 이 화면은 배치와 진행을 보여 준다.
## 위: 결과(끝나면)·전투 이름·형식·목표·전장·조건·양쪽 줄 /
## 가운데: 1대1이면 지금 겨루는 두 사람, 여럿이면(포위·진형) 양쪽 사람 목록 — 상대 줄을 누르면 고른 칸의 상대가 되고,
##         동료 줄의 [지시]로 공세·수비·엄호·보조를 바꾼다. 보이는 상대 배치·버릇·게이지(거리·발각·기세)·사건 대사 /
## 아래: 내 칸(탭하면 고르기·다시 탭하면 비우기)과 손패(탭하면 고른 칸이나 빈 칸에 놓기), 겨루기·자동·결과만·후퇴, 기록.
## 모든 버튼은 48px 이상이고 터치만으로 쓸 수 있다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _ConfirmPopup = preload("res://scripts/UI/confirm_popup.gd")
const _ChoicePopup = preload("res://scripts/UI/choice_popup.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")
const TYPE_COLORS: Dictionary = {
	DuelCard.Type.STRIKE: Color("#b23a2b"), DuelCard.Type.QUICK: Color("#94701a"), DuelCard.Type.GUARD: Color("#2f6b5e"),
	DuelCard.Type.EVADE: Color("#4a6f8a"), DuelCard.Type.FOCUS: Color("#7a5a8c"), DuelCard.Type.TRICK: Color("#5a5a5a"),
}
const LOG_LINES := 60
const ORDER_CYCLE: Array[String] = ["attack", "defend", "cover", "support"]

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
## 1대1 칸(두 사람)과 여럿 칸(사람 목록)
var versus_row: HBoxContainer
var squad_box: VBoxContainer
var intent_label: Label
## 사건 대사 (이번 합에 일어난 일)
var event_label: Label
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
var choice_popup: Control


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

	# 지금 겨루는 사람들
	var versus := _panel(root)
	versus_row = HBoxContainer.new()
	versus_row.add_theme_constant_override("separation", 10)
	versus.add_child(versus_row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	versus_row.add_child(left)
	friend_portrait = _portrait(left)
	friend_label = _label(left, 15)
	friend_bar = _bar(left)
	var mid := Label.new()
	mid.text = "대"
	mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_UiTheme.style_label_title(mid, 28)
	versus_row.add_child(mid)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	versus_row.add_child(right)
	foe_portrait = _portrait(right)
	foe_label = _label(right, 15)
	foe_bar = _bar(right)
	squad_box = VBoxContainer.new()
	squad_box.name = "SquadBox"
	squad_box.add_theme_constant_override("separation", 6)
	versus.add_child(squad_box)
	intent_label = _label(versus, 15)
	event_label = _label(versus, 16)
	event_label.name = "EventLabel"
	event_label.add_theme_color_override("font_color", Color("#8a5a12"))

	# 내 칸과 손패
	var board := _panel(root)
	var slot_title := _label(board, 16)
	slot_title.text = "내 배치 — 칸을 눌러 고르고, 아래 초식을 눌러 놓습니다 (고른 칸을 다시 누르면 비움)"
	if not engine.is_single():
		slot_title.text += "\n여럿과 싸울 때는 칸을 고른 뒤 위의 상대를 눌러 그 칸에서 겨룰 상대를 정합니다"
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


func _portrait(parent: Node, size: Vector2 = Vector2(64, 80)) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = size
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
	if not engine.pending_choice.is_empty():
		_refresh()
		_show_choice()
		return
	engine.prepare_bout()
	plan.clear()
	var me: CombatUnit = engine.controlled()
	plan.resize(me.slot_count() if me else 3)
	selected_slot = 0
	_refresh()
	if auto_mode and not _skipping:
		_auto_bout.call_deferred()


func _refresh() -> void:
	var me: CombatUnit = engine.controlled()
	var foe: CombatUnit = engine.current_foe()
	lineup_label.text = "우리 줄: %s\n상대 줄: %s" % [_lineup(engine.friends, engine.active_friends()), _lineup(engine.foes, engine.active_foes())]
	versus_row.visible = engine.is_single()
	squad_box.visible = not engine.is_single()
	if me and foe:
		if engine.is_single():
			friend_label.text = _unit_text(me)
			foe_label.text = _unit_text(foe)
			friend_bar.max_value = me.max_hp
			friend_bar.value = me.hp
			foe_bar.max_value = foe.max_hp
			foe_bar.value = foe.hp
			friend_portrait.texture = _portrait_of(me)
			foe_portrait.texture = _portrait_of(foe)
		else:
			_fill_squad()
		intent_label.text = _intent_text()
	event_label.text = "\n".join(engine.event_lines)
	event_label.visible = not engine.event_lines.is_empty()
	_fill_slots()
	_fill_hand()
	var idle: bool = not engine.over and not _busy and engine.pending_choice.is_empty()
	fight_button.disabled = not idle or auto_mode
	auto_fill_button.disabled = not idle or auto_mode
	skip_button.disabled = engine.over or _skipping
	auto_button.disabled = engine.over
	auto_button.set_pressed_no_signal(auto_mode)
	order_button.visible = engine.friends.size() > 1 and engine.bout_total == 0 and not engine.over and engine.is_single()
	order_button.text = "주인공을 대장으로" if engine.friends[0].is_player else "주인공을 선봉으로"
	back_button.text = "돌아가기" if engine.over else "후퇴"
	_show_log()


## 상대 배치·버릇과 형식의 게이지
func _intent_text() -> String:
	var lines: PackedStringArray = []
	if engine.is_single():
		var shown: PackedStringArray = []
		var revealed: PackedStringArray = engine.revealed_plan()
		for i in revealed.size():
			shown.append("%d %s" % [i + 1, revealed[i]])
		lines.append("상대 배치 (지혜로 보임): %s" % "  ".join(shown))
		var habit: String = engine.habit_text()
		if not habit.is_empty():
			lines.append("버릇: " + habit)
	var gauge: PackedStringArray = []
	match engine.format:
		"chase":
			gauge.append("거리 %d/%d %s" % [engine.distance, _Balance.CHASE_END, "(끝에 닿으면 %s)" % ("따돌림" if engine.setup.objective == "escape" else "놓침")])
		"stealth":
			gauge.append("발각 %d/%d%s" % [engine.detection, _Balance.STEALTH_ALARM, " — 경보!" if engine.alarm else ""])
		"standoff":
			var me: CombatUnit = engine.controlled()
			gauge.append("기세 싸움 — 나 %d · 상대 %d (먼저 %d)" % [me.momentum, engine.current_foe().momentum, _Balance.STANDOFF_GOAL])
		"tournament":
			gauge.append("비무대회 %d회전 (상대 %d/%d)" % [engine.foe_index + 1, engine.foe_index + 1, engine.foes.size()])
	if engine.is_single() and engine.format != "chase":
		gauge.append("이번 대결 %d/%d합" % [engine.bout_in_duel + 1, engine.max_bouts])
	else:
		gauge.append("%d합째" % (engine.bout_total + 1))
	match engine.setup.objective:
		"escape":
			if engine.format != "chase":
				gauge.append("흘린 공격 %d/%d" % [engine.evades, DuelEngine.ESCAPE_EVADES])
		"survive", "hold_line", "timed":
			gauge.append("합 %d/%d" % [engine.bout_total, engine.setup.objective_rounds])
		"endure":
			gauge.append("받은 피해 %d/%d · 합 %d/%d" % [engine.hero_damage_taken, engine.setup.objective_count, engine.bout_total, engine.setup.objective_rounds])
		"disarm":
			gauge.append("무산시킨 절초 %d/%d" % [engine.nullified, engine.setup.objective_count])
		"capture":
			var target: CombatUnit = engine.ctx.get("capture")
			if target:
				gauge.append("%s 체력 %d%% (%d%% 이하에서 막기 반격·기절로 생포)" % [target.display_name, roundi(target.get_hp_ratio() * 100), roundi(DuelEngine.CAPTURE_RATIO * 100)])
	if engine.ward:
		gauge.append("지킬 %s 체력 %d/%d" % [engine.ward.display_name, engine.ward.hp, engine.ward.max_hp])
	lines.append(" · ".join(gauge))
	for unit in engine.telegraphs:
		lines.append("※ 예고: %s — %d합째 마지막 칸에 「%s」" % [unit.display_name, int(engine.telegraphs[unit]["bout"]), engine.telegraphs[unit]["card"].display_name])
	return "\n".join(lines)


## 여럿과 싸울 때: 양쪽 사람 목록. 상대 줄은 누르면 고른 칸의 상대, 동료 줄은 지시 버튼
func _fill_squad() -> void:
	for child in squad_box.get_children():
		squad_box.remove_child(child)
		child.queue_free()
	var target: CombatUnit = engine.target_of(maxi(0, selected_slot))
	var title := _label(squad_box, 15)
	title.text = "상대 — 눌러서 %d칸의 상대로 정하기" % (maxi(0, selected_slot) + 1)
	var foes: Array[CombatUnit] = engine.active_foes()
	for i in foes.size():
		var foe: CombatUnit = foes[i]
		var button := Button.new()
		button.name = "Foe_%d" % i
		button.toggle_mode = true
		button.set_pressed_no_signal(foe == target)
		button.custom_minimum_size = Vector2(0, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.icon = _portrait_of(foe)
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", 44)
		var revealed: PackedStringArray = engine.revealed_plan(foe)
		button.text = "%s%s — 체력 %d/%d · 기세 %d%s\n배치: %s" % [
			foe.display_name, "" if foe.front or engine.format != "formation" else " (뒷줄)", foe.hp, foe.max_hp, foe.momentum,
			" [%s]" % foe.get_status_text() if not foe.get_status_text().is_empty() else "", " ".join(revealed),
		]
		button.disabled = not engine.is_standing(foe) or engine.over
		button.pressed.connect(choose_target.bind(foe))
		_UiTheme.style_button(button)
		squad_box.add_child(button)
	var ours := _label(squad_box, 15)
	ours.text = "우리 쪽"
	var friends: Array[CombatUnit] = engine.active_friends()
	for i in friends.size():
		var unit: CombatUnit = friends[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		squad_box.add_child(row)
		_portrait(row, Vector2(44, 56)).texture = _portrait_of(unit)
		var label := _label(row, 14)
		label.text = _unit_text(unit) + ("" if unit.front or engine.format != "formation" else " (뒷줄)")
		if not unit.is_player:
			var order := Button.new()
			order.name = "Order_%d" % i
			order.text = "지시: %s" % DuelAI.ORDERS[unit.order]["name"]
			order.custom_minimum_size = Vector2(120, 52)
			order.disabled = engine.over or _busy
			order.pressed.connect(cycle_order.bind(unit))
			_UiTheme.style_button(order)
			row.add_child(order)


## 초상화: 주인공은 주인공 초상화, 인물은 그 인물, 그림이 없는 제자 등은 역할 초상화
func _portrait_of(unit: CombatUnit) -> Texture2D:
	if unit.is_player:
		return ArtAssets.player_portrait(unit.character)
	var found: Texture2D = ArtAssets.portrait(DuelEngine._npc_id(unit))
	return found if found else ArtAssets.role_portrait(unit.character.role)


func _lineup(units: Array[CombatUnit], actives: Array[CombatUnit]) -> String:
	var parts: PackedStringArray = []
	for unit in units:
		var mark: String = "▶" if unit in actives and not engine.over else ""
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
		var text: String = "%d%s\n%s" % [i + 1, " !" if warned else "", "%s\n%s" % [card.display_name, card.get_type_name()] if card else "비어 있음"]
		if not engine.is_single() and engine.target_of(i):
			text += "\n→%s" % engine.target_of(i).display_name
		button.text = text
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
	var me: CombatUnit = engine.controlled()
	if me == null:
		return
	for card in me.cards:
		var button := Button.new()
		button.name = "Card_" + card.id
		var banned: String = DuelRules.banned_reason(card, engine.ctx)
		button.text = card.describe() + ("\n(금지: %s)" % banned if not banned.is_empty() else _hand_hint(card))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 60)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not DuelAI.can_place(card, plan) or engine.over or _busy or not banned.is_empty()
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


## 고른 칸에서 겨룰 상대 (포위·진형)
func choose_target(target: CombatUnit) -> void:
	if _busy or engine.over:
		return
	engine.set_target(maxi(0, selected_slot), target)
	_refresh()


## 동료 지시를 차례로 바꾼다 (공세 → 수비 → 엄호 → 보조)
func cycle_order(unit: CombatUnit) -> void:
	if _busy or engine.over:
		return
	var next: String = ORDER_CYCLE[(ORDER_CYCLE.find(unit.order) + 1) % ORDER_CYCLE.size()]
	engine.set_order(unit, next)
	_refresh()


func auto_fill() -> void:
	if _busy or engine.over or not engine.pending_choice.is_empty():
		return
	plan = engine.auto_plan()
	selected_slot = -1
	_refresh()


func _toggle_order() -> void:
	engine.set_player_first(not engine.friends[0].is_player)
	engine.prepare_bout()
	plan.resize(engine.controlled().slot_count())
	plan.fill(null)
	selected_slot = 0
	_refresh()


## 지금 배치의 사전 점검 (DuelRules.plan_warnings)
func plan_warnings() -> Array[Dictionary]:
	var me: CombatUnit = engine.controlled()
	if me == null or engine.over:
		return []
	return DuelRules.plan_warnings(me, plan, engine.visible_enemy_types(), engine.ctx)


## 손패 초식을 고른 칸에 놓으면 내공·기세가 모자라는지 미리 알려 준다
func _hand_hint(card: DuelCard) -> String:
	var me: CombatUnit = engine.controlled()
	if selected_slot < 0 or selected_slot >= plan.size() or me == null:
		return ""
	var trial: Array = plan.duplicate()
	trial[selected_slot] = card
	for warning in DuelRules.plan_warnings(me, trial.slice(0, selected_slot + 1)):
		if warning["slot"] != selected_slot:
			continue
		if warning["text"].contains("내공이 모자라"):
			return "\n(%d칸에선 내공 부족)" % (selected_slot + 1)
		if warning["text"].contains("기세"):
			return "\n(%d칸에선 기세가 모자랄 수 있음)" % (selected_slot + 1)
	return ""


# ── 교전 ──

## [겨루기]: 정정당당이면 빈 칸을 막고, 확실한 빈틈이 있으면 한 번 묻는다
func _on_fight_pressed() -> void:
	if _busy or engine.over or not engine.pending_choice.is_empty():
		return
	if confirm_popup == null:
		confirm_popup = _ConfirmPopup.new()
		add_child(confirm_popup)
	if engine.setup.has_condition("honor") and plan.has(null):
		confirm_popup.open("정정당당", "정정당당한 겨룸에서는 빈 칸을 둘 수 없습니다. 모든 칸을 채우세요.", Callable(), "확인", "닫기")
		return
	var serious: Array = plan_warnings().filter(func(w: Dictionary) -> bool: return w["serious"])
	if serious.is_empty():
		fight()
		return
	var lines: PackedStringArray = []
	for warning in serious:
		lines.append("· " + warning["text"])
	confirm_popup.open("빈틈이 있습니다", "\n".join(lines) + "\n\n그래도 겨룰까요?", fight, "그래도 겨룬다", "다시 배치")


## 지금 배치로 한 합을 겨룬다. 빈 칸은 빈틈이 된다.
func fight() -> void:
	if _busy or engine.over or not engine.pending_choice.is_empty():
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


## 사건의 선택 (설득·결단): 고를 때까지 다음 합으로 가지 않는다. 자동 전투면 스스로 고른다
func _show_choice() -> void:
	if engine.pending_choice.is_empty():
		return
	if auto_mode:
		answer_choice(engine.auto_choice())
		return
	if choice_popup == null:
		choice_popup = _ChoicePopup.new()
		add_child(choice_popup)
		choice_popup.chosen.connect(func(id: String) -> void: answer_choice(int(id)))
	var options: Array[Dictionary] = []
	for option in engine.pending_choice["options"]:
		options.append({"id": str(option["id"]), "title": str(option["label"]), "description": str(option.get("description", ""))})
	choice_popup.open(str(engine.pending_choice["title"]), "\n".join(engine.pending_choice["lines"]), options, false)


func answer_choice(index: int) -> void:
	if engine.pending_choice.is_empty():
		return
	var said: PackedStringArray = engine.choose(index)
	engine.event_lines = said
	_new_bout()


func set_auto(on: bool) -> void:
	auto_mode = on
	_refresh()
	if on and not _busy and not engine.over:
		if not engine.pending_choice.is_empty():
			_show_choice()
		else:
			_auto_bout()


func _auto_bout() -> void:
	if not auto_mode or _busy or engine.over or _skipping or not engine.pending_choice.is_empty():
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
	if choice_popup:
		choice_popup.visible = false
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
	var result: Dictionary = GameManager.finish_combat(engine.outcome, fallen.size(), fallen, engine.summary())
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
