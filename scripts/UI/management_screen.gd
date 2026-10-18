extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")
const _FacilityPopup = preload("res://scripts/UI/facility_popup.gd")
const _ChoicePopup = preload("res://scripts/UI/choice_popup.gd")
const _DisciplePopup = preload("res://scripts/UI/disciple_popup.gd")
const _BondPopup = preload("res://scripts/UI/bond_popup.gd")
const _ConfirmPopup = preload("res://scripts/UI/confirm_popup.gd")
const _OptionsPopup = preload("res://scripts/UI/options_popup.gd")
const _ChroniclePopup = preload("res://scripts/UI/chronicle_popup.gd")

@onready var year_label: Label = %YearLabel
@onready var season_label: Label = %SeasonLabel
@onready var generation_label: Label = %GenerationLabel
@onready var sect_name_label: Label = %SectNameLabel
@onready var gold_label: Label = %GoldLabel
@onready var food_label: Label = %FoodLabel
@onready var reputation_label: Label = %ReputationLabel
@onready var research_label: Label = %ResearchLabel
@onready var disciple_label: Label = %DiscipleLabel
@onready var facilities_label: Label = %FacilitiesLabel
@onready var character_name_label: Label = %CharacterNameLabel
@onready var character_role_label: Label = %CharacterRoleLabel
@onready var character_stats_label: Label = %CharacterStatsLabel
@onready var martial_arts_label: Label = %MartialArtsLabel
@onready var relationship_label: Label = %RelationshipLabel
@onready var log_label: Label = %LogLabel
@onready var role_resource_label: Label = %RoleResourceLabel
@onready var role_action_box: HBoxContainer = %RoleActionBox
@onready var event_popup: Control = %EventPopup
@onready var action_grid: GridContainer = $Margin/RootHBox/RightPanel/ActionPanel/ActionGrid
@onready var role_popup: Control = %RolePopup
var facility_popup: Control
var chronicle_popup: Control
## 계절마다 강호 세력 동향
var faction_popup: Control
## 역할 행동의 대상을 고르는 팝업
var choice_popup: Control
## 제자 명단 팝업
var disciple_popup: Control
## 인연 팝업
var bond_popup: Control
## 침공 대응 팝업
var invasion_popup: Control
## 저장 슬롯 팝업
var save_popup: Control
## 확인 대화상자, 설정, 연간 보고서
var confirm_popup: Control
var options_popup: Control
var report_popup: Control
## 대상을 고르는 중인 역할 행동 id
var _pending_role_action: String = ""
## 화면에 마지막으로 보여 준 주인공 레벨 (오르면 효과음)
var _shown_level: int = -1
## 주인공 초상화 (역할에 따라 바뀐다)
var character_portrait: TextureRect


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	facility_popup = _FacilityPopup.new()
	add_child(facility_popup)
	facility_popup.upgraded.connect(_execute_action)
	choice_popup = _ChoicePopup.new()
	add_child(choice_popup)
	choice_popup.chosen.connect(_on_role_target_chosen)
	disciple_popup = _DisciplePopup.new()
	add_child(disciple_popup)
	disciple_popup.changed.connect(_execute_action)
	bond_popup = _BondPopup.new()
	add_child(bond_popup)
	bond_popup.acted.connect(_on_bond_acted)
	invasion_popup = _ChoicePopup.new()
	add_child(invasion_popup)
	invasion_popup.chosen.connect(_on_invasion_chosen)
	save_popup = _ChoicePopup.new()
	add_child(save_popup)
	save_popup.chosen.connect(_on_save_slot_chosen)
	confirm_popup = _ConfirmPopup.new()
	add_child(confirm_popup)
	options_popup = _OptionsPopup.new()
	add_child(options_popup)
	report_popup = _ConfirmPopup.new()
	add_child(report_popup)
	chronicle_popup = _ChroniclePopup.new()
	add_child(chronicle_popup)
	faction_popup = _ConfirmPopup.new()
	add_child(faction_popup)
	_connect_bus(EventBus.turn_advanced, _on_turn_advanced)
	_connect_bus(EventBus.resources_changed, _on_resources_changed)
	_connect_bus(EventBus.character_updated, _on_character_updated)
	_connect_bus(EventBus.relationships_changed, _on_relationships_changed)
	_connect_bus(EventBus.action_message, _on_action_message)
	_connect_bus(EventBus.event_triggered, _on_event_triggered)
	_connect_bus(EventBus.role_transitions_available, _on_role_transitions_available)
	_connect_bus(EventBus.role_changed, _on_role_changed)
	_connect_bus(EventBus.ending_reached, _on_ending_reached)
	_connect_bus(EventBus.game_over, _on_game_over)
	if GameManager.is_game_over():
		_on_game_over.call_deferred(GameManager.game_over_id)
		return
	_refresh_all()
	_attach_tips()
	if not GameManager.pending_event.is_empty():
		event_popup.show_event(GameManager.pending_event)
	_show_invasion()
	# 게임패드가 있으면 계절 진행에 포커스를 두어 바로 조작할 수 있게 한다.
	if not Input.get_connected_joypads().is_empty() and not event_popup.visible:
		$Margin/RootHBox/RightPanel/ActionPanel/ActionGrid/AdvanceTurnButton.grab_focus()


## 길게 눌러(마우스는 올려 두면) 계산 근거를 보여 준다.
var tips: Dictionary = {}


func _attach_tips() -> void:
	tips["gold"] = LongPressTip.attach(gold_label, _gold_tip)
	tips["food"] = LongPressTip.attach(food_label, _food_tip)
	tips["reputation"] = LongPressTip.attach(reputation_label, func() -> String:
		return "명성: 해마다 제자 %d명마다 +1. 연회·문파전·기연으로도 오릅니다.\n0이 되면 이야기가 끝납니다(게임오버)." % _Balance.DISCIPLES_PER_YEARLY_REPUTATION
	)
	tips["research"] = LongPressTip.attach(research_label, func() -> String:
		var sect: SectData = GameManager.player_sect
		return "연구점 수입 = 서고 Lv.%d × %d + 지혜 %d × %.1f (역할·시나리오 보정)\n무공 창조·비급 연구·강화·전수·상대 무공 분석에 씁니다." % [
			sect.library_level, _Balance.LIBRARY_RESEARCH_PER_LEVEL, GameManager.player_character.wisdom, _Balance.WISDOM_RESEARCH_RATIO,
		]
	)
	tips["stats"] = LongPressTip.attach(character_stats_label, func() -> String:
		return "전투력 = 무력 + 신법 + 현재 내공 ÷ 10\n무력: 공격·무공 피해 / 신법: 전투력 / 지혜: 연구 성공률·연구점 / 매력: 대화 유대·리더십\n경험치가 차면 경지(레벨)가 오르고 능력치·최대 내공이 오릅니다."
	)
	tips["facilities"] = LongPressTip.attach(facilities_label, func() -> String:
		var lines: PackedStringArray = []
		for facility in SectManager.get_facility_ids():
			lines.append("%s: %s" % [SectManager.FACILITY_INFO[facility]["name"], SectManager.FACILITY_INFO[facility]["effect"]])
		return "\n".join(lines) + "\n시작 수준을 넘는 단계마다 계절 유지비 금화 %d" % _Balance.FACILITY_UPKEEP_GOLD
	)


func _gold_tip() -> String:
	var sect: SectData = GameManager.player_sect
	var forecast: Dictionary = GameManager.estimate_next_season()
	return "다음 계절 금화 %+d\n수입: 기본 %d + 금고 Lv.%d × %d (역할·계절·시나리오 보정, 금고 담당 제자·공물 포함)\n유지비 %d: 제자 %d명 × %d + 확장한 시설 %d단계 × %d\n금화가 모자라면 명성이 떨어지고, 3계절 연속이면 이야기가 끝납니다.\n해마다 %d을 넘는 몫의 %d%%를 잃습니다." % [
		forecast["gold"], _Balance.BASE_GOLD_INCOME, sect.treasury_level, _Balance.TREASURY_GOLD_PER_LEVEL,
		sect.get_gold_upkeep(), sect.disciple_count, _Balance.GOLD_PER_DISCIPLE, sect.get_facility_steps(), _Balance.FACILITY_UPKEEP_GOLD,
		_Balance.GOLD_SAFE_AMOUNT, int(_Balance.GOLD_LOSS_RATE * 100),
	]


func _food_tip() -> String:
	var sect: SectData = GameManager.player_sect
	var forecast: Dictionary = GameManager.estimate_next_season()
	return "다음 계절 식량 %+d\n수입: 기본 %d + 무술장 Lv.%d × %d (역할·계절·시나리오 보정)\n유지비 %d: 제자 %d명 × %d\n식량이 모자라면 제자가 떠납니다. 해마다 %d을 넘는 몫의 %d%%가 상합니다." % [
		forecast["food"], _Balance.BASE_FOOD_INCOME, sect.training_ground_level, _Balance.TRAINING_FOOD_PER_LEVEL,
		sect.get_food_upkeep(), sect.disciple_count, _Balance.FOOD_PER_DISCIPLE,
		_Balance.FOOD_SAFE_AMOUNT, int(_Balance.FOOD_SPOIL_RATE * 100),
	]


## 키보드 단축키: Space 계절 진행, F 시설, M 무공 연구소, W 강호 정세, D 제자 명단, B 인연,
## R 역할 전환, C 연대기, G 강호 지도, S 저장, O 설정, Esc 팝업 닫기(없으면 메인 메뉴로)
const HUB_SHORTCUTS: Dictionary = {
	KEY_SPACE: "_on_advance_turn_pressed",
	KEY_F: "_on_facility_pressed",
	KEY_M: "_on_martial_art_pressed",
	KEY_W: "_on_world_pressed",
	KEY_D: "_on_disciple_pressed",
	KEY_B: "_on_bond_pressed",
	KEY_R: "_on_role_pressed",
	KEY_C: "_on_chronicle_pressed",
	KEY_G: "_on_map_pressed",
	KEY_S: "_on_save_pressed",
	KEY_O: "_on_options_pressed",
}


func _get_open_popups() -> Array[Control]:
	var result: Array[Control] = []
	for popup in [role_popup, facility_popup, choice_popup, disciple_popup, bond_popup, invasion_popup, save_popup, confirm_popup, options_popup, report_popup, chronicle_popup, faction_popup]:
		if popup and popup.visible:
			result.append(popup)
	# 행동 미리보기 확인창은 맨 위에 뜬다.
	var preview: Node = get_node_or_null("PreviewLayer/PreviewPopup")
	if preview and preview.visible:
		result.append(preview)
	return result


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# 기연은 반드시 골라야 하므로 단축키로 넘기지 않는다.
	if event_popup.visible:
		return
	var open: Array[Control] = _get_open_popups()
	if key.keycode == KEY_ESCAPE:
		if open.is_empty():
			_on_main_menu_pressed()
		else:
			open[-1].visible = false
		get_viewport().set_input_as_handled()
		return
	if open.is_empty() and HUB_SHORTCUTS.has(key.keycode) and _shortcut_allowed(HUB_SHORTCUTS[key.keycode]):
		call(HUB_SHORTCUTS[key.keycode])
		get_viewport().set_input_as_handled()


## 전역 EventBus 연결. 화면이 트리를 떠나면 모두 끊어, 떠난 화면이 신호에 반응하지 않게 한다.
var _bus_connections: Array = []


func _connect_bus(bus_signal: Signal, handler: Callable) -> void:
	bus_signal.connect(handler)
	_bus_connections.append([bus_signal, handler])


func _exit_tree() -> void:
	for connection in _bus_connections:
		if connection[0].is_connected(connection[1]):
			connection[0].disconnect(connection[1])
	_bus_connections.clear()


func _refresh_all() -> void:
	_apply_role_layout()
	_update_time_display()
	_update_sect_display(GameManager.player_sect)
	_update_character_display(GameManager.player_character)
	_update_relationships_display(GameManager.player_relationships)
	_update_role_actions()


## 역할마다 할 일이 없는 버튼과 칸을 숨긴다 (RoleDashboard)
func _apply_role_layout() -> void:
	var role: CharacterData.Role = GameManager.player_character.role
	for button_name in RoleDashboard.ACTION_BUTTONS:
		var button: Control = action_grid.get_node_or_null(button_name)
		if button:
			button.visible = RoleDashboard.is_button_visible(role, button_name)
	$Margin/RootHBox/LeftPanel/FacilityPanel.visible = RoleDashboard.get_layout(role)["sect"]


## 버튼이 숨겨진 행동은 단축키로도 열지 않는다.
func _shortcut_allowed(method: String) -> bool:
	for button in action_grid.get_children():
		if button is BaseButton and not button.visible:
			for connection in button.pressed.get_connections():
				if connection["callable"].get_method() == method:
					return false
	return true


## 역할별 고유 행동 버튼과 역할 자원 표시
func _update_role_actions() -> void:
	var character: CharacterData = GameManager.player_character
	role_resource_label.text = "%s\n[%s 고유 행동] %s" % [
		RoleDashboard.get_layout(character.role)["focus"], character.get_role_name(), RoleActions.describe(GameManager),
	]
	for child in role_action_box.get_children():
		role_action_box.remove_child(child)
		child.queue_free()
	var can_act: bool = RoleActions.can_act(GameManager.role_state, GameManager._get_turn_index())
	for action in RoleActions.get_actions(character.role):
		var button := Button.new()
		button.text = action["title"]
		button.custom_minimum_size = Vector2(170, 48)
		button.disabled = not can_act
		button.pressed.connect(_on_role_action_pressed.bind(action["id"]))
		_UiTheme.style_button(button)
		role_action_box.add_child(button)


func _on_role_action_pressed(action_id: String) -> void:
	AudioManager.play_click()
	var action: Dictionary = RoleActions.ACTIONS[action_id]
	if action["target"].is_empty():
		_run_role_action(action_id, "")
		return
	var targets: Array[Dictionary] = RoleActions.get_targets(GameManager, action_id)
	if targets.is_empty():
		_on_action_message("%s: 고를 수 있는 대상이 없습니다." % action["title"])
		return
	_pending_role_action = action_id
	choice_popup.open(action["title"], action["description"], targets)


func _on_role_target_chosen(target_id: String) -> void:
	var action_id: String = _pending_role_action
	_pending_role_action = ""
	if not action_id.is_empty():
		_run_role_action(action_id, target_id)


func _run_role_action(action_id: String, target_id: String) -> void:
	ActionPreview.confirm(
		self, RoleActions.ACTIONS[action_id]["title"],
		_simulate_role_action.bind(action_id, target_id), _do_role_action.bind(action_id, target_id)
	)


## 미리보기용: 전투·기연은 시작하지 않고 행동과 그 여파만 적용한다.
func _simulate_role_action(action_id: String, target_id: String) -> Dictionary:
	var result: Dictionary = RoleActions.perform(GameManager, action_id, target_id)
	GameManager._apply_role_consequences()
	return result


func _do_role_action(action_id: String, target_id: String) -> void:
	var result: Dictionary = GameManager.do_role_action(action_id, target_id)
	var lines: PackedStringArray = result.get("dialogue", PackedStringArray())
	_on_action_message(result["message"] + ("\n" + "\n".join(lines) if not lines.is_empty() else ""))
	if result["success"]:
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	# 전투로 넘어가면 이 화면은 곧 사라진다.
	if is_inside_tree():
		_refresh_all()


func _update_time_display() -> void:
	var year_text: String = "%s %d년" % [ScenarioManager.get_era_name(), GameManager.current_year]
	if ScenarioRules.has_time_limit():
		year_text += " (남은 %d년)" % ScenarioRules.years_left(GameManager.current_year)
	year_label.text = year_text
	season_label.text = GameManager.get_current_season()
	generation_label.text = "「%s」 제%d세대" % [ScenarioManager.current.get("title", ""), GameManager.generation]


func _update_sect_display(sect: SectData) -> void:
	sect_name_label.text = RoleDashboard.get_sect_title(GameManager.player_character.role, sect)
	# 다음 계절 예상 수지 (수입 - 유지비)
	var forecast: Dictionary = GameManager.estimate_next_season()
	gold_label.text = "금화: %d (다음 계절 %+d, 유지비 %d)" % [sect.gold, forecast["gold"], sect.get_gold_upkeep()]
	food_label.text = "식량: %d (다음 계절 %+d, 유지비 %d)" % [sect.food, forecast["food"], sect.get_food_upkeep()]
	# 다음 계절을 넘기지 못할 것 같으면 경고 색으로 표시한다.
	_set_warning(gold_label, sect.gold + forecast["gold"] < 0)
	_set_warning(food_label, sect.food + forecast["food"] < 0)
	reputation_label.text = "명성: %d" % sect.reputation
	research_label.text = "연구점: %d" % sect.research_points
	disciple_label.text = "제자: %d / %d" % [sect.disciple_count, sect.max_disciples]
	var facility_texts: PackedStringArray = []
	for facility in SectManager.get_facility_ids():
		var level: int = SectManager.get_facility_level(sect, facility)
		var name: String = SectManager.FACILITY_INFO[facility]["name"]
		facility_texts.append("%s Lv.%d" % [name, level] if level > 0 else "%s 없음" % name)
	facilities_label.text = "  ".join(facility_texts.slice(0, 3)) + "\n" + "  ".join(facility_texts.slice(3))


func _set_warning(label: Label, warn: bool) -> void:
	if warn:
		label.add_theme_color_override("font_color", _UiTheme.COLORS["accent_red"])
	else:
		label.add_theme_color_override("font_color", _UiTheme.COLORS["text_primary"])


## 인물 패널 왼쪽에 초상화 자리를 만든다. (한 번만)
func _ensure_character_portrait() -> void:
	if character_portrait:
		return
	var content: Control = character_name_label.get_parent()
	var panel: Node = content.get_parent()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.owner = content.owner
	character_portrait = TextureRect.new()
	character_portrait.custom_minimum_size = Vector2(88, 110)
	character_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	character_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(character_portrait)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# reparent는 owner를 지켜 %이름 찾기가 계속 된다.
	content.reparent(row, false)


func _update_character_display(character: CharacterData) -> void:
	if _shown_level >= 0 and character.level > _shown_level:
		AudioManager.play_level_up()
	_shown_level = character.level
	_ensure_character_portrait()
	character_portrait.texture = ArtAssets.role_portrait(character.role)
	character_portrait.visible = character_portrait.texture != null
	character_name_label.text = "%s (%d세)" % [character.display_name, character.age]
	character_role_label.text = character.get_role_name()
	character_stats_label.text = (
		"무력 %d | 신법 %d | 지혜 %d | 매력 %d\n내공 %d/%d | 전투력 %d | 도덕 %d | Lv.%d (경험 %d/%d)"
		% [
			character.strength,
			character.agility,
			character.wisdom,
			character.charisma,
			character.internal_energy_current,
			character.internal_energy_max,
			character.get_combat_power(),
			character.morality,
			character.level,
			character.experience,
			character.get_next_level_experience(),
		]
	)
	martial_arts_label.text = "무공: %s" % character.get_martial_arts_text()


## 경영 화면에는 유대가 깊은 인연 몇 명만 보이고, 나머지는 [인연 돌보기]에서 본다.
const HUB_RELATIONSHIP_LINES := 3


func _update_relationships_display(relationships: Array[RelationshipData]) -> void:
	var sorted: Array[RelationshipData] = relationships.duplicate()
	sorted.sort_custom(func(a: RelationshipData, b: RelationshipData) -> bool: return a.bond_strength > b.bond_strength)
	# 줄 수를 넘으면 마지막 줄을 "외 N명"으로 쓴다.
	var count: int = HUB_RELATIONSHIP_LINES if sorted.size() <= HUB_RELATIONSHIP_LINES else HUB_RELATIONSHIP_LINES - 1
	var shown: Array[RelationshipData] = []
	for rel in sorted.slice(0, count):
		shown.append(rel)
	var text: String = RelationshipManager.format_relationships(shown)
	if sorted.size() > count:
		text += "\n… 외 %d명 — [인연 돌보기]에서 모두 보기" % (sorted.size() - count)
	relationship_label.text = text


func _on_turn_advanced(_year: int, _season: String) -> void:
	_update_time_display()
	_update_role_actions()
	_on_action_message(GameManager.last_turn_report)
	_show_invasion()
	_show_year_report()
	_show_faction_report()


## 계절을 넘기면 우리 문파 인물(문주·교두·의원)과 강호 세력이 무엇을 했는지 보여 준다. (설정에서 끌 수 있다)
func _show_faction_report() -> void:
	if not GameSettings.faction_report:
		return
	if GameManager.last_faction_report.is_empty() and GameManager.last_npc_report.is_empty():
		return
	faction_popup.open("강호 동향 — %s" % GameManager.get_date_text(), NpcAgent.format_season(
		GameManager.last_npc_report, GameManager.last_faction_report
	), Callable(), "확인", "")


## 해가 바뀌면 1년 결산을 보여 준다.
func _show_year_report() -> void:
	if GameManager.pending_year_report.is_empty():
		return
	var report: Dictionary = GameManager.pending_year_report
	GameManager.pending_year_report = {}
	report_popup.open(report["title"], "\n".join(report["lines"]), Callable(), "확인", "")


## 다른 세력이 침공해 왔으면 대응을 고르게 한다. 닫으면 다음 계절에 산문을 내준 것으로 처리된다.
func _show_invasion() -> void:
	if GameManager.pending_invasion.is_empty():
		return
	var invader: SectData = GameManager.get_world_sect(GameManager.pending_invasion)
	if invader == null:
		return
	AudioManager.play_event()
	var bribe_gold: int = _Balance.INVASION_BRIBE_GOLD
	var options: Array[Dictionary] = [
			{"id": "fight", "title": "맞서 싸운다", "description": "방어전: 제자와 인연이 함께 싸웁니다. 막아 내면 %s이(가) 제자를 잃습니다." % invader.sect_name},
			{"id": "bribe", "title": "금화로 물린다 (금화 %d)" % bribe_gold, "description": "싸우지 않고 돌려보냅니다.",
				"disabled": GameManager.player_sect.gold < bribe_gold},
			{"id": "yield", "title": "산문을 내준다", "description": "제자 -%d, 명성 -%d" % [
				_Balance.INVASION_YIELD_DISCIPLES, _Balance.INVASION_YIELD_REPUTATION,
			]},
	]
	invasion_popup.open(
		"%s의 침공" % invader.sect_name,
		"%s의 무리가 산문 앞에 몰려왔습니다. (전력 %d)\n대응하지 않고 계절을 넘기면 산문을 내준 것으로 칩니다." % [
			invader.sect_name, SectWarManager.get_sect_power(invader),
		],
		options
	)


func _on_invasion_chosen(choice: String) -> void:
	var result: Dictionary = GameManager.resolve_invasion(choice)
	if is_inside_tree():
		_on_action_message(result["message"])
		_refresh_all()


func _on_resources_changed(sect: SectData) -> void:
	_update_sect_display(sect)


func _on_character_updated(character: CharacterData) -> void:
	_update_character_display(character)
	_update_role_actions()


func _on_relationships_changed(relationships: Array[RelationshipData]) -> void:
	_update_relationships_display(relationships)


func _on_action_message(message: String) -> void:
	log_label.text = message


func _on_event_triggered(event_data: Dictionary) -> void:
	AudioManager.play_event()
	event_popup.show_event(event_data)


func _on_role_transitions_available(options: Array[Dictionary]) -> void:
	if not options.is_empty():
		_on_action_message("새로운 역할 전환 기회가 있습니다. [역할 전환] 버튼을 누르세요.")


func _on_role_changed(_new_role: CharacterData.Role) -> void:
	_refresh_all()


func _on_ending_reached(ending_id: String) -> void:
	var ending: Dictionary = EndingManager.get_ending(ending_id)
	_on_action_message("엔딩 도달: %s — [엔딩/레거시] 메뉴에서 확인하세요." % ending["title"])


func _on_game_over(_game_over_id: String) -> void:
	AudioManager.play_failure()
	SceneRouter.goto(get_tree(), SceneRouter.ENDING)


func _execute_action(result: Dictionary) -> void:
	EventBus.action_message.emit(result["message"])
	if result["success"]:
		EventBus.resources_changed.emit(GameManager.player_sect)
		EventBus.character_updated.emit(GameManager.player_character)


func _on_advance_turn_pressed() -> void:
	AudioManager.play_click()
	if not GameSettings.action_preview:
		GameManager.advance_turn()
		return
	ActionPreview.get_popup(self).open("계절 넘기기 — 미리보기", _advance_preview_text(), GameManager.advance_turn, "넘기기", "취소")


## 계절을 넘기면 확실히 바뀌는 것(수입·유지비)과 넘긴 뒤에야 알 수 있는 것을 알려 준다.
func _advance_preview_text() -> String:
	var sect: SectData = GameManager.player_sect
	var estimate: Dictionary = GameManager.estimate_next_season()
	var lines: PackedStringArray = ["예상 변화 (수입 - 유지비)"]
	lines.append("금화  %d → %d (%+d)" % [sect.gold, maxi(0, sect.gold + estimate["gold"]), estimate["gold"]])
	lines.append("식량  %d → %d (%+d)" % [sect.food, maxi(0, sect.food + estimate["food"]), estimate["food"]])
	if sect.food + estimate["food"] < 0 or sect.gold + estimate["gold"] < 0:
		lines.append("자원이 모자라 유지비를 다 내지 못하면 제자가 떠납니다.")
	lines.append("")
	lines.append("나이·시설 효과·역할 자원도 계절에 맞춰 바뀌고, 기연·강호 세력의 움직임·침공은 넘긴 뒤에 알 수 있습니다.")
	var left: PackedStringArray = []
	for flag in [["last_elixir_turn", "영약"], ["last_feast_turn", "연회"], ["last_spar_turn", "연습 비무"]]:
		if GameManager.can_do_seasonal(flag[0]):
			left.append(flag[1])
	if not left.is_empty():
		lines.append("이번 계절에 아직 하지 않은 일: " + ", ".join(left))
	return "\n".join(lines)


func _on_train_pressed() -> void:
	ActionPreview.confirm(self, "제자 수련",
		func() -> Dictionary: return SectManager.train_disciples(GameManager.player_sect, GameManager.player_character),
		func() -> void: _execute_action(SectManager.train_disciples(GameManager.player_sect, GameManager.player_character))
	)


func _on_bond_pressed() -> void:
	AudioManager.play_click()
	bond_popup.open()


func _on_bond_acted(result: Dictionary) -> void:
	if is_inside_tree():
		_on_action_message(result["message"])
		_update_relationships_display(GameManager.player_relationships)
		_update_sect_display(GameManager.player_sect)


func _on_disciple_pressed() -> void:
	AudioManager.play_click()
	disciple_popup.open()


func _on_facility_pressed() -> void:
	AudioManager.play_click()
	facility_popup.open()


func _on_elixir_pressed() -> void:
	ActionPreview.confirm(self, "영약 구매", GameManager.buy_elixir, func() -> void: _execute_action(GameManager.buy_elixir()))


func _on_feast_pressed() -> void:
	ActionPreview.confirm(self, "문파 연회", GameManager.hold_feast, func() -> void: _execute_action(GameManager.hold_feast()))


func _on_martial_art_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.MARTIAL_ART)


func _on_role_pressed() -> void:
	if GameManager.pending_role_transitions.is_empty():
		_on_action_message("현재 가능한 역할 전환이 없습니다.")
		return
	role_popup.show_options(GameManager.pending_role_transitions)


func _on_combat_pressed() -> void:
	AudioManager.play_click()
	var result: Dictionary = GameManager.start_sparring()
	if not result["success"]:
		_on_action_message(result["message"])


func _on_sect_war_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.SECT_WAR)


func _on_world_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.WORLD)


func _on_ending_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.ENDING)


func _on_save_pressed() -> void:
	AudioManager.play_click()
	if GameManager.ironman:
		_on_action_message("철인 모드에서는 계절이 바뀔 때 자동으로만 저장됩니다.")
		return
	var options: Array[Dictionary] = []
	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var summary: Dictionary = SaveManager.get_slot_summary(slot)
		options.append({
			"id": str(slot),
			"title": summary["title"],
			"description": ("덮어쓰기 — " if summary["exists"] else "") + summary["detail"],
		})
	save_popup.open("저장", "저장할 슬롯을 고르세요. 계절이 바뀔 때마다 자동 저장도 따로 됩니다.", options)


func _on_save_slot_chosen(slot: String) -> void:
	var result: Dictionary = GameManager.save_game(int(slot))
	_on_action_message(result["message"])
	if result["success"]:
		AudioManager.play_success()
	else:
		AudioManager.play_failure()


func _on_map_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.MAP)


func _on_chronicle_pressed() -> void:
	AudioManager.play_click()
	chronicle_popup.open()


func _on_help_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.HELP)


func _on_main_menu_pressed() -> void:
	AudioManager.play_click()
	confirm_popup.open("메인 메뉴로", "자동 저장한 뒤 메인 메뉴로 나갑니다.\n[계속하기]나 [불러오기]로 이어서 할 수 있습니다.", go_main_menu, "나가기", "머무르기")


## 자동 저장하고 메인 메뉴로 나간다.
func go_main_menu() -> void:
	if GameManager.is_game_active:
		GameManager.autosave()
	SceneRouter.goto(get_tree(), SceneRouter.MAIN_MENU)


func _on_options_pressed() -> void:
	AudioManager.play_click()
	options_popup.open()