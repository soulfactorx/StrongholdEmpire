extends Node

const _ModLoader = preload("res://scripts/Systems/mod_loader.gd")
const _SaveManager = preload("res://scripts/Systems/save_manager.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

const SEASONS: Array[String] = ["봄", "여름", "가을", "겨울"]

var current_year: int = 1
var current_season_index: int = 0
var generation: int = 1
var player_character: CharacterData
var player_sect: SectData
var player_relationships: Array[RelationshipData] = []
var triggered_event_ids: Array[String] = []
var pending_event: Dictionary = {}
var story_flags: Dictionary = {}
var legacy_records: Array[LegacyData] = []
var current_ending_id: String = ""
var pending_role_transitions: Array[Dictionary] = []
var mod_martial_arts: Array[MartialArtData] = []
## 새 게임을 시작했거나 세이브를 불러와 진행 중인 게임이 있는지 여부
var is_game_active: bool = false


func _ready() -> void:
	_load_mod_data()
	_initialize_new_game()


## 새 게임을 시작한다. role_id는 StartingRoles.ROLES의 id.
func start_new_game(display_name: String, role_id: String) -> void:
	_initialize_new_game(role_id, display_name)
	is_game_active = true
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)


func _initialize_new_game(
	role_id: String = StartingRoles.DEFAULT_ID,
	display_name: String = ""
) -> void:
	_set_player_character(StartingRoles.create_character(role_id, display_name))
	player_sect = _create_default_sect()
	StartingRoles.apply_sect_setup(role_id, player_sect, player_character)
	player_relationships = RelationshipManager.create_default_relationships()
	triggered_event_ids.clear()
	pending_event.clear()
	story_flags.clear()
	legacy_records.clear()
	current_ending_id = ""
	pending_role_transitions.clear()
	generation = 1
	current_year = 1
	current_season_index = 0


func _create_default_sect() -> SectData:
	var sect := SectData.new()
	sect.sect_name = "청운검파"
	sect.leader_name = "청운검선"
	return sect


func _set_player_character(character: CharacterData) -> void:
	if player_character and player_character.leveled_up.is_connected(_on_player_leveled_up):
		player_character.leveled_up.disconnect(_on_player_leveled_up)
	player_character = character
	player_character.leveled_up.connect(_on_player_leveled_up)


func _on_player_leveled_up(new_level: int) -> void:
	EventBus.action_message.emit(
		"%s의 경지가 올랐습니다! Lv.%d" % [player_character.display_name, new_level]
	)
	EventBus.character_updated.emit(player_character)


func get_current_season() -> String:
	return SEASONS[current_season_index]


func advance_turn() -> void:
	current_season_index = (current_season_index + 1) % SEASONS.size()
	if current_season_index == 0:
		current_year += 1
		_process_yearly_events()
	_process_seasonal_income()
	refresh_role_transitions()
	_try_trigger_event()
	_check_ending()
	EventBus.turn_advanced.emit(current_year, get_current_season())
	EventBus.resources_changed.emit(player_sect)


func _process_seasonal_income() -> void:
	var season := get_current_season()
	var role_bonus: float = RoleManager.get_role_management_bonus(player_character.role)
	var gold_income: int = int((20 + player_sect.treasury_level * 10) * role_bonus)
	var food_income: int = int((30 + player_sect.training_ground_level * 5) * role_bonus)
	var research_income: int = int(
		(player_sect.library_level * 3 + int(player_character.wisdom * 0.5)) * role_bonus
	)

	match season:
		"봄":
			food_income += 15
		"여름":
			gold_income += 10
		"가을":
			food_income += 25
		"겨울":
			food_income -= 10
			research_income += 5

	player_sect.gold += gold_income
	player_sect.food += food_income
	player_sect.research_points += research_income
	player_sect.reputation += 1


func _process_yearly_events() -> void:
	player_character.age += 1
	player_character.restore_internal_energy()
	player_character.gain_experience(_Balance.YEARLY_TRAINING_EXP)
	EventBus.character_updated.emit(player_character)


func refresh_role_transitions() -> void:
	pending_role_transitions = RoleManager.get_available_transitions(
		player_character,
		player_sect,
		player_relationships,
		story_flags
	)
	if not pending_role_transitions.is_empty():
		EventBus.role_transitions_available.emit(pending_role_transitions)


func _try_trigger_event() -> void:
	if not pending_event.is_empty():
		return

	var event: Dictionary = EventManager.check_turn_events(
		player_character,
		player_sect,
		player_relationships,
		get_current_season(),
		triggered_event_ids,
		story_flags
	)
	if event.is_empty():
		return

	pending_event = event
	EventBus.event_triggered.emit(event)


func _check_ending() -> void:
	if not current_ending_id.is_empty():
		return
	var ending: String = EndingManager.check_endings(
		player_character, player_sect, story_flags
	)
	if ending.is_empty():
		return
	current_ending_id = ending
	story_flags["ending_reached"] = ending
	EventBus.ending_reached.emit(ending)


func resolve_pending_event(choice_index: int) -> void:
	if pending_event.is_empty():
		return

	var result: Dictionary = EventManager.resolve_choice(
		pending_event["id"],
		choice_index,
		player_character,
		player_sect,
		player_relationships,
		story_flags
	)
	pending_event.clear()
	_apply_event_result(result)


func apply_role_transition(role: CharacterData.Role) -> Dictionary:
	var result: Dictionary = RoleManager.apply_transition(
		player_character, player_sect, role
	)
	EventBus.action_message.emit(result["message"])
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.role_changed.emit(player_character.role)
	refresh_role_transitions()
	_check_ending()
	return result


func start_legacy_succession() -> Dictionary:
	if not LegacyManager.can_retire(player_character):
		return {
			"success": false,
			"message": "아직 전승할 수 없습니다. (55세 이상 또는 레벨 10)",
		}

	var legacy: LegacyData = LegacyManager.create_legacy_record(
		player_character,
		player_sect,
		generation,
		current_ending_id
	)
	legacy_records.append(legacy)
	generation += 1

	_set_player_character(LegacyManager.create_successor(legacy, player_sect))
	LegacyManager.apply_legacy_bonuses(player_sect, legacy)
	player_relationships = RelationshipManager.create_default_relationships()
	triggered_event_ids.clear()
	current_ending_id = ""
	story_flags.clear()

	EventBus.legacy_succession.emit(legacy)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)

	return {
		"success": true,
		"message": "%s이(가) %s(으)로 이어갑니다. (제%d세대)" % [
			legacy.predecessor_name,
			player_character.display_name,
			generation,
		],
	}


func resolve_sect_war(commands: Array) -> Dictionary:
	var typed_commands: Array[SectWarManager.Command] = []
	for cmd in commands:
		typed_commands.append(cmd as SectWarManager.Command)
	var result: Dictionary = SectWarManager.resolve_battle(
		player_sect, player_character, typed_commands
	)
	if result.get("victory", false):
		story_flags["won_sect_war"] = true
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	_check_ending()
	return result


func _load_mod_data() -> void:
	mod_martial_arts = _ModLoader.load_martial_arts_from_json()


func save_game() -> Dictionary:
	var state: Dictionary = {
		"version": _SaveManager.SAVE_VERSION,
		"current_year": current_year,
		"current_season_index": current_season_index,
		"generation": generation,
		"story_flags": story_flags,
		"triggered_event_ids": triggered_event_ids,
		"current_ending_id": current_ending_id,
		"character": _SaveManager.serialize_character(player_character),
		"sect": _SaveManager.serialize_sect(player_sect),
		"relationships": _SaveManager.serialize_relationships(player_relationships),
		"legacy_records": _SaveManager.serialize_legacy(legacy_records),
	}
	return _SaveManager.save_game(state)


func load_game() -> Dictionary:
	var result: Dictionary = _SaveManager.load_game()
	if not result["success"]:
		return result
	_apply_save_data(result["data"])
	is_game_active = true
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)
	return result


func _apply_save_data(data: Dictionary) -> void:
	current_year = data.get("current_year", 1)
	current_season_index = data.get("current_season_index", 0)
	generation = data.get("generation", 1)
	story_flags = data.get("story_flags", {})
	triggered_event_ids.clear()
	for event_id in data.get("triggered_event_ids", []):
		triggered_event_ids.append(event_id)
	current_ending_id = data.get("current_ending_id", "")
	pending_event.clear()
	_set_player_character(_SaveManager.deserialize_character(data.get("character", {})))
	player_sect = _SaveManager.deserialize_sect(data.get("sect", {}))
	player_relationships = _SaveManager.deserialize_relationships(data.get("relationships", []))
	legacy_records = _SaveManager.deserialize_legacy(data.get("legacy_records", []))
	refresh_role_transitions()


func has_save_file() -> bool:
	return _SaveManager.has_save()


func _apply_event_result(result: Dictionary) -> void:
	EventBus.event_resolved.emit(result)
	EventBus.action_message.emit(result.get("message", ""))
	EventBus.resources_changed.emit(player_sect)
	EventBus.character_updated.emit(player_character)
	EventBus.relationships_changed.emit(player_relationships)
	refresh_role_transitions()
	_check_ending()
	if result.get("success", false):
		AudioManager.play_success()
	else:
		AudioManager.play_failure()