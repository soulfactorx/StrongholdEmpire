extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")
const _FacilityPopup = preload("res://scripts/UI/facility_popup.gd")
const _ChoicePopup = preload("res://scripts/UI/choice_popup.gd")
const _DisciplePopup = preload("res://scripts/UI/disciple_popup.gd")
const _BondPopup = preload("res://scripts/UI/bond_popup.gd")

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
@onready var role_popup: Control = %RolePopup
var facility_popup: Control
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
## 대상을 고르는 중인 역할 행동 id
var _pending_role_action: String = ""


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
	if not GameManager.pending_event.is_empty():
		event_popup.show_event(GameManager.pending_event)
	_show_invasion()


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
	_update_time_display()
	_update_sect_display(GameManager.player_sect)
	_update_character_display(GameManager.player_character)
	_update_relationships_display(GameManager.player_relationships)
	_update_role_actions()


## 역할별 고유 행동 버튼과 역할 자원 표시
func _update_role_actions() -> void:
	var character: CharacterData = GameManager.player_character
	role_resource_label.text = "[%s 고유 행동] %s" % [character.get_role_name(), RoleActions.describe(GameManager)]
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
	var result: Dictionary = GameManager.do_role_action(action_id, target_id)
	_on_action_message(result["message"])
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
	sect_name_label.text = sect.sect_name
	# 다음 계절 예상 수지 (수입 − 유지비)
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


func _update_character_display(character: CharacterData) -> void:
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
			{"id": "yield", "title": "산문을 내준다", "description": "제자 −%d, 명성 −%d" % [
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
	GameManager.advance_turn()


func _on_train_pressed() -> void:
	_execute_action(SectManager.train_disciples(GameManager.player_sect, GameManager.player_character))


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
	_execute_action(GameManager.buy_elixir())


func _on_feast_pressed() -> void:
	_execute_action(GameManager.hold_feast())


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


func _on_help_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.HELP)


func _on_main_menu_pressed() -> void:
	AudioManager.play_click()
	# 메인 메뉴로 나갈 때도 자동 저장해 둔다.
	if GameManager.is_game_active:
		GameManager.autosave()
	SceneRouter.goto(get_tree(), SceneRouter.MAIN_MENU)