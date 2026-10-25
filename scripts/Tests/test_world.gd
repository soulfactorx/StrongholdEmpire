extends "res://scripts/Tests/test_base.gd"

## 스모크 테스트 — 강호: 인물·문파 데이터, 문파전·밸런스, 외교, 세력 AI·침공
## 실행 순서는 smoke_test.gd의 INIT_SEQUENCE·RUNTIME_SEQUENCE가 정한다.


func _test_npc_roster() -> void:
	var npcs: Array[Dictionary] = NpcRoster.get_all()
	_check(
		npcs.size() > 0 and npcs.size() == _count_json(NpcRoster.NPC_DIR),
		"NPC JSON %d개 모두 검증 통과" % npcs.size()
	)
	var bad_sect_refs: PackedStringArray = []
	for npc in npcs:
		if not (SectRegistry.has_sect(npc["sect_id"]) or npc["sect_id"] == NpcRoster.NO_SECT):
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
	var fellow_bond: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_senior_brother")
	_check(
		relationships.size() == 4 and master_bond.bond_strength == 35 and master_bond.stage == 1
		and rival_bond.bond_type == RelationshipData.BondType.RIVALRY and rival_bond.bond_strength == 15
		and fellow_bond.bond_type == RelationshipData.BondType.FELLOW,
		"문파 데이터의 initial_bonds로 시작 관계 생성 (청운검파: 사부·동문 둘·라이벌)"
	)
	_check(RelationshipManager.create_default_relationships("none").is_empty(), "무소속은 시작 인연 없음")
	var tang: Array[RelationshipData] = RelationshipManager.create_default_relationships("tang")
	_check(RelationshipManager.get_bond_with(tang, "npc_tang_head").bond_type == RelationshipData.BondType.MASTER_DISCIPLE, "사천당가: 가주가 사부")

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
	var optional: Array = SectRegistry.get_optional_ids()
	_check(rivals.size() == _count_json(SectRegistry.SECT_DIR) - 1 - optional.size(), "플레이어 문파 외 세력 %d개 생성 (골라 넣는 세력 %d개는 빼고)" % [rivals.size(), optional.size()])
	_check(optional.size() >= 3 and rivals.all(func(x: SectData) -> bool: return not x.id in optional), "골라 넣는 세력은 기본으로 나오지 않음")
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

	# 해가 바뀌면 굴복하지 않은 세력만 성장 (연간 정산만 따로 본다. 계절마다의 세력 AI는 _test_sect_ai에서)
	var namgung: SectData = gm.get_world_sect("namgung")
	var namgung_before: int = namgung.disciple_count
	var heukpung_before: int = heukpung.disciple_count
	gm._process_yearly_events()
	_check(namgung.disciple_count == namgung_before + _Balance.WORLD_SECT_YEARLY_GROWTH, "강호 세력 연간 성장")
	_check(heukpung.disciple_count == heukpung_before, "굴복한 세력은 성장하지 않음")
	gm.advance_turn()
	gm.pending_event.clear()
	gm.pending_combat = null
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
	SceneRouter.goto(tree, SceneRouter.SECT_WAR)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	_check(screen.target_buttons.size() == 3 and screen.formation_buttons.size() == 4, "문파전 화면: 대상·진형 선택지")
	# 누가 누구와 싸우는지: 우리 문파(지휘하는 나)와 고른 상대가 맞대결 판에 함께 보인다
	var target: SectData = screen._get_target()
	_check(screen.ours_label.text.begins_with(gm.player_sect.sect_name + " (우리 문파)") and screen.ours_label.text.contains("지휘: 화면"), "맞대결 판: 우리 문파와 지휘하는 나")
	_check(screen.theirs_label.text.begins_with(target.sect_name + " (상대)") and screen.title_label.text.contains("VS " + target.sect_name), "맞대결 판: 상대 문파")
	screen._on_target_pressed(1)
	_check(screen._get_target() == screen._targets[1] and screen.theirs_label.text.begins_with(screen._targets[1].sect_name), "상대를 누르면 바뀜")
	screen._on_target_pressed(0)
	_check(screen.chance_label.text.begins_with("예상 승률") and screen.stakes_label.text.contains("이기면"), "예상 승률과 걸린 것")
	_check(screen.round_rows[0]["enemy"].text.contains("?"), "정찰 전에는 적 명령을 모름")
	screen._on_scout_pressed()
	_check(not screen.round_rows[0]["enemy"].text.contains("?"), "정찰 후 1합 적 명령 표시")
	screen._on_formation_pressed(SectWarManager.Formation.CIRCLE)
	_check(screen.get_selected_formation() == SectWarManager.Formation.CIRCLE and screen.formation_hint.text.contains("방원진"), "진형 고르기")
	# 합마다 명령: 고르면 상성이 보이고, 다시 누르면 지운다. 연속 명령은 표시
	screen._on_round_command(0, C.FLANK)
	_check(screen.round_rows[0]["hint"].text != "아직 고르지 않음", "1합 명령의 상성 표시 (%s)" % screen.round_rows[0]["hint"].text)
	screen._on_round_command(1, C.FLANK)
	_check(screen.round_rows[1]["buttons"][2].text.contains("연속"), "같은 명령을 잇달아 쓰면 표시")
	screen._on_round_command(1, C.FLANK)
	_check(screen.get_commands().size() == 1, "다시 누르면 그 합의 명령을 지움")
	screen._add_command(C.FLANK)
	screen._add_command(C.CHARGE)
	_check(not screen.execute_button.disabled and screen.execute_button.text.contains(target.sect_name), "명령 3개를 고르면 전투 개시 가능")
	screen._on_execute_pressed()
	_check(screen.log_label.text.contains("3합:") and not gm.can_wage_war(), "전투 결과 표시와 계절당 1회 제한")
	_check(screen.result_overlay.visible and screen.result_headline.text in ["승리", "패배"] and screen.result_body.text.contains("3합"), "결과 판: 승패와 합마다 결과")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_war_flow"] = true


func _test_diplomacy() -> void:
	var gm: Node = root.get_node("GameManager")

	# 문주·중간관리자만 외교
	_new_quiet_game(gm, "young_disciple")
	_check(not gm.do_diplomacy("namgung", "envoy")["success"], "막내 제자는 외교 불가")

	_new_quiet_game(gm, "leader")
	var namgung: SectData = gm.get_world_sect("namgung")
	var heukpung: SectData = gm.get_world_sect("heukpung")
	namgung.attitude = 0

	# 사절: 금화 소모, 태도 상승, 세력마다 계절에 한 번
	var gold: int = gm.player_sect.gold
	_check(gm.do_diplomacy("namgung", "envoy")["success"] and namgung.attitude == _Balance.DIPLOMAT_ENVOY_ATTITUDE, "사절: 태도 +%d" % _Balance.DIPLOMAT_ENVOY_ATTITUDE)
	_check(gm.player_sect.gold == gold - _Balance.DIPLOMAT_ENVOY_GOLD, "사절: 금화 소모")
	_check(not gm.do_diplomacy("namgung", "envoy")["success"], "같은 세력과는 계절에 한 번")
	_check(gm.do_diplomacy("heukpung", "envoy")["success"], "다른 세력과는 같은 계절에도 가능")

	# 동맹: 태도 50 이상, 동맹은 공격 불가, 문파전 원군
	gm.advance_turn()
	_check(not gm.do_diplomacy("namgung", "alliance")["success"], "태도가 낮으면 동맹 거절")
	namgung.attitude = _Balance.ALLIANCE_MIN_ATTITUDE
	var support_before: int = DiplomacyManager.get_ally_support(gm.world_sects)
	_check(gm.do_diplomacy("namgung", "alliance")["success"] and namgung.allied, "태도 %d: 동맹 성립" % _Balance.ALLIANCE_MIN_ATTITUDE)
	var support: int = DiplomacyManager.get_ally_support(gm.world_sects)
	_check(support_before == 0 and support == roundi(SectWarManager.get_sect_power(namgung) * _Balance.ALLY_WAR_SUPPORT_RATIO), "동맹 원군 전력")
	_check(not gm.get_war_targets().has(namgung), "동맹은 문파전 대상에서 빠짐")
	_check(not gm.resolve_sect_war("namgung", [0, 0, 0])["success"], "동맹 세력 공격 거부")
	var options: Array = DiplomacyManager.get_options(gm, namgung).map(func(o: Dictionary) -> String: return o["id"])
	_check(options.has("break_alliance") and not options.has("alliance") and not options.has("challenge"), "동맹 상태의 외교 선택지")
	# 원군이 문파전 전력에 들어간다 (복사본으로 시험)
	var commands: Array[SectWarManager.Command] = [SectWarManager.Command.CHARGE, SectWarManager.Command.FLANK, SectWarManager.Command.DEFEND]
	var sect_copy: SectData = _SaveManager.deserialize_sect(_SaveManager.serialize_sect(gm.player_sect))
	var enemy_copy: SectData = _SaveManager.deserialize_sect(_SaveManager.serialize_sect(heukpung))
	enemy_copy.disciple_count = 60
	var lost: Dictionary = SectWarManager.resolve_battle(sect_copy, gm.player_character, enemy_copy, commands)
	var won: Dictionary = SectWarManager.resolve_battle(sect_copy, gm.player_character, enemy_copy, commands, {}, SectWarManager.Formation.NONE, {}, 5000)
	_check(not lost["victory"] and won["victory"], "동맹 원군 전력이 문파전 승패에 반영")
	# 동맹 파기
	gm.advance_turn()
	var rep: int = gm.player_sect.reputation
	var attitude: int = namgung.attitude
	_check(gm.do_diplomacy("namgung", "break_alliance")["success"] and not namgung.allied, "동맹 파기")
	_check(namgung.attitude == attitude - _Balance.ALLIANCE_BREAK_ATTITUDE and gm.player_sect.reputation == rep - _Balance.ALLIANCE_BREAK_REPUTATION, "동맹 파기: 태도·명성 하락")

	# 도전장: 명성 +, 태도 -, 결판에 명성이 더 걸린다
	rep = gm.player_sect.reputation
	attitude = heukpung.attitude
	_check(gm.do_diplomacy("heukpung", "challenge")["success"] and gm.challenge_target == "heukpung", "도전장 발송")
	_check(gm.player_sect.reputation == rep + _Balance.CHALLENGE_REPUTATION and heukpung.attitude == attitude - _Balance.CHALLENGE_ATTITUDE, "도전장: 명성 +, 태도 -")
	gm.advance_turn()
	_check(not gm.do_diplomacy("heukpung", "challenge")["success"], "도전장은 결판 전까지 한 번")
	rep = gm.player_sect.reputation
	var result: Dictionary = gm.resolve_sect_war("heukpung", [0, 1, 2])
	_check(gm.challenge_target == "" and result["message"].contains("도전장"), "문파전으로 도전장 결판")

	# 공물: 굴복한 세력에게서 계절마다
	heukpung.subjugated = true
	heukpung.attitude = -40
	options = DiplomacyManager.get_options(gm, heukpung).map(func(o: Dictionary) -> String: return o["id"])
	_check(options.has("tribute") and not options.has("envoy"), "굴복한 세력: 공물 요구 가능")
	gm.advance_turn()
	_check(gm.do_diplomacy("heukpung", "tribute")["success"] and heukpung.tribute, "공물 요구")
	var forecast: int = gm.estimate_next_season()["gold"]
	gold = gm.player_sect.gold
	gm.advance_turn()
	_check(gm.player_sect.gold - gold == forecast and gm.last_turn_report.contains("공물"), "공물: 계절 금화 수입 (예상 수지 반영)")
	_check(heukpung.attitude == -40 - _Balance.TRIBUTE_ATTITUDE_PER_SEASON, "공물을 바칠 때마다 원망이 쌓임")
	heukpung.attitude = _Balance.TRIBUTE_REVOLT_ATTITUDE
	gm.advance_turn()
	_check(not heukpung.tribute and gm.last_turn_report.contains("끊었습니다"), "원망이 극에 달하면 공물을 끊음")
	heukpung.tribute = true
	heukpung.attitude = -40
	gm.advance_turn()
	_check(gm.do_diplomacy("heukpung", "release_tribute")["success"] and not heukpung.tribute and heukpung.attitude > -40, "공물 면제: 태도 상승")

	# 혼담: 그 세력의 연인 (유대 60) → 동맹·사돈
	_new_quiet_game(gm, "leader")
	namgung = gm.get_world_sect("namgung")
	_check(not gm.do_diplomacy("namgung", "marriage")["success"], "연인이 없으면 혼담 불가")
	var lady := RelationshipData.new()
	lady.target_id = "npc_namgung_lady"
	lady.target_name = "남궁설"
	lady.bond_type = RelationshipData.BondType.ROMANCE
	lady.increase_bond(_Balance.MARRIAGE_MIN_BOND)
	gm.player_relationships.append(lady)
	gm.player_sect.gold = 1000
	_check(gm.do_diplomacy("namgung", "marriage")["success"] and namgung.married and namgung.allied, "혼담 성사: 사돈이자 동맹")
	_check(gm.story_flags.get("arc_love_married", false) and gm.story_flags.get("married_namgung", false), "혼담: 연애 아크 혼례로 연결")
	_check(gm.player_sect.gold == 1000 - _Balance.MARRIAGE_GOLD, "혼담 비용")

	# 저장·복원
	gm.challenge_target = "heukpung"
	gm.get_world_sect("cheonma").tribute = true
	gm._apply_save_data(JSON.parse_string(JSON.stringify({
		"character": _SaveManager.serialize_character(gm.player_character),
		"sect": _SaveManager.serialize_sect(gm.player_sect),
		"world_sects": _SaveManager.serialize_sects(gm.world_sects),
		"challenge_target": gm.challenge_target,
	})))
	namgung = gm.get_world_sect("namgung")
	_check(namgung.allied and namgung.married and gm.get_world_sect("cheonma").tribute and gm.challenge_target == "heukpung", "외교 상태 저장·복원")
	_completed["_test_diplomacy"] = true


func _test_diplomacy_screen() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "leader")
	gm.get_world_sect("namgung").attitude = _Balance.ALLIANCE_MIN_ATTITUDE
	SceneRouter.goto(tree, SceneRouter.WORLD)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	var buttons: Array = screen.sect_list.get_children().filter(func(c: Node) -> bool: return c is Button)
	_check(buttons.size() == gm.world_sects.size() and buttons.all(func(b: Button) -> bool: return b.custom_minimum_size.y >= 48), "강호 정세: 세력마다 외교 버튼(48px)")
	screen._on_diplomacy_pressed("namgung")
	_check(screen.choice_popup.visible and screen.choice_popup.get_option_count() >= 3, "외교 선택지 팝업")
	screen.choice_popup._on_option_pressed("alliance")
	await process_frame
	_check(gm.get_world_sect("namgung").allied and screen.log_label.text.contains("동맹"), "화면에서 동맹 체결")
	var titles: String = ""
	for label in screen.sect_list.find_children("*", "Label", true, false):
		titles += label.text
	_check(titles.contains("동맹"), "세력 목록에 동맹 표시")
	# 외교를 할 수 없는 역할은 버튼 없이 까닭을 보인다 (눌러도 반응이 없는 것처럼 보이지 않게)
	_new_quiet_game(gm, "young_disciple")
	SceneRouter.goto(tree, SceneRouter.WORLD)
	await process_frame
	await process_frame
	screen = current_scene
	buttons = screen.sect_list.get_children().filter(func(c: Node) -> bool: return c is Button)
	_check(buttons.is_empty() and screen.log_label.text.contains("막내 제자"), "외교할 수 없는 역할: 버튼 대신 까닭")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_diplomacy_screen"] = true


func _test_sect_ai() -> void:
	var gm: Node = root.get_node("GameManager")
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	var sects: Array[SectData] = ScenarioManager.create_rival_sects()
	var namgung: SectData = sects.filter(func(x: SectData) -> bool: return x.id == "namgung")[0]
	var heukpung: SectData = sects.filter(func(x: SectData) -> bool: return x.id == "heukpung")[0]

	# 침공 조건: 태도가 낮을수록, 첫해·동맹·우호·쿨다운이면 없음
	namgung.attitude = 0
	heukpung.attitude = -60
	_check(SectAI.get_weights(namgung, sects, 10, 3, 1.0)[SectAI.Action.INVADE] == 0.0, "우호·중립 세력은 침공하지 않음")
	_check(SectAI.get_weights(heukpung, sects, 10, 3, 1.0)[SectAI.Action.INVADE] > 0.0, "적대 세력은 침공할 수 있음")
	_check(SectAI.get_weights(heukpung, sects, 2, 1, 1.0)[SectAI.Action.INVADE] == 0.0, "첫해에는 침공 없음")
	_check(SectAI.get_weights(heukpung, sects, 10, 3, 0.0)[SectAI.Action.INVADE] == 0.0, "기연 빈도 0이면 침공 없음")
	var hostile: float = SectAI.get_weights(heukpung, sects, 10, 3, 1.0)[SectAI.Action.INVADE]
	heukpung.attitude = -100
	_check(SectAI.get_weights(heukpung, sects, 10, 3, 1.0)[SectAI.Action.INVADE] > hostile, "태도가 낮을수록 침공이 잦음")
	heukpung.last_invasion_turn = 9
	_check(SectAI.get_weights(heukpung, sects, 10, 3, 1.0)[SectAI.Action.INVADE] == 0.0, "침공 뒤 %d계절은 쉼" % _Balance.AI_INVASION_COOLDOWN)
	heukpung.last_invasion_turn = -1
	heukpung.allied = true
	_check(not SectAI.can_invade(heukpung, 10, 3), "동맹은 침공하지 않음")
	heukpung.allied = false
	ScenarioRules.apply({"ai_aggression": 0.0})
	var calm: Array[float] = SectAI.get_weights(heukpung, sects, 10, 3, 1.0)
	_check(calm[SectAI.Action.ATTACK] == 0.0 and calm[SectAI.Action.INVADE] == 0.0, "호전성 0이면 싸우지 않음")
	ScenarioRules.reset()

	# 계절마다 침공은 한 세력만
	ScenarioRules.apply({"ai_aggression": 3.0})
	for sect in sects:
		sect.attitude = -100
	seed(11)
	var invasions: int = 0
	var max_per_season: int = 0
	for season in 40:
		for sect in sects:
			sect.last_invasion_turn = -1
		var result: Dictionary = SectAI.run_season(sects, 10 + season, 3, 1.0)
		var count: int = Array(result["news"]).filter(func(line: String) -> bool: return line.contains("침공")).size()
		max_per_season = maxi(max_per_season, count)
		if not result["invader"].is_empty():
			invasions += 1
	_check(invasions > 0 and max_per_season <= 1, "침공은 계절에 한 세력만 (40계절 중 %d번)" % invasions)
	ScenarioRules.reset()

	# 세력끼리의 전쟁: 제자는 최소치 아래로 줄지 않고, 몰락한 세력은 치지 않는다
	sects = ScenarioManager.create_rival_sects()
	for sect in sects:
		sect.disciple_count = 12
	var news: String = SectAI._attack(sects[0], sects)
	_check(news.contains(sects[0].sect_name), "세력 전쟁 소식")
	sects[1].disciple_count = _Balance.AI_ATTACK_MIN_TARGET_DISCIPLES - 1
	_check(not SectAI._attack_targets(sects[0], sects).has(sects[1]), "제자가 적은 세력은 공격 대상에서 빠짐")
	sects[2].subjugated = true
	var frozen: int = sects[2].disciple_count
	for season in 20:
		SectAI.run_season(sects, season, 3, 0.0)
	_check(sects[2].disciple_count == frozen, "굴복한 세력은 움직이지 않음")
	_check(sects.all(func(x: SectData) -> bool: return x.disciple_count >= _Balance.AI_MIN_DISCIPLES), "세력 제자는 최소치 아래로 줄지 않음")

	# 밸런스: 시뮬레이션 100판에서 세력 하나가 5년 안에 다른 세력을 모두 무너뜨리지 않는다
	for scenario_id in ["cheonha", "heukpung_winter", "gangho_100"]:
		ScenarioManager.activate(scenario_id)
		seed(scenario_id.hash())
		var dominated: int = 0
		for run in 100:
			var world: Array[SectData] = ScenarioManager.create_rival_sects()
			for season in 20:
				SectAI.run_season(world, 4 + season, 1 + (season + 1) / 4, 0.0)
				if (season + 1) % 4 == 0:
					SectWarManager.grow_world_sects(world)
			var fallen: int = world.filter(func(x: SectData) -> bool: return x.disciple_count <= _Balance.SUBJUGATE_DISCIPLE_THRESHOLD).size()
			if world.size() > 1 and fallen >= world.size() - 1:
				dominated += 1
		_check(dominated == 0, "세력 AI 밸런스 (%s): 100판 중 한 세력이 5년 안에 강호를 휩쓴 판 %d" % [scenario_id, dominated])
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)

	# 계절 진행과 연결: 세력 AI가 움직여 강호 소식이 쌓이고, 기연 빈도 0이면 침공은 없다
	SectAI.active = true
	gm.start_new_game("세력", "leader", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	var powers_before: Array = gm.world_sects.map(func(x: SectData) -> int: return x.disciple_count + x.reputation)
	for i in 8:
		gm.advance_turn()
	var powers_after: Array = gm.world_sects.map(func(x: SectData) -> int: return x.disciple_count + x.reputation)
	_check(powers_after != powers_before and gm.pending_invasion == "", "계절 진행마다 세력 AI가 움직임 (기연 빈도 0이면 침공 없음)")
	SectAI.active = false

	# 침공 대응
	gm.start_new_game("침공", "leader", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	var invader: SectData = gm.get_world_sect("heukpung")
	gm.pending_invasion = "heukpung"
	var gold: int = gm.player_sect.gold
	_check(gm.resolve_invasion("bribe")["success"] and gm.player_sect.gold == gold - _Balance.INVASION_BRIBE_GOLD and gm.pending_invasion == "", "침공: 금화로 물림")
	gm.pending_invasion = "heukpung"
	var disciples: int = gm.player_sect.disciple_count
	var rep: int = gm.player_sect.reputation
	gm.resolve_invasion("yield")
	_check(gm.player_sect.disciple_count == disciples - _Balance.INVASION_YIELD_DISCIPLES and gm.player_sect.reputation == rep - _Balance.INVASION_YIELD_REPUTATION, "침공: 산문을 내줌")
	_check(gm.player_sect.disciples.size() == gm.player_sect.disciple_count, "산문을 내주면 명단에서도 제자가 빠짐")
	gm.pending_invasion = "heukpung"
	disciples = gm.player_sect.disciple_count
	gm.advance_turn()
	_check(gm.pending_invasion == "" and gm.player_sect.disciple_count < disciples and gm.last_turn_report.contains("산문을 내주었습니다"), "대응하지 않고 계절을 넘기면 산문을 내준 것으로")
	_check(gm.world_news.filter(func(line: String) -> bool: return line.contains("산문을 내주었습니다")).size() == 2, "침공 결과가 강호 소식에 남음")

	# 방어전 구성
	var setup: CombatSetup = CombatManager.create_invasion(invader, gm.player_character, gm.player_sect)
	var enemy_ids: Array = setup.enemies.map(func(c: CharacterData) -> String: return c.id)
	_check(setup.invader_id == "heukpung" and enemy_ids.has("npc_heukpung_second") and enemy_ids.has("npc_bandit_0"), "방어전: 흑풍채 졸개와 부채주")
	_check(setup.allies_are_disciples and setup.allies.size() == _Balance.DEFENSE_ALLY_COUNT, "방어전: 문파 제자 합류")
	var cheonma_setup: CombatSetup = CombatManager.create_invasion(gm.get_world_sect("cheonma"), gm.player_character)
	_check(cheonma_setup.enemies.size() == 5 and cheonma_setup.enemies.any(func(c: CharacterData) -> bool: return c.id == "npc_cheonma_envoy"), "큰 세력은 졸개가 많음 (천마신교 4명 + 혈영)")

	# 강호 소식은 최근 %d건까지
	for i in 30:
		gm.add_world_news("소식 %d" % i)
	_check(gm.world_news.size() == _Balance.WORLD_NEWS_LIMIT and gm.world_news[-1].contains("소식 29"), "강호 소식 보관 개수 제한")

	# 저장·복원
	gm.pending_invasion = "cheonma"
	invader.last_invasion_turn = 7
	gm._apply_save_data(JSON.parse_string(JSON.stringify({
		"character": _SaveManager.serialize_character(gm.player_character),
		"sect": _SaveManager.serialize_sect(gm.player_sect),
		"world_sects": _SaveManager.serialize_sects(gm.world_sects),
		"pending_invasion": gm.pending_invasion,
		"world_news": gm.world_news,
	})))
	_check(gm.pending_invasion == "cheonma" and gm.world_news.size() == _Balance.WORLD_NEWS_LIMIT and gm.get_world_sect("heukpung").last_invasion_turn == 7, "침공·강호 소식 저장·복원")

	# 문파 데이터 검증: 졸개·우두머리
	var bad: PackedStringArray = SectRegistry.validate_sect_dict({
		"id": "x", "sect_name": "x", "leader_id": "npc_master", "alignment": "RIGHTEOUS", "soldier_npc": "no_such",
	})
	_check(Array(bad).any(func(e: String) -> bool: return e.contains("soldier_npc")), "없는 졸개 인물 검출")
	_completed["_test_sect_ai"] = true


func _test_invasion_flow() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.start_new_game("침공", "leader", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	gm.pending_invasion = "heukpung"
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	_check(hub.invasion_popup.visible and hub.invasion_popup.get_option_count() == 3, "경영 화면: 침공 대응 팝업")
	var heukpung: SectData = gm.get_world_sect("heukpung")
	var before: int = heukpung.disciple_count
	hub.invasion_popup._on_option_pressed("fight")
	await process_frame
	await process_frame
	var controller: Node = current_scene
	_check(controller.scene_file_path == SceneRouter.COMBAT and gm.pending_combat.invader_id == "heukpung", "맞서 싸우면 방어전")
	for unit in controller.engine.foes:
		unit.take_damage(unit.hp - 1)
	controller.engine.friend_index = controller.engine.friends.find(controller.engine.get_player())
	await controller.skip_to_result()
	_check(heukpung.disciple_count == before - _Balance.INVASION_REPEL_LOSS and gm.world_news[-1].contains("막아 냈습니다"), "침공을 막아 내면 침략 세력 제자 감소, 강호 소식")
	SceneRouter.goto(tree, SceneRouter.WORLD)
	await process_frame
	await process_frame
	var texts: String = ""
	for child in current_scene.npc_list.get_children():
		if child is Label:
			texts += child.text
	_check(texts.contains("강호 소식") and texts.contains("막아 냈습니다"), "강호 정세 화면에 강호 소식")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_invasion_flow"] = true


## 강호 지도와 세력 전략: 본거지, 평정·공략으로 땅 넓히기, 땅 수입, 세력 AI의 확장과 계절 보고, 저장
func _test_world_map_and_factions() -> void:
	var gm: Node = root.get_node("GameManager")
	var file := FileAccess.open(WorldMap.MAP_PATH, FileAccess.READ)
	_check(WorldMap.validate_map_dict(JSON.parse_string(file.get_as_text())).is_empty() and WorldMap.get_regions().size() >= 18, "지도 데이터 검증 (지역 %d곳)" % WorldMap.get_regions().size())
	_check(WorldMap.validate_map_dict({"regions": [{"id": "a", "name": "가", "pos": [0, 0], "neighbors": ["b"]}, {"id": "b", "name": "나", "pos": [1, 1]}]}).size() == 1, "지도 검증: 한쪽 이웃 관계")

	# 새 판: 등장 세력마다 본거지, 골라 넣는 세력은 기본으로 없음
	_new_quiet_game(gm, "leader")
	var state: Dictionary = gm.map_state
	_check(WorldMap.get_home(state, "qingyun") == "qingyun" and WorldMap.get_home(state, "namgung") == "hefei" and WorldMap.get_home(state, "wudang").is_empty(), "본거지: 등장 세력만")
	_check(gm.get_player_regions().size() == 1 and gm.get_world_sect("wudang") == null, "시작: 우리 땅은 본거지 하나")

	# 평정: 맞닿은 빈 땅, 계절에 한 번, 수입·정원 증가
	gm.player_sect.gold = 1000
	gm.player_sect.food = 500
	var max_disciples: int = gm.player_sect.max_disciples
	var forecast: int = gm.estimate_next_season()["gold"]
	_check(gm.get_region_action("beijing")["kind"] == "none", "맞닿지 않은 땅은 노릴 수 없음")
	_check(gm.get_region_action("hefei")["kind"] == "attack" and not gm.get_region_action("hefei")["reason"].is_empty(), "본거지는 빼앗을 수 없음")
	var action: Dictionary = gm.get_region_action("luoyang")
	_check(action["kind"] == "pacify" and action["reason"].is_empty(), "맞닿은 빈 땅: 평정 가능")
	var result: Dictionary = gm.pacify_region("luoyang")
	_check(result["success"] and WorldMap.get_owner(gm.map_state, "luoyang") == "qingyun" and gm.player_sect.gold == 1000 - action["cost"]["gold"], "평정: 땅 차지, 비용")
	_check(gm.player_sect.max_disciples == max_disciples + _Balance.REGION_MAX_DISCIPLES, "평정: 제자 정원 증가")
	_check(gm.estimate_next_season()["gold"] == forecast + int(WorldMap.get_region("luoyang")["gold"]), "땅 수입이 다음 계절 예상에 들어감")
	_check(not gm.pacify_region("kaifeng")["success"], "평정은 계절에 한 번")
	_check(gm.chronicle[-1]["kind"] == "영토", "평정은 연대기에 남음")

	# 공략: 남의 땅은 문파전에서 이기면 차지 (공략으로 고른 땅이 먼저)
	var namgung: SectData = gm.get_world_sect("namgung")
	gm.map_state["owners"]["kaifeng"] = "namgung"
	action = gm.get_region_action("kaifeng")
	_check(action["kind"] == "attack" and action["reason"].is_empty(), "맞닿은 남의 땅: 공략 가능")
	_check(gm.prepare_region_attack("kaifeng")["success"] and gm.pending_region_target == "kaifeng", "공략: 문파전 대상 지정")
	_check(gm._capture_region_from(namgung) == "kaifeng" and WorldMap.get_owner(gm.map_state, "kaifeng") == "qingyun", "문파전 승리: 공략한 땅 차지")
	# 침공을 막지 못하면 맞닿은 땅부터 잃는다 (본거지는 빼고)
	gm.pending_invasion = "namgung"
	gm.resolve_invasion("yield")
	_check(WorldMap.get_owner(gm.map_state, "kaifeng") == "namgung" and WorldMap.get_owner(gm.map_state, "qingyun") == "qingyun", "산문을 내주면 땅을 잃음 (본거지는 그대로)")

	# 문주가 아니면 땅을 넓히지 못한다
	_new_quiet_game(gm, "wanderer")
	_check(gm.get_region_action("luoyang")["kind"] == "none" and gm.get_region_action("luoyang")["reason"].contains("문주"), "문주만 땅을 넓힘")

	# 세력 설정: 골라 넣는 세력과 전략
	gm.start_new_game("세력", "leader", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0}, false, false, {
		"extra": ["wudang", "tang"], "strategies": {"namgung": "military", "heukpung": FactionStrategy.RANDOM},
	})
	_check(gm.get_world_sect("wudang") != null and gm.get_world_sect("tang") != null and gm.get_world_sect("haomun") == null, "골라 넣은 세력만 등장")
	_check(WorldMap.get_home(gm.map_state, "wudang") == "wudang" and gm.get_world_sect("namgung").strategy == "military", "새 세력의 본거지와 고른 전략")
	_check(FactionStrategy.is_valid(gm.get_world_sect("heukpung").strategy), "무작위 전략은 실제 전략으로")
	_check(FactionStrategy.of(gm.get_world_sect("wudang")) == "economy", "데이터의 기본 전략")

	# 세력 AI: 계절마다 세력별 보고, 확장 전략은 빈 땅을 차지한다
	seed(7)
	var expanded: bool = false
	var reports_ok: bool = true
	for season in 12:
		var outcome: Dictionary = SectAI.run_season(gm.world_sects, 8 + season, 3, 0.0, gm.map_state)
		reports_ok = reports_ok and outcome["reports"].size() == gm.world_sects.size() and Array(outcome["reports"]).all(
			func(r: Dictionary) -> bool: return not r["action"].is_empty() and not r["detail"].is_empty() and not r["strategy"].is_empty()
		)
		if WorldMap.count(gm.map_state, "namgung") + WorldMap.count(gm.map_state, "cheonma") + WorldMap.count(gm.map_state, "wudang") > 3:
			expanded = true
	_check(reports_ok, "세력 동향: 세력마다 전략·행동·내용")
	_check(expanded, "세력 AI가 땅을 넓힘")
	_check(SectAI.format_reports(gm.last_faction_report).contains("움직이지") and SectAI.format_reports([{"sect_name": "가", "strategy": "나", "action": "다", "detail": "라"}]).contains("가 [나 전략] 다"), "세력 동향 글")
	var economy: SectData = gm.get_world_sect("wudang")
	economy.gold = _Balance.AI_FORTIFY_GOLD
	economy.training_ground_level = 1
	var weights: Array[float] = SectAI.get_weights(economy, gm.world_sects, 10, 3, 1.0, gm.map_state)
	_check(weights[SectAI.Action.FORTIFY] > weights[SectAI.Action.ATTACK], "내실 전략: 무술장 확장을 공격보다 자주")
	economy.gold = 0
	_check(SectAI.get_weights(economy, gm.world_sects, 10, 3, 1.0, gm.map_state)[SectAI.Action.FORTIFY] == 0.0, "금화가 모자라면 내실 없음")

	# 계절 진행: 세력 동향을 남기고, 저장·불러오기 뒤에도 지도·전략·동향이 남는다
	SectAI.active = true
	gm.advance_turn()
	SectAI.active = false
	_check(gm.last_faction_report.size() == gm.world_sects.size(), "계절 진행: 세력 동향 기록")
	gm.map_state["owners"]["luoyang"] = "qingyun"
	gm.save_game(3)
	_new_quiet_game(gm, "leader")
	gm.load_game(3)
	SaveManager.delete_save(3)
	_check(WorldMap.get_owner(gm.map_state, "luoyang") == "qingyun" and gm.get_world_sect("wudang") != null and gm.get_world_sect("namgung").strategy == "military", "지도·세력·전략 저장·불러오기")
	_check(gm.last_faction_report.size() == gm.world_sects.size(), "세력 동향 저장·불러오기")
	_check(EventManager.conditions_met([{"type": "regions_owned", "op": ">=", "value": 2}], gm.player_character, gm.player_sect, gm.player_relationships, "봄", gm.story_flags), "regions_owned 조건")
	_completed["_test_world_map_and_factions"] = true


## 지도 화면·세력 동향 창·새 게임 세력 설정
func _test_map_screens() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "leader")
	gm.player_sect.gold = 1000
	gm.player_sect.food = 500
	SceneRouter.goto(tree, SceneRouter.MAP)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	_check(screen._region_buttons.size() == WorldMap.get_regions().size() and screen.get_selected() == "qingyun", "지도 화면: 지역 버튼, 본거지 선택")
	_check(screen._region_buttons.values().all(func(b: Button) -> bool: return b.custom_minimum_size.y >= 48), "지역 버튼은 48px 이상")
	screen.select_region("luoyang")
	_check(screen.action_button.visible and not screen.action_button.disabled and screen.action_button.text.begins_with("평정"), "빈 땅: 평정 버튼")
	screen._on_action_pressed()
	_check(WorldMap.get_owner(gm.map_state, "luoyang") == "qingyun" and screen.summary_label.text.contains("땅 2"), "지도 화면에서 평정")
	screen.select_region("beijing")
	_check(not screen.action_button.visible and not screen.log_label.text.is_empty(), "닿지 않는 땅: 까닭 안내")
	screen.open_report()
	_check(screen.report_popup.visible, "지도 화면: 세력 동향 창")
	screen.report_popup.visible = false
	# 공략: 문파전 화면으로, 그 땅의 주인을 먼저 고른다
	gm.map_state["owners"]["kaifeng"] = "heukpung"
	screen.refresh()
	screen.select_region("kaifeng")
	screen._on_action_pressed()
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.SECT_WAR and current_scene._get_target().id == "heukpung", "공략: 문파전 화면에서 그 땅의 주인을 고름")
	gm.pending_region_target = ""
	# 굴복한 세력의 땅은 본거지까지 문파전 없이 편입한다 (문파전 대상에서는 빠져 있으므로)
	var namgung: SectData = gm.get_world_sect("namgung")
	var hefei: String = WorldMap.get_home(gm.map_state, "namgung")
	namgung.subjugated = true
	gm.player_sect.gold = 5000
	gm.player_sect.food = 5000
	gm.story_flags.erase("last_pacify_turn")
	var annex: Dictionary = gm.get_region_action(hefei)
	_check(not gm.get_war_targets().has(namgung) and annex["kind"] == "annex" and annex["reason"].is_empty(), "굴복한 세력의 본거지: 편입 (%s)" % [annex])
	var annexed: Dictionary = gm.annex_region(hefei)
	_check(annexed["success"] and WorldMap.get_owner(gm.map_state, hefei) == gm.player_sect.id and WorldMap.get_home(gm.map_state, "namgung").is_empty(), "편입: 본거지를 거둠 (%s)" % annexed["message"])
	_check(not gm.annex_region(hefei)["success"], "편입한 땅은 다시 편입하지 않음")
	namgung.subjugated = false

	# 경영 화면: 계절을 넘기면 세력 동향 창 (설정)
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	GameSettings.faction_report = true
	SectAI.active = true
	hub._on_advance_turn_pressed()
	SectAI.active = false
	GameSettings.faction_report = false
	GameSettings.action_scenes = false
	_check(hub.faction_popup.visible and hub.faction_popup._message.text.contains("전략"), "계절을 넘기면 세력 동향 창")
	hub.faction_popup.visible = false

	# 새 게임 화면: 세력 설정
	SceneRouter.goto(tree, SceneRouter.NEW_GAME)
	await process_frame
	await process_frame
	var new_game: Node = current_scene
	for i in new_game._scenarios.size():
		if new_game._scenarios[i]["id"] == "cheonha":
			new_game.scenario_list.select(i)
			new_game._on_scenario_selected(i)
	_check(new_game._faction_rows.size() == SectRegistry.get_default_rival_ids().size() + SectRegistry.get_optional_ids().size(), "새 게임: 세력 줄 (기본 + 골라 넣는 세력)")
	new_game.set_faction("tang", true, "military")
	new_game.set_faction("namgung", false, FactionStrategy.RANDOM)
	var setup: Dictionary = new_game.get_faction_setup()
	_check(setup["extra"] == ["tang"] and setup["strategies"] == {"tang": "military", "namgung": FactionStrategy.RANDOM}, "새 게임: 세력 설정 모으기")
	_check(new_game._faction_rows["namgung"]["check"].disabled, "시나리오 세력은 뺄 수 없음")
	new_game._on_start_pressed()
	await process_frame
	await process_frame
	_check(gm.get_world_sect("tang") != null and gm.get_world_sect("tang").strategy == "military", "새 게임 시작: 세력 설정 적용")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_map_screens"] = true
