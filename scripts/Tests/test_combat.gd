extends "res://scripts/Tests/test_base.gd"

## 스모크 테스트 — 전투: 결과·규칙·무공 효과·아군·데이터 전투, 전수·비전·무공 연구소
## 실행 순서는 smoke_test.gd의 INIT_SEQUENCE·RUNTIME_SEQUENCE가 정한다.


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
	controller.leave_combat()
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
	_check(c._turn_manager.is_player_phase() and c._get_controlled() == player, "아군 턴부터 시작하고 주인공을 조종")

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
	c.leave_combat()
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
	c.leave_combat()
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
	_check(c._turn_manager.get_enemy_order().size() == c._get_alive_enemies().size(), "적은 적군 턴에 모두 움직임")

	# 아군 턴에는 아군 칸을 눌러 누구든 고른다
	var ally: CombatUnit = null
	for unit in friends:
		if unit.is_ally:
			ally = unit
			break
	c._act_on_tile(c._get_controlled(), ally.grid_pos)
	_check(c._get_controlled() == ally, "아군 칸을 누르면 그 아군을 조종")
	c.select_next_ally()
	_check(c._get_controlled() != ally and c._get_controlled().is_friendly(), "다음 아군으로 바꾸기")
	c.select_unit(ally)
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
	c.leave_combat()
	await process_frame
	_completed["_test_ally_combat"] = true


func _test_combat_library() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	var ids: Array = CombatLibrary.get_ids()
	_check(ids.size() >= 12, "데이터 전투 %d개 로드" % ids.size())
	_check(CombatManager.has_combat("arc_revenge_duel") and CombatManager.has_combat("night_bandits"), "코드 전투와 데이터 전투 모두 찾음")
	for combat_id in ids:
		var setup: CombatSetup = CombatManager.create_by_id(combat_id, gm.player_character, gm.player_sect)
		var ok: bool = setup.id == combat_id and not setup.enemies.is_empty()
		for pos in setup.enemy_positions + setup.ally_positions + setup.blocked_tiles:
			ok = ok and pos.x >= 0 and pos.x < 16 and pos.y >= 0 and pos.y < 10
		_check(ok, "데이터 전투 구성: %s" % combat_id)
	var allied: CombatSetup = CombatManager.create_by_id("arc_revenge_duel_allied", gm.player_character)
	_check(allied.allies.size() == 1 and allied.allies[0].id == "npc_rival" and not allied.allies_are_disciples, "데이터 전투: 인물 아군 합류")
	var siege: CombatSetup = CombatManager.create_by_id("arc_cheonma_siege", gm.player_character, gm.player_sect)
	_check(siege.allies_are_disciples and siege.allies.size() == _Balance.DEFENSE_ALLY_COUNT, "데이터 전투: 문파 제자 합류")
	_check(siege.enemies[0].id != siege.enemies[1].id, "같은 졸개 템플릿은 서로 다른 id")
	var traitor: CombatSetup = CombatManager.create_by_id("arc_succession_coup_traitor", gm.player_character)
	var master_full: CharacterData = NpcRoster.create_character("npc_master")
	_check(traitor.enemies[0].strength == master_full.strength - 5 and traitor.enemies[0].display_name == "병든 청운검선", "데이터 전투: 능력치 보정과 이름")

	# 패배 플래그
	var duel: CombatSetup = CombatManager.create_by_id("arc_revenge_duel", gm.player_character)
	CombatManager.apply_outcome(duel, CombatManager.Outcome.RETREAT, gm.player_character, gm.player_sect, gm.player_relationships, gm.story_flags)
	_check(gm.story_flags.get("arc_revenge_lost", false) and not gm.story_flags.get("arc_revenge_won", false), "후퇴하면 패배 플래그")

	# 검증 오류
	var errors: PackedStringArray = CombatLibrary.validate_combat_dict({
		"id": "x", "title": "x",
		"enemies": [{"npc": "no_such_npc", "position": [20, 3], "stats": {"luck": 1}}],
		"terrain": {"LAVA": []}, "rewards": {"fame": 1},
	})
	for keyword in ["명부에 없는 인물", "전장 밖", "능력치", "지형", "보상"]:
		_check(Array(errors).any(func(e: String) -> bool: return e.contains(keyword)), "전투 검증 오류 검출: %s" % keyword)
	_check(not CombatLibrary.validate_combat_dict({"id": "x", "title": "x", "enemies": []}).is_empty(), "적 없는 전투 거부")
	_check(not CombatLibrary.validate_combat_dict({"id": "sparring", "title": "x", "enemies": [{"npc": "npc_bandit", "position": [1, 1]}]}).is_empty(), "코드 전투 id와 겹치면 거부")
	_completed["_test_combat_library"] = true


func _test_transmission_and_secret() -> void:
	var gm: Node = root.get_node("GameManager")

	# 비급 목록은 MartialArtLibrary에서 (프리셋 먼저, 모드 뒤)
	var all_arts: Array[MartialArtData] = MartialArtLibrary.get_all()
	var ids: Array = all_arts.map(func(a: MartialArtData) -> String: return a.id)
	_check(ids.has("preset_soul_chase_sword") and ids.has("mod_thunder_palm"), "비급 목록: 프리셋과 모드 무공")
	_check(not MartialArtLibrary.is_mod(all_arts[0]) and MartialArtLibrary.is_mod(all_arts[-1]), "비급 목록: 프리셋이 먼저")

	# 전수: 레벨 요구·연구점·한 무공
	_new_quiet_game(gm, "leader")
	var sect: SectData = gm.player_sect
	var art: MartialArtData = MartialArtLibrary.create_art("preset_soul_chase_sword")
	gm.player_character.learn_martial_art(art)
	var disciple: DiscipleData = sect.disciples[0]
	sect.research_points = 0
	_check(DiscipleRoster.get_transmit_level(art) == 2, "전수 레벨 요구: 복잡도 3 → Lv.2")
	_check(not DiscipleRoster.transmit(sect, disciple.id, art)["success"], "레벨이 모자라면 전수 불가")
	disciple.gain_experience(_Balance.DISCIPLE_EXP_PER_LEVEL)
	_check(not DiscipleRoster.transmit(sect, disciple.id, art)["success"], "연구점이 모자라면 전수 불가")
	sect.research_points = 200
	var cost: int = DiscipleRoster.get_transmit_cost(sect, art)
	_check(DiscipleRoster.transmit(sect, disciple.id, art)["success"] and sect.research_points == 200 - cost, "전수: 연구점 소모")
	_check(disciple.martial_art.id == art.id and disciple.martial_art != art, "제자는 무공 복제본을 익힘")
	_check(not DiscipleRoster.transmit(sect, disciple.id, art)["success"], "같은 무공 재전수 거부")
	DiscipleRoster.toggle_deploy(sect, disciple.id)
	var setup: CombatSetup = CombatManager.create_night_bandits(gm.player_character, sect)
	var ally: CharacterData = setup.allies.filter(func(c: CharacterData) -> bool: return c.id == disciple.id)[0]
	_check(ally.knows_martial_art(art.id), "방어전: 전수받은 제자가 그 무공을 씀")

	# 강화
	var damage: int = art.damage
	var internal: int = art.internal_cost
	sect.research_points = 1000
	_check(not MartialArtManager.designate_secret(art, sect)["success"], "강화하지 않은 무공은 비전 불가")
	_check(MartialArtManager.enhance(art, sect)["success"] and art.enhance_level == 1, "무공 강화 1단계")
	_check(art.damage == damage + _Balance.ENHANCE_DAMAGE and art.internal_cost == internal - _Balance.ENHANCE_INTERNAL_COST_REDUCTION, "강화: 피해 증가, 내공 소모 감소")
	_check(sect.research_points == 1000 - _Balance.ENHANCE_RESEARCH_BASE, "강화 비용")
	_check(MartialArtLibrary.create_art(art.id).enhance_level == 0, "강화는 비급 원본을 바꾸지 않음")

	# 비전
	_check(MartialArtManager.designate_secret(art, sect)["success"] and sect.secret_art.id == art.id, "강화한 무공을 비전으로 지정")
	_check(DiscipleRoster.get_transmit_cost(sect, art) == roundi(cost * _Balance.TRANSMIT_SECRET_SCALE), "비전은 전수 비용 절반")
	MartialArtManager.enhance(art, sect)
	MartialArtManager.enhance(art, sect)
	_check(sect.secret_art.enhance_level == 3 and not MartialArtManager.enhance(art, sect)["success"], "강화는 최고 3단계, 비전도 함께 강해짐")

	# 세대 전승: 후계자가 비전을 물려받는다
	gm.player_character.gain_experience(CharacterData.get_experience_for_level(_Balance.RETIRE_LEVEL))
	var result: Dictionary = gm.start_legacy_succession()
	_check(result["success"] and gm.player_character.knows_martial_art(art.id) and result["message"].contains("비전"), "후계자가 문파 비전을 물려받음")
	var inherited: MartialArtData = gm.player_character.martial_arts.filter(func(a: MartialArtData) -> bool: return a.id == art.id)[0]
	_check(inherited.enhance_level == 3 and inherited != sect.secret_art, "물려받은 비전은 강화 단계 유지, 복제본")

	# 상대 무공 분석
	_new_quiet_game(gm, "leader")
	sect = gm.player_sect
	gm.pending_combat = CombatManager.create_by_id("arc_cheonma_blood_shadow", gm.player_character)
	gm.finish_combat(CombatManager.Outcome.VICTORY)
	_check(gm.observed_arts.has("mod_thunder_palm") and gm.observed_arts["mod_thunder_palm"]["element"] == MartialArtData.FiveElement.FIRE, "전투에서 본 상대 무공 기록 (혈영의 뇌전장)")
	sect.research_points = 0
	var observed: Dictionary = gm.observed_arts["mod_thunder_palm"]
	_check(not MartialArtManager.analyze(observed, sect, gm.analyzed_elements)["success"], "연구점이 모자라면 분석 불가")
	sect.research_points = 100
	_check(MartialArtManager.analyze(observed, sect, gm.analyzed_elements)["success"] and gm.analyzed_elements.has(MartialArtData.FiveElement.FIRE), "상대 무공 분석: 화 속성")
	_check(not MartialArtManager.analyze(observed, sect, gm.analyzed_elements)["success"], "같은 속성 재분석 거부")
	_check(MartialArtManager.get_counter_element(MartialArtData.FiveElement.FIRE) == MartialArtData.FiveElement.WATER, "화를 이기는 속성은 수")
	_check(MartialArtManager.get_counter_bonus(MartialArtData.FiveElement.WATER, gm.analyzed_elements) == _Balance.COUNTER_SUCCESS_BONUS, "상극(수) 무공 창조 성공률 보너스")
	_check(MartialArtManager.get_counter_bonus(MartialArtData.FiveElement.WOOD, gm.analyzed_elements) == 0, "상극이 아니면 보너스 없음")
	_check(not MartialArtManager.analyze({"name": "무속성", "element": 0}, sect, gm.analyzed_elements)["success"], "속성 없는 무공은 분석 불가")
	# 성공률 보너스가 실제 창조에 쓰인다: 성공률 10%짜리 복잡한 무공을 보너스로 25%로
	sect.research_points = 10000
	gm.player_character.wisdom = 0
	sect.library_level = 0
	var blueprint: Dictionary = {
		"name": "역류수장", "category": MartialArtData.Category.PALM, "element": MartialArtData.FiveElement.WATER,
		"yin_yang": MartialArtData.YinYang.YIN, "effects": [0, 1, 2],
	}
	var successes: Array = [0, 0]
	seed(7)
	for i in 600:
		var use: Array = [[], gm.analyzed_elements][i % 2]
		sect.research_points = 10000
		blueprint["name"] = "역류수장%d" % i
		if MartialArtManager.create_from_blueprint(blueprint, sect, gm.player_character, use)["success"]:
			successes[i % 2] += 1
	_check(successes[1] > successes[0] + 20, "분석 보너스로 창조 성공이 늘어남 (%d → %d / 300)" % [successes[0], successes[1]])

	# 세이브 왕복
	_new_quiet_game(gm, "leader")
	sect = gm.player_sect
	art = MartialArtLibrary.create_art("preset_soul_chase_sword")
	art.enhance_level = 2
	gm.player_character.learn_martial_art(art)
	sect.secret_art = art.duplicate(true)
	sect.disciples[0].martial_art = art.duplicate(true)
	gm.observed_arts = {"mod_thunder_palm": {"id": "mod_thunder_palm", "name": "뇌전장", "element": 2, "owner": "혈영"}}
	gm.analyzed_elements = [2]
	var disciple_id: String = sect.disciples[0].id
	gm._apply_save_data(JSON.parse_string(JSON.stringify({
		"character": _SaveManager.serialize_character(gm.player_character),
		"sect": _SaveManager.serialize_sect(sect),
		"observed_arts": gm.observed_arts,
		"analyzed_elements": gm.analyzed_elements,
	})))
	var loaded: SectData = gm.player_sect
	_check(loaded.secret_art != null and loaded.secret_art.id == art.id and loaded.secret_art.enhance_level == 2, "문파 비전 저장·복원")
	_check(DiscipleRoster.get_disciple(loaded, disciple_id).martial_art.id == art.id, "제자의 전수 무공 저장·복원")
	_check(gm.player_character.martial_arts[0].enhance_level == 2, "무공 강화 단계 저장·복원")
	_check(gm.observed_arts["mod_thunder_palm"]["element"] is int and gm.analyzed_elements == [2], "본 무공·분석 속성 저장·복원")
	_completed["_test_transmission_and_secret"] = true


func _test_martial_art_screen_actions() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "leader")
	gm.player_sect.research_points = 500
	gm.player_character.learn_martial_art(MartialArtLibrary.create_art("preset_soul_chase_sword"))
	gm.observed_arts = {"mod_thunder_palm": {"id": "mod_thunder_palm", "name": "뇌전장", "element": 2, "owner": "혈영"}}
	SceneRouter.goto(tree, SceneRouter.MARTIAL_ART)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	_check(screen.preset_list.item_count == MartialArtLibrary.get_all().size(), "무공 연구소: 비급 목록은 MartialArtLibrary")
	screen._on_enhance_pressed()
	_check(screen.choice_popup.visible and screen.choice_popup.get_option_count() == 1, "강화: 습득 무공 고르기")
	screen.choice_popup._on_option_pressed("preset_soul_chase_sword")
	_check(gm.player_character.martial_arts[0].enhance_level == 1, "화면에서 무공 강화")
	screen._on_secret_pressed()
	screen.choice_popup._on_option_pressed("preset_soul_chase_sword")
	_check(gm.player_sect.secret_art != null and screen.secret_label.text.contains("유혼쾌영검"), "화면에서 비전 지정·표시")
	screen._on_analyze_pressed()
	screen.choice_popup._on_option_pressed("mod_thunder_palm")
	_check(gm.analyzed_elements.has(2) and screen.secret_label.text.contains("화"), "화면에서 상대 무공 분석")
	screen.element_option.select(screen.element_option.get_item_index(MartialArtData.FiveElement.WATER))
	screen.element_option.item_selected.emit(screen.element_option.selected)
	_check(screen.success_rate_label.text.contains("상극"), "상극 속성을 고르면 성공률 미리보기에 보너스 표시")

	# 제자 명단에서 전수
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	var target: DiscipleData = gm.player_sect.disciples[0]
	target.gain_experience(_Balance.DISCIPLE_EXP_PER_LEVEL)
	hub._on_disciple_pressed()
	await process_frame
	hub.disciple_popup._on_transmit_pressed(target.id)
	_check(hub.disciple_popup.art_choice.visible and hub.disciple_popup.art_choice.get_option_count() == 1, "전수: 무공 고르기 팝업")
	hub.disciple_popup.art_choice._on_option_pressed("preset_soul_chase_sword")
	_check(target.martial_art != null and hub.log_label.text.contains("전수"), "제자 명단에서 무공 전수")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_martial_art_screen_actions"] = true


## 피해 흔들림과 회심: 켜면 피해가 정해진 폭 안에서 흔들리고, 신법에 따라 회심이 난다.
func _test_damage_randomness() -> void:
	var T := CombatRules.Terrain
	var attacker_char := CharacterData.new()
	attacker_char.strength = 12
	attacker_char.agility = 15
	var attacker := CombatUnit.new(attacker_char, true)
	var defender := CombatUnit.new(CharacterData.new())
	var base: int = CombatRules.calculate_damage(attacker, defender, null, T.PLAIN, T.PLAIN)["damage"]
	CombatRules.randomness = true
	seed(12345)
	var lowest: int = 9999
	var highest: int = 0
	var crits: int = 0
	var spread_ok: bool = true
	var rolls: int = 1000
	for i in rolls:
		var result: Dictionary = CombatRules.calculate_damage(attacker, defender, null, T.PLAIN, T.PLAIN)
		var damage: int = result["damage"]
		if "회심" in result["notes"]:
			crits += 1
			damage = int(damage / _Balance.CRIT_MULTIPLIER)
		else:
			lowest = mini(lowest, damage)
			highest = maxi(highest, damage)
		if damage < floori(base * (1.0 - _Balance.DAMAGE_SPREAD)) - 1 or damage > ceili(base * (1.0 + _Balance.DAMAGE_SPREAD)) + 1:
			spread_ok = false
	CombatRules.randomness = false
	_check(spread_ok, "피해 흔들림은 ±%d%% 안" % roundi(_Balance.DAMAGE_SPREAD * 100))
	_check(lowest < base and highest > base, "피해가 실제로 흔들림 (%d~%d, 기준 %d)" % [lowest, highest, base])
	var expected: float = CombatRules.crit_chance(attacker)
	_check(absf(float(crits) / rolls - expected) < 0.03, "회심 확률이 신법에 맞음 (%.1f%%, 기대 %.1f%%)" % [100.0 * crits / rolls, expected * 100])
	attacker_char.agility = 100
	_check(is_equal_approx(CombatRules.crit_chance(attacker), _Balance.CRIT_MAX), "회심 확률 상한")
	_check(CombatRules.calculate_damage(attacker, defender, null, T.PLAIN, T.PLAIN)["damage"] == base, "끄면 피해가 일정")
	_completed["_test_damage_randomness"] = true


## 기본 공격은 차례에 한 번. 적 AI도 같은 규칙으로, 남은 행동력을 무공에 쓰고 내공 폭주는 피한다.
func _test_basic_attack_limit() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	gm.pending_combat = CombatManager.create_sparring(gm.player_character)
	SceneRouter.goto(tree, SceneRouter.COMBAT)
	await process_frame
	await process_frame
	var c: Node = current_scene
	var player: CombatUnit = c._get_player()
	var enemy: CombatUnit = c._get_alive_enemies()[0]
	enemy.max_hp = 9999
	enemy.hp = 9999
	enemy.grid_pos = player.grid_pos + Vector2i(1, 0)
	player.restore_action_points()
	var ap: int = player.action_points
	c._try_attack(player, enemy.grid_pos)
	var hp_after_first: int = enemy.hp
	_check(hp_after_first < 9999 and player.action_points == ap - 1, "첫 기본 공격")
	c._try_attack(player, enemy.grid_pos)
	_check(enemy.hp == hp_after_first and player.action_points == ap - 1, "같은 차례의 두 번째 기본 공격은 막힘")
	c._update_hud()
	_check(c.get_node("HUD/Panel/VBox/ModeRow/ModeAttackButton").disabled, "기본 공격을 다 쓰면 공격 버튼 비활성")
	player.restore_action_points()
	_check(player.can_basic_attack(), "다음 차례에 기본 공격 회복")

	# 적 AI: 무공을 거듭 쓰고 기본 공격은 한 번
	var art: MartialArtData = MartialArtLibrary.create_art("preset_soul_chase_sword")
	enemy.character.learn_martial_art(art)
	enemy.character.internal_energy_max = 200
	enemy.character.restore_internal_energy()
	enemy.restore_action_points()
	enemy.action_points = 5
	player.max_hp = 9999
	player.hp = 9999
	var energy_before: int = enemy.character.internal_energy_current
	c._run_enemy_ai(enemy)
	var casts: int = (energy_before - enemy.character.internal_energy_current) / art.internal_cost
	_check(casts == 2 and enemy.basic_attacks_left == 0 and enemy.action_points == 0, "적 AI: 무공 두 번 + 기본 공격 한 번으로 행동력을 다 씀 (무공 %d번)" % casts)
	# 시전 뒤 내공이 폭주 기준 아래로 떨어지면 무공을 쓰지 않는다
	enemy.restore_action_points()
	enemy.character.internal_energy_current = int(enemy.character.internal_energy_max * _Balance.OVERLOAD_THRESHOLD) + art.internal_cost - 1
	_check(c._enemy_usable_art(enemy) == null, "적 AI: 내공 폭주가 날 무공은 쓰지 않음")
	enemy.character.internal_energy_current += 1
	_check(c._enemy_usable_art(enemy) == art, "적 AI: 폭주 기준을 지키면 무공 사용")

	gm.pending_combat = null
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_basic_attack_limit"] = true


## 격자 커서: 방향키·게임패드로 칸을 고르고 실행한다.
func _test_grid_cursor() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	gm.pending_combat = CombatManager.create_sparring(gm.player_character)
	SceneRouter.goto(tree, SceneRouter.COMBAT)
	await process_frame
	await process_frame
	var c: Node = current_scene
	var player: CombatUnit = c._get_player()
	var enemy: CombatUnit = c._get_alive_enemies()[0]
	_check(not c.cursor_visible, "커서는 처음에 숨어 있음")
	c.move_cursor(Vector2i.RIGHT)
	_check(c.cursor_visible and c.cursor == player.grid_pos, "처음 방향 입력: 조종 중인 유닛 자리에 커서")
	c.move_cursor(Vector2i.RIGHT)
	_check(c.cursor == player.grid_pos + Vector2i.RIGHT, "방향 입력으로 한 칸 이동")
	_check(c.get_node("CursorLayer").get_child_count() > 0, "커서 테두리 표시")

	# 이동: 커서 칸으로
	var target: Vector2i = c.cursor
	_check(c._get_reachable(player).has(target), "(준비) 커서 칸은 이동 가능")
	c._on_mode_move_pressed()
	c.confirm_cursor()
	_check(player.grid_pos == target, "Enter·A: 커서 칸으로 이동")

	# 가장자리에서는 멈춘다
	c.cursor = Vector2i(c.GRID_WIDTH - 1, 0)
	c.move_cursor(Vector2i.RIGHT)
	c.move_cursor(Vector2i.UP)
	_check(c.cursor == Vector2i(c.GRID_WIDTH - 1, 0), "격자 밖으로 나가지 않음")

	# 게임패드 십자키와 스틱 (스틱은 기울인 순간 한 칸)
	c.cursor = Vector2i(5, 5)
	var dpad := InputEventJoypadButton.new()
	dpad.button_index = JOY_BUTTON_DPAD_LEFT
	dpad.pressed = true
	_check(c._handle_gamepad(dpad) and c.cursor == Vector2i(4, 5), "십자키로 커서 이동")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = 1.0
	c._handle_gamepad(stick)
	c._handle_gamepad(stick)
	_check(c.cursor == Vector2i(4, 6), "스틱은 기울인 채로 있으면 한 칸만")
	stick.axis_value = 0.0
	c._handle_gamepad(stick)
	stick.axis_value = 1.0
	c._handle_gamepad(stick)
	_check(c.cursor == Vector2i(4, 7), "스틱을 놓았다 다시 기울이면 다음 칸")

	# 무공 고르기 (LB·RB): 무공 → … → 기본 공격 순환
	var art: MartialArtData = MartialArtLibrary.create_art("preset_soul_chase_sword")
	gm.player_character.learn_martial_art(art)
	c.cycle_art(1)
	_check(c._action_mode == c.ActionMode.MARTIAL_ART and c._selected_art == art, "RB: 첫 무공 고르기")
	c.cycle_art(1)
	_check(c._action_mode == c.ActionMode.ATTACK, "RB: 마지막 무공 다음은 기본 공격")
	c.cycle_art(-1)
	_check(c._selected_art == art and c._action_mode == c.ActionMode.MARTIAL_ART, "LB: 거꾸로 고르기")

	# 공격: 커서를 적에게 두고 실행
	enemy.grid_pos = player.grid_pos + Vector2i.RIGHT
	enemy.max_hp = 9999
	enemy.hp = 9999
	player.restore_action_points()
	var attack := InputEventJoypadButton.new()
	attack.button_index = JOY_BUTTON_X
	attack.pressed = true
	c._handle_gamepad(attack)
	c.cursor = enemy.grid_pos
	var confirm := InputEventJoypadButton.new()
	confirm.button_index = JOY_BUTTON_A
	confirm.pressed = true
	c._handle_gamepad(confirm)
	_check(enemy.hp < 9999, "X로 공격 모드, A로 커서의 적 공격")
	_check(c._describe_tile(enemy.grid_pos).contains(enemy.display_name), "커서 칸 설명에 유닛 이름")

	# 터치·클릭: 바탕이 입력을 가로채지 않고, 커서가 아니라 이벤트 위치로 칸을 고른다 (Android에서 이동이 안 되던 버그)
	_check(c.get_node("Background").mouse_filter == Control.MOUSE_FILTER_IGNORE, "전투 바탕은 터치를 가로채지 않음")
	player.restore_action_points()
	c._on_mode_move_pressed()
	var tap_target: Vector2i = player.grid_pos + Vector2i.DOWN
	_check(c._get_reachable(player).has(tap_target), "(준비) 터치할 칸은 이동 가능")
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(tap_target) * c.GRID_SIZE + Vector2(c.GRID_SIZE / 2.0, c.GRID_SIZE / 2.0)
	c._unhandled_input(tap)
	_check(player.grid_pos == tap_target and not c.cursor_visible, "터치한 칸으로 이동하고 커서는 숨김")

	gm.pending_combat = null
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_grid_cursor"] = true


## 공격 미리보기·전투 기록·아군 자유 선택
func _test_combat_preview_and_history() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	gm.player_character.learn_martial_art(MartialArtLibrary.create_art("preset_soul_chase_sword"))
	gm.start_combat(CombatManager.create_night_bandits(gm.player_character, gm.player_sect))
	await process_frame
	await process_frame
	GameSettings.combat_preview = true
	var c: Node = current_scene
	var player: CombatUnit = c._get_player()
	var enemy: CombatUnit = c._get_alive_enemies()[0]
	enemy.grid_pos = player.grid_pos + Vector2i.RIGHT
	var hp: int = enemy.hp

	# 기본 공격 미리보기: 실행 전에는 피해가 없고, 취소하면 그대로
	c._on_mode_attack_pressed()
	c._act_on_tile(player, enemy.grid_pos)
	_check(c.is_previewing() and c.preview_panel.visible and enemy.hp == hp, "공격 전 미리보기 (아직 피해 없음)")
	var text: String = c.preview_label.text
	_check(text.contains("예상 피해") and text.contains("체력") and text.contains("행동력"), "미리보기: 예상 피해·체력 변화·내 소모")
	_check(text.contains("다음 적 턴"), "미리보기: 살아남은 대상의 예상 반격")
	c.cancel_preview()
	_check(not c.is_previewing() and enemy.hp == hp and player.basic_attacks_left == 1, "미리보기 취소: 아무 일도 없음")
	c._act_on_tile(player, enemy.grid_pos)
	c.confirm_preview()
	_check(enemy.hp < hp and player.basic_attacks_left == 0, "미리보기 실행: 공격")
	_check(c.history[c.history.size() - 1].contains("기본 공격") and c.history[c.history.size() - 1].contains("→"), "전투 기록: 공격·피해·체력 변화")

	# 무공 미리보기: 내공 소모가 보인다
	var art: MartialArtData = player.get_martial_arts()[0]
	c._on_art_pressed(art)
	c._act_on_tile(player, enemy.grid_pos)
	_check(c.is_previewing() and c.preview_label.text.contains("내공"), "무공 미리보기: 내공 소모")
	_unhandled_key(c, KEY_ESCAPE)
	_check(not c.is_previewing(), "Esc: 미리보기 취소")

	# 아군 자유 선택: 아군 칸을 누르면 그 아군, Tab은 다음 아군
	var ally: CombatUnit = null
	for unit in c._get_alive_friendlies():
		if unit.is_ally:
			ally = unit
			break
	c._on_mode_move_pressed()
	c._act_on_tile(player, ally.grid_pos)
	_check(c._get_controlled() == ally, "아군 턴에 아군을 골라 조종")
	_unhandled_key(c, KEY_TAB)
	_check(c._get_controlled() != ally, "Tab: 다음 아군")

	# 턴 종료 → 적군 턴 → 다음 라운드 아군 턴
	c._on_end_turn_pressed()
	_check(c._turn_manager.is_player_phase() and c._turn_manager.round_number == 2, "턴 종료하면 적군 턴 뒤 2라운드 아군 턴")
	var joined: String = "\n".join(c.history)
	_check(joined.contains("적군 턴") and joined.contains("라운드 2 · 아군 턴"), "전투 기록: 턴 구분")
	_unhandled_key(c, KEY_H)
	_check(c.history_popup.visible and c.history_label.text.contains("전투 시작"), "H: 전투 기록 창")
	_unhandled_key(c, KEY_ESCAPE)
	_check(not c.history_popup.visible, "Esc: 전투 기록 닫기")

	GameSettings.combat_preview = false
	c.leave_combat()
	_check(gm.last_combat_history.size() > 3, "전투가 끝나면 기록을 남김 (연대기용)")
	await process_frame
	await process_frame
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_combat_preview_and_history"] = true


func _unhandled_key(node: Node, keycode: Key) -> void:
	node._unhandled_key_input(_key(keycode))
