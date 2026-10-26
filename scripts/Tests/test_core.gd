extends "res://scripts/Tests/test_base.gd"

## 스모크 테스트 — 기본: 씬 로드, 성장, 저장본 기초, 계절 진행, 씀씀이·게임오버, 경제
## 실행 순서는 smoke_test.gd의 INIT_SEQUENCE·RUNTIME_SEQUENCE가 정한다.


func _test_scenes_load() -> void:
	# 앱 아이콘: 프로젝트 아이콘과 내보내기 프리셋이 가리키는 아이콘 파일이 모두 있다
	var icon: String = str(ProjectSettings.get_setting("application/config/icon", ""))
	_check(icon.begins_with("res://assets/icon/") and ResourceLoader.exists(icon), "앱 아이콘: %s" % icon)
	var presets := ConfigFile.new()
	_check(presets.load("res://export_presets.cfg") == OK, "내보내기 프리셋 읽기")
	var icon_keys: Array = []
	for section in presets.get_sections():
		for key in presets.get_section_keys(section):
			if key.contains("icon") and presets.get_value(section, key) is String and str(presets.get_value(section, key)).begins_with("res://"):
				icon_keys.append(key)
				_check(FileAccess.file_exists(presets.get_value(section, key)), "내보내기 아이콘 파일: %s" % key)
	_check(icon_keys.size() >= 8, "안드로이드·웹·윈도우 아이콘 지정 (%d개)" % icon_keys.size())
	# 앱 안 업데이트(AppUpdater): Android는 릴리스 확인·받기에 인터넷, 받은 APK 설치 화면에 설치 요청 권한이 필요하다
	_check(presets.get_value("preset.0", "platform") == "Android" and presets.get_value("preset.0.options", "permissions/internet", false) == true
		and presets.get_value("preset.0.options", "permissions/request_install_packages", false) == true, "Android 권한: 인터넷·앱 설치 요청 (업데이트)")
	for path in MAIN_SCENES:
		var scene: PackedScene = load(path)
		_check(scene != null and scene.can_instantiate(), "씬 로드: %s" % path)
	_completed["_test_scenes_load"] = true


func _test_level_curve() -> void:
	_check(CharacterData.get_experience_for_level(1) == 0, "경지 1 요구 수련 0")
	_check(CharacterData.get_experience_for_level(2) == 50, "경지 2 요구 수련 50")
	_check(CharacterData.get_experience_for_level(5) == 500, "경지 5 요구 수련 500")
	_completed["_test_level_curve"] = true


func _test_gain_experience() -> void:
	var character := CharacterData.new()
	var base_strength: int = character.strength
	var base_internal: int = character.internal_energy_max
	var signal_levels: Array[int] = []
	character.leveled_up.connect(func(new_level: int) -> void: signal_levels.append(new_level))

	_check(character.gain_experience(49) == 0 and character.level == 1, "수련 49: 경지 유지")
	_check(character.gain_experience(1) == 1 and character.level == 2, "수련 50: 경지 2 도달")
	_check(character.gain_experience(450) == 3 and character.level == 5, "누적 500: 경지 5 도달 (한 번에 여러 경지)")
	_check(signal_levels == [2, 3, 4, 5], "leveled_up 시그널이 경지마다 발생")
	_check(
		character.strength == base_strength + 4 * _Balance.LEVEL_UP_STAT_GAIN,
		"경지업 자질 가산 적용"
	)
	_check(
		character.internal_energy_max == base_internal + 4 * _Balance.LEVEL_UP_INTERNAL_GAIN,
		"경지업 내공 가산 적용"
	)
	_check(character.gain_experience(0) == 0 and character.gain_experience(-5) == 0, "0/음수 수련 무시")

	character.gain_experience(1_000_000)
	_check(character.level == _Balance.MAX_LEVEL, "최대 단계 제한")
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

	# JSON 문자열을 거쳐 실제 저장본 파일과 같은 경로로 검증
	var json_text: String = JSON.stringify(_SaveManager.serialize_character(character))
	var restored: CharacterData = _SaveManager.deserialize_character(JSON.parse_string(json_text))

	_check(restored.martial_arts.size() == 2, "저장본/로드 후 무공 2개 유지")
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
		"창안 무공 필드 복원"
	)
	_check(restored.knows_martial_art("custom_heal"), "복원된 무공 조회")
	_completed["_test_martial_art_round_trip"] = true


func _test_old_save_without_martial_arts() -> void:
	var restored: CharacterData = _SaveManager.deserialize_character({"display_name": "구버전"})
	_check(restored.martial_arts.is_empty(), "구버전 저장본(무공 필드 없음) 호환")
	_completed["_test_old_save_without_martial_arts"] = true


func _test_starting_roles() -> void:
	for entry in StartingRoles.ROLES:
		var character: CharacterData = StartingRoles.create_character(entry["id"], "")
		_check(
			character.role == entry["role"]
			and character.display_name == entry["default_name"]
			and character.internal_energy_current == character.internal_energy_max,
			"시작 신분 생성: %s" % entry["title"]
		)
	var named: CharacterData = StartingRoles.create_character("wanderer", "  연남천 ")
	_check(named.display_name == "연남천", "입력한 이름 사용 (앞뒤 공백 제거)")
	var unknown: CharacterData = StartingRoles.create_character("no_such_role", "")
	_check(unknown.role == CharacterData.Role.YOUNG_DISCIPLE, "알 수 없는 신분 id는 기본 신분")
	var leader: CharacterData = StartingRoles.create_character("leader", "")
	_check(leader.level > 1, "문주는 수련을 갖고 시작")
	_completed["_test_starting_roles"] = true


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
	_check(game_manager.player_character.level > start_level, "연간 수련으로 경지 상승")
	_completed["_test_turn_loop"] = true


func _test_start_new_game() -> void:
	var game_manager: Node = root.get_node_or_null("GameManager")
	if game_manager == null:
		return
	game_manager.story_flags["dirty"] = true
	game_manager.start_new_game("백리운", "leader")
	_check(game_manager.is_game_active, "새 게임 시작 후 진행 중 상태")
	_check(game_manager.player_character.display_name == "백리운", "새 게임 이름 적용")
	_check(game_manager.player_character.role == CharacterData.Role.LEADER, "새 게임 신분 적용")
	_check(game_manager.player_sect.leader_name == "백리운", "문주 시작 시 문파 문주 이름 갱신")
	_check(game_manager.player_sect.gold == 400, "신분별 문파 초기 자원 적용")
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
		SceneRouter.goto(tree, path)
		await process_frame
		await process_frame
		_check(
			current_scene != null and current_scene.scene_file_path == path,
			"화면 전환: %s" % path.get_file()
		)

	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	SceneRouter.goto(tree, SceneRouter.HELP)
	await process_frame
	SceneRouter.back(tree, SceneRouter.MAIN_MENU)
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.HUB, "도움말에서 직전 화면(경영)으로 복귀")
	_completed["_test_scene_navigation"] = true


func _test_upkeep() -> void:
	var sect := SectData.new()
	sect.disciple_count = 10
	sect.library_level = 2
	sect.treasury_level = 3
	_check(sect.get_food_upkeep() == 10 * _Balance.FOOD_PER_DISCIPLE, "식량 씀씀이 = 제자 수 × 단가")
	_check(
		sect.get_gold_upkeep() == 10 * _Balance.GOLD_PER_DISCIPLE + 3 * _Balance.FACILITY_UPKEEP_GOLD,
		"은자 씀씀이 = 제자 + 전각 단계"
	)

	# 정상 납부: 차감, 연속 부족 초기화
	sect.food = 100
	sect.gold = 100
	sect.shortage_seasons = 2
	var result: Dictionary = SectManager.pay_upkeep(sect)
	_check(
		not result["shortage"] and sect.food == 80 and sect.gold == 100 - sect.get_gold_upkeep()
		and sect.shortage_seasons == 0,
		"씀씀이 정상 납부"
	)

	# 식량 부족: 식량 0, 부족분에 비례한 제자 이탈
	sect.food = 2  # 씀씀이 20 → 18 부족 → 18/6 = 3명 이탈
	sect.gold = 100
	result = SectManager.pay_upkeep(sect)
	_check(
		result["shortage"] and sect.food == 0 and result["deserted"] == 3 and sect.disciple_count == 7
		and sect.shortage_seasons == 1,
		"식량 부족: 제자 3명 이탈, 연속 부족 1"
	)

	# 은자 부족: 은자 0, 명성 하락
	sect.food = 1000
	sect.gold = 0
	var rep_before: int = sect.reputation
	result = SectManager.pay_upkeep(sect)
	_check(
		result["shortage"] and sect.gold == 0
		and sect.reputation == rep_before - _Balance.GOLD_SHORTAGE_REPUTATION_LOSS
		and sect.shortage_seasons == 2,
		"은자 부족: 명성 하락, 연속 부족 2"
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
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame

	# 이미 2계절 연속 부족인 상태에서 식량이 바닥난 채 여름을 맞는다
	# (여름 식량 수입 ~35 < 제자 30명 씀씀이 60 → 세 번째 부족)
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
	_check(gm.last_turn_report.contains("씀씀이"), "계절 보고에 씀씀이 표시")

	var year: int = gm.current_year
	var season: int = gm.current_season_index
	gm.advance_turn()
	_check(gm.current_year == year and gm.current_season_index == season, "게임오버 후 계절 진행 불가")
	_check(not gm.start_legacy_succession()["success"], "게임오버 후 세대 전승 불가")

	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.ENDING, "게임오버 시 결말 화면으로 이동")
	_check(
		not current_scene.get_node("%SuccessionButton").visible
		and current_scene.get_node("%BackButton").text == "첫 화면으로",
		"게임오버 화면: 전승 버튼 숨김, 첫 화면으로 이동"
	)

	# 경영 화면으로 돌아가려 해도 결말 화면으로 되돌린다
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.ENDING, "게임오버 상태에서 경영 화면 진입 차단")

	# 저장본에도 게임오버가 남는다
	gm._apply_save_data(JSON.parse_string(JSON.stringify({
		"game_over_id": gm.game_over_id,
		"character": _SaveManager.serialize_character(gm.player_character),
		"sect": _SaveManager.serialize_sect(gm.player_sect),
	})))
	_check(gm.game_over_id == "famine_collapse", "게임오버 상태 저장/복원")

	gm.start_new_game("재시작", "young_disciple")
	_check(not gm.is_game_over() and gm.is_game_active, "새 게임으로 게임오버 해제")
	_completed["_test_game_over_flow"] = true


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
	_check(summer["gold"] == spring["gold"] + 10, "여름 은자 가산")
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

	# 전각
	sect = SectData.new()
	_check(SectManager.get_upgrade_cost(sect, "library") == 80, "서고 첫 확장 80")
	sect.gold = 10000
	SectManager.upgrade_facility(sect, "library")
	_check(sect.library_level == 2 and SectManager.get_upgrade_cost(sect, "library") == 120, "확장할수록 비용 상승 (120)")
	_check(sect.apothecary_level == 0 and SectManager.get_upgrade_cost(sect, "apothecary") == 90, "약방은 0에서 짓기")
	var upkeep_before: int = sect.get_gold_upkeep()
	var result: Dictionary = SectManager.upgrade_facility(sect, "apothecary")
	_check(result["success"] and sect.apothecary_level == 1 and result["message"].contains("지었습니다"), "약방 짓기")
	_check(sect.get_gold_upkeep() == upkeep_before + _Balance.FACILITY_UPKEEP_GOLD, "새 전각도 씀씀이 증가")
	for i in 5:
		SectManager.upgrade_facility(sect, "apothecary")
	_check(sect.apothecary_level == 3 and SectManager.get_upgrade_cost(sect, "apothecary") == -1, "약방 최대 단계 3")
	_check(not SectManager.upgrade_facility(sect, "apothecary")["success"], "최고 수준이면 확장 불가")
	sect.gold = 10
	_check(not SectManager.upgrade_facility(sect, "treasury")["success"], "은자 부족이면 확장 불가")

	var restored: SectData = _SaveManager.deserialize_sect(JSON.parse_string(JSON.stringify(_SaveManager.serialize_sect(sect))))
	_check(restored.apothecary_level == 3 and restored.library_level == 2, "새 전각 저장/복원")
	_completed["_test_economy_rules"] = true


func _test_economy_flow() -> void:
	var gm: Node = root.get_node("GameManager")

	# 무행동 10년: 은자가 시작값의 2배를 넘지 않는다
	gm.start_new_game("무위", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	var start_gold: int = gm.player_sect.gold
	for i in 40:
		gm.advance_turn()
		gm.pending_combat = null
	_check(gm.player_sect.gold <= start_gold * 2, "무행동 10년 은자 %d (시작 %d의 2배 이하)" % [gm.player_sect.gold, start_gold])
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
	_check(gm.player_character.internal_energy_current == regen, "약방 경지 2: 계절 내공 회복 %d" % regen)
	_check(gm.player_character.experience >= exp_before + _Balance.MEDITATION_EXP_PER_LEVEL, "연공실: 계절 수련")
	_check(gm.last_turn_report.contains("약방") and gm.last_turn_report.contains("연공실"), "계절 보고에 전각 효과")

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
	_check(not gm.buy_elixir()["success"], "은자가 부족하면 영약 불가")

	# 해가 바뀌면 정산 문구
	gm.start_new_game("정산", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	gm.player_sect.gold = 2000
	for i in 4:
		gm.advance_turn()
	_check(gm.last_turn_report.contains("새해 정산") and gm.last_turn_report.contains("은자 -"), "새해 정산 보고")

	# 경영 화면: 전각 관리 창 (막내 제자는 전각을 확장할 수 없으므로 문주로 시험)
	gm.start_new_game("전각", "leader", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	_check(hub.gold_label.text.contains("다음 계절"), "경영 화면에 예상 수지 표시")
	hub._on_facility_pressed()
	await process_frame
	var popup: Node = hub.facility_popup
	_check(popup.visible and popup._rows.get_child_count() == SectManager.get_facility_ids().size(), "전각 관리 창: 전각 5종")
	var gold_before_build: int = gm.player_sect.gold
	popup._on_upgrade_pressed("meditation_hall")
	_check(gm.player_sect.meditation_hall_level == 1 and gm.player_sect.gold == gold_before_build - 100, "창에서 연공실 짓기")
	_check(hub.facilities_label.text.contains("연공실 1단계"), "경영 화면 전각 표시 갱신")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_economy_flow"] = true


## 내보낸 빌드 자체 점검(--self-check)이 편집기 환경에서도 통과한다.
func _test_self_check() -> void:
	var result: Dictionary = SelfCheck.run()
	_check(result["ok"], "자체 점검 통과\n    %s" % "\n    ".join(result["lines"]))
	_check(not SelfCheck.requested(), "테스트 실행에는 --self-check 인자가 없음")
	_completed["_test_self_check"] = true
