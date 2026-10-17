extends "res://scripts/Tests/test_base.gd"

## 스모크 테스트 — 시나리오와 엔딩
## 실행 순서는 smoke_test.gd의 INIT_SEQUENCE·RUNTIME_SEQUENCE가 정한다.


func _test_scenario_data() -> void:
	var scenarios: Array[Dictionary] = ScenarioManager.list_scenarios()
	var dir_count: int = DirAccess.get_directories_at(ScenarioManager.SCENARIO_DIR).size()
	_check(scenarios.size() == dir_count and dir_count >= 3, "시나리오 %d개 모두 검증 통과" % dir_count)
	# 처음 하는 사람이 먼저 보도록 입문 수련이 맨 위, 그다음이 기본 시나리오
	_check(scenarios[0]["id"] == "tutorial" and scenarios[1]["id"] == ScenarioManager.DEFAULT_ID, "입문 수련이 첫 번째, 기본 시나리오가 두 번째")

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
	SceneRouter.goto(tree, SceneRouter.NEW_GAME)
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
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
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
	var saved_map: Dictionary = EventManager.map_state
	var saved_player_sect: String = EventManager.player_sect_id

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
		"conquer_world": func(st: Dictionary) -> void:
			st["character"].role = CharacterData.Role.LEADER
			st["sect"].id = "qingyun"
			EventManager.player_sect_id = st["sect"].id
			var state: Dictionary = WorldMap.create_state([st["sect"].id])
			for region in WorldMap.get_regions().slice(0, 12):
				state["owners"][region["id"]] = st["sect"].id
			EventManager.map_state = state,
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
		EventManager.map_state = {}
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
	EventManager.map_state = saved_map
	EventManager.player_sect_id = saved_player_sect
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

	SceneRouter.goto(tree, SceneRouter.ENDING)
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
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_final_ending_flow"] = true


## 입문 수련: 처음부터 수료까지 길잡이 12단계를 차례로 따라간다.
func _test_tutorial_scenario() -> void:
	var gm: Node = root.get_node("GameManager")
	_clear_test_saves()
	gm.start_new_game("입문", "leader", "tutorial")
	_check(gm.pending_event.get("id", "") == "tut_01_hub", "입문 수련: 시작하자마자 첫 길잡이")
	_check(not gm.story_flags.get("tutorial", false), "입문 수련: 일반 길잡이 플래그는 켜지 않음")
	_check(ScenarioRules.time_limit_years() == 4 and gm.world_sects.size() == 2, "입문 수련: 4년, 세력 둘")
	var gold: int = gm.player_sect.gold
	gm.resolve_pending_event(0)
	_check(gm.player_sect.gold == gold + 200, "① 수련 자금")

	# [기연 id, 고를 선택지]. 서고를 확장하지 않았으므로 ③은 안내형(hint)이 나온다.
	var steps: Array = [
		["tut_02_facility", 0], ["tut_03_roster_hint", 0], ["tut_04_event", 0], ["tut_05_combat", 0],
		["tut_06_martial", 0], ["tut_07_bond", 0], ["tut_08_defense", 0], ["tut_09_diplomacy", 0],
		["tut_10_war", 0], ["tut_11_roles", 0], ["tut_12_graduate", 0],
	]
	var heukpung: SectData = gm.get_world_sect("heukpung")
	var heukpung_disciples: int = heukpung.disciple_count
	var combats: int = 0
	for step in steps:
		var seen: String = ""
		for i in 3:
			gm.advance_turn()
			seen = gm.pending_event.get("id", "")
			if not seen.is_empty():
				break
		if seen != step[0]:
			_check(false, "입문 수련: %s 대신 %s (%d년 %s)" % [step[0], seen, gm.current_year, gm.get_current_season()])
			break
		gm.resolve_pending_event(step[1])
		if gm.pending_combat != null:
			combats += 1
			gm.finish_combat(CombatManager.Outcome.VICTORY)
	_check(gm.player_sect.library_level >= 2, "③ 서고를 확장하지 않았으면 길잡이가 대신 확장")
	_check(combats == 2, "⑤ 비무와 ⑧ 방어전 전투가 시작됨 (%d번)" % combats)
	_check(gm.player_character.knows_martial_art("preset_earth_life_palm"), "⑥ 무공 전수받음")
	_check(RelationshipManager.get_bond_with(gm.player_relationships, "npc_swallow") != null, "⑦ 연소화와 인연")
	_check(heukpung.disciple_count < heukpung_disciples and heukpung.attitude < 0, "⑩ 흑풍채가 약해지고 적대")
	_check(gm.current_ending_id == "tutorial_complete" and gm.is_game_over(), "⑫ 수료하면 입문 수료 엔딩으로 끝남")

	# 새 게임 화면: 입문 수련을 고르면 일반 길잡이 선택이 숨는다.
	SceneRouter.goto(tree, SceneRouter.NEW_GAME)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	_check(screen._selected_scenario.get("id", "") == "tutorial" and not screen.tutorial_check.visible, "새 게임 화면: 입문 수련이 기본 선택, 길잡이 선택 숨김")
	screen.scenario_list.select(1)
	screen._on_scenario_selected(1)
	_check(screen.tutorial_check.visible, "새 게임 화면: 다른 시나리오는 길잡이 선택 보임")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_clear_test_saves()
	_completed["_test_tutorial_scenario"] = true
