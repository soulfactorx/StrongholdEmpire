extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _FacilityPopup = preload("res://scripts/UI/facility_popup.gd")
const _ChoicePopup = preload("res://scripts/UI/choice_popup.gd")
const _DisciplePopup = preload("res://scripts/UI/disciple_popup.gd")

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


func _update_relationships_display(relationships: Array[RelationshipData]) -> void:
	relationship_label.text = RelationshipManager.format_relationships(relationships)


func _on_turn_advanced(_year: int, _season: String) -> void:
	_update_time_display()
	_update_role_actions()
	_on_action_message(GameManager.last_turn_report)


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
	var result: Dictionary = GameManager.save_game()
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
	SceneRouter.goto(get_tree(), SceneRouter.MAIN_MENU)