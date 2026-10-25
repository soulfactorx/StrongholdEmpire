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

	# 상대를 몰아붙이면 승리 처리 (합을 다 쓰면 체력 비율이 낮은 쪽이 물러난다)
	var controller: Node = current_scene
	var exp_before: int = gm.player_character.experience
	var rival: CombatUnit = controller.engine.current_foe()
	rival.take_damage(rival.hp - 1)
	await controller.skip_to_result()
	_check(controller.engine.outcome == CombatManager.Outcome.VICTORY and gm.pending_combat == null, "승리 후 예약 전투 해제")
	_check(gm.player_character.experience == exp_before + _Balance.SPAR_EXP, "비무 승리 경험치 반영")

	# 도적 전투: 적 3명이 차례로 나서는 연전, 배율 적용, 후퇴
	gm.start_combat(CombatManager.create_night_bandits(gm.player_character))
	await process_frame
	await process_frame
	controller = current_scene
	var foes: Array = controller.engine.foes
	_check(foes.size() == 3, "도적 전투: 적 3명이 연전으로 나섬")
	var full_hp: int = CombatUnit.new(foes[0].character).max_hp
	_check(foes[0].max_hp == int(full_hp * gm.pending_combat.enemy_hp_scale * ScenarioRules.enemy_strength_scale()), "도적 체력 배율 적용")

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


## 대결 시험용 인물: 내공 100, 신법·지혜를 정할 수 있다
func _duel_unit(name: String, agility: int = 10, player: bool = false) -> CombatUnit:
	var character := CharacterData.new()
	character.display_name = name
	character.agility = agility
	character.internal_energy_max = 100
	character.restore_internal_energy()
	return CombatUnit.new(character, player)


func _card(type: DuelCard.Type, power: int = 20, cost: int = 0) -> DuelCard:
	return DuelCard.make("t_%d_%d" % [type, power], DuelCard.TYPE_NAMES[type], type, power, cost)


## 한 칸을 판정하고 {a 받은 피해, b 받은 피해, 결과}를 돌려준다 (매번 새 인물)
func _clash(ca: DuelCard, cb: DuelCard, weather: String = "clear") -> Dictionary:
	var a: CombatUnit = _duel_unit("갑")
	var b: CombatUnit = _duel_unit("을")
	var result: Dictionary = DuelRules.resolve_slot(0, a, ca, b, cb, weather)
	return {"a": result["damage"]["a"], "b": result["damage"]["b"], "result": result, "unit_a": a, "unit_b": b}


## 초식 배치 대결의 한 칸 판정: 상성·속도·내공·기세·기절·운기·날씨
func _test_duel_rules() -> void:
	var T := DuelCard.Type
	var plain: int = int(20 + 10 * DuelRules.STRENGTH_RATIO)
	# 빈틈과 상성
	var gap: Dictionary = _clash(_card(T.STRIKE), null)
	_check(gap["b"] == int(plain * DuelRules.GAP_TAKEN) and gap["a"] == 0, "빈 칸은 빈틈: 피해 %d배" % DuelRules.GAP_TAKEN)
	var broken: Dictionary = _clash(_card(T.STRIKE), _card(T.GUARD))
	_check(broken["b"] == plain and "막기를 깸" in "\n".join(broken["result"]["lines"]), "강공은 막기를 깸 (온전한 피해)")
	var blocked: Dictionary = _clash(_card(T.QUICK), _card(T.GUARD))
	_check(blocked["b"] == int(plain * DuelRules.GUARD_QUICK) and blocked["a"] > 0, "막기는 속공을 줄이고 받아침")
	var cut: Dictionary = _clash(_card(T.STRIKE), _card(T.QUICK))
	_check(cut["a"] == plain and cut["b"] == int(plain * DuelRules.INTERRUPTED), "속공이 강공을 끊음 (강공 피해 절반)")
	var dodged: Dictionary = _clash(_card(T.STRIKE), _card(T.EVADE))
	_check(dodged["b"] == 0 and dodged["result"]["evaded"]["b"] == 1, "회피는 느린 강공을 흘림")
	var read: Dictionary = _clash(_card(T.TRICK), _card(T.EVADE))
	_check(read["b"] == plain, "술은 회피를 읽음")
	var half: Dictionary = _clash(_card(T.TRICK), _card(T.GUARD))
	_check(half["b"] == int(plain * DuelRules.GUARD_TRICK), "술은 막기를 반쯤 뚫음")
	var open: Dictionary = _clash(_card(T.QUICK), _card(T.FOCUS))
	_check(open["b"] == int(plain * DuelRules.FOCUS_TAKEN), "운기 중에는 무방비")
	var focused: CombatUnit = open["unit_b"]
	_check(focused.momentum == 0 and focused.character.internal_energy_current == 100, "운기: 내공은 최대를 넘지 않고, 맞으면 기세는 그대로 0")

	# 운기: 내공 회복과 기세, 회복 무공은 체력도
	var a: CombatUnit = _duel_unit("갑")
	var b: CombatUnit = _duel_unit("을")
	a.character.internal_energy_current = 10
	a.take_damage(30)
	var heal_card: DuelCard = _card(T.FOCUS, 12)
	heal_card.effects.append("heal")
	DuelRules.resolve_slot(0, a, heal_card, b, _card(T.GUARD), "clear")
	_check(a.character.internal_energy_current == 10 + DuelRules.FOCUS_ENERGY + a.character.wisdom / 2 and a.momentum == 1 and a.hp == a.max_hp - 18, "운기: 내공·기세·회복")

	# 내공·기세가 모자라면 빈틈
	a = _duel_unit("갑")
	b = _duel_unit("을")
	a.character.internal_energy_current = 5
	var result: Dictionary = DuelRules.resolve_slot(0, a, _card(T.STRIKE, 30, 20), b, _card(T.QUICK), "clear")
	_check(result["damage"]["b"] == 0 and a.character.internal_energy_current == 5 and "내공 부족" in "\n".join(result["lines"]), "내공이 모자라면 헛손질 (빈틈)")
	var finisher: DuelCard = _card(T.STRIKE, 50)
	finisher.momentum_cost = 2
	a.momentum = 1
	result = DuelRules.resolve_slot(0, a, finisher, b, _card(T.GUARD), "clear")
	_check(result["damage"]["b"] == 0 and "기세 부족" in "\n".join(result["lines"]), "기세가 모자라면 절초를 못 펼침")
	a.momentum = 3
	result = DuelRules.resolve_slot(0, a, finisher, b, _card(T.GUARD), "clear")
	_check(result["damage"]["b"] > 0 and a.momentum == 2, "절초: 기세를 쓰고 이기면 하나 오름 (3 - 2 + 1)")
	_check(b.momentum == 0, "진 쪽 기세는 0 아래로 내려가지 않음")

	# 속도: 빠른 쪽이 먼저 쳐서 쓰러뜨리면 상대 초식은 나오지 않는다
	a = _duel_unit("갑", 30)
	b = _duel_unit("을", 5)
	b.hp = 5
	var a_hp: int = a.hp
	DuelRules.resolve_slot(0, a, _card(T.QUICK), b, _card(T.QUICK), "clear")
	_check(not b.is_alive() and a.hp == a_hp, "빠른 쪽이 먼저 쓰러뜨리면 반격 없음")

	# 기절: 다음 칸이 막히고, 저항이 생긴다
	a = _duel_unit("갑")
	b = _duel_unit("을")
	var stun: DuelCard = _card(T.TRICK, 5)
	stun.effects.append("stun")
	DuelRules.resolve_slot(0, a, stun, b, _card(T.GUARD), "clear")
	_check(b.has_status("stunned") and b.has_status("stun_immune"), "기절 초식: 대상 기절")
	result = DuelRules.resolve_slot(1, a, _card(T.QUICK), b, _card(T.STRIKE), "clear")
	_check(result["damage"]["a"] == 0 and not b.has_status("stunned"), "기절한 쪽은 그 칸을 펼치지 못함")
	DuelRules.resolve_slot(2, a, stun, b, _card(T.GUARD), "clear")
	_check(not b.has_status("stunned"), "막 풀려난 쪽은 기절 저항")

	# 날씨: 밤에는 회피가 빨라지고, 비에는 화 초식이 약해진다
	a = _duel_unit("갑", 25)
	b = _duel_unit("을", 10)
	_check(DuelRules._speed(b, _card(T.EVADE), "night") == DuelRules._speed(b, _card(T.EVADE), "clear") + 10, "날씨: 밤에는 회피 속도 +1")
	_check(DuelRules._speed(a, _card(T.STRIKE), "snow") == DuelRules._speed(a, _card(T.STRIKE), "clear") - 10, "날씨: 눈 속에서는 강공 속도 -1")
	var fire: DuelCard = _card(T.STRIKE)
	fire.element = MartialArtData.FiveElement.FIRE
	_check(_clash(fire, _card(T.GUARD), "rain")["b"] < _clash(fire, _card(T.GUARD))["b"], "날씨: 비에는 화 초식이 약해짐")

	# 배치 사전 점검: 빈 칸, 내공 부족(앞 칸 운기로 채우면 괜찮음), 기세 부족, 보이는 상대에게 불리한 유형
	a = _duel_unit("갑")
	a.character.internal_energy_current = 10
	var costly: DuelCard = _card(T.STRIKE, 30, 20)
	var warnings: Array[Dictionary] = DuelRules.plan_warnings(a, [null, costly, costly])
	_check(warnings.size() == 3 and warnings[0]["serious"] and warnings[1]["text"].contains("내공이 모자라") and warnings[1]["serious"], "사전 점검: 빈 칸과 내공 부족은 확실한 빈틈")
	warnings = DuelRules.plan_warnings(a, [_card(T.FOCUS, 0), costly, _card(T.GUARD)])
	_check(warnings.is_empty(), "사전 점검: 앞 칸의 운기로 내공을 채우면 괜찮음")
	warnings = DuelRules.plan_warnings(a, [finisher, _card(T.GUARD), _card(T.GUARD)])
	_check(warnings.size() == 1 and not warnings[0]["serious"] and warnings[0]["text"].contains("기세"), "사전 점검: 기세 부족은 주의 (앞 칸에서 이기면 펼침)")
	warnings = DuelRules.plan_warnings(a, [_card(T.EVADE), _card(T.GUARD), _card(T.QUICK)], [T.TRICK, -1, T.GUARD])
	_check(warnings.size() == 2 and warnings[0]["text"].contains("술") and warnings[1]["slot"] == 2, "사전 점검: 보이는 상대 유형에 지는 칸")
	warnings = DuelRules.plan_warnings(a, [_card(T.FOCUS, 0), _card(T.FOCUS, 0), _card(T.GUARD)])
	_check(warnings.any(func(w: Dictionary) -> bool: return w["slot"] == -1 and w["text"].contains("무방비")), "사전 점검: 운기가 많으면 무방비 경고")

	# 상성 안내와 맞받는 유형
	_check(DuelRules.advantage(_card(T.STRIKE), _card(T.GUARD)) == 1 and DuelRules.advantage(_card(T.GUARD), _card(T.STRIKE)) == -1, "상성 안내: 강공 > 막기")
	var cycle_ok: bool = true
	for type in [T.STRIKE, T.QUICK, T.GUARD, T.EVADE, T.TRICK]:
		cycle_ok = cycle_ok and DuelRules.advantage(_card(DuelRules.counter_of(type)), _card(type)) == 1
	_check(cycle_ok, "맞받는 유형은 언제나 상성 우위")
	_completed["_test_duel_rules"] = true


## 초식 카드: 기본 동작, 무공 → 초식 바꾸기, 숙련, 칸 수. 배치 AI
func _test_duel_cards_and_ai() -> void:
	var T := DuelCard.Type
	var basics: Array[DuelCard] = DuelCard.basic_cards()
	_check(basics.size() == 5 and basics.all(func(c: DuelCard) -> bool: return c.art_id.is_empty()), "기본 동작 5가지")
	var art := MartialArtData.new()
	art.id = "t_heavy"
	art.display_name = "붕산권"
	art.damage = 34
	art.internal_cost = 12
	art.special_effects.append(MartialArtData.SpecialEffect.DESTRUCTION)
	var card: DuelCard = DuelCard.from_art(art)
	_check(card.type == T.STRIKE and card.effects.has("pierce") and card.momentum_cost == 2 and card.cost == 12, "파괴 무공은 강공 절초 (기세 2)")
	art.card_type = "TRICK"
	_check(DuelCard.from_art(art).type == T.TRICK, "무공 데이터의 card_type이 유형을 정함")
	var palm := MartialArtData.new()
	palm.id = "t_palm"
	palm.heal_amount = 15
	_check(DuelCard.from_art(palm).type == T.FOCUS and DuelCard.from_art(palm).effects.has("heal"), "회복 무공은 기 유형")
	var hidden := MartialArtData.new()
	hidden.category = MartialArtData.Category.HIDDEN
	hidden.damage = 10
	_check(DuelCard.from_art(hidden).type == T.TRICK, "암기는 술 유형")
	var step := MartialArtData.new()
	step.category = MartialArtData.Category.QINGGONG
	_check(DuelCard.from_art(step).type == T.EVADE, "경공은 회피 유형")

	var hero := CharacterData.new()
	hero.learn_martial_art(art)
	var cards: Array[DuelCard] = DuelCard.cards_for(hero, {"t_heavy": DuelCard.MASTERY_PER_TIER * 2 + 3})
	_check(cards.size() == 6 and cards[5].tier == 2, "숙련: 쓴 횟수 %d번마다 한 단계" % DuelCard.MASTERY_PER_TIER)
	_check(DuelCard.cards_for(hero, {"t_heavy": 999})[5].tier == 3, "숙련 상한 3단")
	var unit := CombatUnit.new(hero, true)
	_check(unit.slot_count() == 3, "Lv.1은 3칸")
	hero.level = 10
	_check(unit.slot_count() == 5, "Lv.10은 5칸")
	hero.level = 30
	_check(unit.slot_count() == 6, "칸은 최대 6")

	# AI 배치: 칸 수만큼, 무공 초식은 한 번씩, 쓸 수 있는 것만
	hero.level = 5
	hero.internal_energy_max = 100
	hero.restore_internal_energy()
	unit.cards = DuelCard.cards_for(hero)
	var rng := RandomNumberGenerator.new()
	var valid: bool = true
	for i in 40:
		rng.seed = i
		unit.momentum = i % 4
		var plan: Array[DuelCard] = DuelAI.plan(unit, [], {"ambition": 60}, 0.5, rng)
		var arts: int = plan.filter(func(c: DuelCard) -> bool: return c.art_id == "t_heavy").size()
		valid = valid and plan.size() == 4 and arts <= 1
	_check(valid, "AI 배치: 칸 수만큼 채우고 무공 초식은 한 번")
	_check(not DuelAI.can_place(cards[5], [cards[5]]) and DuelAI.can_place(basics[0], [basics[0]]), "같은 무공 초식은 한 합에 한 번, 기본 동작은 여러 번")
	# 기세가 차면 절초부터, 상대가 지난 합에 낸 유형을 읽으면 맞받는다
	unit.momentum = 3
	rng.seed = 1
	_check(DuelAI.plan(unit, [], {}, 0.0, rng)[0].id == "t_heavy", "AI: 기세가 차면 절초부터")
	unit.momentum = 0
	rng.seed = 2
	var countered: Array[DuelCard] = DuelAI.plan(unit, [T.STRIKE, T.QUICK, T.GUARD], {}, 1.0, rng)
	_check(countered[0].type == T.QUICK and countered[1].type == T.GUARD and countered[2].type == T.STRIKE, "AI: 지난 합의 유형을 맞받음")
	# 내공이 바닥이면 운기로 채운 만큼만 내공 드는 초식을 놓는다
	hero.internal_energy_current = 0
	var affordable: bool = true
	for i in 20:
		rng.seed = 100 + i
		var energy: int = 0
		for c in DuelAI.plan(unit, [], {}, 0.5, rng):
			energy -= c.cost
			affordable = affordable and energy >= 0
			if c.type == T.FOCUS:
				energy += DuelRules.FOCUS_ENERGY
	_check(affordable, "AI: 내공이 모자라는 초식은 놓지 않음 (운기로 채운 뒤에만)")
	_completed["_test_duel_cards_and_ai"] = true


## 대결 엔진: 연전·순서·목표·정보·버릇·숙련
func _test_duel_engine() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	var hero: CharacterData = gm.player_character
	# 연전: 아군이 먼저, 주인공이 대장. 쓰러진 제자는 손실로 센다
	var setup: CombatSetup = CombatManager.create_night_bandits(hero, gm.player_sect)
	var engine := DuelEngine.new(setup, hero)
	_check(setup.allies.size() >= 1 and engine.friends.size() == setup.allies.size() + 1 and engine.friends[-1].is_player and engine.foes.size() == setup.enemies.size(), "연전: 제자가 앞, 주인공이 대장, 도적이 차례로 (제자 %d명)" % setup.allies.size())
	engine.set_player_first(true)
	_check(engine.current_friend().is_player, "첫 합 전에는 주인공을 선봉으로")
	engine.set_player_first(false)
	var disciple: CombatUnit = engine.current_friend()
	disciple.take_damage(disciple.hp - 1)
	engine.prepare_bout()
	engine.enemy_plan.assign([_card(DuelCard.Type.QUICK, 50), _card(DuelCard.Type.QUICK, 50), _card(DuelCard.Type.QUICK, 50)])
	engine.run_bout([null, null, null])
	_check(not disciple.is_alive() and engine.current_friend() == engine.friends[1] and not engine.over, "앞 사람이 쓰러지면 다음 사람이 나섬")
	_check(engine.fallen_ally_ids() == [disciple.character.id], "쓰러진 제자 기록")
	_check(engine.current_friend().momentum == 0 and engine.bout_in_duel == 0, "새 대결은 기세·합 수가 처음부터")

	# 합을 다 쓰면 체력 비율이 낮은 쪽이 물러난다
	setup = CombatManager.create_sparring(hero)
	setup.max_bouts = 1
	engine = DuelEngine.new(setup, hero)
	engine.current_foe().take_damage(10)
	engine.prepare_bout()
	engine.enemy_plan.assign([_card(DuelCard.Type.GUARD), _card(DuelCard.Type.GUARD), _card(DuelCard.Type.GUARD)])
	var guards: Array = [DuelCard.basic_cards()[2], DuelCard.basic_cards()[2], DuelCard.basic_cards()[2]]
	engine.run_bout(guards)
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY and engine.retired.size() == 1, "합 제한: 체력 비율이 낮은 상대가 물러나 승리")

	# 목표: 우두머리 (호위는 우두머리 체력으로)
	setup = CombatManager.create_bandit_hunt(hero)
	var boss_char: CharacterData = setup.enemies[0]
	setup.set_target_objective(boss_char)
	engine = DuelEngine.new(setup, hero)
	var guard_count: int = setup.enemies.size() - 1
	var plain_boss: int = int(CombatUnit.new(boss_char).max_hp * setup.enemy_hp_scale)
	_check(engine.foes.size() == 1 and engine.guards.size() == guard_count and engine.current_foe().max_hp == int(plain_boss * (1.0 + DuelEngine.GUARD_HP_BONUS * guard_count)), "우두머리 목표: 우두머리와 바로 겨루고 호위 하나마다 체력 +15%")
	engine.current_foe().take_damage(99999)
	engine.prepare_bout()
	engine.run_bout([null, null, null])
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY, "우두머리 목표: 우두머리만 쓰러뜨리면 승리")

	# 목표: 버티기
	setup = CombatManager.create_bandit_hunt(hero)
	setup.add_ally(NpcRoster.create_character("npc_disciple", hero), Vector2i(2, 4))
	setup.objective = "survive"
	setup.objective_rounds = 2
	engine = DuelEngine.new(setup, hero)
	_check(engine.current_friend().is_player, "버티기 목표: 주인공이 선봉")
	engine.get_player().max_hp = 99999
	engine.get_player().hp = 99999
	for i in 2:
		engine.prepare_bout()
		engine.run_bout(guards)
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY and engine.bout_total == 2, "버티기 목표: 합 수를 버티면 승리")

	# 목표: 탈출 (주인공이 선봉으로, 공격을 세 번 흘리면)
	setup = CombatManager.create_bandit_hunt(hero)
	setup.add_ally(NpcRoster.create_character("npc_disciple", hero), Vector2i(2, 4))
	setup.objective = "escape"
	engine = DuelEngine.new(setup, hero)
	_check(engine.current_friend().is_player, "탈출 목표: 주인공이 선봉")
	hero.agility = 99
	engine.prepare_bout()
	engine.enemy_plan.assign([_card(DuelCard.Type.STRIKE), _card(DuelCard.Type.STRIKE), _card(DuelCard.Type.STRIKE)])
	var evade: DuelCard = DuelCard.basic_cards()[3]
	engine.run_bout([evade, evade, evade])
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY and engine.evades == DuelEngine.ESCAPE_EVADES, "탈출 목표: 공격을 세 번 흘리면 빠져나감")

	# 목표: 호위 (지킬 인물은 줄 밖, 우리 쪽이 대결에서 질 때마다 다치고 쓰러지면 패배)
	setup = CombatManager.create_bandit_hunt(hero)
	var merchant: CharacterData = NpcRoster.create_character("npc_merchant", hero)
	setup.add_ally(merchant, Vector2i(2, 4))
	setup.add_ally(NpcRoster.create_character("npc_disciple", hero), Vector2i(2, 6))
	setup.objective = "protect"
	setup.objective_target = merchant.id
	engine = DuelEngine.new(setup, hero)
	_check(engine.ward != null and engine.ward.character.id == merchant.id and engine.friends.size() == 2, "호위 목표: 지킬 인물은 줄에 서지 않음")
	engine.current_friend().take_damage(engine.current_friend().hp - 1)
	engine.prepare_bout()
	engine.enemy_plan.assign([_card(DuelCard.Type.QUICK, 50)])
	engine.run_bout([null])
	_check(not engine.over and engine.ward.hp == engine.ward.max_hp - int(engine.ward.max_hp * DuelEngine.WARD_HIT), "호위 목표: 우리 쪽이 지면 지킬 인물이 다침")
	engine.ward.hp = 1
	engine.current_friend().take_damage(engine.current_friend().hp - 1)
	engine.prepare_bout()
	engine.enemy_plan.assign([_card(DuelCard.Type.QUICK, 50)])
	engine.run_bout([null])
	_check(engine.over and engine.outcome == CombatManager.Outcome.DEFEAT, "호위 목표: 지킬 인물이 쓰러지면 패배")

	# 정보: 지혜에 따라 상대 배치가 보이고, 안개는 한 단계 덜
	setup = CombatManager.create_sparring(hero)
	engine = DuelEngine.new(setup, hero)
	engine.prepare_bout()
	var levels: Array = []
	for wisdom in [10, 15, 20, 30]:
		hero.wisdom = wisdom
		levels.append(engine.reveal_level())
	_check(levels == [0, 1, 2, 3], "정보: 지혜 10·15·20·30 → 보이는 정도 %s" % [levels])
	var shown: PackedStringArray = engine.revealed_plan()
	_check(shown.size() == engine.enemy_plan.size() and shown[0].contains(engine.enemy_plan[0].display_name), "정보: 지혜가 높으면 초식 이름까지")
	hero.wisdom = 15
	shown = engine.revealed_plan()
	_check(shown[0] == engine.enemy_plan[0].get_type_name() and (shown.size() < 2 or shown[1] == "?"), "정보: 낮으면 첫 칸 유형만")
	engine.weather = "fog"
	_check(engine.reveal_level() == 0, "정보: 안개는 한 단계 덜 보임")

	# 버릇: 겨뤄 본 상대가 첫 칸에 자주 낸 유형을 기억한다 (저장된다)
	var memory: Dictionary = {}
	var mastery: Dictionary = {}
	var art := MartialArtData.new()
	art.id = "t_sword"
	art.display_name = "시험검"
	art.damage = 12
	hero.learn_martial_art(art)
	engine = DuelEngine.new(CombatManager.create_sparring(hero), hero, memory, mastery)
	_check(engine.habit_text().is_empty(), "버릇: 처음 겨루는 상대는 모름")
	for i in 3:
		engine.prepare_bout()
		engine.enemy_plan.assign([_card(DuelCard.Type.STRIKE), _card(DuelCard.Type.GUARD), _card(DuelCard.Type.GUARD)])
		var sword: DuelCard = engine.get_player().cards[5]
		engine.run_bout([sword, guards[0], guards[0]])
		if engine.over:
			break
	var rival_id: String = DuelEngine._npc_id(engine.current_foe() if engine.current_foe() else engine.foes[0])
	_check(memory.has(rival_id) and int(memory[rival_id]["first"].get(DuelCard.Type.STRIKE, 0)) >= 1, "버릇: 상대의 첫 칸 유형 기록")
	var again := DuelEngine.new(CombatManager.create_sparring(hero), hero, memory, mastery)
	_check(again.habit_text().contains("강공"), "버릇: 다시 만나면 보임 (%s)" % again.habit_text())
	_check(int(mastery.get("t_sword", 0)) >= 1, "숙련: 무공 초식을 쓰면 횟수가 쌓임")
	gm.duel_memory = memory
	gm.art_mastery = mastery
	gm.save_game(3)
	gm.duel_memory = {}
	gm.art_mastery = {}
	gm.load_game(3)
	_check(gm.duel_memory.has(rival_id) and gm.duel_memory[rival_id]["first"].has(DuelCard.Type.STRIKE) and gm.art_mastery.has("t_sword"), "버릇·숙련 저장과 불러오기")
	SaveManager.delete_save(3)

	# 끝까지 자동으로: 언제나 끝난다
	engine = DuelEngine.new(CombatManager.create_night_bandits(hero, gm.player_sect), hero)
	engine.play_to_end()
	_check(engine.over and engine.history.size() > 3, "자동으로 끝까지 치르면 결과와 기록이 남음")
	_completed["_test_duel_engine"] = true


## 전투 다양화 시험용 구성: 도적 n명 (format·stage·조건은 부른 쪽에서)
func _bandit_setup(hero: CharacterData, count: int, format: String = "duel") -> CombatSetup:
	var setup := CombatSetup.new()
	setup.title = "시험"
	setup.format = format
	for i in count:
		var bandit: CharacterData = NpcRoster.create_character("npc_bandit", hero)
		bandit.id = "npc_bandit_%d" % i
		bandit.display_name = "도적 %d" % i
		setup.add_enemy(bandit, Vector2i(12, i))
	return setup


func _cards(type: DuelCard.Type, count: int, power: int = 20) -> Array[DuelCard]:
	var result: Array[DuelCard] = []
	for i in count:
		result.append(_card(type, power))
	return result


## 형식: 포위·진형·추격·잠입·대치·비무대회
func _test_duel_formats() -> void:
	var T := DuelCard.Type
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	var hero: CharacterData = gm.player_character
	hero.restore_internal_energy()

	# 포위: 적 여럿이 한꺼번에, 졸개는 2칸, 휩쓸기, 압박
	var setup: CombatSetup = _bandit_setup(hero, 5, "siege")
	for enemy in setup.enemies:
		setup.mooks[enemy.id] = true
	var engine := DuelEngine.new(setup, hero)
	_check(engine.active_foes().size() == _Balance.SIEGE_FOES and engine.active_friends().size() == 1 and engine.controlled().is_player, "포위: 적 셋이 한꺼번에, 주인공 선봉")
	_check(engine.active_foes()[0].slot_count() == _Balance.MOOK_SLOTS, "포위: 졸개는 %d칸" % _Balance.MOOK_SLOTS)
	_check(engine.get_player().cards.any(func(c: DuelCard) -> bool: return c.effects.has("sweep")), "포위: 휩쓸기 초식")
	engine.prepare_bout()
	for foe in engine.active_foes():
		if foe == engine.current_foe():
			engine.enemy_plan.assign(_cards(T.GUARD, 2))
		else:
			engine.plans[foe] = _cards(T.GUARD, 2)
	var aimed: CombatUnit = engine.active_foes()[2]
	engine.set_target(0, aimed)
	var sweep: DuelCard = engine.get_player().cards.filter(func(c: DuelCard) -> bool: return c.effects.has("sweep"))[0]
	engine.run_bout([sweep, null, null])
	var lost: Array = engine.active_foes().map(func(u: CombatUnit) -> int: return u.max_hp - u.hp)
	_check(lost.all(func(x: int) -> bool: return x > 0) and aimed.max_hp - aimed.hp == lost.max(), "휩쓸기: 고른 상대는 온전히, 나머지도 맞음 %s" % [lost])
	_check(engine.get_player().momentum >= 2, "포위 압박: 둘러싸인 주인공의 기세가 빨리 오름 (%d)" % engine.get_player().momentum)
	setup = _bandit_setup(hero, 4, "siege")
	setup.stage = "alley"
	_check(DuelEngine.new(setup, hero).active_foes().size() == 2, "좁은 골목: 한꺼번에 둘까지")

	# 진형: 앞·뒷줄, 뒷줄은 술로만, 앞줄이 가로막음, 협공, 엄호
	var front_a := _duel_unit("갑", 10, true)
	var front_b := _duel_unit("을")
	var back_b := _duel_unit("병")
	back_b.front = false
	var ctx: Dictionary = {"format": "formation"}
	var result: Dictionary = DuelRules.resolve_multi(0, [
		{"unit": front_a, "card": _card(T.QUICK), "target": back_b, "side": 0},
		{"unit": front_b, "card": _card(T.GUARD), "target": front_a, "side": 1},
		{"unit": back_b, "card": _card(T.STRIKE), "target": front_a, "side": 1},
	], ctx)
	_check(back_b.hp == back_b.max_hp and front_b.hp < front_b.max_hp, "진형: 앞줄이 뒷줄을 가로막음")
	_check(front_a.hp == front_a.max_hp - int(result["taken"][front_a]) and "닿지 않음" in "\n".join(result["lines"]), "진형: 뒷줄의 강공은 닿지 않음 (술만)")
	var ally_a := _duel_unit("정", 10, true)
	var lone := _duel_unit("무")
	var a1 := _duel_unit("기", 10, true)
	result = DuelRules.resolve_multi(0, [
		{"unit": a1, "card": _card(T.STRIKE), "target": lone, "side": 0},
		{"unit": ally_a, "card": _card(T.STRIKE), "target": lone, "side": 0},
		{"unit": lone, "card": _card(T.GUARD), "target": a1, "side": 1},
	], {"format": "formation"})
	_check("협공" in "\n".join(result["lines"]), "진형: 같은 적을 함께 치면 협공")
	var hitter := _duel_unit("경")
	var ward_u := _duel_unit("신", 10, true)
	var cover := _duel_unit("임", 10, true)
	cover.order = "cover"
	result = DuelRules.resolve_multi(0, [
		{"unit": hitter, "card": _card(T.STRIKE, 30), "target": ward_u, "side": 1},
		{"unit": ward_u, "card": _card(T.QUICK), "target": hitter, "side": 0},
		{"unit": cover, "card": _card(T.GUARD), "target": hitter, "side": 0},
	], {"format": "formation"})
	_check(cover.hp < cover.max_hp and "대신 받음" in "\n".join(result["lines"]), "진형: 엄호 동료가 피해를 나눠 받음")
	setup = _bandit_setup(hero, 3, "formation")
	setup.add_ally(NpcRoster.create_character("npc_disciple", hero), Vector2i(2, 4))
	setup.add_ally(NpcRoster.create_character("npc_disciple", hero), Vector2i(2, 6))
	setup.allies[1].id = "npc_disciple_b"
	setup.orders[setup.allies[1].id] = "cover"
	engine = DuelEngine.new(setup, hero)
	_check(engine.active_friends().size() == 3 and engine.active_foes().size() == 3 and not engine.active_foes()[2].front, "진형: 셋 대 셋, 셋째는 뒷줄")
	engine.set_order(engine.friends[1], "defend")
	_check(engine.friends[1].order == "defend", "진형: 동료 지시 바꾸기")

	# 추격 (쫓기기): 회피로 흘리면 멀어지고, 끝까지 벌리면 따돌림
	setup = _bandit_setup(hero, 1, "chase")
	setup.objective = "escape"
	engine = DuelEngine.new(setup, hero)
	hero.agility = 60
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.STRIKE, 3))
	engine.run_bout(_cards(T.EVADE, 3).map(func(c: DuelCard) -> DuelCard: return DuelCard.basic_cards()[3]))
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY and engine.distance == _Balance.CHASE_END, "추격: 흘릴수록 멀어져 따돌림 (거리 %d)" % engine.distance)
	# 추격 (쫓기): 강공으로 맞히면 좁혀 붙잡고, 연전으로 바뀐다
	setup = _bandit_setup(hero, 1, "chase")
	setup.objective = "catch"
	engine = DuelEngine.new(setup, hero)
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.GUARD, 3))
	engine.run_bout([DuelCard.basic_cards()[1], DuelCard.basic_cards()[1], DuelCard.basic_cards()[1]])
	_check(engine.distance == 0 and engine.format == "duel" and not engine.over, "추격: 따라잡으면 그 자리에서 겨룸 (거리 %d)" % engine.distance)
	hero.agility = 10

	# 잠입: 첫 합 상대는 막기·운기뿐, 기습 2배, 강공은 소리가 나 경보와 숨은 증원
	setup = _bandit_setup(hero, 1, "stealth")
	var lurker: CharacterData = NpcRoster.create_character("npc_bandit", hero)
	lurker.id = "npc_bandit_hidden"
	setup.hidden_foes.append(lurker)
	engine = DuelEngine.new(setup, hero)
	engine.prepare_bout()
	_check(engine.enemy_plan.all(func(c: DuelCard) -> bool: return c.type in [T.GUARD, T.FOCUS]), "잠입: 경계 전 상대는 막기·운기뿐")
	engine.enemy_plan.assign(_cards(T.FOCUS, 3, 0))
	engine.current_foe().max_hp = 9999
	engine.current_foe().hp = 9999
	engine.run_bout([DuelCard.basic_cards()[1], DuelCard.basic_cards()[1], DuelCard.basic_cards()[1]])
	_check(engine.detection == 3 and "암습" in "\n".join(engine.history), "잠입: 첫 합 암습, 강공 셋에 발각 3")
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.GUARD, 3))
	engine.run_bout([DuelCard.basic_cards()[1], DuelCard.basic_cards()[1], DuelCard.basic_cards()[1]])
	_check(engine.alarm and engine.foes.any(func(u: CombatUnit) -> bool: return u.character.id == "npc_bandit_hidden"), "잠입: 발각 %d에 경보, 숨은 자가 나타남" % _Balance.STEALTH_ALARM)

	# 대치: 피해 없이 기세, 먼저 5면 이김. 이어지는 연전이면 기세를 안고 시작
	setup = _bandit_setup(hero, 1, "standoff")
	engine = DuelEngine.new(setup, hero)
	var hp_before: int = engine.current_foe().hp
	for i in 2:
		engine.prepare_bout()
		engine.enemy_plan.assign(_cards(T.GUARD, 3))
		engine.run_bout([DuelCard.basic_cards()[1], DuelCard.basic_cards()[1], DuelCard.basic_cards()[1]])
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY and engine.current_foe().hp == hp_before, "대치: 피해 없이 기세 %d에 먼저 닿으면 이김" % _Balance.STANDOFF_GOAL)
	setup = _bandit_setup(hero, 1, "standoff")
	setup.standoff_then = "duel"
	engine = DuelEngine.new(setup, hero)
	for i in 2:
		engine.prepare_bout()
		engine.enemy_plan.assign(_cards(T.GUARD, 3))
		engine.run_bout([DuelCard.basic_cards()[1], DuelCard.basic_cards()[1], DuelCard.basic_cards()[1]])
	_check(not engine.over and engine.format == "duel" and engine.get_player().momentum == _Balance.STANDOFF_CARRY, "대치 뒤 연전: 이긴 쪽이 기세 %d로 시작" % _Balance.STANDOFF_CARRY)

	# 비무대회: 혼자 연달아, 판 사이 조금 회복, 다음 상대 관전, 성적 플래그
	setup = _bandit_setup(hero, 2, "tournament")
	setup.add_ally(NpcRoster.create_character("npc_disciple", hero), Vector2i(2, 4))
	setup.placement_flags = {"1": "tourney_one", "2": "tourney_won"}
	engine = DuelEngine.new(setup, hero)
	_check(engine.friends.size() == 1 and not engine.habit_text(engine.current_foe()).is_empty(), "비무대회: 혼자 나서고 첫 상대를 관전")
	engine.get_player().take_damage(50)
	var hurt: int = engine.get_player().hp
	engine.current_foe().take_damage(engine.current_foe().hp - 1)
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.FOCUS, 3, 0))
	engine.run_bout([DuelCard.basic_cards()[0], DuelCard.basic_cards()[0], DuelCard.basic_cards()[0]])
	_check(engine.tournament_round == 1 and engine.get_player().hp > hurt and engine.foe_index == 1, "비무대회: 이기면 조금 쉬고 다음 판")
	engine.retreat()
	_check(engine.summary()["placement_flag"] == "tourney_one", "비무대회: 이긴 판 수로 성적 플래그")
	_completed["_test_duel_formats"] = true


## 전장·조건·특성·목표·사건·평가
func _test_duel_variety_rules() -> void:
	var T := DuelCard.Type
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	var hero: CharacterData = gm.player_character
	hero.restore_internal_energy()

	# 전장
	var a := _duel_unit("갑", 20)
	var b := _duel_unit("을")
	var result: Dictionary = DuelRules.resolve_slot(0, a, _card(T.STRIKE), b, _card(T.EVADE), {"stage": "bridge"})
	_check(result["damage"]["b"] > 0 and "피할 곳이 없다" in "\n".join(result["lines"]), "외나무다리: 회피는 헛디딤")
	b.hp = int(b.max_hp * 0.4)
	result = DuelRules.resolve_slot(0, a, _card(T.STRIKE), b, null, {"stage": "bridge"})
	_check(b in result["fallen_off"], "외나무다리: 강공에 몰린 쪽이 떨어짐")
	a = _duel_unit("갑")
	_check(DuelRules._speed(a, _card(T.QUICK), {"stage": "rooftop"}) == DuelRules._speed(a, _card(T.QUICK)) + 10 and DuelRules._speed(a, _card(T.STRIKE), {"stage": "rooftop"}) == DuelRules._speed(a, _card(T.STRIKE)) - 10, "지붕 위: 속공 +1, 강공 -1")
	var steady: int = DuelRules._hit(a, _card(T.STRIKE), b, null, {"stage": "boat", "slot": 0})["damage"]
	var sway: int = DuelRules._hit(a, _card(T.STRIKE), b, null, {"stage": "boat", "slot": 1})["damage"]
	_check(sway < steady, "배 위: 둘째 칸 강공이 흔들림 (%d → %d)" % [steady, sway])
	_check(DuelRules._hit(a, _card(T.TRICK), b, null, {"stage": "bamboo"})["damage"] > DuelRules._hit(a, _card(T.TRICK), b, null)["damage"], "대숲: 술 강화")
	_check(not DuelRules.banned_reason(_card(T.FOCUS), {"stage": "burning"}).is_empty() and not DuelRules.banned_reason(_card(T.TRICK), {"stage": "arena"}).is_empty(), "불타는 장원 운기 불가, 비무대 술 금지")
	a = _duel_unit("갑", 5)
	b = _duel_unit("을", 30)
	DuelRules.resolve_slot(0, a, _card(T.QUICK), b, _card(T.EVADE), {"stage": "ice"})
	_check(a.has_status("slipped"), "빙판: 흘려진 쪽이 미끄러짐")
	var setup: CombatSetup = _bandit_setup(hero, 1)
	setup.stage = "shrine"
	hero.wisdom = 30
	var engine := DuelEngine.new(setup, hero)
	_check(engine.reveal_level() == 0, "밤의 사당: 첫 합은 안 보임")
	setup = _bandit_setup(hero, 1)
	setup.stage = "burning"
	engine = DuelEngine.new(setup, hero)
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.GUARD, 3))
	engine.run_bout(_cards(T.GUARD, 3))
	_check(engine.get_player().hp < engine.get_player().max_hp and engine.current_foe().hp < engine.current_foe().max_hp, "불타는 장원: 합마다 모두 체력 감소")
	setup = _bandit_setup(hero, 1)
	setup.stage = "arena"
	engine = DuelEngine.new(setup, hero)
	engine.current_foe().hp = int(engine.current_foe().max_hp * 0.3)
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.FOCUS, 3, 0))
	engine.run_bout([DuelCard.basic_cards()[0], null, null])
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY and "장외" in "\n".join(engine.history), "비무대: 밀려난 쪽 장외")
	hero.wisdom = 16

	# 조건
	var sword := MartialArtData.new()
	sword.id = "t_cond_sword"
	sword.category = MartialArtData.Category.SWORD
	sword.damage = 12
	hero.learn_martial_art(sword)
	setup = _bandit_setup(hero, 1)
	setup.conditions = PackedStringArray(["unarmed", "wounded", "exhausted", "poisoned"])
	hero.restore_internal_energy()
	engine = DuelEngine.new(setup, hero)
	var me: CombatUnit = engine.get_player()
	_check(not me.cards.any(func(c: DuelCard) -> bool: return c.art_id == "t_cond_sword"), "맨손: 검법 초식이 빠짐")
	_check(me.hp == int(me.max_hp * _Balance.WOUNDED_HP) and me.slot_count() == 2, "부상: 체력 70%, 칸 -1")
	_check(hero.internal_energy_current <= int(hero.internal_energy_max * _Balance.EXHAUSTED_ENERGY), "지침: 내공 절반")
	var energy: int = hero.internal_energy_current
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.GUARD, 3))
	engine.run_bout(_cards(T.GUARD, 2))
	_check(hero.internal_energy_current == energy - _Balance.POISON_DRAIN, "중독: 합마다 내공 감소")
	_check(not DuelRules.banned_reason(_card(T.TRICK), {"conditions": PackedStringArray(["honor"])}).is_empty(), "정정당당: 술 금지")

	# 상대 특성
	a = _duel_unit("갑")
	b = _duel_unit("을")
	b.traits = ["enrage"]
	b.hp = int(b.max_hp * 0.55)
	DuelRules.resolve_slot(0, a, _card(T.STRIKE, 30), b, null)
	_check(b.enraged and b.slot_bonus == 1 and b.momentum >= _Balance.ENRAGE_MOMENTUM - 1, "광폭: 절반 아래에서 칸 +1·기세 (진 칸의 -1 뒤 %d)" % b.momentum)
	b = _duel_unit("을")
	b.traits = ["iron_body"]
	_check(DuelRules._hit(a, _card(T.QUICK), b, null)["damage"] < DuelRules._hit(a, _card(T.QUICK), _duel_unit("병"), null)["damage"], "금강불괴: 속공 반감")
	b = _duel_unit("을")
	b.traits = ["poison_mist"]
	a = _duel_unit("갑")
	DuelRules.resolve_slot(0, a, _card(T.FOCUS, 0), b, _card(T.GUARD))
	_check(a.hp < a.max_hp, "독무: 운기하면 다침")
	b = _duel_unit("을")
	b.traits = ["two_phase"]
	b.hp = 1
	DuelRules.resolve_slot(0, _duel_unit("갑"), _card(T.STRIKE), b, null)
	_check(b.is_alive() and b.second_phase and b.hp == int(b.max_hp * _Balance.SECOND_PHASE_HP), "단계 전환: 한 번 다시 일어남")
	setup = _bandit_setup(hero, 1)
	setup.traits = {"npc_bandit_0": ["telegraph"]}
	engine = DuelEngine.new(setup, hero)
	for i in 3:
		engine.prepare_bout()
		if i == 2:
			_check(engine.enemy_plan[-1].effects.has("telegraph") and engine.revealed_plan()[-1].contains(engine.enemy_plan[-1].display_name), "예고 절초: 셋째 합 마지막 칸, 늘 보임")
		engine.run_bout(_cards(T.GUARD, 3))
	_check("다음 합 마지막 칸" in "\n".join(engine.history), "예고 절초: 한 합 전에 예고")
	setup = _bandit_setup(hero, 1)
	setup.traits = {"npc_bandit_0": ["mirror"]}
	engine = DuelEngine.new(setup, hero)
	engine.last_types = {"friend": [T.EVADE, T.EVADE, T.EVADE], "foe": []}
	engine.prepare_bout()
	_check(engine.enemy_plan.all(func(c: DuelCard) -> bool: return c.type == T.EVADE), "모방: 내가 낸 유형을 따라 냄")

	# 목표: 생포 (몰아붙인 뒤 막기 반격), 죽이면 실패
	setup = _bandit_setup(hero, 1)
	setup.objective = "capture"
	setup.objective_target = "npc_bandit_0"
	engine = DuelEngine.new(setup, hero)
	engine.current_foe().hp = int(engine.current_foe().max_hp * 0.2)
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.QUICK, 3, 2))
	engine.run_bout(_cards(T.GUARD, 3).map(func(c: DuelCard) -> DuelCard: return DuelCard.basic_cards()[2]))
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY and engine.captured, "생포: 막기 반격으로 사로잡음")
	engine = DuelEngine.new(setup, hero)
	engine.current_foe().hp = 1
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.FOCUS, 3, 0))
	engine.run_bout([DuelCard.basic_cards()[1], null, null])
	_check(engine.over and engine.outcome == CombatManager.Outcome.DEFEAT, "생포: 죽이면 실패")
	setup = _bandit_setup(hero, 1)
	setup.objective = "timed"
	setup.objective_rounds = 2
	engine = DuelEngine.new(setup, hero)
	for i in 2:
		engine.prepare_bout()
		engine.enemy_plan.assign(_cards(T.GUARD, 3))
		engine.run_bout(_cards(T.GUARD, 3))
	_check(engine.over and engine.outcome == CombatManager.Outcome.DEFEAT, "시간 안에: 넘기면 패배")
	setup = _bandit_setup(hero, 1)
	setup.objective = "endure"
	setup.objective_rounds = 2
	setup.objective_count = 5
	engine = DuelEngine.new(setup, hero)
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.STRIKE, 3, 30))
	engine.run_bout([null, null, null])
	_check(engine.over and engine.outcome == CombatManager.Outcome.DEFEAT, "버텨 내기: 피해 한도를 넘으면 패배")
	setup = _bandit_setup(hero, 1)
	setup.objective = "disarm"
	setup.objective_count = 2
	engine = DuelEngine.new(setup, hero)
	hero.agility = 60
	engine.prepare_bout()
	var finisher_card: DuelCard = _card(T.STRIKE, 40)
	finisher_card.momentum_cost = 0
	finisher_card.effects.append("telegraph")
	engine.enemy_plan.assign([finisher_card, finisher_card, finisher_card])
	engine.run_bout([DuelCard.basic_cards()[3], DuelCard.basic_cards()[3], DuelCard.basic_cards()[3]])
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY and engine.nullified >= 2, "무기 떨구기: 절초를 흘려 무산")
	hero.agility = 10
	setup = _bandit_setup(hero, 3, "formation")
	setup.objective = "hold_line"
	setup.objective_rounds = 1
	engine = DuelEngine.new(setup, hero)
	engine.get_player().max_hp = 9999
	engine.get_player().hp = 9999
	engine.prepare_bout()
	engine.run_bout(_cards(T.GUARD, 3))
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY, "진지 사수: 앞줄을 지키며 버팀")

	# 사건: 증원, 배신, 인연의 개입, 설득(선택), 결단
	setup = _bandit_setup(hero, 1)
	setup.add_ally(NpcRoster.create_character("npc_senior_brother", hero), Vector2i(2, 4))
	setup.events = [
		{"type": "reinforce", "when": {"bout": 1}, "npc": "npc_bandit", "name": "도적 증원"},
		{"type": "betrayal", "when": {"bout": 1}, "npc": "npc_senior_brother", "lines": ["대사형: 미안하다."]},
	]
	engine = DuelEngine.new(setup, hero)
	var foes_before: int = engine.foes.size()
	engine.prepare_bout()
	engine.run_bout(_cards(T.GUARD, 3))
	_check(engine.foes.size() == foes_before + 2 and engine.foes.any(func(u: CombatUnit) -> bool: return u.character.id == "npc_senior_brother") and engine.event_lines.size() >= 2, "사건: 증원과 배신")
	var master: RelationshipData = RelationshipManager.get_bond_with(gm.player_relationships, "npc_master")
	master.bond_strength = 80
	setup = _bandit_setup(hero, 1)
	setup.events = [{"type": "bond_intervene", "when": {"player_hp_below": 0.5}, "npc": "npc_master"}]
	engine = DuelEngine.new(setup, hero, {}, {}, gm.player_relationships)
	engine.get_player().hp = int(engine.get_player().max_hp * 0.3)
	var low: int = engine.get_player().hp
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.GUARD, 3))
	engine.run_bout(_cards(T.GUARD, 3))
	_check(engine.get_player().hp > low and engine.get_player().momentum >= _Balance.INTERVENE_MOMENTUM, "사건: 인연의 개입 (회복·기세)")
	setup = _bandit_setup(hero, 1)
	setup.events = [{"type": "parley", "when": {"bout": 1}, "lines": ["도적: 잠깐!"]}]
	engine = DuelEngine.new(setup, hero)
	engine.prepare_bout()
	engine.run_bout(_cards(T.GUARD, 3))
	_check(not engine.pending_choice.is_empty() and engine.pending_choice["options"].size() == 2 and engine.run_bout(_cards(T.GUARD, 3)).is_empty(), "사건: 설득 선택을 기다림 (그동안 겨루지 않음)")
	hero.charisma = 20
	engine.choose(0)
	_check(engine.over and engine.outcome == CombatManager.Outcome.VICTORY and not engine.choice_effects.is_empty(), "설득 성공: 상대가 물러나고 효과가 남음")
	setup = _bandit_setup(hero, 1)
	setup.events = [{"type": "decision", "when": {"bout": 1}}]
	engine = DuelEngine.new(setup, hero)
	engine.prepare_bout()
	engine.run_bout(_cards(T.GUARD, 3))
	engine.choose(0)
	_check(engine.get_player().momentum == DuelRules.MAX_MOMENTUM and engine.get_player().hp < engine.get_player().max_hp, "결단: 목숨을 걸면 기세 최고조")
	engine.play_to_end()
	_check(engine.over, "자동: 사건 선택도 스스로 고르며 끝까지")
	hero.charisma = 10

	# 평가와 도전
	setup = _bandit_setup(hero, 1)
	setup.challenge = {"type": "no_trick"}
	engine = DuelEngine.new(setup, hero)
	engine.current_foe().hp = 1
	engine.prepare_bout()
	engine.enemy_plan.assign(_cards(T.FOCUS, 3, 0))
	engine.run_bout([DuelCard.basic_cards()[0], null, null])
	var summary: Dictionary = engine.summary()
	_check(engine.rating() == "완승" and summary["challenge_met"] and summary["challenge"].contains("술"), "평가 완승·도전 달성")
	setup.challenge = {"type": "within_bouts", "value": 0}
	_check(not engine.challenge_met(), "도전: 이루지 못하면 실패")

	# 무인의 성격과 지시
	_check(DuelAI.style_of(NpcRoster.create_character("npc_bandit", hero)) == "mook", "인물 데이터의 무인 성격")
	var unit: CombatUnit = CombatUnit.new(NpcRoster.create_character("npc_disciple", hero), false, true)
	unit.cards = DuelCard.cards_for(unit.character)
	unit.order = "cover"
	var rng := RandomNumberGenerator.new()
	var guards: int = 0
	for i in 20:
		rng.seed = i
		guards += DuelAI.plan(unit, [], {}, 0.0, rng).filter(func(c: DuelCard) -> bool: return c.type == T.GUARD).size()
	_check(guards > 25, "엄호 지시: 막기 위주 (%d/60)" % guards)

	# 데이터 검증
	var bad: Dictionary = {"id": "x", "title": "x", "enemies": [{"npc": "npc_bandit", "traits": ["flying"]}], "format": "space", "stage": "moon",
		"conditions": ["drunk"], "events": [{"type": "explode", "when": {"bout": 1}}], "challenge": {"type": "dance"}}
	var errors: PackedStringArray = CombatLibrary.validate_combat_dict(bad)
	_check(errors.size() == 6, "다양화 데이터 검증: 형식·전장·조건·특성·사건·도전 (%s)" % "; ".join(errors))
	_completed["_test_duel_variety_rules"] = true


## 대결 화면 (여럿·사건): 상대 고르기, 동료 지시, 게이지, 사건 선택, 평가
func _test_duel_screen_formats() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	var hero: CharacterData = gm.player_character
	var setup: CombatSetup = _bandit_setup(hero, 3, "formation")
	setup.add_ally(NpcRoster.create_character("npc_disciple", hero), Vector2i(2, 4))
	setup.events = [{"type": "decision", "when": {"bout": 1}, "lines": ["적이 몰려온다!"]}]
	setup.challenge = {"type": "no_trick"}
	gm.start_combat(setup)
	await process_frame
	await process_frame
	var c: Node = current_scene
	_check(c.squad_box.visible and not c.versus_row.visible and c.squad_box.has_node("Foe_2"), "여럿: 사람 목록과 상대 버튼")
	_check(c.goal_label.text.contains("진형") and c.goal_label.text.contains("도전"), "형식·도전 안내")
	var small: Array = c.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.visible and b.get_combined_minimum_size().y < 48)
	_check(small.is_empty(), "여럿 화면 버튼도 48px 이상")
	c.select_slot(1)
	var foe: CombatUnit = c.engine.active_foes()[1]
	c.squad_box.get_node("Foe_1").pressed.emit()
	_check(c.engine.target_of(1) == foe and c.slot_row.get_node("Slot1").text.contains(foe.display_name), "상대를 눌러 고른 칸의 상대로")
	var ally: CombatUnit = c.engine.active_friends().filter(func(u: CombatUnit) -> bool: return not u.is_player)[0]
	var order_button: Button = c.squad_box.find_child("Order_*", true, false)
	order_button.pressed.emit()
	_check(ally.order == "defend" and c.squad_box.find_child("Order_*", true, false).text.contains("수비"), "동료 지시 바꾸기 (공세 → 수비)")
	# 첫 합에 승부가 나지 않게 모두 체력을 넉넉히 (결단은 첫 합 뒤)
	for unit in c.engine.friends + c.engine.foes:
		unit.max_hp = 9999
		unit.hp = 9999
	c.auto_fill()
	c.fight()
	for i in 20:
		if c.choice_popup != null and c.choice_popup.visible:
			break
		await process_frame
	_check(c.choice_popup != null and c.choice_popup.visible and c.fight_button.disabled, "사건: 결단을 고를 때까지 겨루지 않음")
	c.choice_popup._on_option_pressed("1")
	await process_frame
	_check(c.engine.pending_choice.is_empty() and not c.fight_button.disabled and c.engine.history[-1].contains("버틴다"), "결단을 고르면 다음 합")
	await c.skip_to_result()
	_check(c.result_label.text.contains("평가") and c.result_label.text.contains("도전"), "결과: 평가와 도전")
	c.engine.outcome = CombatManager.Outcome.DEFEAT
	_check(c.result_headline()["title"] == "패배", "결과 판: 패배")
	c.engine.outcome = CombatManager.Outcome.RETREAT
	_check(c.result_headline()["title"] == "후퇴", "결과 판: 후퇴")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame

	# 추격 게이지
	setup = _bandit_setup(hero, 1, "chase")
	setup.objective = "escape"
	gm.start_combat(setup)
	await process_frame
	await process_frame
	c = current_scene
	_check(c.versus_row.visible and c.intent_label.text.contains("거리 %d/%d" % [_Balance.CHASE_START, _Balance.CHASE_END]), "추격: 거리 게이지")
	c.leave_combat()
	await process_frame
	await process_frame
	_completed["_test_duel_screen_formats"] = true


## 대결 화면: 칸 고르기·초식 놓기·겨루기·자동 배치·자동 전투·결과만 보기·후퇴
func _test_duel_screen() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	gm.player_character.learn_martial_art(MartialArtLibrary.create_art("preset_soul_chase_sword"))
	gm.start_combat(CombatManager.create_night_bandits(gm.player_character, gm.player_sect))
	await process_frame
	await process_frame
	var c: Node = current_scene
	_check(c.get_node("Background").mouse_filter == Control.MOUSE_FILTER_IGNORE, "전투 바탕은 터치를 가로채지 않음")
	_check(c.slot_row.get_child_count() == c.engine.current_friend().slot_count(), "칸 수만큼 칸 버튼")
	_check(c.hand_grid.get_child_count() == c.engine.current_friend().cards.size(), "손패: 쓸 수 있는 초식 모두")
	var small: Array = c.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.visible and b.get_combined_minimum_size().y < 48)
	_check(small.is_empty(), "대결 화면 버튼은 모두 48px 이상 (%d개 미달)" % small.size())

	# 칸 고르고 놓기: 놓으면 다음 빈 칸으로
	c.engine.set_player_first(true)
	c._toggle_order()
	_check(not c.engine.current_friend().is_player and c.order_button.text == "주인공을 선봉으로", "선봉·대장 바꾸기")
	c._toggle_order()
	_check(c.engine.current_friend().is_player, "주인공을 선봉으로")
	var hero_cards: Array[DuelCard] = c.engine.current_friend().cards
	var art_card: DuelCard = hero_cards[5]
	c.select_slot(1)
	c.place_card(art_card)
	_check(c.plan[1] == art_card and c.selected_slot == 0, "고른 칸에 초식을 놓고 첫 빈 칸을 고름")
	_check(c.hand_grid.get_node("Card_" + art_card.id).disabled, "이미 놓은 무공 초식은 손패에서 막힘")
	c.place_card(art_card)
	_check(c.plan[0] == null, "같은 무공 초식은 두 번 놓지 못함")
	c.place_card(hero_cards[0])
	c.place_card(hero_cards[0])
	_check(c.plan[0] == hero_cards[0] and c.plan[2] == hero_cards[0], "기본 동작은 여러 칸에")
	c.select_slot(2)
	c.select_slot(2)
	_check(c.plan[2] == null, "고른 칸을 다시 누르면 비움")
	# 사전 점검: 빈 칸이 있으면 알려 주고, 겨루기 전에 한 번 묻는다
	_check(c.warning_label.visible and c.warning_label.text.contains("3칸이 비어"), "사전 점검: 빈 칸 경고")
	_unhandled_key(c, KEY_SPACE)
	_check(c.confirm_popup != null and c.confirm_popup.visible and c.engine.bout_total == 0, "빈틈이 있으면 겨루기 전에 확인")
	c.confirm_popup._answer(false)
	_check(c.engine.bout_total == 0, "다시 배치: 겨루지 않음")
	var broke: CombatUnit = c.engine.current_friend()
	var energy: int = broke.character.internal_energy_current
	broke.character.internal_energy_current = 0
	c.select_slot(2)
	c._refresh()
	_check(c.hand_grid.get_node("Card_basic_chop").text.contains("내공 부족"), "손패: 이 칸에선 내공이 모자라는 초식 표시")
	broke.character.internal_energy_current = energy
	_unhandled_key(c, KEY_A)
	_check(not c.plan.has(null), "A·자동 배치: 모든 칸을 채움")
	_check(c.plan_warnings().all(func(w: Dictionary) -> bool: return not w["serious"]), "자동 배치에는 확실한 빈틈이 없음")

	# 겨루기: 한 합이 지나고 다음 배치를 기다린다
	_unhandled_key(c, KEY_SPACE)
	await process_frame
	_check(c.engine.bout_total == 1 and c.log_label.text.contains("1합"), "겨루기: 한 합 진행과 기록")
	_check(c.plan.size() == c.engine.current_friend().slot_count() and c.plan.all(func(x: Variant) -> bool: return x == null), "다음 합은 빈 칸에서 다시 배치")
	_check(not c.order_button.visible, "첫 합 뒤에는 순서를 바꿀 수 없음")

	# 자동 전투: 합이 저절로 넘어간다
	c.set_auto(true)
	await process_frame
	await process_frame
	_check(c.engine.bout_total >= 2 or c.engine.over, "자동 전투: 합이 저절로 진행")
	c.set_auto(false)
	# 결과만 보기: 끝까지 치르고 결과를 반영한다
	await c.skip_to_result()
	_check(c.engine.over and gm.pending_combat == null and c.result_label.visible, "결과만 보기: 전투가 끝나고 결과 반영")
	_check(gm.last_combat_history.size() > 3, "전투가 끝나면 기록을 남김 (연대기용)")
	_check(c.back_button.text == "돌아가기" and c.fight_button.disabled, "끝나면 돌아가기만")
	# 결과 판: 큰 글씨로 승패, 평가·한 줄, 보상, 기록 보기로 닫기
	var headline: Dictionary = c.result_headline()
	_check(c.result_overlay.visible and c.result_title.text == headline["title"] and c.result_detail.text == c.result_label.text, "결과 판: 큰 글씨의 결과와 보상")
	_check(c.result_title.text in ["완승!", "승리!", "신승!", "패배", "후퇴"] and not c.result_subtitle.text.is_empty(), "결과 판: 승리·패배·후퇴와 한 줄 설명 (%s)" % c.result_title.text)
	_check(c.result_overlay.find_children("*", "Button", true, false).all(func(b: Button) -> bool: return b.get_combined_minimum_size().y >= 48), "결과 판 버튼 48px 이상")
	c.result_overlay.find_child("ResultReviewButton", true, false).pressed.emit()
	_check(not c.result_overlay.visible, "기록 보기: 결과 판을 닫고 전투 기록을 봄")
	c.leave_combat()
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.HUB, "돌아가기: 경영 화면으로")

	# 승리 후 쓰러진 제자는 문파에서 빠진다
	gm.start_combat(CombatManager.create_night_bandits(gm.player_character, gm.player_sect))
	await process_frame
	await process_frame
	c = current_scene
	var disciples_before: int = gm.player_sect.disciple_count
	c.engine.friends[0].take_damage(99999)
	for foe in c.engine.foes:
		foe.take_damage(foe.hp - 1)
	c.engine.friend_index = 1
	await c.skip_to_result()
	_check(c.engine.outcome == CombatManager.Outcome.VICTORY and gm.player_sect.disciple_count == disciples_before - 1, "승리 후 전사한 제자 1명 반영")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	_completed["_test_duel_screen"] = true


func _unhandled_key(node: Node, keycode: Key) -> void:
	node._unhandled_key_input(_key(keycode))


func _test_combat_rules() -> void:
	var E := MartialArtData.FiveElement
	_check(is_equal_approx(CombatRules.element_modifier(E.WOOD, E.EARTH), _Balance.ELEMENT_ADVANTAGE), "목극토: 우위")
	_check(is_equal_approx(CombatRules.element_modifier(E.EARTH, E.WOOD), _Balance.ELEMENT_DISADVANTAGE), "토는 목에 열세")
	_check(is_equal_approx(CombatRules.element_modifier(E.FIRE, E.NONE), 1.0), "무속성 상대는 보정 없음")
	# 대결에서도 오행: 상대 칸의 초식 속성에 따라
	var wood: DuelCard = _card(DuelCard.Type.STRIKE)
	wood.element = E.WOOD
	var earth: DuelCard = _card(DuelCard.Type.GUARD)
	earth.element = E.EARTH
	_check(_clash(wood, earth)["b"] > _clash(_card(DuelCard.Type.STRIKE), earth)["b"], "대결: 오행 상극이면 피해 증가")
	# 기습: 다치지 않은 상대에게만
	var ambush: DuelCard = _card(DuelCard.Type.QUICK)
	ambush.effects.append("ambush")
	var fresh: Dictionary = _clash(ambush, _card(DuelCard.Type.STRIKE))
	var a: CombatUnit = _duel_unit("갑")
	var b: CombatUnit = _duel_unit("을")
	b.take_damage(1)
	var hurt: Dictionary = DuelRules.resolve_slot(0, a, ambush, b, _card(DuelCard.Type.STRIKE), "clear")
	_check(absf(fresh["b"] - hurt["damage"]["b"] * _Balance.AMBUSH_MULTIPLIER) <= 1.0, "기습은 다치지 않은 상대에게만 1.5배")
	# 인연: 원한은 피해를 키우고, 가호는 받는 피해를 나눈다
	a = _duel_unit("갑")
	b = _duel_unit("을")
	var base: int = DuelRules.resolve_slot(0, a, _card(DuelCard.Type.STRIKE), b, null, "clear")["damage"]["b"]
	a = _duel_unit("갑")
	b = _duel_unit("을")
	b.bond_guard = 1.5
	_check(DuelRules.resolve_slot(0, a, _card(DuelCard.Type.STRIKE), b, null, "clear")["damage"]["b"] == int(base / 1.5), "인연의 가호로 받는 피해 감소")
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
	_check(screen.preset_list.item_count == 2 and screen.preset_list.get_item_text(0).contains("청운검법") and screen.preset_list.get_item_text(0).contains("서고"), "무공 연구소: 비급 목록은 소속 문파 서고의 비급")
	_check(screen.known_arts_label.text.contains("[유혼쾌영검]") and screen.known_arts_label.text.contains("피해") and screen.known_arts_label.text.contains("초식"), "보유 무공 목록: 늘 보이고 전투 수치까지")
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

	# 고르던 설정은 화면을 나갔다 와도 이어지고, 이름을 붙여 저장·불러오기·지우기
	screen.name_input.text = "수류검"
	screen.name_input.text_changed.emit("수류검")
	screen.effect1_option.select(screen.effect1_option.get_item_index(MartialArtData.SpecialEffect.SPEED))
	screen.effect1_option.item_selected.emit(screen.effect1_option.selected)
	_check(gm.art_draft["element"] == MartialArtData.FiveElement.WATER and gm.art_draft["name"] == "수류검", "무공 창조: 고르던 설정 기억")
	_check(gm.art_draft["effects"] == [MartialArtData.SpecialEffect.SPEED], "특수 효과 \"없음\"은 효과로 치지 않음")
	screen._on_save_blueprint_pressed()
	_check(gm.art_blueprints.size() == 1 and gm.art_blueprints[0]["title"] == "수류검", "설정 저장 (이름으로)")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	SceneRouter.goto(tree, SceneRouter.MARTIAL_ART)
	await process_frame
	await process_frame
	screen = current_scene
	_check(screen.element_option.get_selected_id() == MartialArtData.FiveElement.WATER and screen.name_input.text == "수류검" and screen.effect1_option.get_selected_id() == MartialArtData.SpecialEffect.SPEED, "다시 열면 고르던 설정 그대로")
	screen.element_option.select(screen.element_option.get_item_index(MartialArtData.FiveElement.FIRE))
	screen.element_option.item_selected.emit(screen.element_option.selected)
	screen._on_load_blueprint_pressed()
	_check(screen.choice_popup.visible and screen.choice_popup.get_option_count() == 1, "저장한 설정 목록")
	screen.choice_popup._on_option_pressed("0")
	_check(screen.element_option.get_selected_id() == MartialArtData.FiveElement.WATER and screen.log_label.text.contains("불러왔습니다"), "저장한 설정 불러오기")
	gm.save_game(3)
	gm.art_blueprints.clear()
	gm.art_draft = {}
	gm.load_game(3)
	_check(gm.art_blueprints.size() == 1 and gm.art_draft["element"] == MartialArtData.FiveElement.WATER and gm.art_blueprints[0]["effects"] == [MartialArtData.SpecialEffect.SPEED], "무공 창조 설정 저장·불러오기")
	SaveManager.delete_save(3)
	screen._on_delete_blueprint_pressed()
	screen.choice_popup._on_option_pressed("0")
	_check(gm.art_blueprints.is_empty(), "저장한 설정 지우기")
	screen._on_load_blueprint_pressed()
	_check(not screen.choice_popup.visible and screen.log_label.text.contains("없습니다"), "저장한 설정이 없으면 안내")

	# 제자 명단에서 전수
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	var target: DiscipleData = gm.player_sect.disciples[0]
	hub._on_disciple_pressed()
	await process_frame
	# 경지가 모자라면 고를 수 없게 까닭을 보이고, 실패 결과는 팝업 안에 바로 보인다
	var need: int = DiscipleRoster.get_transmit_level(gm.player_character.martial_arts[0])
	if target.level < need:
		hub.disciple_popup._on_transmit_pressed(target.id)
		_check(hub.disciple_popup.art_choice.visible and hub.disciple_popup.art_choice.get_option_count() == 1, "전수: 무공 고르기 팝업 (모자라도 까닭과 함께 보임)")
		hub.disciple_popup.art_choice.visible = false
	hub.disciple_popup._apply(DiscipleRoster.transmit(gm.player_sect, target.id, null))
	var notice: Label = hub.disciple_popup.notice_label
	_check(notice.visible and notice.text.begins_with("할 수 없습니다") and notice.get_theme_color("font_color") == _UiTheme.COLORS["accent_red"], "전수 실패: 팝업 안에 붉은 알림")
	target.gain_experience(_Balance.DISCIPLE_EXP_PER_LEVEL * maxi(1, need))
	hub.disciple_popup._on_transmit_pressed(target.id)
	_check(hub.disciple_popup.art_choice.visible and hub.disciple_popup.art_choice.get_option_count() == 1, "전수: 무공 고르기 팝업")
	hub.disciple_popup.art_choice._on_option_pressed("preset_soul_chase_sword")
	_check(target.martial_art != null and hub.log_label.text.contains("전수"), "제자 명단에서 무공 전수")
	_check(hub.disciple_popup.notice_label.text.contains("전수했습니다"), "전수 성공도 팝업 안에 알림")
	# 일괄 수련: 방식 고르기 팝업에 방식마다 인원·금화가 보이고, 고르면 수련한다
	gm.player_sect.gold = 10000
	hub.disciple_popup.refresh()
	_check(not hub.disciple_popup.batch_button.disabled, "일괄 수련 버튼")
	hub.disciple_popup._on_batch_pressed()
	_check(hub.disciple_popup.batch_choice.visible and hub.disciple_popup.batch_choice.get_option_count() == DiscipleRoster.BATCH_MODES.size(), "일괄 수련: 방식 고르기")
	var preview_setting: bool = GameSettings.action_preview
	GameSettings.action_preview = false
	hub.disciple_popup.batch_choice._on_option_pressed("all")
	GameSettings.action_preview = preview_setting
	_check(hub.disciple_popup.notice_label.text.begins_with("일괄 수련") and hub.disciple_popup.batch_button.disabled, "일괄 수련 실행 뒤 버튼이 잠김 (%s)" % hub.disciple_popup.notice_label.text)
	hub.disciple_popup.visible = false
	hub.event_popup.visible = false
	var tip: String = hub.tips["arts"].provider.call()
	_check(tip.contains("보유 무공") and tip.contains("[유혼쾌영검]") and tip.contains("피해"), "경영 화면: 무공 줄을 길게 누르면 보유 무공 자세히")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_martial_art_screen_actions"] = true


## 회심: 켜면 신법에 따라 회심이 나고, 끄면 피해가 일정하다.
func _test_damage_randomness() -> void:
	var T := DuelCard.Type
	var attacker: CombatUnit = _duel_unit("갑", 15)
	var defender: CombatUnit = _duel_unit("을")
	var card: DuelCard = _card(T.STRIKE)
	var base: int = DuelRules._hit(attacker, card, defender, null, "clear")["damage"]
	CombatRules.randomness = true
	seed(12345)
	var crits: int = 0
	var exact: bool = true
	var rolls: int = 1000
	for i in rolls:
		var result: Dictionary = DuelRules._hit(attacker, card, defender, null, "clear")
		if "회심" in result["note"]:
			crits += 1
			exact = exact and absi(result["damage"] - int(base * _Balance.CRIT_MULTIPLIER)) <= 1
		else:
			exact = exact and result["damage"] == base
	CombatRules.randomness = false
	randomize()
	_check(exact, "회심이 아니면 피해가 일정하고, 회심은 %.1f배" % _Balance.CRIT_MULTIPLIER)
	var expected: float = CombatRules.crit_chance(attacker)
	_check(absf(float(crits) / rolls - expected) < 0.03, "회심 확률이 신법에 맞음 (%.1f%%, 기대 %.1f%%)" % [100.0 * crits / rolls, expected * 100])
	attacker.character.agility = 100
	_check(is_equal_approx(CombatRules.crit_chance(attacker), _Balance.CRIT_MAX), "회심 확률 상한")
	_check(DuelRules._hit(attacker, card, defender, null, "clear")["damage"] == base, "끄면 피해가 일정")
	_completed["_test_damage_randomness"] = true


func _test_combat_variety() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "leader")
	# 전장 생성: 유닛 자리는 비우고, 모양마다 지형이 다르며, 같은 씨앗이면 같은 전장
	var keep: Array[Vector2i] = [Vector2i(2, 5), Vector2i(13, 5)]
	var shapes: Dictionary = {}
	for kind in Battlefield.KINDS:
		var setup := CombatSetup.new()
		Battlefield.generate(setup, kind, keep, 7)
		var clear: bool = not setup.blocked_tiles.has(Vector2i(2, 5)) and not setup.blocked_tiles.has(Vector2i(13, 5))
		_check(clear and setup.battlefield == kind and (not setup.terrain.is_empty() or not setup.blocked_tiles.is_empty()), "전장 생성: %s" % kind)
		shapes[str(setup.terrain) + str(setup.blocked_tiles)] = true
	_check(shapes.size() == Battlefield.KINDS.size(), "전장 생성: 모양마다 다름")
	var a := CombatSetup.new()
	var b := CombatSetup.new()
	Battlefield.generate(a, "forest", keep, 11)
	Battlefield.generate(b, "forest", keep, 11)
	_check(a.terrain == b.terrain and a.blocked_tiles == b.blocked_tiles, "전장 생성: 같은 씨앗이면 같은 전장")
	_check(Battlefield.kind_for_region("tianshan") == "snow" and Battlefield.kind_for_region("hangzhou") == "river", "지역에 맞는 전장")

	# 데이터 전투의 목표·날씨·증원: 혈월의 밤은 밤에 4라운드를 버티는 싸움
	ScenarioManager.activate("saga_1_blood_moon")
	var night: CombatSetup = CombatLibrary.create("s1_blood_night_gate", gm.player_character)
	_check(night.objective == "survive" and night.objective_rounds == 4 and night.weather == "night" and night.reinforcements.size() == 2 and night.battlefield == "town" and not night.blocked_tiles.is_empty(), "데이터 전투: 버티기·밤·증원·전장")
	_check(Battlefield.describe(night).contains("4합 동안 버텨라") and Battlefield.describe(night).contains("밤"), "전투 목표 설명")
	var guard: CombatSetup = CombatLibrary.create("s1_guard_the_master", gm.player_character)
	_check(guard.objective == "protect" and guard.objective_target == "npc_master" and guard.objective_target_name == "청운검선", "데이터 전투: 호위 목표")
	var bad: Dictionary = {"id": "x", "title": "x", "enemies": [{"npc": "npc_bandit", "position": [10, 5]}], "objective": {"type": "defeat_target", "target": "npc_master"}, "weather": "storm"}
	var errors: PackedStringArray = CombatLibrary.validate_combat_dict(bad)
	_check(errors.size() == 2, "전투 데이터 검증: 없는 우두머리·날씨 (%s)" % "; ".join(errors))
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	_new_quiet_game(gm, "leader")

	# 코드 전투도 판마다 다르게 (varied): 지역 전장, 계절 날씨, 증원, 의뢰의 여러 모습
	CombatManager.varied = true
	CombatManager.region_id = "chengdu"
	var bandits: CombatSetup = CombatManager.create_night_bandits(gm.player_character)
	_check(bandits.weather == "night" and bandits.battlefield == "forest" and bandits.reinforcements.size() == 1 and bandits.region_id == "chengdu", "코드 전투: 야습은 밤·지역 전장·증원")
	var objectives: Dictionary = {}
	for i in 30:
		objectives[CombatManager.create_bandit_hunt(gm.player_character).objective] = true
	_check(objectives.size() >= 2, "코드 전투: 토벌 의뢰의 여러 목표 (%s)" % [objectives.keys()])
	var hit: CombatSetup = CombatManager.create_assassination(gm.player_character)
	_check(hit.objective == "defeat_target" and hit.weather == "night" and hit.battlefield == "town", "코드 전투: 표적 의뢰는 밤 거리에서 표적만")
	# 형식: 야습은 포위, 표적은 잠입(숨은 순찰), 추격대는 추격·포위, 침공은 진형, 결투는 대치 뒤 연전, 비무는 비무대
	_check(bandits.format == "siege" and bandits.mooks.size() >= 3 and not bandits.challenge.is_empty(), "코드 전투: 야습은 포위, 도적은 졸개, 도전")
	_check(hit.format == "stealth" and hit.hidden_foes.size() == 1 and hit.stage in ["shrine", "rooftop"], "코드 전투: 표적 의뢰는 잠입")
	var hunter_formats: Dictionary = {}
	for i in 20:
		hunter_formats[CombatManager.create_bounty_hunters(gm.player_character).format] = true
	_check(hunter_formats.has("chase") and hunter_formats.has("siege"), "코드 전투: 추격대는 추격 또는 포위")
	var invasion: CombatSetup = CombatManager.create_invasion(gm.get_world_sect("heukpung"), gm.player_character, gm.player_sect)
	_check(invasion.format == "formation" and not invasion.mooks.is_empty(), "코드 전투: 침공은 진형")
	var rival: CombatSetup = CombatManager.create_rival_duel(gm.player_character)
	_check(rival.format == "standoff" and rival.standoff_then == "duel", "코드 전투: 라이벌 결투는 대치 뒤 연전")
	var spar: CombatSetup = CombatManager.create_sparring(gm.player_character)
	_check(spar.stage == "arena" and spar.has_condition("honor"), "코드 전투: 비무는 비무대에서 정정당당")
	var hunt_objectives: Dictionary = {}
	for i in 40:
		hunt_objectives[CombatManager.create_bandit_hunt(gm.player_character).objective] = true
	_check(hunt_objectives.has("capture"), "코드 전투: 토벌 의뢰에 현상수배범 생포")
	CombatManager.varied = false

	# 데이터 전투의 형식 (설계 문서 8절)
	var expected_formats: Dictionary = {
		"arc_love_trial": "standoff", "arc_love_pursuit": "chase", "arc_spy_rescue": "stealth", "arc_revenge_chief": "siege",
		"arc_cheonma_siege": "formation", "martial_tournament": "tournament",
	}
	var wrong: PackedStringArray = []
	for combat_id in expected_formats:
		if CombatLibrary.create(combat_id, gm.player_character).format != expected_formats[combat_id]:
			wrong.append(combat_id)
	_check(wrong.is_empty(), "데이터 전투 형식 (%s)" % ", ".join(wrong))
	var final: CombatSetup = CombatLibrary.create("arc_cheonma_final", gm.player_character)
	_check(final.traits_of("npc_cheonma").has("telegraph") and final.traits_of("npc_cheonma").has("two_phase") and final.events.size() == 2, "천마 결전: 예고 절초·단계 전환·사건")
	var rescue: CombatSetup = CombatLibrary.create("arc_spy_rescue", gm.player_character)
	_check(rescue.hidden_foes.size() == 2, "잠입 전투: 숨은 자")
	var tourney: CombatSetup = CombatLibrary.create("martial_tournament", gm.player_character)
	_check(tourney.enemies.size() == 4 and tourney.placement_flags.has("3") and EventManager.get_event("martial_tournament") != null, "무림대회: 네 판과 성적 플래그, 기연")
	_completed["_test_combat_variety"] = true


## 합 무대 연출: 칸마다 초식 이름·달려들기·피해 숫자를 보여 주고, 끝나면 체력 막대가 실제 체력과 같다
func _test_duel_stage() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	gm.player_character.learn_martial_art(MartialArtLibrary.create_art("preset_soul_chase_sword"))
	GameSettings.combat_effects = true
	gm.start_combat(CombatManager.create_night_bandits(gm.player_character, gm.player_sect))
	await process_frame
	await process_frame
	var c: Node = current_scene
	var stage: DuelStage = c.stage
	_check(c.stage_panel.visible and stage.has_token(c.engine.controlled()) and stage.has_token(c.engine.current_foe()), "합 무대: 겨루는 두 사람의 말")
	_check(not c.friend_portrait.visible, "무대가 있으면 작은 초상화는 접음")
	c.auto_fill()
	var floats_seen: bool = false
	var playing_seen: bool = false
	c.fight()
	for i in 600:
		await process_frame
		if stage.playing:
			playing_seen = true
			# 피해 숫자·초식 이름 같은 떠오르는 글자
			if stage._world.get_children().any(func(n: Node) -> bool: return n is Label):
				floats_seen = true
		if not c._busy:
			break
	_check(playing_seen and not c._busy, "합 무대: 합이 끝날 때까지 연출 (%d칸)" % c.engine.slot_events.size())
	_check(not c.engine.slot_events.is_empty() and c.engine.slot_events[0].has("hp_before") and c.engine.slot_events[0]["cards"].size() >= 2, "합 기록: 칸마다 초식·체력")
	_check(floats_seen, "합 무대: 떠오르는 글자 (피해·초식 이름)")
	var me: CombatUnit = c.engine.controlled()
	if me and stage.has_token(me):
		_check(int(stage._tokens[me]["bar"].value) == me.hp or c.engine.over, "합 무대: 끝나면 체력 막대가 실제 체력 (%d / %d)" % [stage._tokens[me]["bar"].value, me.hp])
	# 결과만 보기는 남은 연출을 기다리지 않는다
	if not c.engine.over:
		c.auto_fill()
		c.fight()
		await process_frame
		var started: int = Time.get_ticks_msec()
		await c.skip_to_result()
		_check(c.engine.over and Time.get_ticks_msec() - started < 3000, "결과만 보기: 연출을 서둘러 끝냄")
	# 설정에서 끄면 무대가 없다
	GameSettings.combat_effects = false
	c._refresh()
	_check(not c.stage_panel.visible and c.friend_portrait.visible, "전투 연출을 끄면 무대 없음")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_duel_stage"] = true
