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
	# 오토로드의 _ready()는 첫 프레임에 실행되므로 런타임 검사는 그 뒤로 미룬다.
	process_frame.connect(_run_runtime_tests, CONNECT_ONE_SHOT)


func _run_runtime_tests() -> void:
	_test_turn_loop()
	_test_start_new_game()
	await _test_scene_navigation()
	await _test_combat_flow()

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
