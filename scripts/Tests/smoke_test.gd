extends SceneTree

## 헤드리스 스모크 테스트.
## 실행: godot --headless --path . -s res://scripts/Tests/smoke_test.gd

const _SaveManager = preload("res://scripts/Systems/save_manager.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

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
var _checks: int = 0


func _initialize() -> void:
	_test_scenes_load()
	_test_level_curve()
	_test_gain_experience()
	_test_martial_art_round_trip()
	_test_old_save_without_martial_arts()
	_test_starting_roles()
	_test_combat_outcomes()
	_test_combat_events()
	_test_event_definitions()
	_test_event_validation()
	_test_event_conditions()
	_test_event_branches()
	_test_event_mod_folder()
	# 오토로드의 _ready()는 첫 프레임에 실행되므로 런타임 검사는 그 뒤로 미룬다.
	process_frame.connect(_run_runtime_tests, CONNECT_ONE_SHOT)


func _run_runtime_tests() -> void:
	_test_turn_loop()
	_test_start_new_game()
	await _test_scene_navigation()
	await _test_combat_flow()
	await _test_event_popup_choices()

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


func _test_level_curve() -> void:
	_check(CharacterData.get_experience_for_level(1) == 0, "Lv.1 요구 경험치 0")
	_check(CharacterData.get_experience_for_level(2) == 50, "Lv.2 요구 경험치 50")
	_check(CharacterData.get_experience_for_level(5) == 500, "Lv.5 요구 경험치 500")


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


func _test_old_save_without_martial_arts() -> void:
	var restored: CharacterData = _SaveManager.deserialize_character({"display_name": "구버전"})
	_check(restored.martial_arts.is_empty(), "구버전 세이브(무공 필드 없음) 호환")


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


## 각 화면을 실제로 띄워 @onready 노드 경로와 시그널 연결이 깨지지 않았는지 확인한다.
func _test_scene_navigation() -> void:
	for path in [
		SceneRouter.MAIN_MENU, SceneRouter.NEW_GAME, SceneRouter.HUB,
		SceneRouter.MARTIAL_ART, SceneRouter.SECT_WAR, SceneRouter.ENDING,
		SceneRouter.HELP, SceneRouter.COMBAT,
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


func _test_combat_events() -> void:
	var st: Dictionary = _make_combat_state()
	var result: Dictionary = EventManager.resolve_choice(
		"night_bandits", 0, st["character"], st["sect"], st["relationships"], st["flags"]
	)
	var setup: CombatSetup = result.get("combat")
	_check(setup != null and setup.enemies.size() == 3, "야습 도적: 싸우기 선택 시 3인 전투 예약")
	result = EventManager.resolve_choice(
		"night_bandits", 1, st["character"], st["sect"], st["relationships"], st["flags"]
	)
	_check(not result.has("combat"), "야습 도적: 피하기 선택 시 전투 없음")
	result = EventManager.resolve_choice(
		"rival_duel", 0, st["character"], st["sect"], st["relationships"], st["flags"]
	)
	_check(result.has("combat") and result["combat"].id == "rival_duel", "라이벌의 도전: 결투 예약")


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
	_check(enemies[0].max_hp == int(full_hp * 0.5), "도적 체력 배율 적용")

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
