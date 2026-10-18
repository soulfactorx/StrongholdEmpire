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
@onready var facility_panel: Control = $Margin/RootHBox/LeftPanel/FacilityPanel
## 행동 버튼 (노드 이름 → 버튼). 세로 배치에서는 버튼이 여러 쪽으로 흩어지므로 이름으로 찾는다.
var _action_buttons: Dictionary = {}
## 세로 배치: 쪽 이름 → 쪽(ScrollContainer), 탭 버튼, 할 일 목록, 맨 위 자원 한 줄
var pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
var todo_box: VBoxContainer
var status_label: Label
var world_report_label: Label
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
	for button in action_grid.get_children():
		_action_buttons[button.name] = button
	if LayoutMode.is_portrait():
		_build_portrait_layout()
	_refresh_all()
	_attach_tips()
	if not GameManager.pending_event.is_empty():
		event_popup.show_event(GameManager.pending_event)
	_show_invasion()
	# 게임패드가 있으면 계절 진행에 포커스를 두어 바로 조작할 수 있게 한다.
	if not Input.get_connected_joypads().is_empty() and not event_popup.visible:
		_action_buttons["AdvanceTurnButton"].grab_focus()


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
	tips["arts"] = LongPressTip.attach(martial_arts_label, func() -> String:
		return "보유 무공\n" + GameManager.player_character.get_martial_arts_detail()
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
	if GameManager.uses_purse():
		return _purse_tip()
	return "다음 계절 금화 %+d\n수입: 기본 %d + 금고 Lv.%d × %d (역할·계절·시나리오 보정, 금고 담당 제자·공물 포함)\n유지비 %d: 제자 %d명 × %d + 확장한 시설 %d단계 × %d\n금화가 모자라면 명성이 떨어지고, 3계절 연속이면 이야기가 끝납니다.\n해마다 %d을 넘는 몫의 %d%%를 잃습니다." % [
		forecast["gold"], _Balance.BASE_GOLD_INCOME, sect.treasury_level, _Balance.TREASURY_GOLD_PER_LEVEL,
		sect.get_gold_upkeep(), sect.disciple_count, _Balance.GOLD_PER_DISCIPLE, sect.get_facility_steps(), _Balance.FACILITY_UPKEEP_GOLD,
		_Balance.GOLD_SAFE_AMOUNT, int(_Balance.GOLD_LOSS_RATE * 100),
	]


func _food_tip() -> String:
	var sect: SectData = GameManager.player_sect
	var forecast: Dictionary = GameManager.estimate_next_season()
	if GameManager.uses_purse():
		return _purse_tip()
	return "다음 계절 식량 %+d\n수입: 기본 %d + 무술장 Lv.%d × %d (역할·계절·시나리오 보정)\n유지비 %d: 제자 %d명 × %d\n식량이 모자라면 제자가 떠납니다. 해마다 %d을 넘는 몫의 %d%%가 상합니다." % [
		forecast["food"], _Balance.BASE_FOOD_INCOME, sect.training_ground_level, _Balance.TRAINING_FOOD_PER_LEVEL,
		sect.get_food_upkeep(), sect.disciple_count, _Balance.FOOD_PER_DISCIPLE,
		_Balance.FOOD_SAFE_AMOUNT, int(_Balance.FOOD_SPOIL_RATE * 100),
	]


## 개인 재산 설명: 문파 수입이 없고 생활비만 나간다. 버는 길은 역할마다 다르다.
func _purse_tip() -> String:
	var ways: String = {
		CharacterData.Role.WANDERER: "의뢰 게시판(토벌·호위, 타지는 보상 %d%%)" % roundi(_Balance.JOB_AWAY_REWARD_SCALE * 100),
		CharacterData.Role.MERCENARY: "세력의 계약(선금·잔금)",
		CharacterData.Role.SPY: "활동비(계절마다 금화 %d)" % _Balance.SPY_STIPEND_GOLD,
		CharacterData.Role.ASSASSIN: "표적 의뢰(금화 %d)" % _Balance.ASSASSINATION_GOLD,
	}.get(GameManager.player_character.role, "역할 행동")
	var sect_line: String = "\n몸담은 %s의 금고(금화 %d, 식량 %d)는 문주가 꾸립니다." % [
		GameManager.player_sect.sect_name, GameManager.player_sect.gold, GameManager.player_sect.food,
	] if GameManager.has_sect() else ""
	return "내 재산 — 문파 수입은 없습니다.\n생활비: 계절마다 식량 %d·금화 %d (식량이 모자라면 식량 1당 금화 %d로 사 먹음)\n금화도 떨어지면 굶주려 내공 -%d\n버는 길: %s, 외출·기연·전투 보상%s" % [
		_Balance.LIVING_FOOD, _Balance.LIVING_GOLD, _Balance.LIVING_FOOD_PRICE, _Balance.STARVE_INTERNAL_LOSS, ways, sect_line,
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
	_update_portrait()
	_update_time_display()
	_update_sect_display(GameManager.player_sect)
	_update_character_display(GameManager.player_character)
	_update_relationships_display(GameManager.player_relationships)
	_update_role_actions()


## 역할마다 할 일이 없는 버튼과 칸을 숨긴다 (RoleDashboard)
func _apply_role_layout() -> void:
	var role: CharacterData.Role = GameManager.player_character.role
	for button_name in RoleDashboard.ACTION_BUTTONS:
		var button: Control = _action_buttons.get(button_name)
		if button:
			button.visible = RoleDashboard.is_button_visible(role, button_name)
	facility_panel.visible = RoleDashboard.get_layout(role)["sect"]
	_update_spar_button()


## 비무 버튼: 겨룰 상대(인연이 있는 인물) 이름을 보이고, 없으면 누를 수 없다.
func _update_spar_button() -> void:
	var button: Button = _action_buttons.get("CombatButton")
	if button == null:
		return
	var partner: String = GameManager.get_spar_partner()
	button.text = "비무 (%s)" % NpcRoster.get_display_name(partner) if not partner.is_empty() else "비무 (상대 없음)"
	button.disabled = partner.is_empty()


## 버튼이 숨겨진 행동은 단축키로도 열지 않는다.
func _shortcut_allowed(method: String) -> bool:
	for button in _action_buttons.values():
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
		# 이동은 역할 행동 횟수와 따로 계절에 한 번
		button.disabled = not GameManager.can_do_seasonal("last_travel_turn") if action["id"] == "travel" else not can_act
		button.pressed.connect(_on_role_action_pressed.bind(action["id"]))
		_UiTheme.style_button(button)
		role_action_box.add_child(button)


func _on_role_action_pressed(action_id: String) -> void:
	AudioManager.play_click()
	var action: Dictionary = RoleActions.ACTIONS[action_id]
	if action["target"].is_empty():
		_run_role_action(action_id, "")
		return
	# 이동은 강호 지도에서 지역을 골라 옮긴다
	if action["target"] == "location":
		SceneRouter.goto(get_tree(), SceneRouter.MAP)
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
	var wallet: SectData = GameManager.get_wallet()
	if GameManager.uses_purse():
		# 개인 재산: 수입 없이 생활비만 나간다. 의뢰·계약·기연으로 번다.
		gold_label.text = "내 금화: %d (다음 계절 %+d, 생활비)" % [wallet.gold, forecast["gold"]]
		food_label.text = "내 식량: %d (다음 계절 %+d, 생활비)" % [wallet.food, forecast["food"]]
	else:
		gold_label.text = "금화: %d (다음 계절 %+d, 유지비 %d)" % [sect.gold, forecast["gold"], sect.get_gold_upkeep()]
		food_label.text = "식량: %d (다음 계절 %+d, 유지비 %d)" % [sect.food, forecast["food"], sect.get_food_upkeep()]
	# 다음 계절을 넘기지 못할 것 같으면 경고 색으로 표시한다.
	_set_warning(gold_label, wallet.gold + forecast["gold"] < 0)
	_set_warning(food_label, wallet.food + forecast["food"] < 0)
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
	# 등장인물로 플레이하면 그 인물의 초상화
	character_portrait.texture = ArtAssets.player_portrait(character)
	character_portrait.visible = character_portrait.texture != null
	character_name_label.text = "%s (%d세)" % [character.display_name, character.age]
	# 지금 있는 지역 (경영 화면 배경도 그 지역의 그림으로)
	character_role_label.text = "%s · 지역: %s" % [character.get_role_name(), GameManager.get_location_text()]
	ArtAssets.set_background(self, ArtAssets.region_background(GameManager.player_region))
	character_stats_label.text = (
		"무력 %d | 신법 %d | 지혜 %d | 매력 %d\n내공 %d/%d | 전투력 %d | 도덕 %d %s | Lv.%d (경험 %d/%d)"
		% [
			character.strength,
			character.agility,
			character.wisdom,
			character.charisma,
			character.internal_energy_current,
			character.internal_energy_max,
			character.get_combat_power(),
			character.morality,
			character.get_alignment_name(),
			character.level,
			character.experience,
			character.get_next_level_experience(),
		]
	)
	martial_arts_label.text = "무공 %d개: %s (길게 누르면 자세히)" % [character.martial_arts.size(), character.get_martial_arts_text()] if not character.martial_arts.is_empty() else "무공: 습득 무공 없음"


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
	_update_portrait()


func _on_character_updated(character: CharacterData) -> void:
	_update_character_display(character)
	_update_role_actions()
	_update_portrait()


func _on_relationships_changed(relationships: Array[RelationshipData]) -> void:
	_update_relationships_display(relationships)
	_update_spar_button()
	_update_portrait()


func _on_action_message(message: String) -> void:
	log_label.text = message
	# 세로 화면에서 안내 줄은 "할 일" 탭에만 있으므로, 다른 탭에서는 토스트로 띄운다
	if LayoutMode.is_portrait() and pages.has("todo") and not pages["todo"].visible:
		Toast.notify(self, message)


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
	var sect: SectData = GameManager.get_wallet()
	var estimate: Dictionary = GameManager.estimate_next_season()
	var lines: PackedStringArray = ["예상 변화 (생활비)" if GameManager.uses_purse() else "예상 변화 (수입 - 유지비)"]
	lines.append("금화  %d → %d (%+d)" % [sect.gold, maxi(0, sect.gold + estimate["gold"]), estimate["gold"]])
	lines.append("식량  %d → %d (%+d)" % [sect.food, maxi(0, sect.food + estimate["food"]), estimate["food"]])
	if sect.food + estimate["food"] < 0 or sect.gold + estimate["gold"] < 0:
		lines.append("노자가 떨어지면 굶주려 내공이 줍니다." if GameManager.uses_purse() else "자원이 모자라 유지비를 다 내지 못하면 제자가 떠납니다.")
	lines.append("")
	lines.append("나이·시설 효과·역할 자원도 계절에 맞춰 바뀌고, 기연·강호 세력의 움직임·침공은 넘긴 뒤에 알 수 있습니다.")
	# 지금 역할로 할 수 있는 일만 (막내 제자에게 연회를 권하지 않는다)
	var left: PackedStringArray = RoleDashboard.get_unused_actions(GameManager)
	if not left.is_empty():
		lines.append("이번 계절에 아직 하지 않은 일 (%s): %s" % [GameManager.player_character.get_role_name(), ", ".join(left)])
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


## 역할 전환 창: 고를 전환이 없어도 열어 갈 수 있는 길과 조건을 보인다.
func _on_role_pressed() -> void:
	GameManager.refresh_role_transitions(false)
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

# ─── 세로(휴대폰) 배치 ─────────────────────────────

## 이 계절 할 일 단계 id → 누르면 할 일
const STEP_HANDLERS: Dictionary = {
	"bond": "_on_bond_pressed", "elixir": "_on_elixir_pressed", "feast": "_on_feast_pressed",
	"spar": "_on_combat_pressed", "disciple_train": "_on_disciple_pressed", "sect_war": "_on_sect_war_pressed",
	"pacify": "_on_map_pressed",
}
## 쪽 이름과 탭 글자
const PAGES: Array = [["todo", "할 일"], ["sect", "문파"], ["hero", "인물"], ["world", "강호"], ["menu", "메뉴"]]


## 세로 화면: 위에 날짜·자원 한 줄, 가운데 쪽(할 일·문파·인물·강호·메뉴), 아래에 [계절 넘기기]와 탭.
## 기존 칸과 버튼을 그대로 옮겨 쓰므로 하는 일(신호·단축키·미리보기)은 가로와 같다.
func _build_portrait_layout() -> void:
	var margin: MarginContainer = $Margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	var old_root: Control = $Margin/RootHBox
	var root := VBoxContainer.new()
	root.name = "PortraitRoot"
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# 위: 날짜와 자원 한 줄
	var top := PanelContainer.new()
	top.name = "TopBar"
	root.add_child(top)
	var top_box := VBoxContainer.new()
	top.add_child(top_box)
	var date_row := HBoxContainer.new()
	date_row.add_theme_constant_override("separation", 12)
	top_box.add_child(date_row)
	year_label.reparent(date_row)
	season_label.reparent(date_row)
	generation_label.reparent(date_row)
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_box.add_child(status_label)

	# 가운데: 쪽들 (한 번에 하나)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(holder)
	for entry in PAGES:
		var scroll := ScrollContainer.new()
		scroll.name = "Page_" + entry[0]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 10)
		scroll.add_child(box)
		holder.add_child(scroll)
		pages[entry[0]] = scroll

	# 할 일: 역할 칸(고유 행동), 이 계절 할 일 목록, 최근 소식
	var todo: VBoxContainer = _page_box("todo")
	$Margin/RootHBox/RightPanel/RolePanel.reparent(todo)
	var todo_panel := PanelContainer.new()
	todo_panel.name = "TodoPanel"
	todo.add_child(todo_panel)
	todo_box = VBoxContainer.new()
	todo_box.add_theme_constant_override("separation", 8)
	todo_panel.add_child(todo_box)
	$Margin/RootHBox/LeftPanel/LogPanel.reparent(todo)

	# 문파: 자원·시설 칸, 문파 운영 버튼
	var sect_page: VBoxContainer = _page_box("sect")
	$Margin/RootHBox/LeftPanel/SectPanel.reparent(sect_page)
	facility_panel.reparent(sect_page)
	_add_button_grid(sect_page, ["TrainButton", "FacilityButton", "FeastButton", "DiscipleButton", "SectWarButton"])

	# 인물: 주인공·인연 칸, 무공·수련 버튼
	var hero: VBoxContainer = _page_box("hero")
	$Margin/RootHBox/RightPanel/CharacterPanel.reparent(hero)
	_add_button_grid(hero, ["MartialArtButton", "ElixirButton", "CombatButton", "RoleButton"])
	$Margin/RootHBox/RightPanel/RelationshipPanel.reparent(hero)

	# 강호: 지도·정세·연대기·엔딩, 지난 계절 동향
	var world: VBoxContainer = _page_box("world")
	var world_grid: GridContainer = _add_button_grid(world, ["MapButton", "WorldButton"])
	for node_name in ["ChronicleButton", "EndingButton"]:
		var button: Button = $Margin/RootHBox/LeftPanel/SystemPanel/SystemVBox.get_node(node_name)
		button.reparent(world_grid)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var report_panel := PanelContainer.new()
	world.add_child(report_panel)
	world_report_label = Label.new()
	world_report_label.name = "WorldReportLabel"
	world_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(world_report_label, 14)
	report_panel.add_child(world_report_label)

	# 메뉴: 저장·도움말·설정·메인 메뉴
	$Margin/RootHBox/LeftPanel/SystemPanel.reparent(_page_box("menu"))

	# 아래: 계절 넘기기(크게)와 탭
	var advance: Button = _action_buttons["AdvanceTurnButton"]
	advance.reparent(root)
	advance.custom_minimum_size = Vector2(0, 64)
	advance.text = "계절 넘기기 ▶"
	var tabs := HBoxContainer.new()
	tabs.name = "TabBar"
	tabs.add_theme_constant_override("separation", 4)
	root.add_child(tabs)
	var group := ButtonGroup.new()
	for entry in PAGES:
		var tab := Button.new()
		tab.name = "Tab_" + entry[0]
		tab.text = entry[1]
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size = Vector2(0, 60)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_page.bind(entry[0]))
		tabs.add_child(tab)
		_tab_buttons[entry[0]] = tab
	old_root.visible = false
	_UiTheme.apply_to_control(root)
	show_page("todo")


func _page_box(page: String) -> VBoxContainer:
	return pages[page].get_child(0)


## 이름으로 고른 행동 버튼을 2열 격자로 옮긴다.
func _add_button_grid(parent: Control, names: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	for button_name in names:
		var button: Button = _action_buttons[button_name]
		button.reparent(grid)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 56)
	return grid


## 세로 화면의 쪽을 바꾼다.
func show_page(page: String) -> void:
	for name in pages:
		pages[name].visible = name == page
	if _tab_buttons.has(page):
		_tab_buttons[page].set_pressed_no_signal(true)
	_update_portrait()


func get_current_page() -> String:
	for name in pages:
		if pages[name].visible:
			return name
	return ""


## 세로 화면의 자원 한 줄·할 일 목록·강호 동향을 새로 그린다.
func _update_portrait() -> void:
	if pages.is_empty():
		return
	var sect: SectData = GameManager.player_sect
	var wallet: SectData = GameManager.get_wallet()
	var forecast: Dictionary = GameManager.estimate_next_season()
	status_label.text = "%s %d (%+d) · 식량 %d (%+d) · 명성 %d · 연구점 %d%s · %s" % [
		"내 금화" if GameManager.uses_purse() else "금화", wallet.gold, forecast["gold"], wallet.food, forecast["food"],
		sect.reputation, sect.research_points,
		" · 제자 %d/%d" % [sect.disciple_count, sect.max_disciples] if GameManager.has_sect() else "",
		GameManager.get_region_name(),
	]
	_set_warning(status_label, wallet.gold + forecast["gold"] < 0 or wallet.food + forecast["food"] < 0)
	for child in todo_box.get_children():
		todo_box.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "이번 계절 할 일 — %s" % GameManager.get_date_text()
	_UiTheme.style_label_title(title, 22)
	todo_box.add_child(title)
	var steps: Array[Dictionary] = RoleDashboard.get_season_steps(GameManager)
	for step in steps:
		if step["id"] == "role_action":
			var note := Label.new()
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.text = "· %s — 위 역할 칸의 버튼으로" % step["title"]
			todo_box.add_child(note)
			continue
		var button := Button.new()
		button.name = "Step_" + step["id"]
		button.text = "%s\n%s" % [step["title"], step["detail"]]
		button.custom_minimum_size = Vector2(0, 64)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(Callable(self, STEP_HANDLERS[step["id"]]))
		_UiTheme.style_button(button)
		todo_box.add_child(button)
	var done := Label.new()
	done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	done.text = "할 일을 마쳤으면 아래 [계절 넘기기]를 누르세요." if not steps.is_empty() else "이번 계절에 할 수 있는 일을 다 했습니다. 아래 [계절 넘기기]를 누르세요."
	_UiTheme.set_font_size(done, 14)
	todo_box.add_child(done)
	world_report_label.text = "지난 계절 강호 동향\n" + NpcAgent.format_season(GameManager.last_npc_report, GameManager.last_faction_report)
