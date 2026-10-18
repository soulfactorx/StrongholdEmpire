extends "res://scripts/Tests/test_base.gd"

## 스모크 테스트 — 역할 고유 행동·전환, 제자 명단, 인연
## 실행 순서는 smoke_test.gd의 INIT_SEQUENCE·RUNTIME_SEQUENCE가 정한다.


func _test_role_actions() -> void:
	var gm: Node = root.get_node("GameManager")

	# 모든 역할에 고유 행동이 1개 이상
	for role_name in CharacterData.Role.keys():
		var actions: Array[Dictionary] = RoleActions.get_actions(CharacterData.Role[role_name])
		_check(not actions.is_empty(), "역할 고유 행동 있음: %s" % role_name)

	# ── 문주: 회의·사절·불만도·축출 ──
	_new_quiet_game(gm, "leader")
	gm.role_state["discontent"] = 30
	var gold_before: int = gm.player_sect.gold
	var result: Dictionary = gm.do_role_action("council")
	_check(
		result["success"] and gm.role_state["discontent"] == 30 - _Balance.COUNCIL_DISCONTENT_RELIEF
		and gm.player_sect.gold == gold_before - _Balance.COUNCIL_GOLD,
		"문주 회의: 불만도 감소, 금화 소모"
	)
	_check(not gm.do_role_action("council")["success"], "역할 행동은 계절마다 한 번")
	var discontent: int = gm.role_state["discontent"]
	gm.advance_turn()
	_check(gm.role_state["discontent"] == discontent + _Balance.DISCONTENT_PER_SEASON, "계절마다 불만도 상승")
	var heukpung: SectData = gm.get_world_sect("heukpung")
	var attitude: int = heukpung.attitude
	_check(not gm.do_role_action("envoy", "no_such_sect")["success"], "사절: 없는 대상 거부")
	_check(gm.do_role_action("envoy", "heukpung")["success"] and heukpung.attitude == attitude + _Balance.ENVOY_ATTITUDE, "사절 파견: 태도 상승")
	gm.player_sect.gold = 1000
	gm.player_sect.food = 500
	discontent = gm.role_state["discontent"]
	gm.hold_feast()
	_check(gm.role_state["discontent"] == maxi(0, discontent - _Balance.FEAST_DISCONTENT_RELIEF), "문주의 연회는 불만도도 낮춤")
	_check(not gm.do_role_action("teaching")["success"], "다른 역할의 행동은 거부")
	gm.role_state["discontent"] = 75
	_check(
		EventManager.conditions_met(EventManager.get_event("leader_rebellion").conditions, gm.player_character, gm.player_sect, gm.player_relationships, "봄", gm.story_flags),
		"불만도 70 이상이면 반란 기연 조건 충족"
	)
	gm.pending_event = {"id": "leader_rebellion"}
	gm.resolve_pending_event(0)
	_check(gm.role_state["discontent"] == 35, "반란 기연 선택지가 불만도를 낮춤 (role_state 효과)")
	gm.role_state["discontent"] = 99
	gm.player_sect.shortage_seasons = 0
	gm.advance_turn()
	_check(gm.player_character.role == CharacterData.Role.WANDERER and gm.story_flags.get("ousted_leader", false), "불만도 100: 문주 축출 → 낭인")
	_check(gm.player_sect.leader_name != gm.player_character.display_name, "축출 후 문파를 다른 사람이 맡음")
	_check(gm.last_turn_report.contains("내쳤습니다"), "축출이 계절 보고에 표시")

	# ── 중간관리자: 부서·건의·강등 ──
	_new_quiet_game(gm, "young_disciple")
	gm.apply_role_transition(CharacterData.Role.MANAGER)
	_check(gm.role_state["trust"] == _Balance.MANAGER_START_TRUST, "중간관리자 시작 신임도")
	var plain_forecast: int = gm.estimate_next_season()["gold"]
	_check(gm.do_role_action("department", "finance")["success"] and gm.role_state["department"] == "finance", "부서 지정: 재정")
	_check(gm.estimate_next_season()["gold"] > plain_forecast, "재정 부서: 예상 금화 수입 증가")
	gm.advance_turn()
	_check(gm.role_state["trust"] == _Balance.MANAGER_START_TRUST + _Balance.DEPT_TRUST_PER_SEASON, "부서를 맡으면 계절마다 신임도 상승")
	_check(not gm.do_role_action("department", "finance")["success"], "같은 부서 재지정 거부")
	var rep_before: int = gm.player_sect.reputation
	var trust_before: int = gm.role_state["trust"]
	result = gm.do_role_action("proposal")
	if result["success"]:
		_check(gm.player_sect.reputation == rep_before + _Balance.PROPOSAL_REPUTATION and gm.role_state["trust"] > trust_before, "건의 성공: 명성·신임 상승")
	else:
		_check(gm.role_state["failures"] == 1 and gm.role_state["trust"] < trust_before, "건의 실패: 신임 하락, 실책 누적")
	_check(not RoleActions.can_act(gm.role_state, gm._get_turn_index()), "건의는 성공·실패와 관계없이 행동 소모")
	gm.do_role_action("department", "intel")
	gm.advance_turn()
	_check(gm.do_role_action("department", "intel")["success"], "다음 계절 정보 부서 지정")
	var plan: Dictionary = gm.prepare_war("heukpung")
	var scout_cost: int = SectWarManager.get_scout_cost(plan, gm.player_character)
	gm.player_sect.gold = 1000
	gm.scout_war("heukpung")
	_check(gm.player_sect.gold == 1000 - roundi(scout_cost * _Balance.DEPT_INTEL_SCOUT_SCALE), "정보 부서: 정찰 비용 절반")
	gm.role_state["failures"] = _Balance.DEMOTION_FAILURES
	gm.advance_turn()
	_check(gm.player_character.role == CharacterData.Role.YOUNG_DISCIPLE and gm.story_flags.get("demoted", false), "실책 누적: 막내 제자로 강등")
	_check(gm.role_history.has("MANAGER") and gm.role_state["failures"] == 0, "강등 후 역할 기록 유지, 실책 초기화")

	# ── 막내 제자: 가르침·외출·시설 제한 ──
	_new_quiet_game(gm, "young_disciple")
	var master: RelationshipData = RelationshipManager.get_bond_with(gm.player_relationships, "npc_master")
	var bond_before: int = master.bond_strength
	var exp_before: int = gm.player_character.experience
	_check(gm.do_role_action("teaching")["success"], "가르침 청하기")
	_check(master.bond_strength == bond_before + _Balance.TEACH_BOND and gm.player_character.experience >= exp_before + _Balance.TEACH_EXP, "가르침: 유대·경험치 상승")
	gm.advance_turn()
	result = gm.do_role_action("outing")
	_check(result["success"] and (result.has("event") == (not gm.pending_event.is_empty())), "외출: 기연 또는 소득")
	gm.pending_event.clear()
	gm.player_sect.gold = 1000
	_check(not gm.upgrade_facility("library")["success"] and gm.player_sect.library_level == 1, "막내 제자는 시설 확장 불가")

	# ── 낭인: 의뢰 게시판·이동·신용 ──
	_new_quiet_game(gm, "wanderer")
	result = RoleActions.perform(gm, "job_board", "hunt")
	_check(result["success"] and result["combat"] is CombatSetup and result["combat"].id == "bandit_hunt", "토벌 의뢰: 전투 구성")
	_check(result["combat"].rewards["gold"] == _Balance.JOB_HUNT_GOLD, "본거지 토벌 보상")
	gm.advance_turn()
	_check(gm.do_role_action("travel", "heukpung")["success"] and gm.role_state["location"] == "heukpung", "이동: 흑풍채의 땅")
	_check(RoleActions.get_targets(gm, "travel").size() == gm.world_sects.size(), "이동 대상: 본거지 + 현재 거처가 아닌 세력")
	gm.advance_turn()
	gm.do_role_action("job_board", "search")
	_check(RoleActions.get_credit(gm.role_state, "heukpung") == _Balance.JOB_CREDIT_GAIN, "타지 의뢰: 그 세력 신용 상승")
	gm.advance_turn()
	gm.player_character.strength = 1
	gm.player_character.agility = 1
	_check(RoleActions.get_escort_chance(gm) == 10, "약하면 호위 성공률 최저")
	gm.player_character.strength = 80
	_check(RoleActions.get_escort_chance(gm) == 95, "강하면 호위 성공률 최고")
	gold_before = gm.player_sect.gold
	result = gm.do_role_action("job_board", "escort")
	if result["success"]:
		_check(gm.player_sect.gold == gold_before + roundi(_Balance.JOB_ESCORT_GOLD * _Balance.JOB_AWAY_REWARD_SCALE), "타지 호위 보상 1.5배")
	else:
		_check(gm.role_state["failures"] == 1, "호위 실패: 실책 누적")

	# ── 스파이: 정보 수집·사보타주·노출도 ──
	_new_quiet_game(gm, "young_disciple")
	gm.apply_role_transition(CharacterData.Role.SPY)
	var research_before: int = gm.player_sect.research_points
	result = gm.do_role_action("intel", "heukpung")
	plan = gm.prepare_war("heukpung")
	_check(result["success"] and not plan["revealed"].has(false), "정보 수집: 적 작전 모두 공개")
	_check(gm.role_state["exposure"] == _Balance.EXPOSURE_INTEL and gm.player_sect.research_points == research_before + _Balance.INTEL_RESEARCH, "정보 수집: 노출도·연구점")
	for i in _Balance.SPY_MISSION_INTEL - 1:
		gm.advance_turn()
		gm.do_role_action("intel", "heukpung")
	_check(gm.story_flags.get("spy_mission_complete", false), "정보 %d회: 스파이 임무 완료" % _Balance.SPY_MISSION_INTEL)
	gm.advance_turn()
	var disciples: int = gm.get_world_sect("cheonma").disciple_count
	gm.do_role_action("sabotage", "cheonma")
	_check(gm.get_world_sect("cheonma").disciple_count == disciples - _Balance.SABOTAGE_DISCIPLES, "사보타주: 적 제자 감소")
	gm.role_state["exposure"] = 60
	_check(
		EventManager.conditions_met(EventManager.get_event("spy_suspicion").conditions, gm.player_character, gm.player_sect, gm.player_relationships, "봄", gm.story_flags),
		"노출도 60 이상이면 의심 기연 조건 충족"
	)
	var exposure: int = gm.role_state["exposure"]
	gm.advance_turn()
	_check(gm.role_state["exposure"] == exposure - _Balance.EXPOSURE_DECAY, "노출도는 계절마다 조금씩 줄어듦")
	gm.role_state["exposure"] = _Balance.EXPOSURE_MAX - 5
	gm.do_role_action("sabotage", "namgung")
	_check(gm.story_flags.get("spy_exposed", false) and gm.current_ending_id == "tragic_execution", "노출도 100: 처형 엔딩")

	# ── 암살자: 표적 의뢰·현상금·은신 ──
	_new_quiet_game(gm, "young_disciple")
	gm.apply_role_transition(CharacterData.Role.SPY)
	gm.apply_role_transition(CharacterData.Role.ASSASSIN)
	result = RoleActions.perform(gm, "assassination")
	_check(result["combat"].id == "assassination" and gm.role_state["bounty"] == _Balance.BOUNTY_PER_CONTRACT, "표적 의뢰: 잠입 전투, 현상금 상승")
	gm.advance_turn()
	_check(gm.role_state["bounty"] == _Balance.BOUNTY_PER_CONTRACT - _Balance.BOUNTY_DECAY, "현상금은 계절마다 조금씩 줄어듦")
	gold_before = gm.player_sect.gold
	_check(gm.do_role_action("lie_low")["success"] and gm.role_state["bounty"] == 0 and gm.player_sect.gold == gold_before - _Balance.LIE_LOW_GOLD, "은신: 현상금 감소")
	gm.advance_turn()
	_check(not gm.do_role_action("lie_low")["success"] and RoleActions.can_act(gm.role_state, gm._get_turn_index()), "쫓는 자가 없으면 은신 불가 (행동 소모 없음)")
	gm.role_state["bounty"] = _Balance.BOUNTY_PURSUIT
	_check(
		EventManager.conditions_met(EventManager.get_event("assassin_bounty_hunters").conditions, gm.player_character, gm.player_sect, gm.player_relationships, "봄", gm.story_flags),
		"현상금 %d 이상이면 추격 기연 조건 충족" % _Balance.BOUNTY_PURSUIT
	)
	gm.pending_event = {"id": "assassin_bounty_hunters"}
	var choice: Dictionary = EventManager.resolve_choice("assassin_bounty_hunters", 0, gm.player_character, gm.player_sect, gm.player_relationships, gm.story_flags)
	gm.pending_event.clear()
	_check(choice.has("combat") and choice["combat"].id == "bounty_hunters", "추격 기연: 추격 전투로 이어짐")

	# ── 의뢰인: 계약 수주·이행·위반·기한 ──
	_new_quiet_game(gm, "mercenary")
	_check(gm.player_character.role == CharacterData.Role.MERCENARY, "의뢰인으로 시작")
	gold_before = gm.player_sect.gold
	_check(gm.do_role_action("contract", "namgung")["success"], "계약 수주")
	var contract: Dictionary = gm.role_state["contract"]
	_check(contract["sect"] == "namgung" and gm.player_sect.gold == gold_before + contract["advance"], "계약 선금 지급")
	gm.advance_turn()
	_check(not gm.do_role_action("contract", "heukpung")["success"], "계약은 한 번에 하나")
	gm.advance_turn()
	result = gm.do_role_action("fulfill")
	var credit: int = RoleActions.get_credit(gm.role_state, "namgung")
	_check(gm.role_state["contract"].is_empty() and (credit == _Balance.CONTRACT_CREDIT_GAIN if result["success"] else credit == -_Balance.CONTRACT_FAIL_CREDIT), "계약 이행: 신용 변화")
	gm.advance_turn()
	gm.do_role_action("contract", "heukpung")
	gm.advance_turn()
	gold_before = gm.player_sect.gold
	attitude = gm.get_world_sect("heukpung").attitude
	_check(gm.do_role_action("breach")["success"] and gm.player_sect.gold == gold_before + _Balance.CONTRACT_BREACH_GOLD, "계약 위반: 금화 획득")
	_check(RoleActions.get_credit(gm.role_state, "heukpung") == -_Balance.CONTRACT_BREACH_CREDIT and gm.get_world_sect("heukpung").attitude < attitude, "계약 위반: 신용·태도 하락")
	gm.advance_turn()
	gm.do_role_action("contract", "cheonma")
	for i in _Balance.CONTRACT_SEASONS + 1:
		gm.advance_turn()
	_check(gm.role_state["contract"].is_empty() and RoleActions.get_credit(gm.role_state, "cheonma") == -_Balance.CONTRACT_BREACH_CREDIT, "계약 기한 초과: 자동 위반")
	gm.role_state["credit"]["namgung"] = _Balance.CONTRACT_MIN_CREDIT - 1
	var contract_targets: Array = RoleActions.get_targets(gm, "contract").map(func(t: Dictionary) -> String: return t["id"])
	_check(not contract_targets.has("namgung"), "신용이 너무 낮은 세력은 계약을 주지 않음")

	# ── 세이브: 역할 자원 저장·복원 ──
	gm.role_state["bounty"] = 33
	var restored: Dictionary = RoleActions.restore_state(JSON.parse_string(JSON.stringify(gm.role_state)))
	_check(restored["bounty"] == 33 and restored["bounty"] is int and restored["credit"]["cheonma"] is int, "역할 자원 JSON 왕복 (정수 유지)")
	_check(RoleActions.restore_state({})["trust"] == _Balance.MANAGER_START_TRUST, "구버전 세이브: 역할 자원 기본값")

	# ── 기연 문법: role_state ──
	var errors: PackedStringArray = []
	EventManager.validate_conditions([{"type": "role_state", "field": "no_such", "op": ">=", "value": 1}], errors)
	_check(not errors.is_empty(), "알 수 없는 역할 자원 조건 거부")
	errors = EventManager.validate_event_dict({
		"id": "x", "title": "x", "description": "x", "conditions": [],
		"choices": [{"label": "a", "message": "b", "effects": [{"type": "role_state", "field": "exposure", "add": 5}]}],
	})
	_check(errors.is_empty(), "role_state 효과 검증 통과")

	# 새 전투 구성
	for combat_id in ["bandit_hunt", "assassination", "bounty_hunters"]:
		var setup: CombatSetup = CombatManager.create_by_id(combat_id, gm.player_character)
		_check(setup.id == combat_id and not setup.enemies.is_empty(), "전투 구성: %s" % combat_id)
	_completed["_test_role_actions"] = true


func _test_role_transitions_extended() -> void:
	var gm: Node = root.get_node("GameManager")

	# 낭인 → 의뢰인 → 낭인
	_new_quiet_game(gm, "wanderer")
	gm.player_character.gain_experience(CharacterData.get_experience_for_level(_Balance.MERCENARY_LEVEL_REQ))
	gm.refresh_role_transitions()
	var roles: Array = gm.pending_role_transitions.map(func(o: Dictionary) -> int: return o["role"])
	_check(roles.has(CharacterData.Role.MERCENARY), "낭인 → 의뢰인 전환 경로")
	gm.apply_role_transition(CharacterData.Role.MERCENARY)
	roles = gm.pending_role_transitions.map(func(o: Dictionary) -> int: return o["role"])
	_check(roles.has(CharacterData.Role.WANDERER), "의뢰인 → 낭인 전환 경로")

	# 이적: 신용을 쌓은 세력에 객경으로
	RoleActions.change_credit(gm.role_state, "namgung", _Balance.DEFECT_CREDIT_REQ)
	gm.refresh_role_transitions()
	var defect: Dictionary = {}
	for option in gm.pending_role_transitions:
		if option.get("kind") == "defect" and option["sect_id"] == "namgung":
			defect = option
	_check(not defect.is_empty(), "신용 %d 이상: 이적 경로" % _Balance.DEFECT_CREDIT_REQ)
	_check(gm.player_sect.id == "none", "낭인 출신 의뢰인은 무소속")
	var gold_before: int = gm.player_sect.gold
	gm.apply_role_transition(defect["role"], defect)
	_check(gm.player_sect.id == "namgung" and gm.player_character.role == CharacterData.Role.MANAGER, "이적: 남궁세가의 중간관리자")
	_check(gm.get_world_sect("none") == null, "무소속에서 이적: 무소속은 강호 세력이 되지 않음")
	_check(gm.player_sect.gold >= gold_before, "무소속에서 이적: 개인 금화를 가지고 감")

	# 문파에 몸담은 의뢰인의 이적: 옛 문파는 강호 세력이 된다
	_new_quiet_game(gm, "mercenary")
	RoleActions.change_credit(gm.role_state, "namgung", _Balance.DEFECT_CREDIT_REQ)
	var old_id: String = gm.player_sect.id
	gm.apply_role_transition(CharacterData.Role.MANAGER, {"role": CharacterData.Role.MANAGER, "sect_id": "namgung", "kind": "defect"})
	var old_sect: SectData = gm.get_world_sect(old_id)
	_check(old_sect != null and old_sect.attitude == _Balance.DEFECT_OLD_SECT_ATTITUDE, "이적: 옛 문파는 강호 세력이 됨")
	_check(gm.get_world_sect("namgung") == null and gm.story_flags.get("defected", false), "이적: 새 문파는 강호 세력 목록에서 빠짐")
	_check(gm.get_war_targets().has(old_sect), "옛 문파도 문파전 대상")

	# 배신: 스파이가 잠입한 세력으로 전향
	_new_quiet_game(gm, "young_disciple")
	gm.apply_role_transition(CharacterData.Role.SPY)
	gm.do_role_action("intel", "heukpung")
	var betray: Dictionary = {}
	for option in gm.pending_role_transitions:
		if option.get("kind") == "betray":
			betray = option
	_check(betray.get("sect_id") == "heukpung", "스파이 배신 경로: 잠입한 세력")
	var morality: int = gm.player_character.morality
	gm.apply_role_transition(betray["role"], betray)
	_check(gm.player_sect.id == "heukpung" and gm.player_character.morality == morality - _Balance.BETRAY_MORALITY_LOSS, "배신: 흑풍채로 전향, 도덕 하락")
	_check(gm.get_world_sect("qingyun").attitude == _Balance.BETRAY_OLD_SECT_ATTITUDE and gm.story_flags.get("betrayed_qingyun", false), "배신: 옛 문파가 적대")

	# 배신: 도덕이 낮은 제자는 적대 세력으로 투항할 수 있다
	_new_quiet_game(gm, "young_disciple")
	gm.player_character.morality = _Balance.BETRAY_MORALITY_REQ
	gm.refresh_role_transitions()
	var kinds: Array = gm.pending_role_transitions.map(func(o: Dictionary) -> String: return o.get("kind", ""))
	_check(kinds.has("betray"), "도덕 %d 이하: 투항 경로" % _Balance.BETRAY_MORALITY_REQ)

	# 문주 승계는 신임도가 필요
	_new_quiet_game(gm, "young_disciple")
	gm.apply_role_transition(CharacterData.Role.MANAGER)
	gm.player_character.gain_experience(CharacterData.get_experience_for_level(_Balance.LEADER_LEVEL_REQ))
	gm.player_sect.reputation = _Balance.LEADER_REPUTATION_REQ
	gm.player_sect.disciple_count = _Balance.LEADER_DISCIPLE_REQ
	RelationshipManager.get_bond_with(gm.player_relationships, "npc_master").increase_bond(60)
	gm.role_state["trust"] = _Balance.MANAGER_TRUST_FOR_LEADER - 1
	gm.refresh_role_transitions()
	roles = gm.pending_role_transitions.map(func(o: Dictionary) -> int: return o["role"])
	_check(not roles.has(CharacterData.Role.LEADER), "신임도가 낮으면 문주 승계 불가")
	gm.role_state["trust"] = _Balance.MANAGER_TRUST_FOR_LEADER
	gm.refresh_role_transitions()
	roles = gm.pending_role_transitions.map(func(o: Dictionary) -> int: return o["role"])
	_check(roles.has(CharacterData.Role.LEADER), "신임도를 갖추면 문주 승계 가능")
	_completed["_test_role_transitions_extended"] = true


func _test_role_actions_hub() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "wanderer")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	_check(hub.role_action_box.get_child_count() == 2, "경영 화면: 낭인 고유 행동 버튼 2개")
	var all_touch_size: bool = true
	for button in hub.role_action_box.get_children():
		all_touch_size = all_touch_size and button.custom_minimum_size.y >= 48
	_check(all_touch_size, "역할 행동 버튼 높이 48px 이상")
	_check(hub.role_resource_label.text.contains("거처"), "낭인 역할 자원 표시")
	hub._on_role_action_pressed("job_board")
	await process_frame
	_check(hub.choice_popup.visible and hub.choice_popup.get_option_count() == RoleActions.JOBS.size(), "의뢰 게시판: 의뢰 고르기 팝업")
	hub.choice_popup._on_option_pressed("search")
	_check(not hub.choice_popup.visible and hub.log_label.text.contains("수색"), "수색 의뢰 실행")
	_check(hub.role_action_box.get_child(0).disabled, "행동 후 이번 계절 역할 버튼 비활성")
	hub._on_advance_turn_pressed()
	await process_frame
	_check(not hub.role_action_box.get_child(0).disabled, "다음 계절 역할 버튼 다시 활성")

	# 역할이 바뀌면 버튼도 바뀐다
	gm.player_character.gain_experience(CharacterData.get_experience_for_level(_Balance.MERCENARY_LEVEL_REQ))
	gm.apply_role_transition(CharacterData.Role.MERCENARY)
	await process_frame
	var titles: Array = hub.role_action_box.get_children().map(func(b: Button) -> String: return b.text)
	_check(titles.has("계약 수주") and titles.size() == 3, "의뢰인 고유 행동 버튼 3개")

	# 막내 제자: 시설 확장 버튼 비활성
	_new_quiet_game(gm, "young_disciple")
	hub._refresh_all()
	hub._on_facility_pressed()
	await process_frame
	var any_enabled: bool = false
	for row in hub.facility_popup._rows.get_children():
		any_enabled = any_enabled or not row.get_child(1).disabled
	_check(not any_enabled, "막내 제자: 시설 확장 버튼 모두 비활성")
	hub.facility_popup.visible = false

	# 표적 의뢰는 전투 화면으로 이어진다
	gm.apply_role_transition(CharacterData.Role.SPY)
	gm.apply_role_transition(CharacterData.Role.ASSASSIN)
	hub._on_role_action_pressed("assassination")
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.COMBAT and gm.pending_combat.id == "assassination", "표적 의뢰: 잠입 전투 화면으로 이동")
	gm.pending_combat = null
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_role_actions_hub"] = true


func _test_starting_sect() -> void:
	var gm: Node = root.get_node("GameManager")
	# 기본: 시나리오의 기본 문파
	_new_quiet_game(gm, "young_disciple")
	var default_id: String = gm.player_sect.id
	_check(gm.has_sect() and gm.get_world_sect(default_id) == null, "기본 소속: 시나리오 기본 문파")

	# 다른 문파를 골라 시작: 기본 문파는 강호 세력이 된다
	gm.start_new_game("소속", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0}, false, false, {"player_sect": "namgung"})
	_check(gm.player_sect.id == "namgung" and gm.get_world_sect("namgung") == null, "시작 문파 선택: 남궁세가")
	_check(gm.get_world_sect(default_id) != null, "고르지 않은 기본 문파는 강호 세력")
	_check(_roster_matches(gm.player_sect), "고른 문파의 제자 명단")
	var leader_id: String = gm.player_sect.leader_id
	if NpcRoster.has_npc(leader_id):
		var master: RelationshipData = _rel(gm, leader_id)
		_check(master != null and master.bond_type == RelationshipData.BondType.MASTER_DISCIPLE, "고른 문파의 문주가 사부")
	var other_masters: bool = gm.player_relationships.any(func(rel: RelationshipData) -> bool:
		return rel.bond_type == RelationshipData.BondType.MASTER_DISCIPLE and str(NpcRoster.get_npc(rel.target_id).get("sect_id", "")) != "namgung")
	_check(not other_masters, "다른 문파의 스승은 사부가 아님")
	_check(not WorldMap.get_home(gm.map_state, "namgung").is_empty(), "고른 문파의 본거지")

	# 낭인: 무소속
	_new_quiet_game(gm, "wanderer")
	var sect: SectData = gm.player_sect
	_check(sect.id == "none" and not gm.has_sect() and sect.disciple_count == 0, "낭인은 무소속 (제자 없음)")
	_check(gm.get_world_sect(default_id) != null, "낭인: 기본 문파는 강호 세력")
	_check(not gm._all_sect_ids().has("none"), "무소속은 지도 세력이 아님")
	_check(EndingManager.check_game_over(sect).is_empty(), "무소속은 제자 0명이어도 끝나지 않음")
	gm.advance_turn()
	_check(gm.pending_invasion.is_empty() and gm.player_sect.id == "none", "무소속: 계절을 넘겨도 침공 없음")
	_check(RoleDashboard.get_sect_title(gm.player_character.role, gm.player_sect).begins_with("무소속"), "무소속 칸 제목")
	gm._apply_save_data(JSON.parse_string(JSON.stringify(gm._build_save_state())))
	_check(gm.player_sect.id == "none" and not gm.has_sect() and gm.get_world_sect("none") == null, "무소속 저장·복원")
	_completed["_test_starting_sect"] = true


func _test_disciple_roster() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "leader")
	var sect: SectData = gm.player_sect

	# 새 게임: 제자 수만큼 이름·능력치를 가진 제자
	_check(_roster_matches(sect) and sect.disciple_count == 12, "새 게임: 제자 명단 12명")
	var ids: Dictionary = {}
	var stats_ok: bool = true
	for disciple in sect.disciples:
		ids[disciple.id] = true
		for value in [disciple.strength, disciple.agility, disciple.wisdom]:
			stats_ok = stats_ok and value >= _Balance.DISCIPLE_STAT_MIN and value <= _Balance.DISCIPLE_STAT_MAX
		stats_ok = stats_ok and disciple.display_name.length() >= 2 and disciple.level == 1
	_check(ids.size() == 12 and stats_ok, "제자마다 고유 id·이름·능력치")
	_check(not gm.world_sects[0].use_roster and gm.world_sects[0].disciples.is_empty(), "강호 세력은 제자 수만 씀")

	# 제자 수가 바뀌면 명단도 맞춰진다 (맡은 일이 있는 제자는 나중에 떠난다)
	var keeper: DiscipleData = sect.disciples[0]
	keeper.deployed = true
	var weakest_power: int = 999
	for disciple in sect.disciples:
		weakest_power = mini(weakest_power, disciple.get_power())
	keeper.strength = 1
	keeper.agility = 1
	sect.disciple_count += 3
	_check(_roster_matches(sect) and sect.disciples.size() == 15, "제자 수가 늘면 새 제자 합류")
	sect.disciple_count -= 5
	_check(_roster_matches(sect) and sect.disciples.has(keeper), "제자 수가 줄면 맡은 일 없는 제자부터 떠남")
	keeper.deployed = false
	gm.pending_event = {"id": "leader_rebellion"}
	gm.role_state["discontent"] = 80
	gm.player_sect.gold = 1000
	gm.resolve_pending_event(1)
	_check(_roster_matches(sect) and sect.disciple_count == 7, "기연 효과로 제자가 줄어도 명단 일치")
	sect.food = 0
	sect.disciple_count = 12
	SectManager.pay_upkeep(sect)
	_check(_roster_matches(sect) and sect.disciple_count < 12, "식량 부족 이탈도 명단에 반영")

	# 배치: 시설 레벨만큼 자리, 수입 보너스
	_new_quiet_game(gm, "leader")
	sect = gm.player_sect
	var a: DiscipleData = sect.disciples[0]
	var b: DiscipleData = sect.disciples[1]
	var research_before: int = gm.estimate_next_season()["gold"]
	var plain: Dictionary = SectManager.compute_seasonal_income(sect, gm.player_character, "봄")
	_check(DiscipleRoster.assign(sect, a.id, "treasury")["success"], "금고에 제자 배치")
	_check(not DiscipleRoster.assign(sect, b.id, "treasury")["success"], "금고 Lv.1은 한 자리")
	var with_bonus: Dictionary = SectManager.compute_seasonal_income(sect, gm.player_character, "봄")
	_check(with_bonus["gold"] == plain["gold"] + a.wisdom / _Balance.DISCIPLE_TREASURY_WISDOM_PER_GOLD, "금고 담당: 지혜만큼 금화 수입")
	_check(gm.estimate_next_season()["gold"] >= research_before, "예상 수지에 배치 보너스 반영")
	DiscipleRoster.assign(sect, b.id, "library")
	with_bonus = SectManager.compute_seasonal_income(sect, gm.player_character, "봄")
	_check(with_bonus["research"] == plain["research"] + b.wisdom / _Balance.DISCIPLE_LIBRARY_WISDOM_PER_POINT, "서고 담당: 지혜만큼 연구점")
	sect.treasury_level = 2
	_check(DiscipleRoster.assign(sect, sect.disciples[2].id, "treasury")["success"], "금고를 확장하면 자리가 늘어남")
	_check(DiscipleRoster.cycle_assignment(sect, a.id)["success"] and a.assignment == "", "배치 돌리기: 금고 → 없음")
	_check(DiscipleRoster.cycle_assignment(sect, a.id)["success"] and a.assignment == "training_ground", "배치 돌리기: 서고가 차 있으면 무술장")
	var exp_before: int = a.experience
	_check(DiscipleRoster.on_season(sect).contains("무술장") and a.experience == exp_before + _Balance.DISCIPLE_TRAINING_GROUND_EXP, "무술장 담당: 계절 수련")

	# 개별 수련과 경지
	var gold_before: int = sect.gold
	var turn: int = gm._get_turn_index()
	_check(DiscipleRoster.train(sect, b.id, turn)["success"] and sect.gold == gold_before - _Balance.DISCIPLE_TRAIN_GOLD, "개별 수련: 금화 소모")
	_check(not DiscipleRoster.train(sect, b.id, turn)["success"], "개별 수련은 계절에 한 번")
	var strength: int = b.strength
	_check(b.gain_experience(_Balance.DISCIPLE_EXP_PER_LEVEL * 3) >= 1 and b.strength > strength, "경지가 오르면 능력치 상승")

	# 출전 지정과 방어전
	_check(DiscipleRoster.toggle_deploy(sect, sect.disciples[5].id)["success"], "출전 지정")
	DiscipleRoster.toggle_deploy(sect, sect.disciples[6].id)
	_check(not DiscipleRoster.toggle_deploy(sect, sect.disciples[7].id)["success"], "출전은 %d명까지" % _Balance.DEFENSE_ALLY_COUNT)
	var setup: CombatSetup = CombatManager.create_night_bandits(gm.player_character, sect)
	var ally_ids: Array = setup.allies.map(func(c: CharacterData) -> String: return c.id)
	_check(ally_ids.has(sect.disciples[5].id) and ally_ids.has(sect.disciples[6].id), "방어전: 출전 지정한 제자가 나섬")
	_check(setup.allies[0].display_name == DiscipleRoster.get_disciple(sect, ally_ids[0]).display_name, "아군 이름은 제자 이름")
	var fallen: DiscipleData = DiscipleRoster.get_disciple(sect, ally_ids[0])
	var survivor: DiscipleData = DiscipleRoster.get_disciple(sect, ally_ids[1])
	var count_before: int = sect.disciple_count
	var outcome: Dictionary = CombatManager.apply_outcome(
		setup, CombatManager.Outcome.VICTORY, gm.player_character, sect, gm.player_relationships, gm.story_flags, 1, [fallen.id]
	)
	_check(not sect.disciples.has(fallen) and sect.disciple_count == count_before - 1 and _roster_matches(sect), "쓰러진 제자는 명단에서 빠짐")
	_check(outcome["message"].contains(fallen.display_name), "전사한 제자 이름을 알림")
	_check(survivor.battles == 1, "살아남은 참전 제자: 참전 기록")

	# 문파전 전력: 제자 경지
	var power: int = SectWarManager.get_military_power(sect, gm.player_character)
	sect.disciples[0].level += 2
	_check(SectWarManager.get_military_power(sect, gm.player_character) == power + 2 * _Balance.DISCIPLE_LEVEL_WAR_POWER, "제자 경지가 문파전 전력에 반영")

	# 세이브 왕복과 구버전 변환
	var restored: SectData = _SaveManager.deserialize_sect(JSON.parse_string(JSON.stringify(_SaveManager.serialize_sect(sect))))
	var same: bool = _roster_matches(restored) and restored.disciples.size() == sect.disciples.size()
	for i in sect.disciples.size():
		var x: DiscipleData = sect.disciples[i]
		var y: DiscipleData = restored.disciples[i]
		same = same and x.id == y.id and x.display_name == y.display_name and x.level == y.level and x.assignment == y.assignment and x.deployed == y.deployed and x.wisdom == y.wisdom
	_check(same and restored.next_disciple_id == sect.next_disciple_id, "제자 명단 저장·복원")
	var old_sect: Dictionary = _SaveManager.serialize_sect(sect)
	for key in ["use_roster", "disciples", "next_disciple_id"]:
		old_sect.erase(key)
	old_sect["disciple_count"] = 9
	gm._apply_save_data(JSON.parse_string(JSON.stringify({
		"character": _SaveManager.serialize_character(gm.player_character),
		"sect": old_sect,
	})))
	_check(_roster_matches(gm.player_sect) and gm.player_sect.disciple_count == 9, "구버전 세이브: 제자 수만큼 무작위 제자")

	# 다른 세력으로 옮겨 가면 그 세력의 명단을 만든다
	_new_quiet_game(gm, "mercenary")
	var old_id: String = gm.player_sect.id
	RoleActions.change_credit(gm.role_state, "namgung", _Balance.DEFECT_CREDIT_REQ)
	gm.apply_role_transition(CharacterData.Role.MANAGER, {"role": CharacterData.Role.MANAGER, "sect_id": "namgung", "kind": "defect"})
	_check(_roster_matches(gm.player_sect) and gm.player_sect.id == "namgung", "이적: 새 문파 제자 명단")
	_check(not gm.get_world_sect(old_id).use_roster, "이적: 옛 문파는 제자 수만 남음")
	_completed["_test_disciple_roster"] = true


func _test_disciple_roster_flow() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "leader")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	hub._on_disciple_pressed()
	await process_frame
	var popup: Node = hub.disciple_popup
	_check(popup.visible and popup.get_row_count() == gm.player_sect.disciple_count, "제자 명단 팝업: 제자마다 한 줄")
	var row: HBoxContainer = popup._rows.get_child(0)
	var touch_ok: bool = true
	for i in range(1, row.get_child_count()):
		touch_ok = touch_ok and row.get_child(i).custom_minimum_size.y >= 48
	_check(touch_ok, "제자 명단 버튼 높이 48px 이상")
	var first_id: String = popup._rows.get_child(0).get_child(1).pressed.get_connections()[0]["callable"].get_bound_arguments()[0]
	row.get_child(1).pressed.emit()
	await process_frame
	_check(DiscipleRoster.get_disciple(gm.player_sect, first_id).assignment == "library", "팝업에서 배치 (서고)")
	_check(hub.log_label.text.contains("서고"), "배치 결과 알림")
	popup._rows.get_child(0).get_child(3).pressed.emit()
	await process_frame
	_check(hub.log_label.text.contains("수련"), "팝업에서 개별 수련")
	popup.visible = false

	# 실제 전투: 출전 제자가 쓰러지면 명단에서 빠진다
	var sect: SectData = gm.player_sect
	DiscipleRoster.toggle_deploy(sect, sect.disciples[3].id)
	var deployed_id: String = sect.disciples[3].id
	gm.start_combat(CombatManager.create_night_bandits(gm.player_character, sect))
	await process_frame
	await process_frame
	var controller: Node = current_scene
	var fallen_unit: CombatUnit = null
	for unit in controller._units:
		if unit.is_ally and unit.character.id == deployed_id:
			fallen_unit = unit
	_check(fallen_unit != null, "전투: 출전 지정 제자가 아군으로 참전")
	if fallen_unit:
		fallen_unit.take_damage(99999)
		var count_before: int = sect.disciple_count
		for unit in controller._get_alive_enemies():
			unit.take_damage(99999)
		controller._check_victory()
		_check(DiscipleRoster.get_disciple(sect, deployed_id) == null and sect.disciple_count == count_before - 1, "전투에서 쓰러진 제자가 명단에서 빠짐")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_disciple_roster_flow"] = true


## 이벤트 확률 0에서 계절을 넘겨 우선 기연이 일어나는지 본다.
func _priority_event_after_turn(gm: Node) -> String:
	gm.pending_event.clear()
	gm.advance_turn()
	return str(gm.pending_event.get("id", ""))


func _test_bond_evolution() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	var turn: int = gm._get_turn_index()

	# 새 인물: 연애 후보 2, 세력 2인자, 낭인 동료 2
	for npc_id in ["npc_healer", "npc_scholar", "npc_heukpung_second", "npc_iron_blade", "npc_swallow"]:
		_check(NpcRoster.has_npc(npc_id) and NpcRoster.is_listed(NpcRoster.get_npc(npc_id)), "새 인물 명부·목록: %s" % npc_id)
	_check(not NpcRoster.is_listed(NpcRoster.get_npc("npc_bandit")), "졸개는 인물 목록에서 빠짐")
	_check(NpcRoster.get_npc("npc_iron_blade")["sect_id"] == NpcRoster.NO_SECT, "무소속 인물")

	# 상호작용: 대화·선물·횟수 제한
	var master: RelationshipData = _rel(gm, "npc_master")
	var bond_before: int = master.bond_strength
	var talk: Dictionary = gm.interact_with("npc_master", "talk")
	# 청운검선은 담소를 좋아해 대화하면 유대가 더 오른다 (취향, LIKE_BOND_MULTIPLIER)
	var talk_gain: int = roundi((_Balance.TALK_BOND + gm.player_character.charisma / _Balance.TALK_CHARISMA_DIVISOR) * _Balance.LIKE_BOND_MULTIPLIER)
	_check(NpcAgent.likes("npc_master", "talk") and not NpcAgent.likes("npc_master", "gift"), "인물 취향: 청운검선은 담소")
	_check(talk["success"] and master.bond_strength == bond_before + talk_gain and talk["message"].contains("반깁니다"), "대화: 좋아하는 일이면 유대 +%d" % talk_gain)
	var gold_before: int = gm.player_sect.gold
	_check(gm.interact_with("npc_master", "gift")["success"] and gm.player_sect.gold == gold_before - _Balance.GIFT_GOLD, "선물: 금화 소모")
	_check(master.bond_strength == bond_before + talk_gain + _Balance.GIFT_BOND, "선물: 유대 +%d" % _Balance.GIFT_BOND)
	_check(not gm.interact_with("npc_master", "talk")["success"], "상호작용은 계절마다 %d번" % _Balance.INTERACTIONS_PER_SEASON)
	gm.advance_turn()
	gm.pending_event.clear()
	_check(RelationshipManager.get_interactions_left(gm.story_flags, gm._get_turn_index()) == _Balance.INTERACTIONS_PER_SEASON, "다음 계절에 다시 가능")
	var spar: Dictionary = RelationshipManager.interact(gm.player_relationships, "npc_rival", "spar", gm.player_character, gm.player_sect, gm.story_flags, gm._get_turn_index())
	_check(spar["combat"].enemies[0].id == "npc_rival" and spar["combat"].rewards["bond"] == roundi(_Balance.SPAR_BOND_WIN * _Balance.LIKE_BOND_MULTIPLIER), "비무 신청: 그 인물과의 비무 (비무를 좋아해 유대 더)")

	# 원한: 대화로 누그러지고, 비무는 거부
	master.bond_type = RelationshipData.BondType.HATRED
	var hatred: int = master.bond_strength
	RelationshipManager.interact(gm.player_relationships, "npc_master", "talk", gm.player_character, gm.player_sect, gm.story_flags, gm._get_turn_index())
	_check(master.bond_strength < hatred, "원한 상대와 대화하면 원한이 누그러짐")
	_check(not RelationshipManager.interact(gm.player_relationships, "npc_master", "spar", gm.player_character, gm.player_sect, gm.story_flags, gm._get_turn_index() + 1)["success"], "원한 상대와는 비무 불가")
	# 원한이 거의 사라지면 화해 기연 (우선 기연)
	master.bond_strength = 5
	_check(_priority_event_after_turn(gm) == "bond_master_reconcile", "원한이 누그러지면 스승과의 화해 기연")
	gm.resolve_pending_event(0)
	_check(master.bond_type == RelationshipData.BondType.MASTER_DISCIPLE, "화해: 원한 → 사제")

	# 유대 단계가 오르면 그 인물의 기연이 확률과 관계없이 일어난다
	_new_quiet_game(gm, "young_disciple")
	_rel(gm, "npc_rival").increase_bond(60)
	_check(_priority_event_after_turn(gm) == "bond_rival_confession", "남궁휘 유대 60: 「라이벌의 고백」")
	gm.resolve_pending_event(0)
	_check(_rel(gm, "npc_rival").bond_type == RelationshipData.BondType.BLOOD_OATH, "라이벌 → 혈맹")
	_rel(gm, "npc_master").increase_bond(30)
	_check(_priority_event_after_turn(gm) == "bond_master_story", "스승 유대 60: 「스승의 옛이야기」")
	gm.resolve_pending_event(0)

	# 낯선 사이 → 지인 → 연인
	gm.pending_event = {"id": "bond_meet_swallow"}
	gm.resolve_pending_event(0)
	var swallow: RelationshipData = _rel(gm, "npc_swallow")
	_check(swallow != null and swallow.bond_type == RelationshipData.BondType.ACQUAINTANCE and swallow.get_bond_name() == "지인", "만남 기연: 지인 관계")
	swallow.increase_bond(20)
	_check(_priority_event_after_turn(gm) == "bond_swallow_heart", "연소화 유대 40: 고백 기연")
	gm.resolve_pending_event(0)
	_check(swallow.bond_type == RelationshipData.BondType.ROMANCE, "지인 → 연인")
	gm.pending_event = {"id": "bond_meet_iron_blade"}
	gm.resolve_pending_event(0)
	_rel(gm, "npc_iron_blade").increase_bond(30)
	_check(_priority_event_after_turn(gm) == "bond_iron_blade_oath", "고무진 유대 50: 의형제 기연")
	gm.resolve_pending_event(0)
	_check(_rel(gm, "npc_iron_blade").bond_type == RelationshipData.BondType.BLOOD_OATH, "지인 → 혈맹")

	# 배신하면 떠나온 문파의 스승이 원수가 된다
	_new_quiet_game(gm, "young_disciple")
	gm.player_character.morality = _Balance.BETRAY_MORALITY_REQ
	gm.refresh_role_transitions()
	var betray: Dictionary = {}
	for option in gm.pending_role_transitions:
		if option.get("kind") == "betray":
			betray = option
	gm.apply_role_transition(betray["role"], betray)
	var betrayed_master: RelationshipData = _rel(gm, "npc_master")
	_check(betrayed_master.bond_type == RelationshipData.BondType.HATRED and betrayed_master.bond_strength >= _Balance.BETRAY_HATRED_MIN, "배신: 사제 → 원한")
	_check(_rel(gm, "npc_rival").bond_type == RelationshipData.BondType.RIVALRY, "다른 세력 인물의 관계는 그대로")

	# 방어전 합류: 유대 60 이상인 사제·혈맹·연인
	_new_quiet_game(gm, "young_disciple")
	var setup: CombatSetup = CombatManager.create_night_bandits(gm.player_character, gm.player_sect)
	_check(CombatManager.add_bond_allies(setup, gm.player_relationships, gm.player_character).is_empty(), "유대가 낮으면 인연 합류 없음")
	_rel(gm, "npc_master").increase_bond(30)
	var joined: PackedStringArray = CombatManager.add_bond_allies(setup, gm.player_relationships, gm.player_character)
	var master_ally: Array = setup.allies.filter(func(c: CharacterData) -> bool: return c.id == "npc_master")
	_check(joined.size() == 1 and master_ally.size() == 1, "유대 60 스승이 방어전에 합류")
	var pos: Vector2i = setup.ally_positions[setup.allies.find(master_ally[0])]
	_check(not pos in setup.enemy_positions and not pos in setup.blocked_tiles and pos != setup.player_position, "합류 인물은 빈 칸에 선다")
	_check(CombatManager.add_bond_allies(setup, gm.player_relationships, gm.player_character).is_empty(), "같은 인물은 두 번 합류하지 않음")
	_check(RelationshipManager.get_bond_allies(gm.player_relationships, "qingyun").is_empty(), "상대 세력 소속 인연은 합류하지 않음")

	# 인연의 가호: 받는 피해 감소
	var guard: float = RelationshipManager.get_defense_modifier(gm.player_relationships, ["npc_master"])
	_check(guard > 1.0 and RelationshipManager.get_defense_modifier(gm.player_relationships, ["npc_rival"]) == 1.0, "사제는 가호, 라이벌은 없음")
	var attacker := CombatUnit.new(NpcRoster.create_character("npc_bandit"))
	var defender := CombatUnit.new(gm.player_character, true)
	var plain: int = CombatRules.calculate_damage(attacker, defender, null, CombatRules.Terrain.PLAIN, CombatRules.Terrain.PLAIN)["damage"]
	var guarded: Dictionary = CombatRules.calculate_damage(attacker, defender, null, CombatRules.Terrain.PLAIN, CombatRules.Terrain.PLAIN, 1.0, 1.5)
	_check(guarded["damage"] < plain and "인연의 가호" in guarded["notes"], "인연의 가호로 받는 피해 감소")

	# 기연 검증: priority 형식
	var errors: PackedStringArray = EventManager.validate_event_dict({"id": "x", "title": "x", "description": "x", "priority": "yes", "conditions": [], "choices": [{"label": "a", "message": "b", "effects": []}]})
	_check(Array(errors).any(func(e: String) -> bool: return e.contains("priority")), "priority 형식 오류 검출")
	_completed["_test_bond_evolution"] = true


func _test_bond_flow() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	hub._on_bond_pressed()
	await process_frame
	var popup: Node = hub.bond_popup
	_check(popup.visible and popup.get_row_count() == gm.player_relationships.size(), "인연 팝업: 관계마다 한 줄")
	var bond_before: int = _rel(gm, "npc_master").bond_strength
	_check(popup._rows.get_child(0).get_child(0) is TextureRect, "인연 팝업: 줄마다 초상화")
	popup._rows.get_child(0).get_child(2).pressed.emit()
	await process_frame
	_check(_rel(gm, "npc_master").bond_strength > bond_before and hub.log_label.text.contains("이야기"), "팝업에서 대화")
	popup.visible = false

	# 경영 화면은 인연이 많아도 세 줄까지만
	for npc_id in ["npc_swallow", "npc_iron_blade", "npc_healer"]:
		var rel := RelationshipData.new()
		rel.target_id = npc_id
		rel.target_name = NpcRoster.get_display_name(npc_id)
		rel.bond_type = RelationshipData.BondType.ACQUAINTANCE
		gm.player_relationships.append(rel)
	hub._update_relationships_display(gm.player_relationships)
	_check(hub.relationship_label.text.split("\n").size() == 3 and hub.relationship_label.text.contains("외 3명"), "경영 화면 인연 표시는 세 줄")

	# 방어전에 스승이 합류해 싸운다
	_rel(gm, "npc_master").increase_bond(40)
	gm.pending_event = {"id": "night_bandits"}
	gm.resolve_pending_event(0)
	await process_frame
	await process_frame
	var controller: Node = current_scene
	var master_unit: CombatUnit = null
	var enemy_unit: CombatUnit = controller._get_alive_enemies()[0]
	for unit in controller._units:
		if unit.is_ally and unit.character.id == "npc_master":
			master_unit = unit
	_check(controller.scene_file_path == SceneRouter.COMBAT and master_unit != null, "야습 도적: 스승이 아군으로 합류")
	_check(controller._relationship_defense(enemy_unit, controller._get_player()) > 1.0, "스승과 함께 싸우면 주인공이 인연의 가호를 받음")
	gm.pending_combat = null
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_bond_flow"] = true


## 인물 AI: 직책 인물이 성향·처지에 맞게 계절의 일을 하고, 그 일을 동향·연대기에 남긴다.
func _test_npc_agents() -> void:
	var gm: Node = root.get_node("GameManager")
	# 성향·취향: 데이터가 있으면 그것, 없으면 능력치에서
	var all_ok: bool = NpcRoster.get_all().all(func(npc: Dictionary) -> bool:
		var traits: Dictionary = NpcAgent.get_traits(npc["id"])
		return traits.size() == NpcAgent.TRAIT_NAMES.size() and traits.values().all(func(v: int) -> bool: return v >= 0 and v <= 100) \
			and not NpcAgent.get_likes(npc["id"]).is_empty()
	)
	_check(all_ok, "모든 인물: 성향 5가지(0~100)와 취향")
	_check(NpcAgent.get_traits("npc_master")["caution"] == 75 and NpcAgent.get_traits("npc_cheonma")["ambition"] == 95, "인물 데이터의 성향")
	_check(NpcAgent.describe("npc_healer").contains("좋아함: 선물"), "성향·취향 설명")
	_check(NpcRoster.validate_npc_dict({"id": "x", "display_name": "x", "sect_id": "none", "role": "WANDERER", "traits": {"ambition": 150}, "likes": ["dance"]}).size() == 2, "인물 검증: 성향 범위·취향 종류")
	_check(SectRegistry.validate_sect_dict({"id": "x", "sect_name": "x", "alignment": "RIGHTEOUS", "leader_id": "npc_master", "officers": [{"npc": "npc_master", "post": "king"}]}).size() == 1, "문파 검증: 직책")
	var cheonma: Array = NpcAgent.leader_multipliers("npc_cheonma")
	var wudang: Array = NpcAgent.leader_multipliers("npc_wudang_head")
	_check(cheonma[SectAI.Action.ATTACK] > wudang[SectAI.Action.ATTACK] and wudang[SectAI.Action.FORTIFY] > cheonma[SectAI.Action.FORTIFY], "문주 성향이 세력 AI에: 야망 → 공격, 신중 → 내실")

	# 막내 제자: 계절을 넘기면 NPC 문주가 살림을 맡고 교두·의원도 일한다
	NpcAgent.active = true
	_new_quiet_game(gm, "young_disciple")
	_check(NpcAgent.get_officers(gm.player_sect).size() == 3 and NpcAgent.npc_runs_sect(gm), "우리 문파 직책 인물 3명, 막내 제자면 문주가 살림")
	gm.player_sect.gold = 1500
	gm.player_sect.food = 800
	gm.player_character.internal_energy_current = 10
	var exp_before: int = gm.player_sect.disciples.reduce(func(sum: int, d: DiscipleData) -> int: return sum + d.level * 1000 + d.experience, 0)
	var state_before: Array = [gm.player_sect.disciple_count, gm.player_sect.reputation, gm.player_sect.gold, WorldMap.count(gm.map_state, gm.player_sect.id)]
	gm.advance_turn()
	gm.pending_event.clear()
	var posts: Array = gm.last_npc_report.map(func(r: Dictionary) -> String: return r["post"])
	_check(posts == ["문주", "교두", "의원"] and gm.last_npc_report.all(func(r: Dictionary) -> bool: return not r["action"].is_empty() and not r["detail"].is_empty()), "인물 동향: 문주·교두·의원이 한 일")
	var exp_after: int = gm.player_sect.disciples.reduce(func(sum: int, d: DiscipleData) -> int: return sum + d.level * 1000 + d.experience, 0)
	_check(exp_after > exp_before, "교두가 제자를 가르침")
	_check(gm.last_npc_report[2]["action"] == "치료" and gm.player_character.internal_energy_current > 10, "의원이 내공을 돌봄")
	var leader_action: String = gm.last_npc_report[0]["action"]
	_check(leader_action in ["제자 모집", "시설 확장", "문파 연회", "땅 평정", "사절 파견", "재물 아끼기"], "문주의 결정: %s" % leader_action)
	var state_after: Array = [gm.player_sect.disciple_count, gm.player_sect.reputation, gm.player_sect.gold, WorldMap.count(gm.map_state, gm.player_sect.id)]
	_check(leader_action == "재물 아끼기" or state_after != state_before, "문주의 결정이 문파에 반영됨")
	_check(gm.chronicle.any(func(e: Dictionary) -> bool: return e["kind"] == "인물" and Array(e["lines"]).size() == 3), "인물 동향이 연대기에 남음")

	# 성향대로: 야망이 크면 땅을 넓히고, 신중하면 재물을 아끼거나 시설을 넓힌다
	# (새 게임을 시작하면 인물 데이터를 다시 읽으므로 시작한 뒤에 성향을 바꾼다)
	var counts: Dictionary = {}
	for temper in ["bold", "careful"]:
		counts[temper] = {}
		seed(5)
		for i in 20:
			_new_quiet_game(gm, "young_disciple")
			NpcRoster.get_npc("npc_master")["traits"] = {"ambition": 100, "caution": 0, "benevolence": 0, "greed": 50, "loyalty": 50} if temper == "bold" else {"ambition": 0, "caution": 100, "benevolence": 0, "greed": 50, "loyalty": 50}
			gm.player_sect.gold = 1500
			gm.player_sect.food = 800
			var outcome: Dictionary = NpcAgent._lead(gm, "npc_master")
			counts[temper][outcome["action"]] = counts[temper].get(outcome["action"], 0) + 1
	_check(counts["bold"].get("땅 평정", 0) > counts["careful"].get("땅 평정", 0), "야망 큰 문주는 땅을 더 넓힘 %s / %s" % [counts["bold"], counts["careful"]])
	_check(counts["careful"].get("시설 확장", 0) + counts["careful"].get("재물 아끼기", 0) > counts["bold"].get("시설 확장", 0) + counts["bold"].get("재물 아끼기", 0), "신중한 문주는 시설·저축")
	# 금고가 비면 아낀다
	_new_quiet_game(gm, "young_disciple")
	gm.player_sect.gold = 50
	_check(NpcAgent._lead(gm, "npc_master")["action"] == "재물 아끼기", "금고가 비면 재물을 아낌")

	# 문주면 살림은 내 몫: 문주 NPC는 움직이지 않고 교두·의원만
	_new_quiet_game(gm, "leader")
	gm.advance_turn()
	gm.pending_event.clear()
	_check(gm.last_npc_report.map(func(r: Dictionary) -> String: return r["post"]) == ["교두", "의원"], "내가 문주면 교두·의원만 일함")
	gm.save_game(3)
	gm.last_npc_report.clear()
	gm.load_game(3)
	SaveManager.delete_save(3)
	_check(gm.last_npc_report.size() == 2, "인물 동향 저장·불러오기")
	_check(NpcAgent.format_season(gm.last_npc_report, []).contains("우리 문파 인물"), "강호 동향 글: 우리 문파 인물")
	NpcAgent.active = false
	_completed["_test_npc_agents"] = true
