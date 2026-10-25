extends Control

## 문파전 지휘 화면. 위에서 아래로 한 줄기로 읽힌다:
##   맞대결 판(우리 문파 VS 상대, 문주·제자·전력·예상 승률) → 1. 상대 고르기 → 2. 출진 준비(진형·장수·정찰)
##   → 3. 세 합의 명령(합마다 버튼으로 고르고, 정찰로 안 적의 수와 상성을 바로 보여 줌) → 전투 개시 → 결과 판.
## 판정 규칙은 SectWarManager에 있다. 화면은 코드로 만들고, 버튼은 모두 48px 이상이다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 명령 버튼 순서와 이름표 (ButtonHelp가 이름으로 설명을 찾는다)
const COMMAND_BUTTONS: Array = [
	[SectWarManager.Command.CHARGE, "ChargeButton"],
	[SectWarManager.Command.DEFEND, "DefendButton"],
	[SectWarManager.Command.FLANK, "FlankButton"],
	[SectWarManager.Command.RETREAT, "RetreatButton"],
]
## 진형 선택지 순서
const FORMATIONS: Array = [
	SectWarManager.Formation.NONE,
	SectWarManager.Formation.CRANE,
	SectWarManager.Formation.FISH,
	SectWarManager.Formation.CIRCLE,
]

## 합마다 고른 명령 (-1이면 아직)
var _round_commands: Array[int] = []
var _targets: Array[SectData] = []
var _target_index: int = -1
var _generals: Array[Dictionary] = []
var _general_index: int = -1
var _formation: SectWarManager.Formation = SectWarManager.Formation.NONE

var title_label: Label
## 맞대결 판
var ours_label: Label
var theirs_label: Label
var ours_bar: ProgressBar
var theirs_bar: ProgressBar
var chance_label: Label
var stakes_label: Label
## 1. 상대
var target_box: HFlowContainer
var target_buttons: Array[Button] = []
var enemy_label: Label
## 2. 준비
var formation_buttons: Array[Button] = []
var formation_hint: Label
var general_button: Button
var scout_button: Button
## 3. 명령: 합마다 {enemy: Label, buttons: [Button], hint: Label}
var round_rows: Array[Dictionary] = []
var round_label: Label
var execute_button: Button
var log_label: Label
## 결과 판
var result_overlay: Control
var result_headline: Label
var result_body: Label


func _ready() -> void:
	_round_commands.resize(_Balance.WAR_ROUNDS)
	_round_commands.fill(-1)
	_build()
	_UiTheme.apply_to_control(self)
	_fill_targets()
	if not GameManager.can_wage_war():
		log_label.text = "이번 계절에는 이미 문파전을 치렀습니다. 다음 계절을 기다리세요."
	elif not GameManager.pending_region_target.is_empty():
		log_label.text = "%s 공략: 이기면 이 땅을 차지합니다." % WorldMap.get_region(GameManager.pending_region_target).get("name", "")
	else:
		log_label.text = "상대를 고르고, 세 합의 명령을 정한 뒤 [전투 개시]를 누르세요."
	_update_display()


# ── 화면 만들기 ──

func _build() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 16)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_UiTheme.style_label_title(title_label, 26)
	header.add_child(title_label)
	var back := _button("문파로 돌아가기", _on_back_pressed, 180)
	back.name = "BackButton"
	header.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.custom_minimum_size.x = minf(900.0, get_viewport_rect().size.x - 48.0)
	center.add_child(body)

	body.add_child(_build_versus())
	var section: VBoxContainer = _section(body, "1. 상대 문파", "강호의 세력 가운데 공격할 곳을 고릅니다. 약한 곳부터 보입니다.")
	target_box = HFlowContainer.new()
	target_box.add_theme_constant_override("h_separation", 8)
	target_box.add_theme_constant_override("v_separation", 8)
	section.add_child(target_box)
	enemy_label = _text(15)
	section.add_child(enemy_label)

	section = _section(body, "2. 출진 준비", "진형은 명령 하나를 강하게, 그 명령을 이기는 수에는 약하게 만듭니다. 장수는 유대 깊은 인연이 함께 싸웁니다.")
	var formations := HFlowContainer.new()
	formations.add_theme_constant_override("h_separation", 8)
	formations.add_theme_constant_override("v_separation", 8)
	section.add_child(formations)
	for formation in FORMATIONS:
		var button := _button(SectWarManager.FORMATION_NAMES[formation], _on_formation_pressed.bind(formation), 150)
		button.toggle_mode = true
		formation_buttons.append(button)
		formations.add_child(button)
	formation_hint = _text(14)
	section.add_child(formation_hint)
	var prep := HFlowContainer.new()
	prep.add_theme_constant_override("h_separation", 8)
	prep.add_theme_constant_override("v_separation", 8)
	section.add_child(prep)
	general_button = _button("장수: 없음", _on_general_pressed, 260)
	general_button.name = "GeneralButton"
	general_button.set_meta("help", "누를 때마다 함께 싸울 장수를 바꿉니다. 사부·혈맹·배우자·제자 가운데 유대 %d 이상인 인연만 나섭니다." % _Balance.WAR_GENERAL_MIN_BOND)
	prep.add_child(general_button)
	scout_button = _button("정찰", _on_scout_pressed, 220)
	scout_button.name = "ScoutButton"
	prep.add_child(scout_button)

	section = _section(body, "3. 세 합의 명령", "상성: 돌격 > 측면 공격 > 방어 > 돌격. 같은 명령을 잇달아 쓰면 약해지고, 적은 지난 전투의 수를 기억합니다.")
	round_label = _text(15)
	section.add_child(round_label)
	for i in _Balance.WAR_ROUNDS:
		section.add_child(_build_round_row(i))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	section.add_child(actions)
	var reset := _button("명령 초기화", _on_reset_pressed, 160)
	reset.name = "ResetButton"
	actions.add_child(reset)
	execute_button = _button("전투 개시", _on_execute_pressed, 0)
	execute_button.name = "ExecuteButton"
	execute_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	execute_button.custom_minimum_size.y = 56
	actions.add_child(execute_button)
	log_label = _text(15)
	section.add_child(log_label)

	_build_result_overlay()


## 맞대결 판: 왼쪽 우리 문파, 오른쪽 상대. 전력 막대와 예상 승률, 걸린 것.
func _build_versus() -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	ours_label = _text(15)
	left.add_child(ours_label)
	ours_bar = _bar(_UiTheme.COLORS["accent_jade"])
	left.add_child(ours_bar)
	var vs := Label.new()
	vs.text = "VS"
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_UiTheme.style_label_title(vs, 28)
	vs.add_theme_color_override("font_color", _UiTheme.COLORS["accent_red"])
	row.add_child(vs)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	theirs_label = _text(15)
	theirs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(theirs_label)
	theirs_bar = _bar(_UiTheme.COLORS["accent_red"])
	theirs_bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	right.add_child(theirs_bar)
	chance_label = Label.new()
	chance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UiTheme.set_font_size(chance_label, 20)
	box.add_child(chance_label)
	stakes_label = _text(14)
	stakes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stakes_label)
	return panel


func _build_round_row(index: int) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var name := Label.new()
	name.text = "%d합" % (index + 1)
	_UiTheme.style_label_title(name, 20)
	top.add_child(name)
	var enemy := _text(15)
	enemy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(enemy)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 6)
	box.add_child(buttons)
	var list: Array[Button] = []
	for entry in COMMAND_BUTTONS:
		var button := _button(SectWarManager.COMMAND_NAMES[entry[0]], _on_round_command.bind(index, entry[0]), 120)
		button.name = "%s%d" % [entry[1], index + 1]
		button.set_meta("help", ButtonHelp._by_name().get(entry[1], ""))
		button.toggle_mode = true
		buttons.add_child(button)
		list.append(button)
	var hint := _text(14)
	box.add_child(hint)
	round_rows.append({"enemy": enemy, "buttons": list, "hint": hint})
	return panel


## 결과 판: 큰 승패 글씨, 합마다 결과, 얻고 잃은 것
func _build_result_overlay() -> void:
	result_overlay = Control.new()
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	result_overlay.visible = false
	add_child(result_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.add_child(center)
	var panel := PanelContainer.new()
	LayoutMode.fit_width(panel, 640)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	result_headline = Label.new()
	result_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_UiTheme.style_label_title(result_headline, 44)
	box.add_child(result_headline)
	result_body = _text(16)
	box.add_child(result_body)
	var close := _button("확인", func() -> void: result_overlay.visible = false, 0)
	close.name = "ResultCloseButton"
	box.add_child(close)


## 한지 판 하나에 제목·설명을 놓고, 내용을 넣을 상자를 돌려준다
func _section(parent: Control, title: String, note: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var label := Label.new()
	label.text = title
	_UiTheme.style_label_title(label, 22)
	box.add_child(label)
	var hint := _text(14)
	hint.text = note
	hint.add_theme_color_override("font_color", _UiTheme.COLORS["text_muted"])
	box.add_child(hint)
	return box


func _text(size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_UiTheme.set_font_size(label, size)
	return label


func _button(text: String, callback: Callable, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 48)
	button.pressed.connect(callback)
	return button


func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 14
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.12)
	bar.add_theme_stylebox_override("background", bg)
	return bar


# ── 자료 ──

func _fill_targets() -> void:
	_targets = GameManager.get_war_targets()
	for button in target_buttons:
		button.queue_free()
	target_buttons.clear()
	for i in _targets.size():
		var sect: SectData = _targets[i]
		var button := _button("", _on_target_pressed.bind(i), 200)
		button.toggle_mode = true
		button.text = "%s\n%s · 전력 %d" % [sect.sect_name, sect.get_alignment_name(), SectWarManager.get_sect_power(sect)]
		_UiTheme.style_button(button)
		target_box.add_child(button)
		target_buttons.append(button)
	_target_index = 0 if not _targets.is_empty() else -1
	# 지도에서 [공략]으로 왔으면 그 땅의 주인을 먼저 고른다.
	var region_id: String = GameManager.pending_region_target
	if not region_id.is_empty():
		var owner: String = WorldMap.get_owner(GameManager.map_state, region_id)
		for i in _targets.size():
			if _targets[i].id == owner:
				_target_index = i
	_fill_generals()


func _fill_generals() -> void:
	var target: SectData = _get_target()
	_generals = GameManager.get_war_generals(target.id if target else "")
	_general_index = -1


func _get_target() -> SectData:
	return _targets[_target_index] if _target_index >= 0 and _target_index < _targets.size() else null


func get_selected_formation() -> SectWarManager.Formation:
	return _formation


func get_selected_general() -> Dictionary:
	return _generals[_general_index] if _general_index >= 0 and _general_index < _generals.size() else {}


## 고른 명령 (다 고른 합까지만, 순서대로)
func get_commands() -> Array[SectWarManager.Command]:
	var result: Array[SectWarManager.Command] = []
	for command in _round_commands:
		if command < 0:
			break
		result.append(command as SectWarManager.Command)
	return result


func _our_power() -> int:
	return (
		SectWarManager.get_military_power(GameManager.player_sect, GameManager.player_character)
		+ int(get_selected_general().get("power", 0)) + DiplomacyManager.get_ally_support(GameManager.world_sects)
	)


# ── 표시 ──

func _update_display() -> void:
	var sect: SectData = GameManager.player_sect
	var hero: CharacterData = GameManager.player_character
	var target: SectData = _get_target()
	var general: Dictionary = get_selected_general()
	var ally_power: int = DiplomacyManager.get_ally_support(GameManager.world_sects)
	var power: int = _our_power()
	var parts: PackedStringArray = []
	if not general.is_empty():
		parts.append("장수 +%d" % general["power"])
	if ally_power > 0:
		parts.append("동맹 원군 +%d" % ally_power)
	ours_label.text = "%s (우리 문파)\n지휘: %s (%s)\n제자 %d · 전력 %d%s" % [
		sect.sect_name, hero.display_name, hero.get_role_name(), sect.disciple_count, power,
		" (%s)" % ", ".join(parts) if not parts.is_empty() else "",
	]
	for i in target_buttons.size():
		target_buttons[i].set_pressed_no_signal(i == _target_index)
		target_buttons[i].text = ("▶ " if i == _target_index else "") + "%s\n%s · 전력 %d" % [
			_targets[i].sect_name, _targets[i].get_alignment_name(), SectWarManager.get_sect_power(_targets[i]),
		]
	for i in formation_buttons.size():
		formation_buttons[i].set_pressed_no_signal(FORMATIONS[i] == _formation)
		formation_buttons[i].text = ("▶ " if FORMATIONS[i] == _formation else "") + SectWarManager.FORMATION_NAMES[FORMATIONS[i]]
	formation_hint.text = _formation_text(_formation)
	general_button.disabled = _generals.is_empty()
	general_button.text = "장수: %s" % (
		"%s (전력 +%d%s)" % [general["name"], general["power"], ", %s 특기" % SectWarManager.COMMAND_NAMES[general["specialty"]] if general["specialty"] >= 0 else ""]
		if not general.is_empty() else ("없음" if not _generals.is_empty() else "함께할 인연 없음")
	)

	var plan: Dictionary = {}
	if target == null:
		title_label.text = "문파전"
		theirs_label.text = "상대 없음"
		enemy_label.text = "강호의 모든 세력이 굴복했거나 동맹입니다."
		scout_button.disabled = true
		chance_label.text = ""
		stakes_label.text = ""
		ours_bar.value = 100
		theirs_bar.value = 0
	else:
		plan = GameManager.prepare_war(target.id)
		var enemy_power: int = SectWarManager.get_sect_power(target)
		title_label.text = "문파전 — %s VS %s" % [sect.sect_name, target.sect_name]
		theirs_label.text = "%s (상대)\n문주 %s · %s\n제자 %d · 전력 %d" % [
			target.sect_name, target.leader_name, target.get_alignment_name(), target.disciple_count, enemy_power,
		]
		var top: float = maxf(1.0, maxf(power, enemy_power))
		ours_bar.value = power / top * 100.0
		theirs_bar.value = enemy_power / top * 100.0
		var chance: float = SectWarManager.estimate_win_chance(
			power, enemy_power, get_commands(), _formation, general, plan, SectWarManager.get_tactics(target)
		)
		chance_label.text = "예상 승률 %d%%%s" % [roundi(chance * 100), "" if get_commands().size() == _Balance.WAR_ROUNDS else " (명령을 다 고르면 정확해집니다)"]
		chance_label.add_theme_color_override("font_color", _UiTheme.COLORS["accent_jade"] if chance >= 0.5 else _UiTheme.COLORS["accent_red"])
		stakes_label.text = _stakes_text(target)
		enemy_label.text = "명성 %d · 태도 %s · 진형 %s · 즐겨 쓰는 명령 %s%s" % [
			target.reputation, target.get_attitude_text(),
			SectWarManager.FORMATION_NAMES[plan["enemy_formation"]],
			SectWarManager.COMMAND_NAMES[SectWarManager.get_preferred_command(target)],
			"\n적은 지난 전투에서 본 우리 수를 기억하고 대비합니다." if not target.observed_commands.is_empty() else "",
		]
		var all_known: bool = not plan["revealed"].has(false)
		scout_button.disabled = all_known or not GameManager.can_wage_war()
		scout_button.text = "정찰 완료" if all_known else "정찰 (은자 %d)" % roundi(
			SectWarManager.get_scout_cost(plan, hero) * RoleActions.get_scout_scale(GameManager.role_state, hero.role)
		)

	# 합마다: 정찰한 적 명령, 고른 아군 명령, 상성
	for i in round_rows.size():
		var row: Dictionary = round_rows[i]
		var known: int = int(plan["enemy_commands"][i]) if not plan.is_empty() and plan["revealed"][i] else -1
		row["enemy"].text = "적: %s" % (SectWarManager.COMMAND_NAMES[known] if known >= 0 else "? (정찰하면 보임)")
		var mine: int = _round_commands[i]
		for j in COMMAND_BUTTONS.size():
			var command: int = COMMAND_BUTTONS[j][0]
			var button: Button = row["buttons"][j]
			button.set_pressed_no_signal(command == mine)
			button.text = ("▶ " if command == mine else "") + SectWarManager.COMMAND_NAMES[command]
			# 앞 합과 같은 명령은 약해진다고 버튼에 표시
			if i > 0 and command == _round_commands[i - 1] and command != SectWarManager.Command.RETREAT:
				button.text += " (연속)"
		var hint: String = "아직 고르지 않음" if mine < 0 else SectWarManager.matchup_text(mine, known)
		if mine >= 0 and known < 0 and mine != SectWarManager.Command.RETREAT:
			hint = "적의 수를 모름 — 진형·성향을 보고 고르세요"
		row["hint"].text = hint
		row["hint"].add_theme_color_override("font_color", _hint_color(hint))
	var chosen: int = get_commands().size()
	round_label.text = "고른 명령: %d / %d" % [chosen, _Balance.WAR_ROUNDS]
	execute_button.disabled = chosen < _Balance.WAR_ROUNDS or target == null or not GameManager.can_wage_war()
	execute_button.text = "전투 개시 — %s 공격" % target.sect_name if target else "전투 개시"


func _hint_color(hint: String) -> Color:
	if hint.begins_with("유리"):
		return _UiTheme.COLORS["accent_jade"]
	if hint.begins_with("불리"):
		return _UiTheme.COLORS["accent_red"]
	return _UiTheme.COLORS["text_muted"]


func _formation_text(formation: SectWarManager.Formation) -> String:
	if not SectWarManager.FORMATION_BOOSTS.has(formation):
		return "진형 없음: 어느 명령도 강해지거나 약해지지 않습니다."
	var boosted: SectWarManager.Command = SectWarManager.FORMATION_BOOSTS[formation]
	var weak: SectWarManager.Command = SectWarManager.COMMAND_BEATS.find_key(boosted)
	var text: String = "%s: %s 강화, %s 약화" % [SectWarManager.FORMATION_NAMES[formation], SectWarManager.COMMAND_NAMES[boosted], SectWarManager.COMMAND_NAMES[weak]]
	if formation == SectWarManager.Formation.CIRCLE:
		text += ". 지더라도 제자를 덜 잃습니다"
	return text


## 이기면·지면 걸린 것
func _stakes_text(target: SectData) -> String:
	var win: PackedStringArray = [
		"명성 +%d~%d" % [_Balance.WAR_WIN_REPUTATION + 2 * _Balance.WAR_WIN_REPUTATION_PER_ROUND, _Balance.WAR_WIN_REPUTATION + 3 * _Balance.WAR_WIN_REPUTATION_PER_ROUND],
		"은자 +%d~" % (_Balance.WAR_WIN_GOLD + 2 * _Balance.WAR_WIN_GOLD_PER_ROUND),
		"적 제자 -%d~" % (_Balance.WAR_ENEMY_DISCIPLE_LOSS + 2),
	]
	if target.disciple_count - (_Balance.WAR_ENEMY_DISCIPLE_LOSS + 2) <= _Balance.SUBJUGATE_DISCIPLE_THRESHOLD:
		win.append("굴복시킬 수 있음")
	if not WorldMap.regions_of(GameManager.map_state, target.id).is_empty():
		win.append("땅 하나 차지")
	var lose: String = "제자 -%d~, 명성 -%d~" % [maxi(1, _Balance.WAR_LOSS_DISCIPLES), _Balance.WAR_LOSS_REPUTATION]
	if GameManager.challenge_target == target.id:
		win.append("도전장 결판 명성 +%d" % _Balance.CHALLENGE_WIN_REPUTATION)
		lose += ", 도전장 명성 -%d" % _Balance.CHALLENGE_LOSS_REPUTATION
	return "이기면: %s\n지면: %s" % [", ".join(win), lose]


# ── 입력 ──

func _on_target_pressed(index: int) -> void:
	AudioManager.play_click()
	_target_index = index
	_fill_generals()
	_update_display()


func _on_formation_pressed(formation: SectWarManager.Formation) -> void:
	AudioManager.play_click()
	_formation = formation
	_update_display()


func _on_general_pressed() -> void:
	AudioManager.play_click()
	_general_index += 1
	if _general_index >= _generals.size():
		_general_index = -1
	_update_display()


func _on_round_command(index: int, command: SectWarManager.Command) -> void:
	AudioManager.play_click()
	_round_commands[index] = -1 if _round_commands[index] == command else command
	_update_display()


## 비어 있는 첫 합에 명령을 넣는다 (예전 순서대로 고르는 방식, 테스트·단축용)
func _add_command(command: SectWarManager.Command) -> void:
	var index: int = _round_commands.find(-1)
	if index < 0:
		log_label.text = "이미 %d합의 명령을 모두 골랐습니다. 바꾸려면 그 합의 다른 명령을 누르세요." % _Balance.WAR_ROUNDS
		return
	_round_commands[index] = command
	_update_display()


func _on_scout_pressed() -> void:
	var target: SectData = _get_target()
	if target == null:
		return
	AudioManager.play_click()
	var result: Dictionary = GameManager.scout_war(target.id)
	log_label.text = result["message"]
	Toast.notify_result(self, result)
	_update_display()


func _on_reset_pressed() -> void:
	_round_commands.fill(-1)
	log_label.text = "명령을 초기화했습니다."
	_update_display()


func _on_execute_pressed() -> void:
	var target: SectData = _get_target()
	if target == null or get_commands().size() < _Balance.WAR_ROUNDS:
		return
	var enemy_name: String = target.sect_name
	var result: Dictionary = GameManager.resolve_sect_war(
		target.id, get_commands(), _formation, get_selected_general().get("id", "")
	)
	var lines: PackedStringArray = [result["message"], ""]
	lines.append_array(result.get("logs", PackedStringArray()))
	log_label.text = "\n".join(lines)
	if result.get("victory", false):
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	_show_result(result, enemy_name)
	_round_commands.fill(-1)
	if result.get("subjugated", false):
		_fill_targets()
	_update_display()


func _show_result(result: Dictionary, enemy_name: String) -> void:
	if not result.has("rounds"):
		Toast.notify(self, result["message"], true)
		return
	var victory: bool = result.get("victory", false)
	result_headline.text = "승리" if victory else "패배"
	result_headline.add_theme_color_override("font_color", _UiTheme.COLORS["accent_jade"] if victory else _UiTheme.COLORS["accent_red"])
	var lines: PackedStringArray = ["%s VS %s" % [GameManager.player_sect.sect_name, enemy_name], ""]
	for round_result in result["rounds"]:
		var outcome: int = round_result["outcome"]
		lines.append("%d합  아군 %s  vs  적 %s  —  %s  (%d : %d)" % [
			round_result["round"], SectWarManager.COMMAND_NAMES[round_result["player_command"]],
			SectWarManager.COMMAND_NAMES[round_result["enemy_command"]],
			"이김" if outcome > 0 else ("짐" if outcome < 0 else "비김"),
			round_result["player_score"], round_result["enemy_score"],
		])
	lines.append("")
	lines.append(result["message"])
	result_body.text = "\n".join(lines)
	result_overlay.visible = true


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)
