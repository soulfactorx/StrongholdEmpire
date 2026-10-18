extends "res://scripts/Tests/test_base.gd"

## 스모크 테스트 — 기연: 정의·검증·조건·분기·모드 폴더·문법 확장·진행 기록, 스토리 아크
## 실행 순서는 smoke_test.gd의 INIT_SEQUENCE·RUNTIME_SEQUENCE가 정한다.


func _test_event_definitions() -> void:
	# 하위 폴더(스토리 아크)까지 센다.
	var json_count: int = EventManager.collect_json_files(EventManager.EVENTS_DIR).size()
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
	SceneRouter.goto(tree, SceneRouter.HUB)
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
		"잘못된 관계 유형": {"conditions": [{"type": "relationship_type", "target": "npc_rival", "bond_type": "LOVER"}]},
		"잘못된 역할 기록": {"conditions": [{"type": "role_history", "role": "EMPEROR"}]},
		"명부에 없는 인물과 관계": {"choices": [{"label": "a", "effects": [{"type": "add_relationship", "target": "npc_nobody", "bond_type": "ROMANCE"}]}]},
		"없는 무공 습득": {"choices": [{"label": "a", "effects": [{"type": "learn_art", "art": "no_art"}]}]},
		"없는 엔딩": {"choices": [{"label": "a", "effects": [{"type": "end_game", "ending": "no_ending"}]}]},
		"음수 가중치": {"weight": -1},
	}
	for label in bad_cases:
		_check(not EventManager.validate_event_dict(_event_with(bad_cases[label])).is_empty(), "새 문법 오류 검출: %s" % label)
	_completed["_test_event_grammar_validation"] = true


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


## 스토리 아크 한 단계: 기연이 후보에 오를 때까지 계절을 넘기고, 정한 선택지와 전투 결과를 적용한다.
## step: [기연 id, 선택지 번호, (선택) 전투 결과 CombatManager.Outcome]
func _arc_step(gm: Node, step: Array) -> bool:
	var event_id: String = step[0]
	var found: bool = false
	for i in 40:
		var candidates: Array[EventData] = EventManager.get_candidates(
			gm.player_character, gm.player_sect, gm.player_relationships,
			gm.get_current_season(), gm.triggered_event_ids, gm.story_flags
		)
		if candidates.any(func(e: EventData) -> bool: return e.id == event_id):
			found = true
			break
		gm.advance_turn()
		gm.pending_event.clear()
	if not found:
		_check(false, "아크 기연 발생: %s (%s %d년 %s)" % [event_id, ScenarioManager.current_id, gm.current_year, gm.get_current_season()])
		return false
	var event: EventData = EventManager.get_event(event_id)
	if not event.can_repeat:
		gm.triggered_event_ids.append(event_id)
	var result: Dictionary = EventManager.resolve_choice(
		event_id, step[1], gm.player_character, gm.player_sect, gm.player_relationships, gm.story_flags
	)
	if result.has("combat"):
		var outcome: CombatManager.Outcome = step[2] if step.size() > 2 else CombatManager.Outcome.VICTORY
		CombatManager.apply_outcome(result["combat"], outcome, gm.player_character, gm.player_sect, gm.player_relationships, gm.story_flags)
	if result.has("end_game"):
		gm._force_end(result["end_game"])
	gm._check_end_states()
	return true


func _run_arc(gm: Node, steps: Array, label: String) -> bool:
	for step in steps:
		if not _arc_step(gm, step):
			_check(false, "아크 진행 중단: %s (%s)" % [label, step[0]])
			return false
	return true


func _test_story_arcs() -> void:
	var gm: Node = root.get_node("GameManager")
	var V: CombatManager.Outcome = CombatManager.Outcome.VICTORY
	var D: CombatManager.Outcome = CombatManager.Outcome.DEFEAT

	# 아크 기연은 data/events/arcs/의 하위 폴더에서 읽는다.
	for arc in ["revenge", "succession", "love", "spy", "cheonma"]:
		var files: PackedStringArray = EventManager.collect_json_files(EventManager.EVENTS_DIR.path_join("arcs").path_join(arc))
		_check(files.size() >= 4 and files.size() <= 8, "아크 %s: 기연 %d개 (4~8)" % [arc, files.size()])
	var manual_endings: Array = ["mercy_blade", "usurper", "marriage_alliance", "hidden_valley", "fallen_blossom", "web_of_shadows", "demon_slayer", "fallen_sect"]
	for ending_id in manual_endings:
		_check(EndingManager.has_ending(ending_id), "아크 엔딩 존재: %s" % ending_id)

	# ── 복수와 용서: 패배 후 재도전 → 용서 → 자비의 검 ──
	_new_quiet_game(gm, "young_disciple")
	if _run_arc(gm, [
		["arc_revenge_ambush", 0], ["arc_revenge_trail", 1], ["arc_revenge_confrontation", 0, D],
		["arc_revenge_rematch", 0, V], ["arc_revenge_judgment", 1],
	], "복수와 용서"):
		var blade: RelationshipData = RelationshipManager.get_bond_with(gm.player_relationships, "npc_shadow_blade")
		_check(blade != null and blade.bond_type == RelationshipData.BondType.BLOOD_OATH, "복수: 용서하면 원한이 혈맹으로")
		_run_arc(gm, [["arc_revenge_mercy", 0]], "복수와 용서")
		_check(gm.current_ending_id == "mercy_blade", "복수: 자비의 검 엔딩")
	# 남궁휘와 함께 귀영을 꺾고 배후의 마진까지
	_new_quiet_game(gm, "young_disciple")
	var heukpung: SectData = gm.get_world_sect("heukpung")
	var heukpung_disciples: int = heukpung.disciple_count
	if _run_arc(gm, [
		["arc_revenge_ambush", 1], ["arc_revenge_trail", 0], ["arc_revenge_confrontation", 1, V],
		["arc_revenge_judgment", 2], ["arc_revenge_mastermind", 0, V], ["arc_revenge_chief_aftermath", 0],
	], "복수: 배후 처단"):
		_check(gm.story_flags.get("arc_revenge_closed", false) and heukpung.disciple_count < heukpung_disciples, "복수: 마진 처단 후 흑풍채 약화")
		_check(gm.current_ending_id.is_empty(), "복수: 배후 처단 길은 엔딩 없이 계속")

	# ── 승계와 배신: 반란 진압 → 후계 지명 ──
	_new_quiet_game(gm, "young_disciple")
	if _run_arc(gm, [
		["arc_succession_illness", 1], ["arc_succession_conspiracy", 0], ["arc_succession_civil_war", 0, V],
		["arc_succession_heir", 0],
	], "승계와 배신"):
		gm.refresh_role_transitions()
		var roles: Array = gm.pending_role_transitions.map(func(o: Dictionary) -> int: return o["role"])
		_check(gm.story_flags.get("arc_succession_heir", false) and roles.has(CharacterData.Role.MANAGER), "승계: 후계자는 중간관리자 승진 가능")
	# 진무겸에 가담해 스승을 친다 → 찬탈자
	_new_quiet_game(gm, "young_disciple")
	var morality: int = gm.player_character.morality
	if _run_arc(gm, [
		["arc_succession_illness", 0], ["arc_succession_conspiracy", 1], ["arc_succession_traitor_night", 0, V],
		["arc_succession_usurper", 0],
	], "승계: 찬탈"):
		_check(gm.current_ending_id == "usurper" and gm.player_character.morality <= morality - 25, "승계: 찬탈자의 옥좌 엔딩")
	# 내분에서 지면 산문을 되찾는 기연이 반복된다
	_new_quiet_game(gm, "young_disciple")
	_run_arc(gm, [
		["arc_succession_illness", 1], ["arc_succession_conspiracy", 2], ["arc_succession_civil_war", 0, D],
		["arc_succession_retake", 0, D], ["arc_succession_retake", 0, V], ["arc_succession_heir", 1],
	], "승계: 재도전")
	_check(gm.story_flags.get("arc_succession_heir", false), "승계: 두 번 진 뒤 되찾고 후계 지명")

	# ── 금단의 사랑: 청혼 → 시험 승리 → 혼례 ──
	_new_quiet_game(gm, "young_disciple")
	var namgung: SectData = gm.get_world_sect("namgung")
	if _run_arc(gm, [
		["arc_love_meeting", 0], ["arc_love_letters", 0], ["arc_love_opposition", 0], ["arc_love_trial", 0, V],
		["arc_love_wedding", 0],
	], "금단의 사랑"):
		_check(gm.current_ending_id == "marriage_alliance" and namgung.attitude >= 20, "사랑: 두 가문의 맹약 엔딩")
	# 도주 → 추격전 패배 → 꺾인 매화
	_new_quiet_game(gm, "young_disciple")
	if _run_arc(gm, [
		["arc_love_meeting", 0], ["arc_love_letters", 0], ["arc_love_opposition", 1], ["arc_love_pursuit", 0, D],
		["arc_love_tragedy", 0],
	], "사랑: 비극"):
		_check(gm.current_ending_id == "fallen_blossom", "사랑: 꺾인 매화 엔딩")
	# 도주 → 추격전 승리 → 은거곡 (생을 마치는 엔딩)
	_new_quiet_game(gm, "young_disciple")
	if _run_arc(gm, [
		["arc_love_meeting", 0], ["arc_love_letters", 0], ["arc_love_opposition", 1], ["arc_love_pursuit", 0, V],
		["arc_love_valley", 0],
	], "사랑: 은거"):
		_check(gm.current_ending_id == "hidden_valley" and gm.story_flags.get("life_ended", false), "사랑: 은거곡 엔딩은 생을 마침")

	# ── 스파이 이중생활: 세 번의 위기 → 양쪽을 속인다 → 거미줄의 주인 ──
	_new_quiet_game(gm, "young_disciple")
	gm.apply_role_transition(CharacterData.Role.SPY)
	gm.do_role_action("intel", "namgung")
	if _run_arc(gm, [
		["arc_spy_contact", 0], ["arc_spy_crisis1", 0], ["arc_spy_crisis2", 0, V], ["arc_spy_crisis3", 1, V],
		["arc_spy_choice", 2], ["arc_spy_web", 0],
	], "스파이 이중생활"):
		_check(gm.story_flags.get("arc_spy_rescued", false) and gm.story_flags.get("arc_spy_enforcer_slain", false), "스파이: 구출·결판 승리 기록")
		_check(gm.current_ending_id == "web_of_shadows", "스파이: 거미줄의 주인 엔딩")
	# 집법당주에게 지면 정체가 드러나 처형된다
	_new_quiet_game(gm, "young_disciple")
	gm.apply_role_transition(CharacterData.Role.SPY)
	gm.do_role_action("intel", "namgung")
	if _run_arc(gm, [
		["arc_spy_contact", 1], ["arc_spy_crisis1", 1], ["arc_spy_crisis2", 1], ["arc_spy_crisis3", 1, D],
	], "스파이: 발각"):
		_check(gm.current_ending_id == "tragic_execution", "스파이: 결판에서 지면 비극적 처형")
	# 충성을 택하면 임무 완료로 복귀할 수 있다
	_new_quiet_game(gm, "young_disciple")
	gm.apply_role_transition(CharacterData.Role.SPY)
	gm.do_role_action("intel", "namgung")
	_run_arc(gm, [
		["arc_spy_contact", 0], ["arc_spy_crisis1", 0], ["arc_spy_crisis2", 1], ["arc_spy_crisis3", 1, V], ["arc_spy_choice", 0],
	], "스파이: 충성")
	gm.refresh_role_transitions()
	var spy_roles: Array = gm.pending_role_transitions.map(func(o: Dictionary) -> int: return o["role"])
	_check(spy_roles.has(CharacterData.Role.MANAGER) and gm.current_ending_id.is_empty(), "스파이: 충성하면 복귀 경로")

	# ── 마교 대침공: 연합 → 혈영 격퇴 → 방어전 → 천마 격파 ──
	_new_quiet_game(gm, "young_disciple")
	EventManager.set_flag(gm.story_flags, "cheonma_letter_refused")
	if _run_arc(gm, [
		["arc_cheonma_omen", 0], ["arc_cheonma_council", 0], ["arc_cheonma_assassin", 0, V],
		["arc_cheonma_siege_allied", 0, V], ["arc_cheonma_final", 0, V], ["arc_cheonma_triumph", 0],
	], "마교 대침공"):
		_check(gm.current_ending_id == "demon_slayer" and gm.current_year >= 5, "마교: 천마를 벤 영웅 엔딩")
	# 홀로 버티다 산문이 무너진다
	_new_quiet_game(gm, "young_disciple")
	EventManager.set_flag(gm.story_flags, "cheonma_letter_refused")
	if _run_arc(gm, [
		["arc_cheonma_omen", 1], ["arc_cheonma_assassin", 1], ["arc_cheonma_siege_alone", 0, D], ["arc_cheonma_fall", 0],
	], "마교: 함락"):
		_check(gm.current_ending_id == "fallen_sect", "마교: 무너진 산문 엔딩")
	# 밀약을 맺었거나 다른 시나리오면 시작하지 않는다
	gm.start_new_game("다른 시나리오", "young_disciple", "gangho_100", {"event_rate": 0.0})
	EventManager.set_flag(gm.story_flags, "cheonma_letter_refused")
	gm.current_year = 6
	_check(not EventManager.conditions_met(EventManager.get_event("arc_cheonma_omen").conditions, gm.player_character, gm.player_sect, gm.player_relationships, "봄", gm.story_flags), "마교 대침공 아크는 천하대란 시나리오 전용")
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	_new_quiet_game(gm, "young_disciple")
	EventManager.set_flag(gm.story_flags, "cheonma_letter_refused")
	EventManager.set_flag(gm.story_flags, "cheonma_pact")
	gm.current_year = 6
	gm._sync_event_context()
	_check(not EventManager.conditions_met(EventManager.get_event("arc_cheonma_omen").conditions, gm.player_character, gm.player_sect, gm.player_relationships, "봄", gm.story_flags), "마교와 밀약했으면 대침공 아크 없음")
	_completed["_test_story_arcs"] = true
