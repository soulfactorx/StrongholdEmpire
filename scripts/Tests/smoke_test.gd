extends SceneTree

## 헤드리스 스모크 테스트.
## 실행: godot --headless --path . -s res://scripts/Tests/smoke_test.gd

const _SaveManager = preload("res://scripts/Systems/save_manager.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")
const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

const MAIN_SCENES: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/Combat/combat_scene.tscn",
	"res://scenes/Combat/grid_demo.tscn",
	"res://scenes/UI/management_screen.tscn",
	"res://scenes/UI/martial_art_screen.tscn",
	"res://scenes/UI/sect_war_screen.tscn",
	"res://scenes/UI/ending_screen.tscn",
	"res://scenes/UI/help_screen.tscn",
	"res://scenes/UI/new_game_screen.tscn",
]

var _failures: int = 0
## 끝까지 실행된 검사 함수 이름
var _completed: Dictionary = {}
var _checks: int = 0


func _initialize() -> void:
	_test_scenes_load()
	_check(_completed.has("_test_scenes_load"), "_test_scenes_load 끝까지 실행")
	_test_level_curve()
	_check(_completed.has("_test_level_curve"), "_test_level_curve 끝까지 실행")
	_test_gain_experience()
	_check(_completed.has("_test_gain_experience"), "_test_gain_experience 끝까지 실행")
	_test_martial_art_round_trip()
	_check(_completed.has("_test_martial_art_round_trip"), "_test_martial_art_round_trip 끝까지 실행")
	_test_old_save_without_martial_arts()
	_check(_completed.has("_test_old_save_without_martial_arts"), "_test_old_save_without_martial_arts 끝까지 실행")
	_test_starting_roles()
	_check(_completed.has("_test_starting_roles"), "_test_starting_roles 끝까지 실행")
	_test_combat_outcomes()
	_check(_completed.has("_test_combat_outcomes"), "_test_combat_outcomes 끝까지 실행")
	_test_combat_events()
	_check(_completed.has("_test_combat_events"), "_test_combat_events 끝까지 실행")
	_test_event_definitions()
	_check(_completed.has("_test_event_definitions"), "_test_event_definitions 끝까지 실행")
	_test_event_validation()
	_check(_completed.has("_test_event_validation"), "_test_event_validation 끝까지 실행")
	_test_event_conditions()
	_check(_completed.has("_test_event_conditions"), "_test_event_conditions 끝까지 실행")
	_test_event_branches()
	_check(_completed.has("_test_event_branches"), "_test_event_branches 끝까지 실행")
	_test_event_mod_folder()
	_check(_completed.has("_test_event_mod_folder"), "_test_event_mod_folder 끝까지 실행")
	_test_upkeep()
	_check(_completed.has("_test_upkeep"), "_test_upkeep 끝까지 실행")
	_test_game_over_conditions()
	_check(_completed.has("_test_game_over_conditions"), "_test_game_over_conditions 끝까지 실행")
	_test_npc_roster()
	_check(_completed.has("_test_npc_roster"), "_test_npc_roster 끝까지 실행")
	_test_sect_registry()
	_check(_completed.has("_test_sect_registry"), "_test_sect_registry 끝까지 실행")
	_test_world_sect_events()
	_check(_completed.has("_test_world_sect_events"), "_test_world_sect_events 끝까지 실행")
	_test_combat_rules()
	_check(_completed.has("_test_combat_rules"), "_test_combat_rules 끝까지 실행")
	_test_martial_art_library()
	_check(_completed.has("_test_martial_art_library"), "_test_martial_art_library 끝까지 실행")
	_test_ally_setup()
	_check(_completed.has("_test_ally_setup"), "_test_ally_setup 끝까지 실행")
	_test_event_grammar_validation()
	_check(_completed.has("_test_event_grammar_validation"), "_test_event_grammar_validation 끝까지 실행")
	_test_event_grammar_conditions()
	_check(_completed.has("_test_event_grammar_conditions"), "_test_event_grammar_conditions 끝까지 실행")
	_test_event_grammar_effects()
	_check(_completed.has("_test_event_grammar_effects"), "_test_event_grammar_effects 끝까지 실행")
	# 오토로드의 _ready()는 첫 프레임에 실행되므로 런타임 검사는 그 뒤로 미룬다.
	process_frame.connect(_run_runtime_tests, CONNECT_ONE_SHOT)


func _run_runtime_tests() -> void:
	# 각 검사가 끝까지 실행됐는지 확인한다. 스크립트 오류로 중단되면 완료 표시가 남지 않는다.
	_test_turn_loop()
	_check(_completed.has("_test_turn_loop"), "_test_turn_loop 끝까지 실행")
	_test_start_new_game()
	_check(_completed.has("_test_start_new_game"), "_test_start_new_game 끝까지 실행")
	await _test_scene_navigation()
	_check(_completed.has("_test_scene_navigation"), "_test_scene_navigation 끝까지 실행")
	await _test_combat_flow()
	_check(_completed.has("_test_combat_flow"), "_test_combat_flow 끝까지 실행")
	await _test_event_popup_choices()
	_check(_completed.has("_test_event_popup_choices"), "_test_event_popup_choices 끝까지 실행")
	await _test_game_over_flow()
	_check(_completed.has("_test_game_over_flow"), "_test_game_over_flow 끝까지 실행")
	_test_world_state_and_war()
	_check(_completed.has("_test_world_state_and_war"), "_test_world_state_and_war 끝까지 실행")
	await _test_combat_effects()
	_check(_completed.has("_test_combat_effects"), "_test_combat_effects 끝까지 실행")
	await _test_ally_combat()
	_check(_completed.has("_test_ally_combat"), "_test_ally_combat 끝까지 실행")
	_test_event_progress_tracking()
	_check(_completed.has("_test_event_progress_tracking"), "_test_event_progress_tracking 끝까지 실행")
	_test_scenario_data()
	_check(_completed.has("_test_scenario_data"), "_test_scenario_data 끝까지 실행")
	_test_scenario_parameters()
	_check(_completed.has("_test_scenario_parameters"), "_test_scenario_parameters 끝까지 실행")
	_test_scenario_flow()
	_check(_completed.has("_test_scenario_flow"), "_test_scenario_flow 끝까지 실행")
	await _test_new_game_screen_scenarios()
	_check(_completed.has("_test_new_game_screen_scenarios"), "_test_new_game_screen_scenarios 끝까지 실행")
	_test_ending_data()
	_check(_completed.has("_test_ending_data"), "_test_ending_data 끝까지 실행")
	_test_every_ending_reachable()
	_check(_completed.has("_test_every_ending_reachable"), "_test_every_ending_reachable 끝까지 실행")
	await _test_final_ending_flow()
	_check(_completed.has("_test_final_ending_flow"), "_test_final_ending_flow 끝까지 실행")
	_test_war_rules()
	_check(_completed.has("_test_war_rules"), "_test_war_rules 끝까지 실행")
	_test_war_balance()
	_check(_completed.has("_test_war_balance"), "_test_war_balance 끝까지 실행")
	await _test_war_flow()
	_check(_completed.has("_test_war_flow"), "_test_war_flow 끝까지 실행")
	_test_economy_rules()
	_check(_completed.has("_test_economy_rules"), "_test_economy_rules 끝까지 실행")
	await _test_economy_flow()
	_check(_completed.has("_test_economy_flow"), "_test_economy_flow 끝까지 실행")

	print("스모크 테스트: %d개 검사, %d개 실패" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


func _test_scenes_load() -> void:
	for path in MAIN_SCENES:
		var scene: PackedScene = load(path)
		_check(scene != null and scene.can_instantiate(), "씬 로드: %s" % path)
	_completed["_test_scenes_load"] = true


func _test_level_curve() -> void:
	_check(CharacterData.get_experience_for_level(1) == 0, "Lv.1 요구 경험치 0")
	_check(CharacterData.get_experience_for_level(2) == 50, "Lv.2 요구 경험치 50")
	_check(CharacterData.get_experience_for_level(5) == 500, "Lv.5 요구 경험치 500")
	_completed["_test_level_curve"] = true


func _test_gain_experience() -> void:
	var character := CharacterData.new()
	var base_strength: int = character.strength
	var base_internal: int = character.internal_energy_max
	var signal_levels: Array[int] = []
	character.leveled_up.connect(func(new_level: int) -> void: signal_levels.append(new_level))

	_check(character.gain_experience(49) == 0 and character.level == 1, "경험치 49: 레벨 유지")
	_check(character.gain_experience(1) == 1 and character.level == 2, "경험치 50: Lv.2 도달")
	_check(character.gain_experience(450) == 3 and character.level == 5, "누적 500: Lv.5 도달 (한 번에 여러 레벨)")
	_check(signal_levels == [2, 3, 4, 5], "leveled_up 시그널이 레벨마다 발생")
	_check(
		character.strength == base_strength + 4 * _Balance.LEVEL_UP_STAT_GAIN,
		"레벨업 능력치 보너스 적용"
	)
	_check(
		character.internal_energy_max == base_internal + 4 * _Balance.LEVEL_UP_INTERNAL_GAIN,
		"레벨업 내공 보너스 적용"
	)
	_check(character.gain_experience(0) == 0 and character.gain_experience(-5) == 0, "0/음수 경험치 무시")

	character.gain_experience(1_000_000)
	_check(character.level == _Balance.MAX_LEVEL, "최대 레벨 제한")
	_completed["_test_gain_experience"] = true


func _test_martial_art_round_trip() -> void:
	var character := CharacterData.new()
	character.display_name = "테스트"
	var preset: MartialArtData = load("res://resources/MartialArts/soul_chase_sword.tres")
	character.learn_martial_art(preset)
	var custom := MartialArtData.new()
	custom.id = "custom_heal"
	custom.display_name = "대지생명장"
	custom.category = MartialArtData.Category.PALM
	custom.element = MartialArtData.FiveElement.EARTH
	custom.special_effects.append(MartialArtData.SpecialEffect.HEAL)
	custom.heal_amount = 21
	custom.damage = 0
	character.learn_martial_art(custom)

	# JSON 문자열을 거쳐 실제 세이브 파일과 같은 경로로 검증
	var json_text: String = JSON.stringify(_SaveManager.serialize_character(character))
	var restored: CharacterData = _SaveManager.deserialize_character(JSON.parse_string(json_text))

	_check(restored.martial_arts.size() == 2, "세이브/로드 후 무공 2개 유지")
	if restored.martial_arts.size() != 2:
		return
	var a: MartialArtData = restored.martial_arts[0]
	_check(
		a.id == preset.id and a.display_name == preset.display_name
		and a.element == preset.element and a.damage == preset.damage
		and a.move_bonus == preset.move_bonus and a.internal_cost == preset.internal_cost,
		"프리셋 무공 필드 복원"
	)
	_check(a.special_effects == preset.special_effects, "특수효과 배열 복원")
	var b: MartialArtData = restored.martial_arts[1]
	_check(
		b.category == MartialArtData.Category.PALM and b.heal_amount == 21
		and b.special_effects == [MartialArtData.SpecialEffect.HEAL],
		"창조 무공 필드 복원"
	)
	_check(restored.knows_martial_art("custom_heal"), "복원된 무공 조회")
	_completed["_test_martial_art_round_trip"] = true


func _test_old_save_without_martial_arts() -> void:
	var restored: CharacterData = _SaveManager.deserialize_character({"display_name": "구버전"})
	_check(restored.martial_arts.is_empty(), "구버전 세이브(무공 필드 없음) 호환")
	_completed["_test_old_save_without_martial_arts"] = true


func _test_turn_loop() -> void:
	var game_manager: Node = root.get_node_or_null("GameManager")
	_check(game_manager != null, "GameManager 오토로드 존재")
	if game_manager == null or game_manager.player_character == null:
		_check(false, "GameManager 초기화 완료")
		return
	var start_level: int = game_manager.player_character.level
	for i in 8:
		game_manager.advance_turn()
		if not game_manager.pending_event.is_empty():
			game_manager.resolve_pending_event(0)
	_check(game_manager.current_year == 3, "8턴 진행 후 3년차")
	_check(game_manager.player_character.level > start_level, "연간 수련으로 레벨 상승")
	_completed["_test_turn_loop"] = true


func _test_starting_roles() -> void:
	for entry in StartingRoles.ROLES:
		var character: CharacterData = StartingRoles.create_character(entry["id"], "")
		_check(
			character.role == entry["role"]
			and character.display_name == entry["default_name"]
			and character.internal_energy_current == character.internal_energy_max,
			"시작 역할 생성: %s" % entry["title"]
		)
	var named: CharacterData = StartingRoles.create_character("wanderer", "  연남천 ")
	_check(named.display_name == "연남천", "입력한 이름 사용 (앞뒤 공백 제거)")
	var unknown: CharacterData = StartingRoles.create_character("no_such_role", "")
	_check(unknown.role == CharacterData.Role.YOUNG_DISCIPLE, "알 수 없는 역할 id는 기본 역할")
	var leader: CharacterData = StartingRoles.create_character("leader", "")
	_check(leader.level > 1, "문주는 경험치를 갖고 시작")
	_completed["_test_starting_roles"] = true


func _test_start_new_game() -> void:
	var game_manager: Node = root.get_node_or_null("GameManager")
	if game_manager == null:
		return
	game_manager.story_flags["dirty"] = true
	game_manager.start_new_game("백리운", "leader")
	_check(game_manager.is_game_active, "새 게임 시작 후 진행 중 상태")
	_check(game_manager.player_character.display_name == "백리운", "새 게임 이름 적용")
	_check(game_manager.player_character.role == CharacterData.Role.LEADER, "새 게임 역할 적용")
	_check(game_manager.player_sect.leader_name == "백리운", "문주 시작 시 문파 문주 이름 갱신")
	_check(game_manager.player_sect.gold == 400, "역할별 문파 초기 자원 적용")
	_check(
		game_manager.current_year == 1 and game_manager.current_season_index == 0
		and game_manager.story_flags.is_empty() and game_manager.triggered_event_ids.is_empty(),
		"새 게임이 이전 진행 상태를 초기화"
	)
	_completed["_test_start_new_game"] = true


## 각 화면을 실제로 띄워 @onready 노드 경로와 시그널 연결이 깨지지 않았는지 확인한다.
func _test_scene_navigation() -> void:
	for path in [
		SceneRouter.MAIN_MENU, SceneRouter.NEW_GAME, SceneRouter.HUB,
		SceneRouter.MARTIAL_ART, SceneRouter.SECT_WAR, SceneRouter.ENDING,
		SceneRouter.HELP, SceneRouter.WORLD, SceneRouter.COMBAT,
	]:
		SceneRouter.goto(self, path)
		await process_frame
		await process_frame
		_check(
			current_scene != null and current_scene.scene_file_path == path,
			"화면 전환: %s" % path.get_file()
		)

	SceneRouter.goto(self, SceneRouter.HUB)
	await process_frame
	SceneRouter.goto(self, SceneRouter.HELP)
	await process_frame
	SceneRouter.back(self, SceneRouter.MAIN_MENU)
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.HUB, "도움말에서 직전 화면(경영)으로 복귀")
	_completed["_test_scene_navigation"] = true


func _make_combat_state() -> Dictionary:
	var character := CharacterData.new()
	character.internal_energy_max = 100
	character.restore_internal_energy()
	var sect := SectData.new()
	var relationships: Array[RelationshipData] = RelationshipManager.create_default_relationships()
	return {"character": character, "sect": sect, "relationships": relationships, "flags": {}}


func _apply(setup: CombatSetup, outcome: CombatManager.Outcome, st: Dictionary) -> Dictionary:
	return CombatManager.apply_outcome(
		setup, outcome, st["character"], st["sect"], st["relationships"], st["flags"]
	)


func _test_combat_outcomes() -> void:
	# 비무 승리: 경험치와 라이벌 유대
	var st: Dictionary = _make_combat_state()
	var rival_bond: RelationshipData = RelationshipManager.get_bond_with(st["relationships"], "npc_rival")
	var bond_before: int = rival_bond.bond_strength
	var spar: CombatSetup = CombatManager.create_sparring(st["character"])
	var result: Dictionary = _apply(spar, CombatManager.Outcome.VICTORY, st)
	_check(
		result["success"] and st["character"].experience == _Balance.SPAR_EXP
		and rival_bond.bond_strength == bond_before + 5,
		"비무 승리: 경험치와 라이벌 유대 상승"
	)

	# 결투 패배: 명성 감소, 부상, 유대 감소
	st = _make_combat_state()
	rival_bond = RelationshipManager.get_bond_with(st["relationships"], "npc_rival")
	bond_before = rival_bond.bond_strength
	var rep_before: int = st["sect"].reputation
	var duel: CombatSetup = CombatManager.create_rival_duel(st["character"])
	result = _apply(duel, CombatManager.Outcome.DEFEAT, st)
	_check(
		not result["success"] and st["sect"].reputation == rep_before - 5
		and st["character"].internal_energy_current == 30
		and rival_bond.bond_strength == bond_before - 5,
		"결투 패배: 명성 -5, 내공 30%로 감소, 유대 -5"
	)
	_check(not st["flags"].has("won_rival_duel"), "패배 시 승리 플래그 없음")

	st = _make_combat_state()
	_apply(CombatManager.create_rival_duel(st["character"]), CombatManager.Outcome.VICTORY, st)
	_check(st["flags"].get("won_rival_duel", false), "결투 승리 시 스토리 플래그 설정")

	# 도적 전투 후퇴: 손실 절반, 부상 완화
	st = _make_combat_state()
	var gold_before: int = st["sect"].gold
	var bandits: CombatSetup = CombatManager.create_night_bandits(st["character"])
	result = _apply(bandits, CombatManager.Outcome.RETREAT, st)
	_check(
		st["sect"].gold == gold_before - 20 and st["character"].internal_energy_current == 65,
		"후퇴: 금화 손실 절반, 내공 65%"
	)

	# 금화가 모자라도 음수가 되지 않는다
	st = _make_combat_state()
	st["sect"].gold = 10
	_apply(bandits, CombatManager.Outcome.DEFEAT, st)
	_check(st["sect"].gold == 0, "패배 손실이 보유 금화를 넘지 않음")
	_completed["_test_combat_outcomes"] = true


func _test_combat_events() -> void:
	var st: Dictionary = _make_combat_state()
	var result: Dictionary = EventManager.resolve_choice(
		"night_bandits", 0, st["character"], st["sect"], st["relationships"], st["flags"]
	)
	var setup: CombatSetup = result.get("combat")
	_check(
		setup != null and setup.enemies.size() == 3 + setup.allies.size(),
		"야습 도적: 싸우기 선택 시 도적 3명 + 합류 제자 수만큼 전투 예약"
	)
	result = EventManager.resolve_choice(
		"night_bandits", 1, st["character"], st["sect"], st["relationships"], st["flags"]
	)
	_check(not result.has("combat"), "야습 도적: 피하기 선택 시 전투 없음")
	result = EventManager.resolve_choice(
		"rival_duel", 0, st["character"], st["sect"], st["relationships"], st["flags"]
	)
	_check(result.has("combat") and result["combat"].id == "rival_duel", "라이벌의 도전: 결투 예약")
	_completed["_test_combat_events"] = true


func _test_combat_flow() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.start_new_game("시험", "young_disciple")

	# 비무: 계절당 한 번
	_check(gm.can_spar(), "새 게임에서 비무 가능")
	var spar_result: Dictionary = gm.start_sparring()
	await process_frame
	await process_frame
	_check(
		spar_result["success"] and current_scene.scene_file_path == SceneRouter.COMBAT,
		"비무 시작 시 전투 화면으로 이동"
	)
	_check(not gm.start_sparring()["success"], "같은 계절 두 번째 비무 거부")

	# 적을 모두 쓰러뜨리면 승리 처리
	var controller: Node = current_scene
	var exp_before: int = gm.player_character.experience
	for unit in controller._get_alive_enemies():
		unit.take_damage(99999)
	controller._check_victory()
	_check(gm.pending_combat == null, "승리 후 예약 전투 해제")
	_check(gm.player_character.experience == exp_before + _Balance.SPAR_EXP, "비무 승리 경험치 반영")

	# 도적 전투: 적 3명, 배율 적용, 적 AI 공격, 후퇴
	gm.start_combat(CombatManager.create_night_bandits(gm.player_character))
	await process_frame
	await process_frame
	controller = current_scene
	var enemies: Array = controller._get_alive_enemies()
	_check(enemies.size() == 3, "도적 전투: 적 3명 배치")
	var full_hp: int = CombatUnit.new(enemies[0].character).max_hp
	_check(enemies[0].max_hp == int(full_hp * gm.pending_combat.enemy_hp_scale), "도적 체력 배율 적용")

	var player: CombatUnit = controller._get_player()
	var attacker: CombatUnit = enemies[0]
	player.grid_pos = attacker.grid_pos + Vector2i(-1, 0)
	var hp_before: int = player.hp
	controller._run_enemy_ai(attacker)
	_check(player.hp < hp_before, "인접한 적이 플레이어를 공격")

	var gold_before: int = gm.player_sect.gold
	controller._on_back_pressed()
	await process_frame
	await process_frame
	_check(gm.player_sect.gold == gold_before - 20, "전투 중 후퇴: 손실 절반 반영")
	_check(current_scene.scene_file_path == SceneRouter.HUB, "후퇴 후 경영 화면으로 복귀")

	# 기연 선택지에서 전투로 이어지는 흐름
	gm.pending_event = {"id": "rival_duel"}
	gm.resolve_pending_event(0)
	await process_frame
	await process_frame
	_check(
		current_scene.scene_file_path == SceneRouter.COMBAT
		and gm.pending_combat != null and gm.pending_combat.id == "rival_duel",
		"기연 선택으로 결투 시작"
	)
	_completed["_test_combat_flow"] = true


func _test_event_definitions() -> void:
	var json_count: int = 0
	for file_name in DirAccess.get_files_at(EventManager.EVENTS_DIR):
		if file_name.ends_with(".json"):
			json_count += 1
	var definitions: Array[EventData] = EventManager.get_definitions()
	_check(json_count > 0 and definitions.size() == json_count, "기연 JSON %d개 모두 검증 통과" % json_count)
	for id in [
		"master_trial", "night_bandits", "sect_fellowship", "ancient_manual", "spy_recruitment",
		"spy_mission", "assassin_contract", "leader_council", "rival_duel",
	]:
		_check(EventManager.get_event(id) != null, "기연 존재: %s" % id)
	_completed["_test_event_definitions"] = true


func _test_event_validation() -> void:
	var good: Dictionary = {
		"id": "t", "title": "제목", "description": "설명",
		"conditions": [{"type": "season", "in": ["봄"]}],
		"choices": [{"label": "확인", "message": "", "effects": []}],
	}
	_check(EventManager.validate_event_dict(good).is_empty(), "정상 기연 정의 통과")

	var bad_cases: Dictionary = {
		"빈 선택지": {"choices": []},
		"알 수 없는 조건": {"conditions": [{"type": "weather"}]},
		"알 수 없는 캐릭터 필드": {"conditions": [{"type": "character", "field": "luck", "op": ">=", "value": 1}]},
		"잘못된 연산자": {"conditions": [{"type": "sect", "field": "gold", "op": "=>", "value": 1}]},
		"알 수 없는 역할": {"conditions": [{"type": "role", "in": ["NINJA"]}]},
		"알 수 없는 효과": {"choices": [{"label": "a", "effects": [{"type": "teleport"}]}]},
		"알 수 없는 전투": {"choices": [{"label": "a", "effects": [{"type": "combat", "combat": "dragon"}]}]},
		"chance 없는 분기": {"choices": [{"label": "a", "effects": [], "branches": [{"effects": []}]}]},
	}
	for label in bad_cases:
		var data: Dictionary = good.duplicate(true)
		data.merge(bad_cases[label], true)
		_check(not EventManager.validate_event_dict(data).is_empty(), "잘못된 정의 검출: %s" % label)
	_completed["_test_event_validation"] = true


func _test_event_conditions() -> void:
	var st: Dictionary = _make_combat_state()
	var character: CharacterData = st["character"]
	var council: EventData = EventManager.get_event("leader_council")
	character.role = CharacterData.Role.LEADER
	_check(
		EventManager._conditions_met(council, character, st["sect"], st["relationships"], "여름", st["flags"]),
		"문파 회의: 여름 + 문주면 발생"
	)
	_check(
		not EventManager._conditions_met(council, character, st["sect"], st["relationships"], "가을", st["flags"]),
		"문파 회의: 가을에는 발생하지 않음"
	)
	character.role = CharacterData.Role.SPY
	_check(
		not EventManager._conditions_met(council, character, st["sect"], st["relationships"], "여름", st["flags"]),
		"문파 회의: 문주가 아니면 발생하지 않음"
	)

	# 반복 불가 기연은 한 번 발생하면 다시 나오지 않는다
	var triggered: Array[String] = []
	for i in 30:
		var event: Dictionary = EventManager.check_turn_events(
			character, st["sect"], st["relationships"], "가을", triggered, st["flags"]
		)
		if event.is_empty():
			break
	var unique: Dictionary = {}
	for id in triggered:
		unique[id] = true
	_check(unique.size() == triggered.size(), "반복 불가 기연은 중복 발생하지 않음")
	_completed["_test_event_conditions"] = true


func _test_event_branches() -> void:
	var seen_exposed: bool = false
	var seen_success: bool = false
	var exposed_clean: bool = true
	for sd in 60:
		var st: Dictionary = _make_combat_state()
		seed(sd)
		EventManager.resolve_choice("spy_mission", 0, st["character"], st["sect"], st["relationships"], st["flags"])
		if st["flags"].get("spy_exposed", false):
			seen_exposed = true
			exposed_clean = exposed_clean and not st["flags"].has("spy_mission_complete")
		elif st["flags"].get("spy_mission_complete", false):
			seen_success = true
	_check(seen_exposed and seen_success, "확률 분기: 노출·성공 결과가 모두 나옴")
	_check(exposed_clean, "정체 노출 분기는 기본 효과를 적용하지 않음")
	randomize()

	var st2: Dictionary = _make_combat_state()
	var result: Dictionary = EventManager.resolve_choice(
		"master_trial", 5, st2["character"], st2["sect"], st2["relationships"], st2["flags"]
	)
	_check(not result["success"], "범위 밖 선택지는 실패 처리")
	_completed["_test_event_branches"] = true


func _test_event_mod_folder() -> void:
	var dir_path: String = "user://_test_events"
	DirAccess.make_dir_recursive_absolute(dir_path)
	var mod_event: Dictionary = {
		"id": "mod_three_choices", "title": "갈림길", "description": "세 갈래 길",
		"conditions": [],
		"choices": [
			{"label": "왼쪽", "message": "금화 +5", "effects": [{"type": "sect", "field": "gold", "add": 5}]},
			{"label": "가운데", "message": "", "effects": []},
			{"label": "오른쪽", "message": "", "effects": [{"type": "flag", "flag": "went_right"}]},
		],
	}
	var file := FileAccess.open(dir_path.path_join("mod.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(mod_event))
	file.close()
	# 깨진 JSON은 건너뛰어야 한다. (이 검사 중 출력되는 JSON 파싱 ERROR는 의도된 것)
	var broken := FileAccess.open(dir_path.path_join("broken.json"), FileAccess.WRITE)
	broken.store_string("{ 잘못된 json")
	broken.close()

	EventManager.reload_definitions(dir_path)
	_check(EventManager.get_definitions().size() == 1, "모드 폴더: 정상 파일만 로드")
	var st: Dictionary = _make_combat_state()
	var gold_before: int = st["sect"].gold
	EventManager.resolve_choice("mod_three_choices", 0, st["character"], st["sect"], st["relationships"], st["flags"])
	EventManager.resolve_choice("mod_three_choices", 2, st["character"], st["sect"], st["relationships"], st["flags"])
	_check(st["sect"].gold == gold_before + 5 and st["flags"].get("went_right", false), "모드 기연 효과 적용")

	DirAccess.remove_absolute(dir_path.path_join("mod.json"))
	DirAccess.remove_absolute(dir_path.path_join("broken.json"))
	DirAccess.remove_absolute(dir_path)
	EventManager.reload_definitions()
	_completed["_test_event_mod_folder"] = true


func _test_event_popup_choices() -> void:
	SceneRouter.goto(self, SceneRouter.HUB)
	await process_frame
	await process_frame
	var popup: Node = current_scene.get_node("%EventPopup")
	popup.show_event({"title": "갈림길", "description": "", "choices": PackedStringArray(["가", "나", "다"])})
	await process_frame
	var buttons: Array = popup.get_node("%ChoiceBox").get_children().filter(
		func(n: Node) -> bool: return n is Button and not n.is_queued_for_deletion()
	)
	_check(buttons.size() == 3 and popup.visible, "기연 팝업: 선택지 3개 버튼 생성")
	_completed["_test_event_popup_choices"] = true


func _test_upkeep() -> void:
	var sect := SectData.new()
	sect.disciple_count = 10
	sect.library_level = 2
	sect.treasury_level = 3
	_check(sect.get_food_upkeep() == 10 * _Balance.FOOD_PER_DISCIPLE, "식량 유지비 = 제자 수 × 단가")
	_check(
		sect.get_gold_upkeep() == 10 * _Balance.GOLD_PER_DISCIPLE + 3 * _Balance.FACILITY_UPKEEP_GOLD,
		"금화 유지비 = 제자 + 시설 단계"
	)

	# 정상 납부: 차감, 연속 부족 초기화
	sect.food = 100
	sect.gold = 100
	sect.shortage_seasons = 2
	var result: Dictionary = SectManager.pay_upkeep(sect)
	_check(
		not result["shortage"] and sect.food == 80 and sect.gold == 100 - sect.get_gold_upkeep()
		and sect.shortage_seasons == 0,
		"유지비 정상 납부"
	)

	# 식량 부족: 식량 0, 부족분에 비례한 제자 이탈
	sect.food = 2  # 유지비 20 → 18 부족 → 18/6 = 3명 이탈
	sect.gold = 100
	result = SectManager.pay_upkeep(sect)
	_check(
		result["shortage"] and sect.food == 0 and result["deserted"] == 3 and sect.disciple_count == 7
		and sect.shortage_seasons == 1,
		"식량 부족: 제자 3명 이탈, 연속 부족 1"
	)

	# 금화 부족: 금화 0, 명성 하락
	sect.food = 1000
	sect.gold = 0
	var rep_before: int = sect.reputation
	result = SectManager.pay_upkeep(sect)
	_check(
		result["shortage"] and sect.gold == 0
		and sect.reputation == rep_before - _Balance.GOLD_SHORTAGE_REPUTATION_LOSS
		and sect.shortage_seasons == 2,
		"금화 부족: 명성 하락, 연속 부족 2"
	)

	# 저장/불러오기에 연속 부족 계절 유지
	var restored: SectData = _SaveManager.deserialize_sect(
		JSON.parse_string(JSON.stringify(_SaveManager.serialize_sect(sect)))
	)
	_check(restored.shortage_seasons == 2, "연속 부족 계절 저장/복원")
	_completed["_test_upkeep"] = true


func _test_game_over_conditions() -> void:
	var sect := SectData.new()
	_check(EndingManager.check_game_over(sect).is_empty(), "기본 문파는 게임오버 아님")
	sect.disciple_count = 0
	_check(EndingManager.check_game_over(sect) == "sect_disbanded", "제자 0명: 문파 해산")
	sect = SectData.new()
	sect.shortage_seasons = _Balance.SHORTAGE_GAME_OVER_SEASONS
	_check(EndingManager.check_game_over(sect) == "famine_collapse", "연속 부족: 곳간이 비다")
	sect = SectData.new()
	sect.reputation = 0
	_check(EndingManager.check_game_over(sect) == "disgraced", "명성 0: 명성 실추")
	_completed["_test_game_over_conditions"] = true


func _test_game_over_flow() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.start_new_game("궁핍", "young_disciple")
	SceneRouter.goto(self, SceneRouter.HUB)
	await process_frame
	await process_frame

	# 이미 2계절 연속 부족인 상태에서 식량이 바닥난 채 여름을 맞는다
	# (여름 식량 수입 ~35 < 제자 30명 유지비 60 → 세 번째 부족)
	var signalled: Array[String] = []
	var on_over := func(id: String) -> void: signalled.append(id)
	var bus: Node = root.get_node("EventBus")
	bus.game_over.connect(on_over)
	gm.player_sect.disciple_count = 30
	gm.player_sect.max_disciples = 30
	gm.player_sect.food = 0
	gm.player_sect.shortage_seasons = _Balance.SHORTAGE_GAME_OVER_SEASONS - 1
	_check(not gm.is_game_over(), "부족 2계절까지는 진행 중")
	gm.advance_turn()
	bus.game_over.disconnect(on_over)

	_check(gm.is_game_over() and gm.game_over_id == "famine_collapse", "3계절 연속 부족 시 게임오버")
	_check(signalled == ["famine_collapse"], "game_over 시그널 1회 발생")
	_check(not gm.is_game_active, "게임오버 후 진행 중 상태 해제")
	_check(gm.last_turn_report.contains("유지비"), "계절 보고에 유지비 표시")

	var year: int = gm.current_year
	var season: int = gm.current_season_index
	gm.advance_turn()
	_check(gm.current_year == year and gm.current_season_index == season, "게임오버 후 계절 진행 불가")
	_check(not gm.start_legacy_succession()["success"], "게임오버 후 세대 전승 불가")

	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.ENDING, "게임오버 시 엔딩 화면으로 이동")
	_check(
		not current_scene.get_node("%SuccessionButton").visible
		and current_scene.get_node("%BackButton").text == "메인 메뉴로",
		"게임오버 화면: 전승 버튼 숨김, 메인 메뉴로 이동"
	)

	# 경영 화면으로 돌아가려 해도 엔딩 화면으로 되돌린다
	SceneRouter.goto(self, SceneRouter.HUB)
	await process_frame
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.ENDING, "게임오버 상태에서 경영 화면 진입 차단")

	# 세이브에도 게임오버가 남는다
	gm._apply_save_data(JSON.parse_string(JSON.stringify({
		"game_over_id": gm.game_over_id,
		"character": _SaveManager.serialize_character(gm.player_character),
		"sect": _SaveManager.serialize_sect(gm.player_sect),
	})))
	_check(gm.game_over_id == "famine_collapse", "게임오버 상태 저장/복원")

	gm.start_new_game("재시작", "young_disciple")
	_check(not gm.is_game_over() and gm.is_game_active, "새 게임으로 게임오버 해제")
	_completed["_test_game_over_flow"] = true


func _count_json(dir_path: String) -> int:
	var count: int = 0
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".json"):
			count += 1
	return count


func _test_npc_roster() -> void:
	var npcs: Array[Dictionary] = NpcRoster.get_all()
	_check(
		npcs.size() > 0 and npcs.size() == _count_json(NpcRoster.NPC_DIR),
		"NPC JSON %d개 모두 검증 통과" % npcs.size()
	)
	var bad_sect_refs: PackedStringArray = []
	for npc in npcs:
		if not SectRegistry.has_sect(npc["sect_id"]):
			bad_sect_refs.append(npc["id"])
	_check(bad_sect_refs.is_empty(), "모든 NPC의 소속 문파가 존재 %s" % bad_sect_refs)

	# 라이벌은 플레이어 레벨에 맞춰 성장한다 (기존 하드코딩 값과 동일)
	var player := CharacterData.new()
	var rival: CharacterData = NpcRoster.create_character("npc_rival", player)
	_check(rival.level == 2 and rival.strength == 14 and rival.internal_energy_max == 100, "라이벌 기본 능력치")
	player.level = 5
	rival = NpcRoster.create_character("npc_rival", player)
	_check(
		rival.level == 5 and rival.strength == 17 and rival.agility == 16
		and rival.internal_energy_max == 130 and rival.internal_energy_current == 130,
		"라이벌 레벨 5 성장"
	)
	var bandit: CharacterData = NpcRoster.create_character("npc_bandit", player)
	_check(bandit.level == 4 and bandit.strength == 11 and bandit.wisdom == 5, "도적은 플레이어보다 1레벨 낮게")
	var master: CharacterData = NpcRoster.create_character("npc_master")
	_check(master.display_name == "청운검선" and master.role == CharacterData.Role.LEADER, "스승 데이터 로드")

	var relationships: Array[RelationshipData] = RelationshipManager.create_default_relationships()
	var master_bond: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_master")
	var rival_bond: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_rival")
	_check(
		relationships.size() == 2 and master_bond.bond_strength == 35 and master_bond.stage == 1
		and rival_bond.bond_type == RelationshipData.BondType.RIVALRY and rival_bond.bond_strength == 15,
		"명부의 initial_bond로 시작 관계 생성"
	)

	_check(not NpcRoster.validate_npc_dict({"id": "x", "display_name": "x", "sect_id": "s", "role": "KING"}).is_empty(), "잘못된 NPC 역할 검출")
	_check(
		not NpcRoster.validate_npc_dict({
			"id": "x", "display_name": "x", "sect_id": "s", "role": "LEADER", "stats": {"luck": 3},
		}).is_empty(),
		"잘못된 NPC 능력치 검출"
	)
	_completed["_test_npc_roster"] = true


func _test_sect_registry() -> void:
	var player_sect: SectData = SectRegistry.create_player_sect()
	_check(player_sect.id == "qingyun" and player_sect.sect_name == "청운검파" and player_sect.gold == 500, "플레이어 문파 데이터 로드")
	_check(player_sect.leader_name == "청운검선", "문주 이름을 명부에서 가져옴")
	var rivals: Array[SectData] = SectRegistry.create_rival_sects()
	_check(rivals.size() == _count_json(SectRegistry.SECT_DIR) - 1, "플레이어 문파 외 세력 %d개 생성" % rivals.size())
	var alignments: Dictionary = {}
	for sect in rivals:
		alignments[sect.alignment] = true
		_check(NpcRoster.has_npc(sect.leader_id), "%s 문주가 명부에 있음" % sect.sect_name)
	_check(alignments.size() == 3, "정파·사파·마교 세력이 모두 존재")
	_check(
		not SectRegistry.validate_sect_dict({"id": "x", "sect_name": "x", "alignment": "RIGHTEOUS", "leader_id": "nobody"}).is_empty(),
		"없는 문주를 가리키는 문파 검출"
	)
	_check(
		not SectRegistry.validate_sect_dict({
			"id": "x", "sect_name": "x", "alignment": "NEUTRAL", "leader_id": "npc_master",
		}).is_empty(),
		"잘못된 성향 검출"
	)
	_completed["_test_sect_registry"] = true


func _test_world_sect_events() -> void:
	var st: Dictionary = _make_combat_state()
	var world: Array[SectData] = SectRegistry.create_rival_sects()
	EventManager.world_sects = world
	var heukpung: SectData = null
	for sect in world:
		if sect.id == "heukpung":
			heukpung = sect
	var toll: EventData = EventManager.get_event("heukpung_toll")
	_check(
		EventManager._conditions_met(toll, st["character"], st["sect"], st["relationships"], "봄", st["flags"]),
		"흑풍채 통행세: 적대적일 때 발생"
	)
	st["flags"]["subjugated_heukpung"] = true
	_check(
		not EventManager._conditions_met(toll, st["character"], st["sect"], st["relationships"], "봄", st["flags"]),
		"흑풍채 통행세: 굴복시킨 뒤에는 발생하지 않음"
	)
	var gold_before: int = st["sect"].gold
	var attitude_before: int = heukpung.attitude
	EventManager.resolve_choice("heukpung_toll", 0, st["character"], st["sect"], st["relationships"], st["flags"])
	_check(st["sect"].gold == gold_before - 50 and heukpung.attitude == attitude_before + 15, "통행세 납부: 금화 -50, 태도 +15")

	heukpung.attitude = 95
	EventManager.resolve_choice("heukpung_toll", 0, st["character"], st["sect"], st["relationships"], st["flags"])
	_check(heukpung.attitude == 100, "태도는 100을 넘지 않음")

	var bad: Dictionary = {
		"id": "t", "title": "t", "description": "t",
		"choices": [{"label": "a", "effects": [{"type": "world_sect", "sect": "qingyun", "field": "attitude", "add": 1}]}],
	}
	_check(not EventManager.validate_event_dict(bad).is_empty(), "플레이어 문파를 강호 세력으로 지정하면 오류")
	EventManager.world_sects = root.get_node("GameManager").world_sects
	_completed["_test_world_sect_events"] = true


func _test_world_state_and_war() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.start_new_game("정벌", "leader")
	_check(gm.player_sect.id == "qingyun" and gm.world_sects.size() == 3, "새 게임: 플레이어 문파와 강호 세력 3개")
	_check(gm.get_war_targets().size() == 3, "처음에는 세 세력 모두 공격 가능")

	# 강한 아군 대 약해진 흑풍채: 승리하면 굴복
	var heukpung: SectData = gm.get_world_sect("heukpung")
	heukpung.disciple_count = 6
	gm.player_sect.disciple_count = 30
	gm.player_sect.training_ground_level = 5
	var rep_before: int = gm.player_sect.reputation
	var commands: Array = [
		SectWarManager.Command.FLANK, SectWarManager.Command.DEFEND, SectWarManager.Command.FLANK,
	]
	var result: Dictionary = gm.resolve_sect_war("heukpung", commands)
	_check(result["victory"] and result["subjugated"] and heukpung.subjugated, "흑풍채 굴복")
	_check(gm.story_flags.get("subjugated_heukpung", false), "굴복 스토리 플래그 설정")
	_check(gm.player_sect.reputation > rep_before + _Balance.SUBJUGATE_REPUTATION_BONUS, "굴복 보너스 명성")
	_check(gm.get_war_targets().size() == 2, "굴복한 세력은 공격 대상에서 제외")
	_check(not gm.resolve_sect_war("namgung", commands)["success"], "문파전은 계절당 한 번")

	# 해가 바뀌면 굴복하지 않은 세력만 성장
	var namgung: SectData = gm.get_world_sect("namgung")
	var namgung_before: int = namgung.disciple_count
	var heukpung_before: int = heukpung.disciple_count
	for i in 4:
		gm.advance_turn()
		gm.pending_event.clear()
		gm.pending_combat = null
	_check(namgung.disciple_count == namgung_before + _Balance.WORLD_SECT_YEARLY_GROWTH, "강호 세력 연간 성장")
	_check(heukpung.disciple_count == heukpung_before, "굴복한 세력은 성장하지 않음")
	_check(gm.can_wage_war(), "다음 계절에는 다시 문파전 가능")

	# 저장/불러오기
	var state: Dictionary = JSON.parse_string(JSON.stringify({
		"character": _SaveManager.serialize_character(gm.player_character),
		"sect": _SaveManager.serialize_sect(gm.player_sect),
		"world_sects": _SaveManager.serialize_sects(gm.world_sects),
	}))
	gm._apply_save_data(state)
	var restored: SectData = gm.get_world_sect("heukpung")
	_check(
		gm.world_sects.size() == 3 and restored.subjugated and restored.alignment == SectData.Alignment.UNORTHODOX
		and restored.leader_id == "npc_heukpung_chief",
		"강호 세력 저장/복원"
	)
	_check(gm.player_sect.id == "qingyun", "플레이어 문파 id 저장/복원")
	state.erase("world_sects")
	gm._apply_save_data(state)
	_check(gm.world_sects.size() == 3 and not gm.get_world_sect("heukpung").subjugated, "구버전 세이브는 강호 세력 초기값 사용")
	_completed["_test_world_state_and_war"] = true


func _make_unit(strength: int = 10, player: bool = true) -> CombatUnit:
	var character := CharacterData.new()
	character.strength = strength
	return CombatUnit.new(character, player)


func _test_combat_rules() -> void:
	var T := CombatRules.Terrain
	_check(
		CombatRules.move_cost(T.PLAIN) == 1 and CombatRules.move_cost(T.FOREST) == _Balance.FOREST_MOVE_COST
		and CombatRules.move_cost(T.WATER) == _Balance.WATER_MOVE_COST,
		"지형별 이동 비용"
	)

	# 3×1 통로: (1,0)이 수풀이면 행동력 2로 (1,0)까지만, 3이면 (2,0)까지
	var terrain := {Vector2i(1, 0): T.FOREST}
	var passable := func(pos: Vector2i) -> bool: return pos.x >= 0 and pos.x < 3 and pos.y == 0
	var terrain_of := func(pos: Vector2i) -> int: return terrain.get(pos, T.PLAIN)
	var reach: Dictionary = CombatRules.reachable_tiles(Vector2i(0, 0), 2, passable, terrain_of)
	_check(reach.has(Vector2i(1, 0)) and not reach.has(Vector2i(2, 0)), "수풀은 이동 비용 2")
	reach = CombatRules.reachable_tiles(Vector2i(0, 0), 3, passable, terrain_of)
	_check(reach.get(Vector2i(2, 0)) == 3 and not reach.has(Vector2i(0, 0)), "도달 가능 칸과 비용")

	# 벽을 돌아가는 경로
	var wall: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)]
	var open := func(pos: Vector2i) -> bool:
		return pos.x >= 0 and pos.x < 5 and pos.y >= 0 and pos.y < 5 and not wall.has(pos)
	var plain := func(_pos: Vector2i) -> int: return T.PLAIN
	var path: Array[Vector2i] = CombatRules.find_path(
		Vector2i(0, 0), func(pos: Vector2i) -> bool: return pos == Vector2i(4, 0), open, plain
	)
	_check(path.size() == 10 and path[-1] == Vector2i(4, 0) and not path.any(func(p): return wall.has(p)), "벽을 돌아가는 최단 경로")
	var walk: Dictionary = CombatRules.walk_path(path, 4, plain)
	_check(walk["index"] == 3 and walk["cost"] == 4, "행동력만큼만 경로 이동")
	_check(
		CombatRules.find_path(Vector2i(0, 0), func(pos: Vector2i) -> bool: return pos == Vector2i(9, 9), open, plain).is_empty(),
		"도달할 수 없으면 빈 경로"
	)

	var E := MartialArtData.FiveElement
	_check(is_equal_approx(CombatRules.element_modifier(E.WOOD, E.EARTH), _Balance.ELEMENT_ADVANTAGE), "목극토: 우위")
	_check(is_equal_approx(CombatRules.element_modifier(E.EARTH, E.WOOD), _Balance.ELEMENT_DISADVANTAGE), "토는 목에 열세")
	_check(is_equal_approx(CombatRules.element_modifier(E.FIRE, E.NONE), 1.0), "무속성 상대는 보정 없음")

	# 피해 계산
	var attacker: CombatUnit = _make_unit(12)
	var defender: CombatUnit = _make_unit(10, false)
	var basic: int = CombatRules.calculate_damage(attacker, defender, null, T.PLAIN, T.PLAIN)["damage"]
	_check(basic == _Balance.BASE_ATTACK_DAMAGE + 12, "기본 공격 피해 = 기준 + 무력")
	_check(
		CombatRules.calculate_damage(attacker, defender, null, T.HIGH, T.PLAIN)["damage"] == int(basic * _Balance.HIGH_ATTACK),
		"고지 공격 보너스"
	)
	_check(
		CombatRules.calculate_damage(attacker, defender, null, T.PLAIN, T.FOREST)["damage"] == int(basic * _Balance.FOREST_DEFENSE),
		"수풀 엄폐"
	)
	attacker.add_status("empowered", 2)
	_check(
		CombatRules.calculate_damage(attacker, defender, null, T.PLAIN, T.PLAIN)["damage"] == int(basic * _Balance.EMPOWER_MULTIPLIER),
		"기세 상태 피해 증가"
	)
	attacker.tick_statuses()
	attacker.tick_statuses()
	_check(not attacker.has_status("empowered"), "상태는 턴이 지나면 사라짐")

	var ambush_art := MartialArtData.new()
	ambush_art.damage = 20
	ambush_art.special_effects.append(MartialArtData.SpecialEffect.AMBUSH)
	var first: int = CombatRules.calculate_damage(attacker, defender, ambush_art, T.PLAIN, T.PLAIN)["damage"]
	defender.take_damage(1)
	var second: int = CombatRules.calculate_damage(attacker, defender, ambush_art, T.PLAIN, T.PLAIN)["damage"]
	# 정수 변환 시점 차이로 1 이내 오차는 허용
	_check(absf(first - second * _Balance.AMBUSH_MULTIPLIER) <= 1.0, "기습은 다치지 않은 대상에게만 1.5배")

	var ranged := MartialArtData.new()
	ranged.range = 2
	var melee := MartialArtData.new()
	_check(
		CombatRules.get_art_range(ranged, T.HIGH) == 2 + _Balance.HIGH_RANGE_BONUS
		and CombatRules.get_art_range(melee, T.HIGH) == 1,
		"고지 사거리 보너스는 원거리 무공만"
	)

	# 내공 폭주: 내공이 넉넉하면 일어나지 않고, 바닥이면 확률적으로 일어난다
	var caster := CharacterData.new()
	caster.internal_energy_max = 100
	caster.internal_energy_current = 100
	var art := MartialArtData.new()
	art.internal_cost = 20
	var safe: bool = true
	for sd in 50:
		seed(sd)
		safe = safe and CombatRules.roll_overload(caster, art) == 0
	caster.internal_energy_current = 5
	var overloads: int = 0
	for sd in 100:
		seed(sd)
		if CombatRules.roll_overload(caster, art) == int(20 * _Balance.OVERLOAD_DAMAGE_PER_COST):
			overloads += 1
	randomize()
	_check(safe, "내공이 넉넉하면 폭주 없음")
	_check(overloads > 10 and overloads < 60, "내공 바닥일 때 폭주 확률 적용 (%d/100)" % overloads)
	_completed["_test_combat_rules"] = true


func _test_martial_art_library() -> void:
	_check(
		MartialArtLibrary.has_art("preset_soul_chase_sword") and MartialArtLibrary.has_art("preset_earth_life_palm")
		and MartialArtLibrary.has_art("mod_thunder_palm"),
		"무공 목록: 프리셋과 모드 무공"
	)
	var a: MartialArtData = MartialArtLibrary.create_art("preset_soul_chase_sword")
	a.damage = 999
	_check(MartialArtLibrary.create_art("preset_soul_chase_sword").damage != 999, "무공 목록은 복제본을 줌")

	var player := CharacterData.new()
	player.level = 2
	_check(NpcRoster.create_character("npc_rival", player).martial_arts.is_empty(), "라이벌은 레벨 2에서는 무공 없음")
	player.level = 3
	var rival: CharacterData = NpcRoster.create_character("npc_rival", player)
	_check(rival.knows_martial_art("preset_soul_chase_sword"), "라이벌은 레벨 3부터 유혼쾌영검 사용")
	_check(
		not NpcRoster.validate_npc_dict({
			"id": "x", "display_name": "x", "sect_id": "s", "role": "LEADER",
			"martial_arts": [{"id": "no_such_art"}],
		}).is_empty(),
		"없는 무공을 가진 NPC 검출"
	)
	_completed["_test_martial_art_library"] = true


## 전투 씬에서 무공 효과와 적 AI를 확인한다.
func _test_combat_effects() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.start_new_game("효과", "young_disciple")
	var setup := CombatSetup.new()
	setup.title = "시험장"
	setup.player_position = Vector2i(2, 5)
	setup.blocked_tiles = [Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6)]
	setup.set_terrain([Vector2i(3, 5)], CombatRules.Terrain.FOREST)
	var dummy: CharacterData = NpcRoster.create_character("npc_bandit")
	dummy.agility = 1  # 플레이어가 먼저 움직이도록
	setup.add_enemy(dummy, Vector2i(10, 5))
	gm.start_combat(setup)
	await process_frame
	await process_frame
	var c: Node = current_scene
	var player: CombatUnit = c._get_player()
	var enemy: CombatUnit = c._get_alive_enemies()[0]
	_check(c._turn_manager.get_current_unit() == player, "느린 적 상대로 플레이어 선공")

	# 다중 칸 이동: 수풀(2) + 평지(1) = 3
	var ap_before: int = player.action_points
	c._try_move(player, Vector2i(4, 5))
	_check(player.grid_pos == Vector2i(4, 5) and player.action_points == ap_before - 3, "수풀을 지나 두 칸 이동 (행동력 -3)")

	# 제어: 기절 → 적 차례 건너뜀
	var control := MartialArtData.new()
	control.display_name = "점혈수"
	control.range = 9
	control.damage = 1
	control.internal_cost = 1
	control.action_cost = 1
	control.special_effects.append(MartialArtData.SpecialEffect.CONTROL)
	player.character.internal_energy_current = player.character.internal_energy_max
	c._perform_art(player, enemy, control)
	_check(enemy.has_status("stunned"), "제어: 대상 기절")
	var enemy_pos: Vector2i = enemy.grid_pos
	c._on_end_turn_pressed()
	_check(enemy.grid_pos == enemy_pos and not enemy.has_status("stunned"), "기절한 적은 차례를 건너뜀")
	c._perform_art(player, enemy, control)
	_check(not enemy.has_status("stunned"), "막 풀려난 적은 기절 저항")

	# 파괴력: 밀어내기, 막히면 추가 피해
	var smash := MartialArtData.new()
	smash.display_name = "붕산권"
	smash.range = 9
	smash.damage = 5
	smash.internal_cost = 1
	smash.action_cost = 1
	smash.special_effects.append(MartialArtData.SpecialEffect.DESTRUCTION)
	player.grid_pos = Vector2i(9, 5)
	enemy.grid_pos = Vector2i(10, 5)
	player.action_points = 5
	c._perform_art(player, enemy, smash)
	_check(enemy.grid_pos == Vector2i(11, 5), "파괴력: 한 칸 밀려남")
	player.grid_pos = Vector2i(14, 5)
	enemy.grid_pos = Vector2i(15, 5)
	var hp_before: int = enemy.hp
	c._perform_art(player, enemy, smash)
	var expected: int = int(CombatRules.calculate_damage(player, enemy, smash, 0, 0)["damage"] * (1 + _Balance.KNOCKBACK_WALL_BONUS))
	_check(enemy.grid_pos == Vector2i(15, 5) and hp_before - enemy.hp == expected, "파괴력: 가장자리에 막히면 추가 피해")

	# 강화 + 회복
	var palm: MartialArtData = MartialArtLibrary.create_art("preset_earth_life_palm")
	player.take_damage(30)
	var hurt_hp: int = player.hp
	player.action_points = 5
	c._perform_art(player, null, palm)
	_check(player.hp > hurt_hp and player.has_status("empowered"), "대지생명장: 회복과 기세")

	# 적 AI: 벽 뒤에서 길을 찾아 다가온다
	player.grid_pos = Vector2i(4, 5)
	enemy.grid_pos = Vector2i(8, 5)
	enemy.statuses.clear()
	enemy.action_points = enemy.max_action_points
	# 벽을 돌아가느라 잠시 멀어질 수 있으므로 몇 차례 안에 붙는지 본다.
	var never_on_wall: bool = true
	for i in 6:
		enemy.action_points = enemy.max_action_points
		c._run_enemy_ai(enemy)
		never_on_wall = never_on_wall and not setup.blocked_tiles.has(enemy.grid_pos)
		if CombatRules.distance(enemy.grid_pos, player.grid_pos) == 1:
			break
	_check(
		CombatRules.distance(enemy.grid_pos, player.grid_pos) == 1 and never_on_wall,
		"적이 벽을 돌아 플레이어에게 접근"
	)
	c._on_back_pressed()
	await process_frame
	await process_frame

	# 레벨 3 라이벌은 무공을 쓴다
	gm.start_new_game("무공", "young_disciple")
	gm.player_character.gain_experience(CharacterData.get_experience_for_level(3))
	gm.start_combat(CombatManager.create_sparring(gm.player_character))
	await process_frame
	await process_frame
	c = current_scene
	player = c._get_player()
	var rival: CombatUnit = c._get_alive_enemies()[0]
	rival.grid_pos = player.grid_pos + Vector2i(1, 0)
	rival.action_points = rival.max_action_points
	var ie_before: int = rival.character.internal_energy_current
	c._run_enemy_ai(rival)
	_check(rival.character.internal_energy_current < ie_before, "라이벌 AI가 무공 사용")
	_check(c.art_list.get_child_count() == player.get_martial_arts().size(), "무공 버튼이 습득 무공 수만큼")
	c._on_back_pressed()
	await process_frame
	_completed["_test_combat_effects"] = true


func _test_ally_setup() -> void:
	var player := CharacterData.new()
	var sect := SectData.new()
	sect.training_ground_level = 3
	var setup: CombatSetup = CombatManager.create_night_bandits(player, sect)
	_check(setup.allies.size() == _Balance.DEFENSE_ALLY_COUNT and setup.allies_are_disciples, "방어전에 제자 2명 합류")
	var base: CharacterData = NpcRoster.create_character("npc_disciple", player)
	_check(setup.allies[0].strength == base.strength + 2 * _Balance.ALLY_TRAINING_STAT_BONUS, "무술장 레벨만큼 제자 강화")
	_check(setup.allies[0].display_name != setup.allies[1].display_name, "제자 이름 구분")

	sect.disciple_count = 1
	_check(CombatManager.create_night_bandits(player, sect).allies.size() == 1, "보유 제자 수만큼만 합류")
	var no_sect: CombatSetup = CombatManager.create_night_bandits(player)
	_check(no_sect.allies.is_empty() and not no_sect.allies_are_disciples, "문파 정보 없으면 아군 없음")
	_check(CombatManager.create_sparring(player).allies.is_empty(), "비무는 1대1")

	# 기연에서 시작한 방어전에도 제자가 합류한다
	var st: Dictionary = _make_combat_state()
	var result: Dictionary = EventManager.resolve_choice(
		"night_bandits", 0, st["character"], st["sect"], st["relationships"], st["flags"]
	)
	_check(result["combat"].allies.size() == _Balance.DEFENSE_ALLY_COUNT, "기연 야습 도적: 제자 합류")

	# 쓰러진 제자는 문파에서 빠진다
	st = _make_combat_state()
	var disciples_before: int = st["sect"].disciple_count
	var outcome: Dictionary = CombatManager.apply_outcome(
		setup, CombatManager.Outcome.VICTORY, st["character"], st["sect"], st["relationships"], st["flags"], 1
	)
	_check(
		st["sect"].disciple_count == disciples_before - 1 and outcome["message"].contains("제자 1명 전사"),
		"승리해도 쓰러진 제자 수만큼 문파 제자 감소"
	)
	_completed["_test_ally_setup"] = true


func _test_ally_combat() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.start_new_game("동료", "young_disciple")
	gm.player_character.learn_martial_art(MartialArtLibrary.create_art("preset_earth_life_palm"))
	var setup: CombatSetup = CombatManager.create_night_bandits(gm.player_character, gm.player_sect)
	gm.start_combat(setup)
	await process_frame
	await process_frame
	var c: Node = current_scene
	var friends: Array = c._get_alive_friendlies()
	_check(friends.size() == 3, "주인공과 제자 2명 배치")
	_check(
		c._turn_manager.turn_order.size() == friends.size() + c._get_alive_enemies().size(),
		"아군·적 모두 턴 순서에 포함"
	)

	# 아군 차례가 오면 그 유닛을 조종한다
	var ally: CombatUnit = null
	var guard: int = 10
	while guard > 0:
		guard -= 1
		var controlled: CombatUnit = c._get_controlled()
		if controlled and controlled.is_ally:
			ally = controlled
			break
		c._on_end_turn_pressed()
	_check(ally != null, "아군 차례에 아군을 조종")
	if ally:
		_check(c._art_buttons_owner == ally and c.art_list.get_child_count() == ally.get_martial_arts().size(), "무공 버튼이 조종 중인 유닛 기준")
		var ap_before: int = ally.action_points
		var target_tile: Vector2i = c._get_reachable(ally).keys()[0]
		c._try_move(ally, target_tile)
		_check(ally.grid_pos == target_tile and ally.action_points < ap_before, "아군 이동")

	# 적은 가장 가까운 아군을 노린다
	var player: CombatUnit = c._get_player()
	var bandit: CombatUnit = c._get_alive_enemies()[0]
	var disciple: CombatUnit = null
	for unit in c._get_alive_friendlies():
		if unit.is_ally:
			disciple = unit
	player.grid_pos = Vector2i(0, 0)
	disciple.grid_pos = Vector2i(10, 4)
	bandit.grid_pos = Vector2i(10, 5)
	bandit.action_points = bandit.max_action_points
	var disciple_hp: int = disciple.hp
	var player_hp: int = player.hp
	c._run_enemy_ai(bandit)
	_check(disciple.hp < disciple_hp and player.hp == player_hp, "적은 가장 가까운 아군을 공격")

	# 회복 무공으로 아군 치료
	player.grid_pos = disciple.grid_pos + Vector2i(0, -1)
	player.action_points = player.max_action_points
	player.character.restore_internal_energy()
	var hurt: int = disciple.hp
	c._perform_art(player, disciple, player.get_martial_arts()[0])
	_check(disciple.hp > hurt, "회복 무공으로 아군 치료")

	# 제자가 쓰러져도 전투는 계속되고, 승리 후 문파 제자가 준다
	disciple.take_damage(99999)
	c._after_hit(disciple)
	_check(not c._combat_over, "제자가 쓰러져도 전투 계속")
	var disciples_before: int = gm.player_sect.disciple_count
	for enemy in c._get_alive_enemies():
		enemy.take_damage(99999)
	c._check_victory()
	_check(c._combat_over and gm.player_sect.disciple_count == disciples_before - 1, "승리 후 전사한 제자 1명 반영")
	c._on_back_pressed()
	await process_frame
	_completed["_test_ally_combat"] = true


func _event_with(extra: Dictionary) -> Dictionary:
	var data: Dictionary = {
		"id": "t", "title": "t", "description": "t",
		"choices": [{"label": "a", "effects": []}],
	}
	data.merge(extra, true)
	return data


func _test_event_grammar_validation() -> void:
	var good_cases: Dictionary = {
		"year": {"conditions": [{"type": "year", "op": ">=", "value": 3}]},
		"turns_since_flag": {"conditions": [{"type": "turns_since_flag", "flag": "f", "op": ">=", "value": 4}]},
		"relationship_type": {"conditions": [{"type": "relationship_type", "target": "npc_rival", "bond_type": "RIVALRY"}]},
		"role_history": {"conditions": [{"type": "role_history", "role": "SPY", "value": false}]},
		"set_bond_type": {"choices": [{"label": "a", "effects": [{"type": "set_bond_type", "target": "npc_rival", "bond_type": "BLOOD_OATH"}]}]},
		"add_relationship": {"choices": [{"label": "a", "effects": [{"type": "add_relationship", "target": "npc_cheonma", "bond_type": "HATRED"}]}]},
		"learn_art": {"choices": [{"label": "a", "effects": [{"type": "learn_art", "art": "preset_earth_life_palm"}]}]},
		"end_game": {"choices": [{"label": "a", "effects": [{"type": "end_game", "ending": "famine_collapse"}]}]},
		"weight": {"weight": 2.5},
	}
	for label in good_cases:
		var errors: PackedStringArray = EventManager.validate_event_dict(_event_with(good_cases[label]))
		_check(errors.is_empty(), "새 문법 정상 통과: %s %s" % [label, errors])

	var bad_cases: Dictionary = {
		"year 연산자": {"conditions": [{"type": "year", "op": "~", "value": 3}]},
		"turns_since_flag 플래그 누락": {"conditions": [{"type": "turns_since_flag", "op": ">=", "value": 1}]},
		"잘못된 관계 유형": {"conditions": [{"type": "relationship_type", "target": "npc_rival", "bond_type": "FRIEND"}]},
		"잘못된 역할 기록": {"conditions": [{"type": "role_history", "role": "EMPEROR"}]},
		"명부에 없는 인물과 관계": {"choices": [{"label": "a", "effects": [{"type": "add_relationship", "target": "npc_nobody", "bond_type": "ROMANCE"}]}]},
		"없는 무공 습득": {"choices": [{"label": "a", "effects": [{"type": "learn_art", "art": "no_art"}]}]},
		"없는 엔딩": {"choices": [{"label": "a", "effects": [{"type": "end_game", "ending": "no_ending"}]}]},
		"음수 가중치": {"weight": -1},
	}
	for label in bad_cases:
		_check(not EventManager.validate_event_dict(_event_with(bad_cases[label])).is_empty(), "새 문법 오류 검출: %s" % label)
	_completed["_test_event_grammar_validation"] = true


func _condition_holds(condition: Dictionary, st: Dictionary) -> bool:
	var event := EventData.new()
	event.conditions.append(condition)
	return EventManager._conditions_met(event, st["character"], st["sect"], st["relationships"], "봄", st["flags"])


func _test_event_grammar_conditions() -> void:
	var saved_year: int = EventManager.current_year
	var saved_turn: int = EventManager.current_turn
	var saved_history: Array[String] = EventManager.role_history
	var saved_flag_turns: Dictionary = EventManager.flag_turns
	EventManager.flag_turns = {}
	var st: Dictionary = _make_combat_state()

	EventManager.current_year = 3
	_check(_condition_holds({"type": "year", "op": ">=", "value": 3}, st), "year: 3년차 조건 충족")
	_check(not _condition_holds({"type": "year", "op": ">=", "value": 4}, st), "year: 4년차 조건 불충족")

	var since: Dictionary = {"type": "turns_since_flag", "flag": "oath", "op": ">=", "value": 4}
	_check(not _condition_holds(since, st), "turns_since_flag: 켜진 적 없으면 거짓")
	EventManager.current_turn = 10
	EventManager.set_flag(st["flags"], "oath")
	EventManager.current_turn = 13
	_check(not _condition_holds(since, st), "turns_since_flag: 3계절 경과는 불충족")
	EventManager.current_turn = 14
	_check(_condition_holds(since, st), "turns_since_flag: 4계절 경과 충족")
	EventManager.set_flag(st["flags"], "oath", false)
	_check(not _condition_holds(since, st), "turns_since_flag: 꺼진 플래그는 거짓")

	_check(_condition_holds({"type": "relationship_type", "target": "npc_rival", "bond_type": "RIVALRY"}, st), "relationship_type: 라이벌 일치")
	_check(not _condition_holds({"type": "relationship_type", "target": "npc_rival", "bond_type": "BLOOD_OATH"}, st), "relationship_type: 불일치")
	_check(not _condition_holds({"type": "relationship_type", "target": "npc_cheonma", "bond_type": "HATRED"}, st), "relationship_type: 관계 없으면 거짓")

	EventManager.role_history = ["YOUNG_DISCIPLE", "SPY"] as Array[String]
	_check(_condition_holds({"type": "role_history", "role": "SPY"}, st), "role_history: 거쳐 온 역할")
	_check(not _condition_holds({"type": "role_history", "role": "LEADER"}, st), "role_history: 거치지 않은 역할")
	_check(_condition_holds({"type": "role_history", "role": "LEADER", "value": false}, st), "role_history: 거친 적 없음 조건")

	# 가중치: 1 대 9로 뽑히는지
	var light := EventData.new()
	light.id = "light"
	var heavy := EventData.new()
	heavy.id = "heavy"
	heavy.weight = 9.0
	var heavy_count: int = 0
	seed(7)
	for i in 1000:
		if EventManager._pick_weighted([light, heavy] as Array[EventData]) == heavy:
			heavy_count += 1
	randomize()
	_check(heavy_count > 850 and heavy_count < 950, "가중치 9배 기연이 약 90%% 선택 (%d/1000)" % heavy_count)

	EventManager.current_year = saved_year
	EventManager.current_turn = saved_turn
	EventManager.role_history = saved_history
	EventManager.flag_turns = saved_flag_turns
	_completed["_test_event_grammar_conditions"] = true


func _test_event_grammar_effects() -> void:
	var st: Dictionary = _make_combat_state()
	var result: Dictionary = {}
	var apply := func(effect: Dictionary) -> void:
		EventManager._apply_effect(effect, st["character"], st["sect"], st["relationships"], st["flags"], result)

	apply.call({"type": "set_bond_type", "target": "npc_rival", "bond_type": "BLOOD_OATH"})
	var rival: RelationshipData = RelationshipManager.get_bond_with(st["relationships"], "npc_rival")
	_check(rival.bond_type == RelationshipData.BondType.BLOOD_OATH, "set_bond_type: 라이벌 → 혈맹")

	apply.call({"type": "add_relationship", "target": "npc_cheonma_envoy", "bond_type": "HATRED", "strength": 25})
	var envoy: RelationshipData = RelationshipManager.get_bond_with(st["relationships"], "npc_cheonma_envoy")
	_check(
		envoy != null and envoy.target_name == "혈영" and envoy.bond_type == RelationshipData.BondType.HATRED
		and envoy.bond_strength == 25,
		"add_relationship: 명부 인물과 원한 관계 생성"
	)
	var count: int = st["relationships"].size()
	apply.call({"type": "add_relationship", "target": "npc_cheonma_envoy", "bond_type": "ROMANCE"})
	_check(st["relationships"].size() == count and envoy.bond_type == RelationshipData.BondType.HATRED, "add_relationship: 이미 있으면 무시")

	apply.call({"type": "learn_art", "art": "preset_earth_life_palm"})
	_check(st["character"].knows_martial_art("preset_earth_life_palm"), "learn_art: 무공 습득")

	apply.call({"type": "end_game", "ending": "unify_righteous"})
	_check(result.get("end_game") == "unify_righteous", "end_game: 결과에 엔딩 지정")

	# 신규 기연 데이터
	var sworn: EventData = EventManager.get_event("rival_sworn_brothers")
	var secret: EventData = EventManager.get_event("master_secret_art")
	_check(sworn != null and secret != null and sworn.weight > 1.0, "신규 기연 로드 (가중치 포함)")
	_completed["_test_event_grammar_effects"] = true


## GameManager가 역할 기록·플래그 시점을 남기고, 저장·불러오기와 end_game을 처리하는지 확인한다.
func _test_event_progress_tracking() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.start_new_game("기록", "young_disciple")
	_check(gm.role_history == ["YOUNG_DISCIPLE"], "새 게임: 시작 역할 기록")
	gm.apply_role_transition(CharacterData.Role.SPY)
	gm.apply_role_transition(CharacterData.Role.MANAGER)
	_check(gm.role_history == ["YOUNG_DISCIPLE", "SPY", "MANAGER"], "역할 전환 기록")
	_check(EventManager.role_history == gm.role_history, "기연 판정에 역할 기록 공유")

	for i in 3:
		gm.advance_turn()
		gm.pending_event.clear()
		gm.pending_combat = null
	_check(EventManager.current_turn == gm._get_turn_index() and EventManager.current_year == gm.current_year, "계절 진행 시 기연 진행 상황 동기화")

	EventManager.set_flag(gm.story_flags, "test_flag")
	_check(gm.flag_turns.get("test_flag") == gm._get_turn_index(), "플래그 켜진 계절 기록")

	# 결투 승리 플래그도 시점이 남는다 (의형제 기연 조건)
	var duel: CombatSetup = CombatManager.create_rival_duel(gm.player_character)
	gm.pending_combat = duel
	gm.finish_combat(CombatManager.Outcome.VICTORY)
	_check(gm.flag_turns.get("won_rival_duel") == gm._get_turn_index(), "전투 승리 플래그 시점 기록")

	# 저장/불러오기
	var state: Dictionary = JSON.parse_string(JSON.stringify({
		"current_year": gm.current_year,
		"current_season_index": gm.current_season_index,
		"story_flags": gm.story_flags,
		"flag_turns": gm.flag_turns,
		"role_history": gm.role_history,
		"character": _SaveManager.serialize_character(gm.player_character),
		"sect": _SaveManager.serialize_sect(gm.player_sect),
	}))
	var expected_turn: int = gm.flag_turns["test_flag"]
	gm.start_new_game("초기화", "leader")
	gm._apply_save_data(state)
	_check(
		gm.flag_turns.get("test_flag") == expected_turn and gm.role_history.has("SPY")
		and EventManager.flag_turns == gm.flag_turns,
		"플래그 시점·역할 기록 저장/복원"
	)
	state.erase("role_history")
	state.erase("flag_turns")
	gm._apply_save_data(state)
	_check(gm.role_history.size() == 1 and gm.flag_turns.is_empty(), "구버전 세이브: 현재 역할만 기록")

	# 의형제 기연: 결투 승리 4계절 뒤, 라이벌 유대 40 이상
	gm.start_new_game("의형제", "young_disciple")
	var rival: RelationshipData = RelationshipManager.get_bond_with(gm.player_relationships, "npc_rival")
	rival.bond_strength = 45
	EventManager.set_flag(gm.story_flags, "won_rival_duel")
	var sworn: EventData = EventManager.get_event("rival_sworn_brothers")
	var holds := func() -> bool:
		return EventManager._conditions_met(
			sworn, gm.player_character, gm.player_sect, gm.player_relationships,
			gm.get_current_season(), gm.story_flags
		)
	_check(not holds.call(), "의형제 기연: 결투 직후에는 발생하지 않음")
	for i in 4:
		gm.advance_turn()
		gm.pending_event.clear()
		gm.pending_combat = null
	_check(holds.call(), "의형제 기연: 4계절 뒤 발생 조건 충족")
	gm.pending_event = {"id": "rival_sworn_brothers"}
	gm.resolve_pending_event(0)
	_check(rival.bond_type == RelationshipData.BondType.BLOOD_OATH, "의형제 기연: 혈맹으로 전환")

	# end_game 효과로 게임오버
	var dir_path: String = "user://_test_end_game"
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(dir_path.path_join("end.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"id": "test_end", "title": "끝", "description": "끝",
		"choices": [{"label": "끝낸다", "effects": [{"type": "end_game", "ending": "disgraced"}]}],
	}))
	file.close()
	EventManager.reload_definitions(dir_path)
	gm.pending_event = {"id": "test_end"}
	gm.resolve_pending_event(0)
	_check(gm.is_game_over() and gm.game_over_id == "disgraced", "end_game: 기연으로 게임오버")
	DirAccess.remove_absolute(dir_path.path_join("end.json"))
	DirAccess.remove_absolute(dir_path)
	EventManager.reload_definitions()
	gm.start_new_game("정리", "young_disciple")
	_completed["_test_event_progress_tracking"] = true


func _test_scenario_data() -> void:
	var scenarios: Array[Dictionary] = ScenarioManager.list_scenarios()
	var dir_count: int = DirAccess.get_directories_at(ScenarioManager.SCENARIO_DIR).size()
	_check(scenarios.size() == dir_count and dir_count >= 3, "시나리오 %d개 모두 검증 통과" % dir_count)
	_check(scenarios[0]["id"] == ScenarioManager.DEFAULT_ID, "기본 시나리오가 목록 첫 번째")

	var base: Dictionary = {"id": "x", "title": "x", "description": "x"}
	_check(ScenarioManager.validate_scenario_dict(base).is_empty(), "최소 시나리오 정의 통과")
	var bad_cases: Dictionary = {
		"알 수 없는 파라미터": {"parameters": {"speed": 2}},
		"범위 밖 파라미터": {"parameters": {"event_rate": 1.5}},
		"bool 파라미터에 숫자": {"parameters": {"legacy_enabled": 1}},
		"알 수 없는 시작 역할": {"start_roles": ["emperor"]},
		"알 수 없는 승리 엔딩": {"victory_endings": ["no_ending"]},
		"알 수 없는 문파": {"sects": ["shaolin"]},
		"제목 없는 전용 엔딩": {"endings": {"e": {"description": "x"}}},
	}
	for label in bad_cases:
		var data: Dictionary = base.duplicate(true)
		data.merge(bad_cases[label], true)
		_check(not ScenarioManager.validate_scenario_dict(data).is_empty(), "시나리오 오류 검출: %s" % label)

	# 흑풍의 겨울: 전용 세력 구성·기연·엔딩·파라미터
	ScenarioManager.activate("heukpung_winter")
	var rivals: Array[SectData] = ScenarioManager.create_rival_sects()
	var rival_ids: Array = rivals.map(func(x: SectData) -> String: return x.id)
	_check(rival_ids == ["heukpung", "namgung"], "시나리오 등장 세력만 생성 %s" % [rival_ids])
	_check(rivals[0].disciple_count == 22 and rivals[0].attitude == -80, "시나리오 세력 수치 덮어쓰기")
	_check(EventManager.get_event("heukpung_raid") != null and EventManager.get_event("night_bandits") != null, "공용 기연 + 시나리오 전용 기연 로드")
	_check(EndingManager.has_ending("winter_defended"), "시나리오 전용 엔딩 등록")
	_check(
		ScenarioRules.time_limit_years() == 5 and not ScenarioRules.legacy_enabled()
		and is_equal_approx(ScenarioRules.exp_scale(), 1.5) and ScenarioRules.end_on_victory(),
		"시나리오 파라미터 적용"
	)
	_check(ScenarioManager.get_start_role_ids() == ["young_disciple", "leader"], "시나리오 시작 역할 제한")

	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	_check(EventManager.get_event("heukpung_raid") == null and not EndingManager.has_ending("winter_defended"), "시나리오를 바꾸면 전용 데이터 해제")
	_check(ScenarioRules.time_limit_years() == 20 and ScenarioRules.legacy_enabled(), "기본 시나리오 파라미터")
	var errors: PackedStringArray = ScenarioManager.activate("no_such_scenario")
	_check(not errors.is_empty() and ScenarioManager.current_id == ScenarioManager.DEFAULT_ID, "없는 시나리오는 기본 시나리오로")
	_check(ScenarioManager.describe_length(ScenarioManager.get_scenario("gangho_100")) == "제한 없음 · 최대 5세대", "시나리오 길이 요약")
	_completed["_test_scenario_data"] = true


func _test_scenario_parameters() -> void:
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID, {"exp_scale": 1.5, "upkeep_scale": 0.5, "world_growth_scale": 1.5})
	var character := CharacterData.new()
	character.gain_experience(10)
	_check(character.experience == 15, "경험치 배율 1.5")
	var sect := SectData.new()
	sect.disciple_count = 10
	_check(sect.get_food_upkeep() == 10, "유지비 배율 0.5")
	var world: Array[SectData] = SectRegistry.create_rival_sects(["namgung"])
	var before: int = world[0].disciple_count
	SectWarManager.grow_world_sects(world)
	_check(world[0].disciple_count == before + 3, "세력 성장 배율 1.5 (2 → 3)")
	_check(ScenarioManager.user_overrides.has("exp_scale"), "세부 설정 값 보관")

	var bad: PackedStringArray = ScenarioManager.activate(ScenarioManager.DEFAULT_ID, {"exp_scale": 99})
	_check(not bad.is_empty() and is_equal_approx(ScenarioRules.exp_scale(), 1.0) and ScenarioManager.user_overrides.is_empty(), "잘못된 세부 설정은 무시")

	ScenarioRules.reset()
	var normal_power: int = SectWarManager.get_sect_power(world[0])
	ScenarioRules.apply({"enemy_strength_scale": 1.25})
	_check(SectWarManager.get_sect_power(world[0]) == roundi(normal_power * 1.25), "적 강도 배율이 세력 전력에 반영")
	ScenarioRules.apply({"time_limit_years": 10})
	_check(ScenarioRules.years_left(7) == 3 and ScenarioRules.has_time_limit(), "남은 연수 계산")
	ScenarioRules.apply({"time_limit_years": 0})
	_check(ScenarioRules.years_left(7) == 9999, "제한 없음이면 남은 연수 무한")

	# 기연 조건: scenario, years_left
	ScenarioManager.activate("heukpung_winter")
	EventManager.current_year = 3
	var st: Dictionary = _make_combat_state()
	_check(_condition_holds({"type": "scenario", "in": ["heukpung_winter"]}, st), "scenario 조건 충족")
	_check(not _condition_holds({"type": "scenario", "in": ["cheonha"]}, st), "scenario 조건 불충족")
	_check(_condition_holds({"type": "years_left", "op": "==", "value": 2}, st), "years_left 조건 (5년 중 3년차 → 2)")
	_check(not EventManager.validate_event_dict(_event_with({"conditions": [{"type": "scenario", "in": []}]})).is_empty(), "빈 scenario 조건 검출")
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	_completed["_test_scenario_parameters"] = true


func _test_scenario_flow() -> void:
	var gm: Node = root.get_node("GameManager")

	# 기연 빈도 0이면 기연이 일어나지 않는다
	gm.start_new_game("고요", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	for i in 8:
		gm.advance_turn()
		gm.pending_combat = null
	_check(gm.triggered_event_ids.is_empty() and gm.pending_event.is_empty(), "기연 빈도 0: 기연 없음")

	# 수입 배율
	gm.start_new_game("부유", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	var gold_before: int = gm.player_sect.gold
	var upkeep: int = gm.player_sect.get_gold_upkeep()
	gm.advance_turn()
	var normal_income: int = gm.player_sect.gold - gold_before + upkeep
	gm.start_new_game("부유", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0, "income_scale": 1.25})
	gold_before = gm.player_sect.gold
	gm.advance_turn()
	_check(gm.player_sect.gold - gold_before + upkeep == roundi(normal_income * 1.25), "수입 배율 1.25")

	# 흑풍의 겨울: 제한 연수 5년이 끝나면 시대 종결
	gm.start_new_game("겨울", "leader", "heukpung_winter", {"event_rate": 0.0})
	_check(gm.world_sects.size() == 2 and gm.player_sect.id == "qingyun", "시나리오로 새 게임: 세력 2개")
	gm.player_sect.gold = 99999
	gm.player_sect.food = 99999
	var guard: int = 0
	while not gm.is_game_over() and guard < 40:
		guard += 1
		gm.advance_turn()
		gm.pending_event.clear()
		gm.pending_combat = null
	_check(gm.game_over_id == "era_end" and guard == 20, "5년(20계절) 뒤 시대 종결 (%d계절)" % guard)
	_check(gm.current_year == 5 and gm.get_current_season() == "겨울", "마지막 해 겨울에서 멈춤")
	_check(gm.get_date_text() == "흑풍 5년 겨울", "시나리오 연호 표시")
	var eval: Dictionary = gm.get_evaluation()
	_check(eval["score"] > 0 and not eval["grade"].is_empty() and eval["lines"].size() >= 6, "시대 종결 평가")

	# 세대 전승 제한
	gm.start_new_game("겨울", "leader", "heukpung_winter")
	gm.player_character.age = 60
	_check(not gm.start_legacy_succession()["success"], "세대 전승 없는 시나리오")
	gm.start_new_game("백년", "leader", "gangho_100")
	gm.player_character.age = 60
	gm.generation = 5
	_check(not gm.start_legacy_succession()["success"], "최대 세대 도달 시 전승 불가")
	gm.generation = 1
	_check(gm.start_legacy_succession()["success"], "최대 세대 전에는 전승 가능")

	# 승리 엔딩으로 시나리오 완수
	gm.start_new_game("토벌", "leader", "heukpung_winter")
	EventManager.set_flag(gm.story_flags, "subjugated_heukpung")
	gm.pending_event = {"id": "winter_defended"}
	gm.resolve_pending_event(0)
	_check(gm.current_ending_id == "winter_defended" and gm.game_over_id == "scenario_complete", "승리 엔딩 도달 시 시나리오 완수")
	_check(gm.get_evaluation()["lines"].has("시나리오 승리: +%d" % _Balance.SCORE_VICTORY), "평가에 시나리오 승리 반영")

	# 저장/불러오기
	gm.start_new_game("저장", "leader", "heukpung_winter", {"time_limit_years": 10})
	var state: Dictionary = JSON.parse_string(JSON.stringify({
		"scenario_id": ScenarioManager.current_id,
		"scenario_overrides": ScenarioManager.user_overrides,
		"character": _SaveManager.serialize_character(gm.player_character),
		"sect": _SaveManager.serialize_sect(gm.player_sect),
		"world_sects": _SaveManager.serialize_sects(gm.world_sects),
	}))
	gm.start_new_game("다른 판", "young_disciple")
	gm._apply_save_data(state)
	_check(
		ScenarioManager.current_id == "heukpung_winter" and ScenarioRules.time_limit_years() == 10
		and EventManager.get_event("heukpung_raid") != null,
		"시나리오·세부 설정 저장/복원"
	)
	state.erase("scenario_id")
	state.erase("scenario_overrides")
	gm._apply_save_data(state)
	_check(ScenarioManager.current_id == ScenarioManager.DEFAULT_ID, "구버전 세이브는 기본 시나리오")

	gm.start_new_game("정리", "young_disciple")
	_completed["_test_scenario_flow"] = true


func _test_new_game_screen_scenarios() -> void:
	SceneRouter.goto(self, SceneRouter.NEW_GAME)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	_check(screen.scenario_list.item_count == ScenarioManager.list_scenarios().size(), "새 게임 화면: 시나리오 목록")
	var winter_index: int = ScenarioManager.list_scenarios().map(func(x): return x["id"]).find("heukpung_winter")
	screen.scenario_list.select(winter_index)
	screen._on_scenario_selected(winter_index)
	_check(screen.role_list.item_count == 2, "새 게임 화면: 시나리오별 시작 역할")
	_check(ScenarioManager.current_id == ScenarioManager.DEFAULT_ID, "시나리오를 둘러봐도 현재 게임은 그대로")
	var option: OptionButton = screen._setting_options["time_limit_years"]
	option.select(2)  # 10년
	option.item_selected.emit(2)
	_check(screen.get_overrides() == {"time_limit_years": 10}, "세부 설정 값 수집")
	_check(screen.scenario_length_label.text.contains("10년"), "길이 요약에 세부 설정 반영")
	screen._on_start_pressed()
	await process_frame
	await process_frame
	_check(
		ScenarioManager.current_id == "heukpung_winter" and ScenarioRules.time_limit_years() == 10
		and current_scene.scene_file_path == SceneRouter.HUB,
		"새 게임 화면에서 시나리오로 시작"
	)
	_check(current_scene.year_label.text.contains("흑풍 1년") and current_scene.year_label.text.contains("남은 9년"), "경영 화면에 연호와 남은 연수")
	# 경영 화면을 떠나면 전역 신호 연결이 끊긴다 (떠난 화면이 게임오버 등에 반응하지 않음)
	var bus: Node = root.get_node("EventBus")
	_check(bus.game_over.get_connections().size() == 1, "경영 화면이 게임오버 신호에 연결됨")
	SceneRouter.goto(self, SceneRouter.MAIN_MENU)
	await process_frame
	await process_frame
	_check(bus.game_over.get_connections().is_empty() and bus.turn_advanced.get_connections().is_empty(), "경영 화면을 떠나면 신호 연결 해제")
	root.get_node("GameManager").start_new_game("정리", "young_disciple")
	_completed["_test_new_game_screen_scenarios"] = true


func _test_ending_data() -> void:
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	var endings: Array[Dictionary] = EndingManager.get_all_endings()
	var file_count: int = _count_json(EndingManager.ENDING_DIR)
	_check(endings.size() == file_count and file_count >= 10, "공용 엔딩 %d개 모두 검증 통과" % file_count)
	var priorities: Dictionary = {}
	var duplicated: bool = false
	for ending in endings:
		if ending.get("auto", true):
			duplicated = duplicated or priorities.has(int(ending["priority"]))
			priorities[int(ending["priority"])] = true
	_check(not duplicated, "자동 엔딩의 우선순위가 모두 다름")
	_check(EndingManager.get_all_endings()[0]["id"] == "tragic_execution", "우선순위 높은 순 정렬")

	var base: Dictionary = {
		"id": "x", "title": "x", "description": "x", "priority": 1,
		"conditions": [{"type": "flag", "flag": "f"}],
	}
	_check(EndingManager.validate_ending_dict(base).is_empty(), "엔딩 정의 정상 통과")
	var bad_cases: Dictionary = {
		"priority 없음": {"priority": null},
		"조건 없는 자동 엔딩": {"conditions": []},
		"잘못된 tone": {"tone": "happy"},
		"게임오버 id와 겹침": {"id": "era_end"},
		"잘못된 조건": {"conditions": [{"type": "weather"}]},
		"final 형식": {"final": "yes"},
	}
	for label in bad_cases:
		var data: Dictionary = base.duplicate(true)
		data.merge(bad_cases[label], true)
		if data["priority"] == null:
			data.erase("priority")
		_check(not EndingManager.validate_ending_dict(data).is_empty(), "엔딩 오류 검출: %s" % label)
	var manual: Dictionary = {"id": "m", "title": "m", "description": "m", "auto": false, "conditions": []}
	_check(EndingManager.validate_ending_dict(manual).is_empty(), "수동 엔딩은 priority·조건 없이도 통과")

	# 우선순위가 겹치면 뒤의 파일을 건너뛴다
	var dir_path: String = "user://_test_endings"
	DirAccess.make_dir_recursive_absolute(dir_path)
	for id in ["a_first", "b_second"]:
		var file := FileAccess.open(dir_path.path_join(id + ".json"), FileAccess.WRITE)
		var data: Dictionary = base.duplicate(true)
		data["id"] = id
		file.store_string(JSON.stringify(data))
		file.close()
	EndingManager.reload_data(dir_path)
	_check(EndingManager.has_ending("a_first") and not EndingManager.has_ending("b_second"), "겹치는 우선순위 엔딩 거부")
	for id in ["a_first", "b_second"]:
		DirAccess.remove_absolute(dir_path.path_join(id + ".json"))
	DirAccess.remove_absolute(dir_path)

	# 시나리오 전용 엔딩은 해당 시나리오에서만
	ScenarioManager.activate("heukpung_winter")
	_check(EndingManager.has_ending("winter_defended") and EndingManager.has_ending("unify_righteous"), "시나리오 전용 + 공용 엔딩")
	_check(not EndingManager.get_ending("winter_defended").get("auto", true), "전용 엔딩은 기연으로만 도달 (auto false)")
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	_check(not EndingManager.has_ending("winter_defended"), "다른 시나리오에서는 전용 엔딩 없음")
	_check(
		not ScenarioManager.validate_scenario_dict({"id": "x", "title": "x", "description": "x", "endings": {}}).is_empty(),
		"scenario.json의 endings 필드는 폴더로 옮기라는 오류"
	)
	_completed["_test_ending_data"] = true


## 엔딩마다 그 엔딩만 만족하도록 상태를 만들어, 판정이 정확히 그 엔딩을 고르는지 확인한다.
func _test_every_ending_reachable() -> void:
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	var saved_world: Array[SectData] = EventManager.world_sects
	var saved_history: Array[String] = EventManager.role_history
	var saved_generation: int = EventManager.current_generation

	var art := func(id: String) -> MartialArtData:
		var a := MartialArtData.new()
		a.id = id
		return a
	var setups: Dictionary = {
		"tragic_execution": func(st: Dictionary) -> void: st["flags"]["spy_exposed"] = true,
		"blood_soaked_path": func(st: Dictionary) -> void:
			EventManager.role_history = ["SPY", "ASSASSIN"] as Array[String]
			st["character"].morality = 5,
		"hermit_master": func(st: Dictionary) -> void:
			st["character"].role = CharacterData.Role.WANDERER
			st["character"].level = 12
			for i in 4:
				st["character"].learn_martial_art(art.call("a%d" % i)),
		"demonic_shadow": func(st: Dictionary) -> void:
			st["flags"]["cheonma_pact"] = true
			st["character"].morality = 25
			st["sect"].reputation = 60,
		"unify_righteous": func(st: Dictionary) -> void:
			st["character"].role = CharacterData.Role.LEADER
			st["character"].morality = 70
			st["sect"].reputation = 100
			EventManager.world_sects[0].subjugated = true
			EventManager.world_sects[1].subjugated = true,
		"master_successor": func(st: Dictionary) -> void:
			st["character"].role = CharacterData.Role.LEADER
			st["flags"]["inherited_master_art"] = true
			RelationshipManager.get_bond_with(st["relationships"], "npc_master").bond_strength = 85,
		"sworn_legend": func(st: Dictionary) -> void:
			st["flags"]["sworn_with_rival"] = true
			var rival: RelationshipData = RelationshipManager.get_bond_with(st["relationships"], "npc_rival")
			rival.bond_type = RelationshipData.BondType.BLOOD_OATH
			rival.bond_strength = 85
			st["sect"].reputation = 85,
		"shadow_empire": func(st: Dictionary) -> void:
			st["character"].role = CharacterData.Role.SPY
			st["character"].morality = 30
			st["sect"].reputation = 70
			st["flags"]["assassin_path"] = true,
		"new_sect_founder": func(st: Dictionary) -> void:
			st["character"].role = CharacterData.Role.MANAGER
			st["flags"]["spy_mission_complete"] = true
			st["sect"].reputation = 85,
		"wanderer_legend": func(st: Dictionary) -> void:
			st["character"].role = CharacterData.Role.WANDERER
			st["character"].level = 6
			st["character"].learn_martial_art(art.call("a"))
			st["character"].learn_martial_art(art.call("b")),
		"three_generations": func(st: Dictionary) -> void:
			EventManager.current_generation = 3
			st["sect"].reputation = 90,
		"golden_sect": func(st: Dictionary) -> void:
			st["sect"].gold = 3000
			st["sect"].treasury_level = 5,
	}
	var auto_ids: Array = EndingManager.get_all_endings().filter(
		func(e: Dictionary) -> bool: return e.get("auto", true)
	).map(func(e: Dictionary) -> String: return e["id"])
	_check(setups.keys().all(func(id: String) -> bool: return auto_ids.has(id)) and setups.size() == auto_ids.size(), "모든 자동 엔딩에 도달 시험 상태가 있음")

	for ending_id in setups:
		var st: Dictionary = _make_combat_state()
		EventManager.world_sects = SectRegistry.create_rival_sects()
		EventManager.role_history = ["YOUNG_DISCIPLE"] as Array[String]
		EventManager.current_generation = 1
		setups[ending_id].call(st)
		var result: String = EndingManager.check_endings(st["character"], st["sect"], st["flags"], st["relationships"])
		_check(result == ending_id, "엔딩 도달: %s (판정 %s)" % [ending_id, result])

	var plain: Dictionary = _make_combat_state()
	EventManager.world_sects = SectRegistry.create_rival_sects()
	EventManager.role_history = ["YOUNG_DISCIPLE"] as Array[String]
	EventManager.current_generation = 1
	_check(EndingManager.check_endings(plain["character"], plain["sect"], plain["flags"], plain["relationships"]).is_empty(), "시작 상태에서는 엔딩 없음")

	EventManager.world_sects = saved_world
	EventManager.role_history = saved_history
	EventManager.current_generation = saved_generation
	_completed["_test_every_ending_reachable"] = true


func _test_final_ending_flow() -> void:
	var gm: Node = root.get_node("GameManager")

	# 전승할 수 있는 시나리오: 생이 끝나면 시간이 멈추고, 나이와 관계없이 후계자로 이어 간다
	gm.start_new_game("처형", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	gm.apply_role_transition(CharacterData.Role.SPY)
	EventManager.set_flag(gm.story_flags, "spy_exposed")
	gm._check_end_states()
	_check(gm.current_ending_id == "tragic_execution" and gm.story_flags.get("life_ended", false), "생을 마치는 엔딩: 생 종료 표시")
	_check(not gm.is_game_over(), "전승 가능하면 게임오버가 아님")
	var turn: int = gm._get_turn_index()
	gm.advance_turn()
	_check(gm._get_turn_index() == turn, "생이 끝나면 계절이 흐르지 않음")
	var summary: PackedStringArray = gm.get_run_summary()
	_check(summary[1] == "역할 변천: 막내 제자 → 스파이", "요약: 역할 변천 %s" % summary[1])
	_check(summary[2] == "굴복시킨 세력: 없음" and summary[4].begins_with("주요 인연: 청운검선"), "요약: 세력·인연")

	SceneRouter.goto(self, SceneRouter.ENDING)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	_check(
		screen.legacy_label.text.contains("역할 변천") and screen.legacy_label.text.contains("평가:")
		and screen.desc_label.text.contains("후계자"),
		"엔딩 화면: 요약·평가·후계자 안내"
	)
	_check(screen.title_label.get_theme_color("font_color") == _UiTheme.COLORS["accent_red"], "비극 엔딩은 붉은 제목")

	var result: Dictionary = gm.start_legacy_succession()
	_check(result["success"] and gm.generation == 2 and not gm.story_flags.get("life_ended", false), "나이와 관계없이 후계자로 전승")
	_check(EventManager.current_generation == 2, "세대 정보 동기화")
	gm.advance_turn()
	_check(gm._get_turn_index() == turn + 1, "후계자로 시간이 다시 흐름")

	# 전승할 수 없는 시나리오: 이야기가 끝난다
	gm.start_new_game("겨울 처형", "young_disciple", "heukpung_winter", {"event_rate": 0.0})
	EventManager.set_flag(gm.story_flags, "spy_exposed")
	gm._check_end_states()
	_check(gm.game_over_id == "story_end" and gm.current_ending_id == "tragic_execution", "전승 불가 시나리오: 이야기의 끝")

	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(self, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_final_ending_flow"] = true


func _test_war_rules() -> void:
	var C := SectWarManager.Command
	var F := SectWarManager.Formation
	_check(
		is_equal_approx(SectWarManager.matchup_multiplier(C.CHARGE, C.FLANK), _Balance.WAR_ADVANTAGE)
		and is_equal_approx(SectWarManager.matchup_multiplier(C.FLANK, C.DEFEND), _Balance.WAR_ADVANTAGE)
		and is_equal_approx(SectWarManager.matchup_multiplier(C.DEFEND, C.CHARGE), _Balance.WAR_ADVANTAGE),
		"상성: 돌격 > 측면 > 방어 > 돌격"
	)
	_check(is_equal_approx(SectWarManager.matchup_multiplier(C.FLANK, C.CHARGE), _Balance.WAR_DISADVANTAGE), "지는 상성 배율")
	_check(is_equal_approx(SectWarManager.matchup_multiplier(C.CHARGE, C.CHARGE), 1.0), "같은 명령은 보정 없음")
	_check(is_equal_approx(SectWarManager.matchup_multiplier(C.RETREAT, C.CHARGE), _Balance.WAR_RETREAT_POWER), "후퇴는 전력 감소")
	_check(
		is_equal_approx(SectWarManager.formation_multiplier(F.CRANE, C.FLANK), _Balance.WAR_FORMATION_BONUS)
		and is_equal_approx(SectWarManager.formation_multiplier(F.CRANE, C.CHARGE), _Balance.WAR_FORMATION_PENALTY)
		and is_equal_approx(SectWarManager.formation_multiplier(F.CRANE, C.DEFEND), 1.0)
		and is_equal_approx(SectWarManager.formation_multiplier(F.NONE, C.CHARGE), 1.0),
		"진형 배율: 학익진은 측면 강화, 측면을 이기는 돌격 약화"
	)

	var sects: Array[SectData] = SectRegistry.create_rival_sects()
	var heukpung: SectData = sects.filter(func(x: SectData) -> bool: return x.id == "heukpung")[0]
	_check(SectWarManager.get_formation(heukpung) == F.FISH, "사파 기본 진형: 어린진")
	var tactics: Dictionary = SectWarManager.get_tactics(heukpung)
	_check(tactics[C.CHARGE] >= tactics[C.DEFEND] and tactics[C.FLANK] >= tactics[C.DEFEND], "사파는 돌격·측면을 즐겨 씀")
	var plan: Dictionary = SectWarManager.plan_battle(heukpung)
	_check(plan["enemy_commands"].size() == _Balance.WAR_ROUNDS and not plan["revealed"].has(true), "작전 계획: 3라운드, 모두 미공개")

	# 전술 가중치대로 명령을 고르는지
	seed(11)
	var charges: int = 0
	for i in 1000:
		if SectWarManager.plan_battle(heukpung)["enemy_commands"][0] == C.CHARGE:
			charges += 1
	randomize()
	var expected_charges: float = tactics[C.CHARGE] / tactics.values().reduce(func(a, b): return a + b) * 1000
	_check(absf(charges - expected_charges) < 60, "전술 가중치 반영 (돌격 %d/1000, 기대 %d)" % [charges, expected_charges])

	# 문파 데이터의 전술·진형 검증
	var base: Dictionary = {"id": "x", "sect_name": "x", "alignment": "RIGHTEOUS", "leader_id": "npc_master"}
	var custom: Dictionary = base.duplicate()
	custom["war_tactics"] = {"CHARGE": 1, "DEFEND": 0}
	custom["war_formation"] = "CRANE"
	_check(SectRegistry.validate_sect_dict(custom).is_empty(), "문파 데이터 전술·진형 지정 통과")
	custom["war_tactics"] = {"SNEAK": 1}
	_check(not SectRegistry.validate_sect_dict(custom).is_empty(), "알 수 없는 문파전 명령 검출")
	custom = base.duplicate()
	custom["war_formation"] = "SQUARE"
	_check(not SectRegistry.validate_sect_dict(custom).is_empty(), "알 수 없는 진형 검출")
	_check(
		not NpcRoster.validate_npc_dict({"id": "x", "display_name": "x", "sect_id": "s", "role": "LEADER", "war_specialty": "MAGIC"}).is_empty(),
		"알 수 없는 장수 특기 검출"
	)

	# 정찰
	var character := CharacterData.new()
	_check(SectWarManager.get_scout_cost(plan, character) == _Balance.WAR_SCOUT_COST, "정찰 비용")
	_check(SectWarManager.reveal_next(plan) == 0 and SectWarManager.reveal_next(plan) == 1, "정찰은 앞 라운드부터 공개")
	_check(SectWarManager.get_scout_cost(plan, character) == _Balance.WAR_SCOUT_COST + 2 * _Balance.WAR_SCOUT_COST_STEP, "정찰할수록 비싸짐")
	character.role = CharacterData.Role.SPY
	_check(SectWarManager.get_scout_cost(plan, character) == (_Balance.WAR_SCOUT_COST + 2 * _Balance.WAR_SCOUT_COST_STEP) / 2, "스파이는 정찰 비용 절반")
	SectWarManager.reveal_next(plan)
	_check(SectWarManager.reveal_next(plan) == -1, "모두 공개되면 더 정찰할 것 없음")

	# 장수 특기
	var general: Dictionary = SectWarManager.describe_general("npc_master")
	_check(general["specialty"] == C.DEFEND and general["power"] > 0, "청운검선: 방어 특기 장수")
	var plain: Dictionary = SectWarManager.resolve_round(100, C.DEFEND, F.NONE, {}, 100, C.DEFEND, F.NONE, 0, -1, -1, 0.0)
	var boosted: Dictionary = SectWarManager.resolve_round(100, C.DEFEND, F.NONE, general, 100, C.DEFEND, F.NONE, 0, -1, -1, 0.0)
	_check(plain["outcome"] == 0 and boosted["outcome"] == 1, "장수 특기 명령이면 같은 전력에서 우세")
	var repeated: Dictionary = SectWarManager.resolve_round(100, C.DEFEND, F.NONE, {}, 100, C.DEFEND, F.NONE, 1, C.DEFEND, -1, 0.0)
	_check(repeated["outcome"] == -1, "같은 명령을 연달아 쓰면 약해짐")

	# 적의 학습: 지난 전투에서 본 명령을 맞받아치는 수
	heukpung.observed_commands.assign([C.CHARGE, C.CHARGE, C.CHARGE])
	seed(5)
	var counters: int = 0
	for i in 1000:
		if SectWarManager.plan_battle(heukpung)["enemy_commands"][0] == C.DEFEND:
			counters += 1
	randomize()
	var defend_share: float = tactics[C.DEFEND] / tactics.values().reduce(func(a, b): return a + b)
	var expected: float = (_Balance.WAR_ADAPT_CHANCE + (1.0 - _Balance.WAR_ADAPT_CHANCE) * defend_share) * 1000
	_check(absf(counters - expected) < 60, "적이 지난 전투의 돌격을 방어로 대비 (%d/1000, 기대 %d)" % [counters, expected])
	heukpung.observed_commands.clear()
	_completed["_test_war_rules"] = true


## 같은 전력에서 고정 명령 조합의 승률을 본다.
## 1) 처음 맞붙을 때(진형 없음) 어떤 조합도 60% 이하
## 2) 같은 조합을 되풀이하면 적이 기억해 대비하므로, 진형을 맞춰도 60% 이하
func _test_war_balance() -> void:
	var C := SectWarManager.Command
	var all_commands: Array = [C.CHARGE, C.DEFEND, C.FLANK, C.RETREAT]
	var combos: Array = []
	for a in all_commands:
		for b in all_commands:
			for c in all_commands:
				combos.append([a, b, c])
	var formations: Array = [
		SectWarManager.Formation.NONE, SectWarManager.Formation.CRANE,
		SectWarManager.Formation.FISH, SectWarManager.Formation.CIRCLE,
	]
	var win_rate := func(sect: SectData, combo: Array, formation: int, trials: int) -> float:
		var wins: int = 0
		for t in trials:
			var plan: Dictionary = SectWarManager.plan_battle(sect)
			var enemy: Array = plan["enemy_commands"]
			var score: int = 0
			for r in 3:
				score += SectWarManager.resolve_round(
					100, combo[r], formation, {}, 100, enemy[r], plan["enemy_formation"], r,
					combo[r - 1] if r > 0 else -1, enemy[r - 1] if r > 0 else -1
				)["outcome"]
			if score > 0:
				wins += 1
		return float(wins) / trials

	# 표본 오차 때문에 최댓값이 부풀지 않도록, 200판으로 후보를 고른 뒤 상위 5개를 2000판으로 다시 잰다.
	var best_of := func(sect: SectData, candidates: Array, observe: bool) -> float:
		var scored: Array = []
		for candidate in candidates:
			sect.observed_commands.assign(candidate[0] if observe else [])
			scored.append([win_rate.call(sect, candidate[0], candidate[1], 200), candidate])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var best: float = 0.0
		for entry in scored.slice(0, 5):
			sect.observed_commands.assign(entry[1][0] if observe else [])
			best = maxf(best, win_rate.call(sect, entry[1][0], entry[1][1], 2000))
		sect.observed_commands.clear()
		return best

	seed(21)
	for sect in SectRegistry.create_rival_sects():
		var first_candidates: Array = combos.map(func(combo: Array) -> Array: return [combo, SectWarManager.Formation.NONE])
		var repeat_candidates: Array = []
		for combo in combos:
			for formation in formations:
				repeat_candidates.append([combo, formation])
		var first_best: float = best_of.call(sect, first_candidates, false)
		var repeat_best: float = best_of.call(sect, repeat_candidates, true)
		_check(first_best <= 0.6, "%s: 첫 대결 최선의 고정 조합 승률 %d%% (60%% 이하)" % [sect.sect_name, roundi(first_best * 100)])
		_check(repeat_best <= 0.6, "%s: 같은 조합을 되풀이할 때 최선 승률 %d%% (60%% 이하)" % [sect.sect_name, roundi(repeat_best * 100)])
	randomize()
	_completed["_test_war_balance"] = true


func _test_war_flow() -> void:
	var gm: Node = root.get_node("GameManager")
	var C := SectWarManager.Command
	gm.start_new_game("전략", "leader", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})

	# 장수 후보: 유대가 깊은 사제·혈맹만
	_check(gm.get_war_generals().is_empty(), "유대가 얕으면 장수 없음")
	RelationshipManager.get_bond_with(gm.player_relationships, "npc_master").bond_strength = 60
	var rival: RelationshipData = RelationshipManager.get_bond_with(gm.player_relationships, "npc_rival")
	rival.bond_type = RelationshipData.BondType.BLOOD_OATH
	rival.bond_strength = 60
	_check(gm.get_war_generals("heukpung").size() == 2, "사제·혈맹 인물이 장수 후보")
	_check(gm.get_war_generals("namgung").size() == 1, "상대 세력 소속 인물은 장수 제외")

	# 작전 계획은 같은 계절 동안 유지되고, 정찰한 명령이 실제 명령과 같다
	var plan: Dictionary = gm.prepare_war("heukpung")
	_check(gm.prepare_war("heukpung") == plan, "같은 계절·같은 상대면 계획 유지")
	var gold_before: int = gm.player_sect.gold
	var scout: Dictionary = gm.scout_war("heukpung")
	_check(scout["success"] and gm.player_sect.gold == gold_before - _Balance.WAR_SCOUT_COST and plan["revealed"][0], "정찰: 금화 소모, 1라운드 공개")
	gm.player_sect.gold = 0
	_check(not gm.scout_war("heukpung")["success"], "금화가 없으면 정찰 불가")
	gm.player_sect.gold = 500

	var expected_first: int = plan["enemy_commands"][0]
	var result: Dictionary = gm.resolve_sect_war(
		"heukpung", [C.CHARGE, C.DEFEND, C.FLANK], SectWarManager.Formation.CIRCLE, "npc_master"
	)
	_check(result["rounds"].size() == 3 and result["rounds"][0]["enemy_command"] == expected_first, "정찰한 명령대로 적이 움직임")
	_check(gm.pending_war_plan.is_empty(), "문파전 뒤 계획 초기화")
	_check(gm.get_world_sect("heukpung").observed_commands == [C.CHARGE, C.DEFEND, C.FLANK], "적이 아군 명령을 기억")
	var saved: SectData = _SaveManager.deserialize_sect(JSON.parse_string(JSON.stringify(_SaveManager.serialize_sect(gm.get_world_sect("heukpung")))))
	_check(saved.observed_commands == [C.CHARGE, C.DEFEND, C.FLANK], "기억한 명령 저장/복원")

	gm.advance_turn()
	var new_plan: Dictionary = gm.prepare_war("heukpung")
	_check(not new_plan["revealed"].has(true), "계절이 바뀌면 새 계획")

	# 패배 손실: 후퇴·방원진이면 줄어든다
	var weak := SectData.new()
	weak.disciple_count = 20
	var weak_char := CharacterData.new()
	var strong: SectData = SectRegistry.create_rival_sects(["cheonma"])[0]
	var all_lose_plan: Dictionary = SectWarManager.plan_battle(strong)
	var lost_plain: Dictionary = SectWarManager.resolve_battle(weak, weak_char, strong, [C.CHARGE, C.CHARGE, C.CHARGE] as Array[SectWarManager.Command], all_lose_plan)
	var plain_loss: int = 20 - weak.disciple_count
	weak.disciple_count = 20
	SectWarManager.resolve_battle(weak, weak_char, strong, [C.RETREAT, C.RETREAT, C.CHARGE] as Array[SectWarManager.Command], all_lose_plan, SectWarManager.Formation.CIRCLE)
	var careful_loss: int = 20 - weak.disciple_count
	_check(not lost_plain["victory"] and careful_loss < plain_loss, "후퇴·방원진으로 패배 손실 감소 (%d → %d)" % [plain_loss, careful_loss])

	# 화면
	gm.start_new_game("화면", "leader", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	SceneRouter.goto(self, SceneRouter.SECT_WAR)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	_check(screen.target_option.item_count == 3 and screen.formation_option.item_count == 4, "문파전 화면: 대상·진형 선택지")
	_check(screen.plan_label.text.contains("적 ?"), "정찰 전에는 적 명령을 모름")
	screen._on_scout_pressed()
	_check(not screen.plan_label.text.begins_with("1라운드: 아군 —  /  적 ?"), "정찰 후 1라운드 적 명령 표시")
	for command in [C.FLANK, C.FLANK, C.CHARGE]:
		screen._add_command(command)
	_check(not screen.execute_button.disabled, "명령 3개를 고르면 전투 개시 가능")
	screen._on_execute_pressed()
	_check(screen.log_label.text.contains("라운드 3") and not gm.can_wage_war(), "전투 결과 표시와 계절당 1회 제한")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(self, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_war_flow"] = true


func _test_economy_rules() -> void:
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	var sect := SectData.new()
	var character := CharacterData.new()
	character.wisdom = 10
	character.role = CharacterData.Role.YOUNG_DISCIPLE
	var spring: Dictionary = SectManager.compute_seasonal_income(sect, character, "봄")
	_check(
		spring["gold"] == _Balance.BASE_GOLD_INCOME + _Balance.TREASURY_GOLD_PER_LEVEL
		and spring["food"] == _Balance.BASE_FOOD_INCOME + _Balance.TRAINING_FOOD_PER_LEVEL + 15
		and spring["research"] == _Balance.LIBRARY_RESEARCH_PER_LEVEL + 5,
		"봄 수입 계산 %s" % [spring]
	)
	var summer: Dictionary = SectManager.compute_seasonal_income(sect, character, "여름")
	_check(summer["gold"] == spring["gold"] + 10, "여름 금화 보너스")
	character.role = CharacterData.Role.LEADER
	_check(SectManager.compute_seasonal_income(sect, character, "봄")["gold"] == int(spring["gold"] * 1.2), "문주 경영 보정")

	# 재고 손실
	sect.gold = 1000
	sect.food = 800
	var losses: Dictionary = SectManager.apply_yearly_losses(sect)
	_check(losses["gold_loss"] == 75 and losses["food_loss"] == 100 and sect.gold == 925 and sect.food == 700, "재고 손실: 안전량 초과분의 일부")
	sect.gold = 400
	sect.food = 250
	losses = SectManager.apply_yearly_losses(sect)
	_check(losses["gold_loss"] == 0 and losses["food_loss"] == 0 and losses["message"].is_empty(), "안전량 이하면 손실 없음")
	sect.disciple_count = 12
	var rep_before: int = sect.reputation
	_check(SectManager.apply_yearly_reputation(sect) == 2 and sect.reputation == rep_before + 2, "제자 12명: 해마다 명성 +2")

	# 시설
	sect = SectData.new()
	_check(SectManager.get_upgrade_cost(sect, "library") == 80, "서고 첫 확장 80")
	sect.gold = 10000
	SectManager.upgrade_facility(sect, "library")
	_check(sect.library_level == 2 and SectManager.get_upgrade_cost(sect, "library") == 120, "확장할수록 비용 상승 (120)")
	_check(sect.apothecary_level == 0 and SectManager.get_upgrade_cost(sect, "apothecary") == 90, "약방은 0에서 짓기")
	var upkeep_before: int = sect.get_gold_upkeep()
	var result: Dictionary = SectManager.upgrade_facility(sect, "apothecary")
	_check(result["success"] and sect.apothecary_level == 1 and result["message"].contains("지었습니다"), "약방 짓기")
	_check(sect.get_gold_upkeep() == upkeep_before + _Balance.FACILITY_UPKEEP_GOLD, "새 시설도 유지비 증가")
	for i in 5:
		SectManager.upgrade_facility(sect, "apothecary")
	_check(sect.apothecary_level == 3 and SectManager.get_upgrade_cost(sect, "apothecary") == -1, "약방 최대 Lv.3")
	_check(not SectManager.upgrade_facility(sect, "apothecary")["success"], "최고 수준이면 확장 불가")
	sect.gold = 10
	_check(not SectManager.upgrade_facility(sect, "treasury")["success"], "금화 부족이면 확장 불가")

	var restored: SectData = _SaveManager.deserialize_sect(JSON.parse_string(JSON.stringify(_SaveManager.serialize_sect(sect))))
	_check(restored.apothecary_level == 3 and restored.library_level == 2, "새 시설 저장/복원")
	_completed["_test_economy_rules"] = true


func _test_economy_flow() -> void:
	var gm: Node = root.get_node("GameManager")

	# 무행동 10년: 금화가 시작값의 2배를 넘지 않는다
	gm.start_new_game("무위", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	var start_gold: int = gm.player_sect.gold
	for i in 40:
		gm.advance_turn()
		gm.pending_combat = null
	_check(gm.player_sect.gold <= start_gold * 2, "무행동 10년 금화 %d (시작 %d의 2배 이하)" % [gm.player_sect.gold, start_gold])
	_check(gm.player_sect.food <= 1000 and gm.player_sect.food > 0, "무행동 10년 식량 %d (부족도 과잉도 아님)" % gm.player_sect.food)

	# 예상 수지가 실제와 같다 (해가 바뀌지 않는 계절)
	gm.start_new_game("예측", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	var forecast: Dictionary = gm.estimate_next_season()
	var gold_before: int = gm.player_sect.gold
	var food_before: int = gm.player_sect.food
	gm.advance_turn()
	_check(
		gm.player_sect.gold - gold_before == forecast["gold"] and gm.player_sect.food - food_before == forecast["food"],
		"다음 계절 예상 수지가 실제와 같음"
	)
	var rep_before: int = gm.player_sect.reputation
	gm.advance_turn()
	_check(gm.player_sect.reputation == rep_before, "계절마다 명성이 저절로 오르지 않음")

	# 약방·연공실 효과
	gm.player_sect.apothecary_level = 2
	gm.player_sect.meditation_hall_level = 1
	gm.player_character.internal_energy_current = 0
	var exp_before: int = gm.player_character.experience
	gm.advance_turn()
	var regen: int = int(gm.player_character.internal_energy_max * _Balance.APOTHECARY_INTERNAL_REGEN * 2)
	_check(gm.player_character.internal_energy_current == regen, "약방 Lv.2: 계절 내공 회복 %d" % regen)
	_check(gm.player_character.experience >= exp_before + _Balance.MEDITATION_EXP_PER_LEVEL, "연공실: 계절 수련 경험치")
	_check(gm.last_turn_report.contains("약방") and gm.last_turn_report.contains("연공실"), "계절 보고에 시설 효과")

	# 영약·연회: 계절마다 한 번
	gm.player_sect.gold = 1000
	gm.player_sect.food = 500
	var internal_max: int = gm.player_character.internal_energy_max
	_check(gm.buy_elixir()["success"] and gm.player_character.internal_energy_max == internal_max + _Balance.ELIXIR_INTERNAL_GAIN, "영약: 최대 내공 증가")
	_check(not gm.buy_elixir()["success"], "영약은 계절마다 한 번")
	rep_before = gm.player_sect.reputation
	_check(gm.hold_feast()["success"] and gm.player_sect.reputation == rep_before + _Balance.FEAST_REPUTATION, "연회: 명성 증가")
	_check(not gm.hold_feast()["success"], "연회는 계절마다 한 번")
	gm.advance_turn()
	_check(gm.can_do_seasonal("last_feast_turn") and gm.can_do_seasonal("last_elixir_turn"), "다음 계절에는 다시 가능")
	gm.player_sect.gold = 10
	_check(not gm.buy_elixir()["success"], "금화가 부족하면 영약 불가")

	# 해가 바뀌면 정산 문구
	gm.start_new_game("정산", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	gm.player_sect.gold = 2000
	for i in 4:
		gm.advance_turn()
	_check(gm.last_turn_report.contains("새해 정산") and gm.last_turn_report.contains("금화 -"), "새해 정산 보고")

	# 경영 화면: 시설 관리 팝업
	gm.start_new_game("시설", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	SceneRouter.goto(self, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	_check(hub.gold_label.text.contains("다음 계절"), "경영 화면에 예상 수지 표시")
	hub._on_facility_pressed()
	await process_frame
	var popup: Node = hub.facility_popup
	_check(popup.visible and popup._rows.get_child_count() == SectManager.get_facility_ids().size(), "시설 관리 팝업: 시설 5종")
	var gold_before_build: int = gm.player_sect.gold
	popup._on_upgrade_pressed("meditation_hall")
	_check(gm.player_sect.meditation_hall_level == 1 and gm.player_sect.gold == gold_before_build - 100, "팝업에서 연공실 짓기")
	_check(hub.facilities_label.text.contains("연공실 Lv.1"), "경영 화면 시설 표시 갱신")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(self, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_economy_flow"] = true
