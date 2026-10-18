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


# ── 메인 시나리오 「강호삼란」 ──

const SAGA_IDS: Array = ["saga_1_blood_moon", "saga_2_black_lotus", "saga_3_blue_sky"]


func gm() -> Node:
	return root.get_node("GameManager")


## 등장인물로 새 게임을 시작한다 (기연 확률 0: 우선 기연만 일어난다).
func _start_saga(scenario_id: String, npc_id: String) -> void:
	gm().start_new_game("", "young_disciple", scenario_id, {"event_rate": 0.0}, false, false, {"playable": npc_id})


## 등장인물로 계절을 넘기며 끝까지 플레이한다. plan: {기연 id: 선택지 글 앞부분}, 없는 기연은 보이는 마지막 선택지.
## outcomes: {기연 id: 전투 결과} (기본 승리). 일어난 기연 id 목록을 돌려준다.
## start_level을 주면 그 레벨로 시작한다 (수련으로 경지를 쌓은 셈).
func _play_saga(scenario_id: String, npc_id: String, plan: Dictionary, outcomes: Dictionary = {}, start_level: int = 0) -> Array:
	_start_saga(scenario_id, npc_id)
	if start_level > 0:
		gm().player_character.level = start_level
	var seen: Array = []
	for i in 40:
		if gm().is_game_over():
			break
		if gm().pending_event.is_empty():
			gm().advance_turn()
			continue
		var event: Dictionary = gm().pending_event
		seen.append(event["id"])
		# 계획에 없는 기연은 보이는 마지막 선택지 (대개 누구나 고를 수 있는 무난한 선택지)
		var shown: int = (event["choices"] as Array).size() - 1
		if plan.has(event["id"]):
			shown = -1
			var labels: Array = Array(event["choices"])
			for j in labels.size():
				if str(labels[j]).begins_with(plan[event["id"]]):
					shown = j
			if shown < 0:
				_check(false, "%s(%s): 「%s」 선택지가 보이지 않음 — 보이는 선택지 %s" % [scenario_id, npc_id, plan[event["id"]], labels])
				return seen
		var original: int = int(event["choice_map"][shown])
		gm().pending_event = {}
		var result: Dictionary = EventManager.resolve_choice(
			event["id"], original, gm().player_character, gm().player_sect, gm().player_relationships, gm().story_flags, str(event.get("subject", ""))
		)
		if result.has("combat"):
			CombatManager.apply_outcome(
				result["combat"], outcomes.get(event["id"], CombatManager.Outcome.VICTORY),
				gm().player_character, gm().player_sect, gm().player_relationships, gm().story_flags
			)
		if result.has("end_game"):
			gm()._force_end(result["end_game"])
		gm()._check_end_states()
		# 전투 결과로 이어지는 기연(승리·패배 뒤의 장면)은 다음 계절을 기다리지 않고 바로 확인한다.
		if not gm().is_game_over():
			gm()._try_trigger_event()
	return seen


func _test_main_saga_system() -> void:
	for scenario_id in SAGA_IDS:
		var scenario: Dictionary = ScenarioManager.get_scenario(scenario_id)
		_check(not scenario.is_empty(), "메인 시나리오 정의: %s" % scenario_id)
		ScenarioManager.activate(scenario_id)
		# 등장인물 데이터: 명부에 있고, 인연 대상도 명부에 있다. 이 시나리오의 기연과 엔딩만 읽는다.
		for entry in ScenarioManager.get_playables(scenario):
			_check(NpcRoster.has_npc(entry["npc"]), "%s 등장인물 명부: %s" % [scenario_id, entry["npc"]])
			for target in entry.get("bonds", {}):
				_check(NpcRoster.has_npc(target) and target != entry["npc"], "%s 등장인물 %s 인연 대상: %s" % [scenario_id, entry["npc"], target])
		_check(EventManager.get_event("rival_duel") == null and EventManager.get_event("arc_cheonma_omen") == null, "%s: 정한 공용 기연 폴더만 읽음" % scenario_id)
		_check(not EndingManager.has_ending("conquer_world"), "%s: 공용 엔딩을 읽지 않음" % scenario_id)
		for ending_id in scenario.get("victory_endings", []):
			_check(EndingManager.has_ending(ending_id), "%s 엔딩: %s" % [scenario_id, ending_id])

	# 남궁휘로 시작: 인물의 이름·초상화·소속·인연·플래그, 자기 자신과는 관계가 없다.
	_start_saga("saga_1_blood_moon", "npc_rival")
	var hero: CharacterData = gm().player_character
	_check(hero.display_name == "남궁휘" and hero.portrait_id == "npc_rival" and hero.level == 3, "등장인물: 이름·초상화·레벨")
	_check(hero.knows_martial_art("manual_namgung_plum_sword"), "등장인물: 시작 무공")
	_check(gm().player_sect.id == "namgung" and gm().player_npc_id == "npc_rival", "등장인물: 소속 문파")
	_check(gm().story_flags.get("playing_npc_rival", false) == true, "등장인물: playing_ 플래그")
	_check(_rel(gm(), "npc_namgung_lord") != null and _rel(gm(), "npc_namgung_lady") != null and _rel(gm(), "npc_rival") == null, "등장인물: 시작 인연 (자기 자신은 없음)")
	_check(hero.get_alignment() == "good" and hero.get_alignment_name() == "선(협객)", "성향: 도덕 66은 선")
	# 안내형 시나리오라 첫 기연(붉은 달)이 바로 뜬다. 남궁휘의 선택지와 장면 대사만 보인다.
	var opening: Dictionary = gm().pending_event
	_check(opening.get("id", "") == "s1_red_moon", "메인 시나리오: 시작하자마자 붉은 달")
	var labels: Array = Array(opening.get("choices", []))
	_check(labels.has("서신을 찢는다 — 정파는 무릎 꿇지 않는다") and not labels.has("교주의 명을 받든다"), "선택지 조건: 주인공별 선택지")
	_check(labels.size() == (opening["choice_map"] as Array).size() and labels.size() < EventManager.get_event("s1_red_moon").choices.size(), "선택지 조건: 보이는 것만 choice_map에")
	var text: String = str(opening.get("description", ""))
	_check(text.contains("남궁천: 천마가") and text.contains("남궁휘: 누이는 빠져") and not text.contains("위무량: 혈영"), "장면 대사: 주인공 대사와 only 줄")
	# 보이는 순번으로 고르면 원래 선택지가 적용된다.
	var morality: int = hero.morality
	gm().resolve_pending_event(labels.find("서신을 찢는다 — 정파는 무릎 꿇지 않는다"))
	_check(hero.morality == morality + 3 and gm().story_flags.get("s1_defiant", false), "choice_map: 보이는 순번 → 원래 선택지")

	# 혈영으로 시작: 무공·악 성향, 같은 기연의 다른 선택지
	_start_saga("saga_1_blood_moon", "npc_cheonma_envoy")
	_check(gm().player_character.get_alignment() == "evil" and gm().player_sect.id == "cheonma", "혈영: 악 성향, 천마신교")
	_check(Array(gm().pending_event.get("choices", [])).has("교주의 명을 받든다"), "혈영: 자기 선택지")
	_check(str(gm().pending_event.get("description", "")).contains("혈영: 명을 받듭니다"), "혈영: player 대사는 주인공 이름으로")
	# 저장·불러오기: 등장인물 id와 초상화가 이어진다.
	var state: Dictionary = gm()._build_save_state()
	gm().player_npc_id = ""
	gm()._apply_save_data(state)
	_check(gm().player_npc_id == "npc_cheonma_envoy" and gm().player_character.portrait_id == "npc_cheonma_envoy", "저장/불러오기: 등장인물")
	_check(ArtAssets.player_portrait(gm().player_character) == ArtAssets.portrait("npc_cheonma_envoy"), "주인공 초상화: 등장인물의 초상화")
	_completed["_test_main_saga_system"] = true


func _test_main_saga_paths() -> void:
	var D: CombatManager.Outcome = CombatManager.Outcome.DEFEAT
	var sid: String = "saga_1_blood_moon"
	# 남궁휘: 선의 길 → 남궁의 재건
	var seen: Array = _play_saga(sid, "npc_rival", {
		"s1_red_moon": "서신을 찢는다", "s1_hwi_shadow_of_father": "명을 따르고", "s1_alliance": "맹회 말석",
		"s1_hwi_rival": "웃으며", "s1_black_wind_offer": "사파와 손잡는", "s1_lady_and_shadow": "누이를 찾아가",
		"s1_hwi_sister_secret": "누이의 마음을", "s1_traitor_within": "의심을 접고", "s1_blood_night": "무너지는 서문",
		"s1_hwi_father_falls": "가문을", "s1_demon_reign": "저항한다", "s1_crossroads": "지켜야 할",
		"s1_finale_hwi": "남궁세가를",
	})
	_check(gm().current_ending_id == "s1_namgung_rebuilt" and gm().game_over_id == "scenario_complete", "1장 남궁휘: 남궁의 재건 (%s)" % [seen])
	_check(seen.find("s1_blood_night") > seen.find("s1_traitor_within") and seen.find("s1_traitor_within") > seen.find("s1_lady_and_shadow"), "1장: 연표 순서")
	# 남궁휘: 혈월의 밤 무모한 돌격 → 배드 엔딩
	_play_saga(sid, "npc_rival", {"s1_blood_night": "홀로 천마의", "s1_black_wind_offer": "사파와 손잡는"})
	_check(gm().current_ending_id == "s1_bad_sacrifice" and gm().game_over_id == "story_end", "1장 남궁휘: 혈월의 제물 (배드)")
	# 연소화: 마진의 금화를 받으면 흑풍의 덫
	_play_saga(sid, "npc_swallow", {"s1_so_majin_deal": "금화를", "s1_so_trap_springs": "끝까지"})
	_check(gm().current_ending_id == "s1_bad_black_wind_trap", "1장 연소화: 흑풍의 덫 (배드)")
	# 연소화: 피난민을 이끌어 강남으로
	_play_saga(sid, "npc_swallow", {
		"s1_red_moon": "피난 보따리", "s1_so_orphan": "소년을 데려간다", "s1_so_majin_deal": "거절하고",
		"s1_so_haomun": "거절한다", "s1_blood_night": "부상자와", "s1_so_exodus": "행렬의 맨 앞",
		"s1_demon_reign": "저항한다", "s1_crossroads": "지켜야 할", "s1_finale_so": "피난민들의",
	})
	_check(gm().current_ending_id == "s1_lantern_refugees", "1장 연소화: 피난길의 등불")
	_check(_rel(gm(), "npc_orphan") != null and _rel(gm(), "npc_orphan").bond_type == RelationshipData.BondType.PUPIL, "1장 연소화: 석두를 제자로")
	# 진무겸: 마교와 손잡고 서문을 연다 → 마교의 총관
	_play_saga(sid, "npc_senior_brother", {
		"s1_red_moon": "서신을 다시 접어", "s1_mu_heir": "왜 제가", "s1_alliance": "맹주 자리를",
		"s1_black_wind_offer": "소문만", "s1_mu_envoy": "손을 잡는다", "s1_mu_soha": "거짓말로",
		"s1_traitor_within": "사형제 하나에게", "s1_blood_night": "약속대로", "s1_mu_aftermath": "마교의 총관",
		"s1_demon_reign": "투항한다", "s1_crossroads": "더 높은", "s1_finale_mu": "마교의 중원 총관",
	})
	_check(gm().current_ending_id == "s1_demon_steward", "1장 진무겸: 마교의 총관")
	# 진무겸: 마음을 돌려 사부의 등 뒤를 지킨다 → 참회의 검
	_play_saga(sid, "npc_senior_brother", {
		"s1_red_moon": "사부께", "s1_mu_heir": "사부의 뜻에", "s1_alliance": "대사형으로서",
		"s1_mu_envoy": "거절하고", "s1_blood_night": "문을 열지 않고", "s1_mu_aftermath": "사부의 검을",
		"s1_demon_reign": "저항한다", "s1_crossroads": "지켜야 할", "s1_finale_mu": "사부의 빈자리",
	})
	_check(gm().current_ending_id == "s1_repentant_sword", "1장 진무겸: 참회의 검")
	# 혈영: 남궁설을 사랑해 칼을 거둔다
	_play_saga(sid, "npc_cheonma_envoy", {
		"s1_red_moon": "붉은 달을 오래", "s1_hy_blade": "칼을 받으며", "s1_alliance": "맹회의 하인으로",
		"s1_lady_and_shadow": "그녀의 손을", "s1_hy_seol_again": "그녀와 함께", "s1_traitor_within": "첩자 노릇",
		"s1_blood_night": "불길 속에서 남궁설", "s1_hy_after_night": "남궁설이 무사한지", "s1_demon_reign": "잔당 사냥에서",
		"s1_hy_choice": "남궁설과 함께", "s1_finale_hy": "바닷가",
	})
	_check(gm().current_ending_id == "s1_sheathed_blade", "1장 혈영: 칼을 거둔 자객")
	# 혈영: 상처 입은 천마를 꺾고 교주가 된다 (지존). 레벨이 모자라면 천마의 분노.
	var supreme_plan: Dictionary = {
		"s1_red_moon": "교주의 명을", "s1_hy_blade": "무릎 꿇고", "s1_alliance": "맹회의 하인으로",
		"s1_lady_and_shadow": "얼굴을 본 자는", "s1_traitor_within": "첩자 노릇", "s1_blood_night": "교주의 명대로",
		"s1_hy_after_night": "교주의 상처를 오래", "s1_demon_reign": "교주의 오른팔로", "s1_hy_choice": "천마에게 칼을",
	}
	_play_saga(sid, "npc_cheonma_envoy", supreme_plan, {}, 9)
	_check(gm().current_ending_id == "s1_demon_supreme", "1장 혈영: 마도지존")
	_play_saga(sid, "npc_cheonma_envoy", supreme_plan, {"s1_hy_choice": D}, 9)
	_check(gm().current_ending_id == "s1_bad_heaven_wrath", "1장 혈영: 천마에게 지면 천마의 분노")
	# 경지가 모자라면 천마를 노리는 길은 곧바로 천마의 분노다.
	supreme_plan["s1_hy_choice"] = "지금 천마를"
	_play_saga(sid, "npc_cheonma_envoy", supreme_plan)
	_check(gm().current_ending_id == "s1_bad_heaven_wrath", "1장 혈영: 준비 없이 천마에게 칼을 들면 천마의 분노")

	# ── 2장 흑련천하 ──
	sid = "saga_2_black_lotus"
	_start_saga(sid, "s2_ma_hwarin")
	_check(not NpcRoster.is_listed(NpcRoster.get_npc("npc_rival")) and NpcRoster.is_listed(NpcRoster.get_npc("s2_namgung_un")), "2장: 다른 시대의 인물은 숨김")
	_check(gm().player_sect.sect_name == "흑련맹" and gm().player_sect.leader_id == "s2_dokgo_cheon" and gm().player_sect.leader_name == "독고천", "2장: 문파 이름·문주 바꾸기")
	_check(NpcAgent.get_officers(gm().player_sect)[0]["npc"] == "s2_dokgo_cheon", "2장: 바뀐 문주가 문주 직책을 맡음")
	_check(EventManager.get_event("bond_meet_swallow") == null and EventManager.get_event("bond_g_friend_drink") != null, "2장: 공용 기연 파일 앞부분으로 고르기")
	var lovers: Dictionary = {
		"s2_hr_fathers_shadow": "거절한다", "s2_hr_test": "베는 척", "s2_river_lovers": "밧줄을",
		"s2_black_lotus_pact": "맹주 곁에서", "s2_hr_crossroad": "남궁운에게", "s2_great_march": "검을 간다",
		"s2_luoyang_battle": "혼란 속에서 남궁운", "s2_lotus_reign": "흑련의 법 아래", "s2_finale_hr": "남궁운과",
	}
	_play_saga(sid, "s2_ma_hwarin", lovers)
	_check(gm().current_ending_id == "s2_lovers_cross", "2장 마화린: 강을 건넌 연인")
	_play_saga(sid, "s2_ma_hwarin", {
		"s2_black_lotus_pact": "맹세하는 척", "s2_hr_crossroad": "맹주의 자리를", "s2_luoyang_battle": "맹주의 선봉",
		"s2_hr_dokgo": "검을 뽑는다",
	}, {}, 10)
	_check(gm().current_ending_id == "s2_lotus_supreme", "2장 마화린: 흑련맹주 (지존)")
	_play_saga(sid, "s2_ma_hwarin", {"s2_black_lotus_pact": "맹세하는 척", "s2_luoyang_battle": "지금 맹주의"})
	_check(gm().current_ending_id == "s2_bad_lotus_blade", "2장 마화린: 맹주의 칼 (배드)")
	_play_saga(sid, "s2_namgung_hwi", {
		"s2_hw_sister": "혈영을 용서한다", "s2_hw_sons_love": "허락한다", "s2_black_lotus_pact": "거절한다",
		"s2_luoyang_battle": "무너지는 성벽", "s2_hw_after_luoyang": "세가의 문을", "s2_lotus_reign": "흑련의 법 아래",
		"s2_finale_hw": "손녀에게",
	})
	_check(gm().current_ending_id == "s2_righteous_lantern", "2장 남궁휘: 정파의 등불")
	var hy_rel: RelationshipData = _rel(gm(), "s2_hyeolyeong")
	_check(hy_rel != null and hy_rel.bond_type == RelationshipData.BondType.ACQUAINTANCE, "2장 남궁휘: 혈영을 용서하면 원한이 풀린다 (%s)" % [hy_rel.get_bond_name() if hy_rel else "없음"])
	_play_saga(sid, "s2_hyeolyeong", {
		"s2_y_granddaughter": "아기를", "s2_mugyeom_revolt": "반역자", "s2_black_lotus_pact": "남은 교도들을",
		"s2_luoyang_battle": "교도들을 이끌고", "s2_y_ring": "반지를 받는다", "s2_finale_y": "천마의 자리를",
	})
	_check(gm().current_ending_id == "s2_heaven_heir", "2장 혈영: 천마의 계승")
	_play_saga(sid, "s2_hyeolyeong", {"s2_mugyeom_revolt": "반역자"}, {"s2_mugyeom_revolt": D})
	_check(gm().current_ending_id == "s2_bad_civil_war", "2장 혈영: 내전에서 지면 내전의 제물 (배드)")
	_play_saga(sid, "s2_seokun", {
		"s2_mugyeom_revolt": "사부의 원수를", "s2_su_revenge_done": "목숨만은", "s2_black_lotus_pact": "흑련 아래",
		"s2_luoyang_battle": "무너지는 성벽", "s2_lotus_reign": "흑련의 법을 따르지", "s2_finale_su": "조용히",
	})
	_check(gm().current_ending_id == "s2_qingyun_rebuilt" and gm().story_flags.get("s2_su_spared", false), "2장 석운: 청운재건")
	_play_saga(sid, "s2_seokun", {"s2_black_lotus_pact": "흑련의 사자를", "s2_su_gate_test": "산문을 걸고"}, {"s2_su_gate_test": D})
	_check(gm().current_ending_id == "s2_bad_fallen_gate", "2장 석운: 산문이 다시 불타다 (배드)")

	# ── 3장 청천재명 ──
	sid = "saga_3_blue_sky"
	var supreme: Dictionary = {
		"s3_tyranny": "사부께", "s3_ch_master": "사부의 검을", "s3_uprising": "처형장으로", "s3_ch_saintess": "손을 내민다",
		"s3_hwarin_turns": "마화린을 받아들인다", "s3_murim_alliance": "맹주로 추대받는다", "s3_last_order": "개봉으로 갈",
		"s3_kaifeng_battle": "흑련의 성문을", "s3_ch_gyeol": "살려 준다", "s3_new_dawn": "흑련에 짓밟힌",
		"s3_finale_ch": "정·사·마를",
	}
	_play_saga(sid, "s3_cheongha", supreme, {}, 9)
	_check(gm().current_ending_id == "s3_murim_supreme", "3장 청하: 무림맹주 (지존)")
	supreme["s3_finale_ch"] = "무림맹의 검으로"
	_play_saga(sid, "s3_cheongha", supreme)
	_check(gm().current_ending_id == "s3_blue_sky_sword", "3장 청하: 청천의 검")
	_play_saga(sid, "s3_cheongha", {"s3_uprising": "처형장으로", "s3_ch_captured_ev": "입을 다문다"}, {"s3_uprising": D})
	_check(gm().current_ending_id in ["s3_bad_hound", "s3_survivor"] and gm().story_flags.get("s3_ch_captured", false), "3장 청하: 붙잡히면 흑련의 감옥 (%s)" % gm().current_ending_id)
	_play_saga(sid, "s3_cheongha", {"s3_kaifeng_battle": "홀로"})
	_check(gm().current_ending_id == "s3_bad_kaifeng", "3장 청하: 개봉의 불길 (배드)")
	_play_saga(sid, "s3_namgung_yeon", {
		"s3_ny_grandfather": "할아버지의 검을", "s3_uprising": "봉기한 사람들에게 남궁", "s3_hwarin_turns": "마화린을 받아들인다",
		"s3_ny_hwarin": "그녀를 믿는다", "s3_murim_alliance": "맹주로 청하를", "s3_kaifeng_battle": "흑련의 성문을",
		"s3_finale_ny": "남궁의 깃발을",
	})
	_check(gm().current_ending_id == "s3_namgung_return", "3장 남궁연: 남궁의 귀환")
	_play_saga(sid, "s3_dokgo_gyeol", {
		"s3_tyranny": "처형을 미루라고", "s3_dg_childhood": "마음을", "s3_uprising": "봉기의 주모자를", "s3_dg_envoy": "아버지 몰래",
		"s3_hwarin_turns": "그녀를 놓아준다", "s3_last_order": "흑련을 떠난다", "s3_kaifeng_battle": "흑련의 깃발을",
		"s3_finale_dg": "흑련이 짓밟은",
	})
	_check(gm().current_ending_id == "s3_beyond_father", "3장 독고결: 아버지를 넘어 (%s %s)" % [gm().current_ending_id, gm().game_over_id])
	_play_saga(sid, "s3_dokgo_gyeol", {
		"s3_tyranny": "법을 어긴 자들을", "s3_uprising": "봉기한 마을을", "s3_hwarin_turns": "배신자를",
		"s3_dg_hwarin_caught": "아버지의 명대로", "s3_last_order": "아버지에게 칼을", "s3_dg_father_won_ev": "맹주의 자리에",
		"s3_kaifeng_battle": "마지막 성루", "s3_finale_dg": "끝까지",
	})
	_check(gm().current_ending_id == "s3_blood_heir" and gm().story_flags.get("s3_hwarin_dead", false), "3장 독고결: 피의 계승자 (%s %s)" % [gm().current_ending_id, gm().game_over_id])
	_play_saga(sid, "s3_wi_seola", {
		"s3_sa_story": "그 여인의", "s3_sa_zealots": "피의 맹세를 거부", "s3_sa_alliance_offer": "받아들인다",
		"s3_kaifeng_battle": "교도들을 이끌고", "s3_sa_peace_mission": "혈영과 함께", "s3_finale_sa": "무림맹과",
	})
	_check(gm().current_ending_id == "s3_saintess_peace", "3장 위설아: 성녀의 화친")
	_play_saga(sid, "s3_wi_seola", {
		"s3_tyranny": "할아버지의 원수", "s3_sa_story": "할아버지 위무량의", "s3_sa_zealots": "피의 맹세를 받아들",
		"s3_cult_reborn_ev": "교도들에게", "s3_kaifeng_battle": "싸움이 끝나기를", "s3_new_dawn": "빈자리를", "s3_finale_sa": "천마의 자리에",
	})
	_check(gm().current_ending_id == "s3_heaven_returns", "3장 위설아: 천마의 재림")
	_completed["_test_main_saga_paths"] = true
