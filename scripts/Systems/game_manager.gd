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
## 플레이어 문파를 제외한 강호의 세력들
var world_sects: Array[SectData] = []
var player_relationships: Array[RelationshipData] = []
var triggered_event_ids: Array[String] = []
var pending_event: Dictionary = {}
var story_flags: Dictionary = {}
## 플래그 이름 → 켜진 계절. 기연의 turns_since_flag 조건에 쓴다.
var flag_turns: Dictionary = {}
## 이번 인물이 거쳐 온 역할 이름 (CharacterData.Role 키)
var role_history: Array[String] = []
var legacy_records: Array[LegacyData] = []
var current_ending_id: String = ""
## 게임오버 id. 비어 있지 않으면 이야기가 끝난 상태다.
var game_over_id: String = ""
## 직전 계절 진행의 수입·유지비 요약
var last_turn_report: String = ""
var pending_role_transitions: Array[Dictionary] = []
var mod_martial_arts: Array[MartialArtData] = []
## 새 게임을 시작했거나 세이브를 불러와 진행 중인 게임이 있는지 여부
var is_game_active: bool = false
## 전투 씬이 읽어 갈 전투 구성. 전투가 끝나면 비운다.
var pending_combat: CombatSetup = null


func _ready() -> void:
	_load_mod_data()
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	_initialize_new_game()


## 새 게임을 시작한다. role_id는 StartingRoles.ROLES의 id.
## overrides는 새 게임 "세부 설정"에서 바꾼 시나리오 파라미터다.
func start_new_game(
	display_name: String,
	role_id: String,
	scenario_id: String = ScenarioManager.DEFAULT_ID,
	overrides: Dictionary = {}
) -> void:
	ScenarioManager.activate(scenario_id, overrides)
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
	player_sect = ScenarioManager.create_player_sect()
	world_sects = ScenarioManager.create_rival_sects()
	StartingRoles.apply_sect_setup(role_id, player_sect, player_character)
	player_relationships = RelationshipManager.create_default_relationships()
	triggered_event_ids.clear()
	pending_event.clear()
	story_flags.clear()
	flag_turns.clear()
	role_history.clear()
	_record_role(player_character.role)
	legacy_records.clear()
	current_ending_id = ""
	game_over_id = ""
	last_turn_report = ""
	pending_role_transitions.clear()
	pending_combat = null
	generation = 1
	current_year = 1
	current_season_index = 0
	_sync_event_context()


## 기연 판정에 쓰는 진행 상황을 EventManager에 넘긴다. (딕셔너리·배열은 같은 객체를 공유)
func _sync_event_context() -> void:
	EventManager.world_sects = world_sects
	EventManager.current_year = current_year
	EventManager.current_turn = _get_turn_index()
	EventManager.role_history = role_history
	EventManager.flag_turns = flag_turns


func _record_role(role: CharacterData.Role) -> void:
	var role_name: String = CharacterData.Role.find_key(role)
	if not role_history.has(role_name):
		role_history.append(role_name)


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


## "천하대란 3년 가을"처럼 시나리오 연호를 붙인 날짜
func get_date_text() -> String:
	return "%s %d년 %s" % [ScenarioManager.get_era_name(), current_year, get_current_season()]


func advance_turn() -> void:
	if is_game_over():
		return
	# 제한 연수의 마지막 겨울이 끝나면 시대가 끝난다.
	if (
		ScenarioRules.has_time_limit()
		and current_year >= ScenarioRules.time_limit_years()
		and current_season_index == SEASONS.size() - 1
	):
		last_turn_report = "%s — 시대가 저물었습니다." % get_date_text()
		_force_end("era_end")
		EventBus.turn_advanced.emit(current_year, get_current_season())
		return
	current_season_index = (current_season_index + 1) % SEASONS.size()
	if current_season_index == 0:
		current_year += 1
		_process_yearly_events()
	_sync_event_context()
	var income: String = _process_seasonal_income()
	var upkeep: Dictionary = SectManager.pay_upkeep(player_sect)
	last_turn_report = "%s — %s | %s" % [get_date_text(), income, upkeep["message"]]
	refresh_role_transitions()
	_check_end_states()
	if not is_game_over():
		_try_trigger_event()
	EventBus.turn_advanced.emit(current_year, get_current_season())
	EventBus.resources_changed.emit(player_sect)


func _process_seasonal_income() -> String:
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

	var scale: float = ScenarioRules.income_scale()
	gold_income = roundi(gold_income * scale)
	food_income = roundi(food_income * scale)
	research_income = roundi(research_income * scale)
	player_sect.gold += gold_income
	player_sect.food += food_income
	player_sect.research_points += research_income
	player_sect.reputation += 1
	return "수입: 금화 +%d, 식량 +%d, 연구점 +%d" % [gold_income, food_income, research_income]


func _process_yearly_events() -> void:
	player_character.age += 1
	player_character.restore_internal_energy()
	player_character.gain_experience(_Balance.YEARLY_TRAINING_EXP)
	SectWarManager.grow_world_sects(world_sects)
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
	if randf() >= ScenarioRules.event_rate():
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


func is_game_over() -> bool:
	return not game_over_id.is_empty()


## 게임오버를 먼저 확인하고, 아니면 엔딩을 확인한다.
func _check_end_states() -> void:
	if is_game_over():
		return
	var over_id: String = EndingManager.check_game_over(player_sect)
	if not over_id.is_empty():
		game_over_id = over_id
		is_game_active = false
		pending_event.clear()
		EventBus.game_over.emit(over_id)
		return
	_check_ending()


func _check_ending() -> void:
	if not current_ending_id.is_empty():
		return
	var ending: String = EndingManager.check_endings(
		player_character, player_sect, story_flags
	)
	if ending.is_empty():
		return
	_reach_ending(ending)


func _reach_ending(ending: String) -> void:
	current_ending_id = ending
	EventManager.set_flag(story_flags, "ending_reached", ending)
	EventBus.ending_reached.emit(ending)
	if ScenarioRules.end_on_victory() and ScenarioManager.is_victory_ending(ending):
		_force_end("scenario_complete")


## 그 판의 평가 (엔딩 화면용)
func get_evaluation() -> Dictionary:
	return EndingManager.evaluate(
		player_character,
		player_sect,
		world_sects,
		generation,
		current_ending_id,
		ScenarioManager.is_victory_ending(current_ending_id)
	)


## 기연의 end_game 효과: 엔딩이면 엔딩에 도달하고, 게임오버면 이야기를 끝낸다.
func _force_end(end_id: String) -> void:
	if EndingManager.GAME_OVERS.has(end_id):
		if not is_game_over():
			game_over_id = end_id
			is_game_active = false
			pending_event.clear()
			EventBus.game_over.emit(end_id)
	elif EndingManager.has_ending(end_id) and current_ending_id.is_empty():
		_reach_ending(end_id)


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
	_record_role(player_character.role)
	refresh_role_transitions()
	_check_end_states()
	return result


func start_legacy_succession() -> Dictionary:
	if is_game_over():
		return {"success": false, "message": "이야기가 끝나 전승할 수 없습니다."}
	if not ScenarioRules.legacy_enabled():
		return {"success": false, "message": "이 시나리오에서는 세대 전승을 할 수 없습니다."}
	var max_generations: int = ScenarioRules.max_generations()
	if max_generations > 0 and generation >= max_generations:
		return {"success": false, "message": "이 시나리오의 마지막 세대입니다. (최대 %d세대)" % max_generations}
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
	flag_turns.clear()
	role_history.clear()
	_record_role(player_character.role)

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


func get_world_sect(sect_id: String) -> SectData:
	for sect in world_sects:
		if sect.id == sect_id:
			return sect
	return null


## 강호 세력을 약한 순서로 정렬해 돌려준다.
func get_world_sects_by_power() -> Array[SectData]:
	var result: Array[SectData] = world_sects.duplicate()
	result.sort_custom(func(a: SectData, b: SectData) -> bool:
		return SectWarManager.get_sect_power(a) < SectWarManager.get_sect_power(b)
	)
	return result


## 문파전을 걸 수 있는 세력 (굴복하지 않은 세력, 약한 순서)
func get_war_targets() -> Array[SectData]:
	var result: Array[SectData] = []
	for sect in get_world_sects_by_power():
		if not sect.subjugated:
			result.append(sect)
	return result


func can_wage_war() -> bool:
	return story_flags.get("last_war_turn", -1) != _get_turn_index()


## 문파전. 계절마다 한 번, 굴복하지 않은 세력을 상대로만 할 수 있다.
func resolve_sect_war(target_id: String, commands: Array) -> Dictionary:
	if not can_wage_war():
		return {"success": false, "victory": false, "message": "이번 계절에는 이미 문파전을 치렀습니다."}
	var enemy: SectData = get_world_sect(target_id)
	if enemy == null or enemy.subjugated:
		return {"success": false, "victory": false, "message": "공격할 수 없는 상대입니다."}
	var typed_commands: Array[SectWarManager.Command] = []
	for cmd in commands:
		typed_commands.append(cmd as SectWarManager.Command)
	EventManager.set_flag(story_flags, "last_war_turn", _get_turn_index())
	var result: Dictionary = SectWarManager.resolve_battle(
		player_sect, player_character, enemy, typed_commands
	)
	if result.get("victory", false):
		EventManager.set_flag(story_flags, "won_sect_war")
		EventManager.set_flag(story_flags, "defeated_%s" % enemy.id)
	if result.get("subjugated", false):
		EventManager.set_flag(story_flags, "subjugated_%s" % enemy.id)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	_check_end_states()
	return result


## 전투를 시작한다. 전투 씬으로 이동하고, 결과는 finish_combat으로 받는다.
func start_combat(setup: CombatSetup) -> void:
	pending_combat = setup
	SceneRouter.goto(get_tree(), SceneRouter.COMBAT)


## 전투 씬이 사용할 구성을 돌려준다. 예약된 전투가 없으면(개발자 메뉴 등) 비무를 만든다.
func get_or_create_combat_setup() -> CombatSetup:
	if pending_combat == null:
		pending_combat = CombatManager.create_sparring(player_character)
	return pending_combat


func can_spar() -> bool:
	return story_flags.get("last_spar_turn", -1) != _get_turn_index()


## 경영 화면의 비무. 계절마다 한 번만 할 수 있다.
func start_sparring() -> Dictionary:
	if not can_spar():
		return {"success": false, "message": "이번 계절에는 이미 비무를 했습니다."}
	EventManager.set_flag(story_flags, "last_spar_turn", _get_turn_index())
	start_combat(CombatManager.create_sparring(player_character))
	return {"success": true, "message": "남궁휘에게 비무를 청합니다."}


## 전투 결과를 반영하고 결과(message, outcome 포함)를 돌려준다.
func finish_combat(outcome: CombatManager.Outcome, fallen_allies: int = 0) -> Dictionary:
	if pending_combat == null:
		return {"success": false, "message": "진행 중인 전투가 없습니다."}
	var result: Dictionary = CombatManager.apply_outcome(
		pending_combat,
		outcome,
		player_character,
		player_sect,
		player_relationships,
		story_flags,
		fallen_allies
	)
	pending_combat = null
	EventBus.combat_finished.emit(result)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)
	refresh_role_transitions()
	_check_end_states()
	if result["success"]:
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	return result


func _get_turn_index() -> int:
	return current_year * SEASONS.size() + current_season_index


func _load_mod_data() -> void:
	mod_martial_arts = _ModLoader.load_martial_arts_from_json()


func save_game() -> Dictionary:
	var state: Dictionary = {
		"version": _SaveManager.SAVE_VERSION,
		"scenario_id": ScenarioManager.current_id,
		"scenario_overrides": ScenarioManager.user_overrides,
		"current_year": current_year,
		"current_season_index": current_season_index,
		"generation": generation,
		"story_flags": story_flags,
		"flag_turns": flag_turns,
		"role_history": role_history,
		"triggered_event_ids": triggered_event_ids,
		"current_ending_id": current_ending_id,
		"game_over_id": game_over_id,
		"character": _SaveManager.serialize_character(player_character),
		"sect": _SaveManager.serialize_sect(player_sect),
		"world_sects": _SaveManager.serialize_sects(world_sects),
		"relationships": _SaveManager.serialize_relationships(player_relationships),
		"legacy_records": _SaveManager.serialize_legacy(legacy_records),
	}
	return _SaveManager.save_game(state)


func load_game() -> Dictionary:
	var result: Dictionary = _SaveManager.load_game()
	if not result["success"]:
		return result
	_apply_save_data(result["data"])
	is_game_active = not is_game_over()
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)
	return result


func _apply_save_data(data: Dictionary) -> void:
	# 시나리오를 먼저 켜야 전용 인물·문파·기연이 준비된다. 구버전 세이브는 기본 시나리오.
	ScenarioManager.activate(
		data.get("scenario_id", ScenarioManager.DEFAULT_ID),
		data.get("scenario_overrides", {})
	)
	current_year = data.get("current_year", 1)
	current_season_index = data.get("current_season_index", 0)
	generation = data.get("generation", 1)
	story_flags = data.get("story_flags", {})
	flag_turns.clear()
	for flag in data.get("flag_turns", {}):
		flag_turns[flag] = int(data["flag_turns"][flag])
	role_history.clear()
	for role_name in data.get("role_history", []):
		role_history.append(str(role_name))
	triggered_event_ids.clear()
	for event_id in data.get("triggered_event_ids", []):
		triggered_event_ids.append(event_id)
	current_ending_id = data.get("current_ending_id", "")
	game_over_id = data.get("game_over_id", "")
	pending_event.clear()
	_set_player_character(_SaveManager.deserialize_character(data.get("character", {})))
	player_sect = _SaveManager.deserialize_sect(data.get("sect", {}))
	# 강호 세력이 없는 구버전 세이브는 데이터 초기값으로 채운다.
	if data.has("world_sects"):
		world_sects = _SaveManager.deserialize_sects(data["world_sects"])
	else:
		world_sects = SectRegistry.create_rival_sects()
	# 역할 기록이 없는 구버전 세이브는 현재 역할만 기록한다.
	_record_role(player_character.role)
	_sync_event_context()
	player_relationships = _SaveManager.deserialize_relationships(data.get("relationships", []))
	legacy_records = _SaveManager.deserialize_legacy(data.get("legacy_records", []))
	refresh_role_transitions()


func has_save_file() -> bool:
	return _SaveManager.has_save()


func _apply_event_result(result: Dictionary) -> void:
	if result.has("end_game"):
		_force_end(result["end_game"])
	EventBus.event_resolved.emit(result)
	EventBus.action_message.emit(result.get("message", ""))
	EventBus.resources_changed.emit(player_sect)
	EventBus.character_updated.emit(player_character)
	EventBus.relationships_changed.emit(player_relationships)
	refresh_role_transitions()
	_check_end_states()
	if result.get("success", false):
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	# 전투로 이어지는 선택지는 결과를 반영한 뒤 전투 씬으로 넘어간다.
	if result.has("combat"):
		start_combat(result["combat"])