class_name DuelEngine
extends RefCounted

## 초식 배치 대결 한 판. 화면과 분리되어 있어 테스트와 밸런스 시뮬레이터가 그대로 쓴다.
## 형식(docs/전투_다양화_설계.md):
##   duel 연전(양쪽 줄에서 한 사람씩 1대1) · siege 포위(적 여럿이 한꺼번에) · formation 진형(앞·뒷줄, 여럿 대 여럿) ·
##   chase 추격(거리 게이지) · stealth 잠입(발각 게이지·기습) · standoff 대치(피해 없는 기세 싸움) · tournament 비무대회(연속 1대1)
##
## 흐름: prepare_bout()로 상대(와 동료)가 배치를 정하고, 플레이어 배치로 run_bout()을 부르면 칸마다 판정한다.
## 사건이 선택을 요구하면 pending_choice가 차고, choose()로 고를 때까지 다음 합으로 가지 않는다.
## 목표: defeat_all · defeat_target(1대1이면 우두머리와 바로 겨룸, 호위 하나마다 우두머리 체력 +15%) · survive · escape ·
##       protect(지킬 인물은 줄 밖) · capture(생포) · catch(쫓아 붙잡기) · timed(시간 안에) · endure(버텨 내기) ·
##       disarm(절초 무산) · hold_line(진지 사수)

const _Balance = preload("res://scripts/Systems/game_balance.gd")

const MAX_BOUTS := _Balance.DUEL_MAX_BOUTS
const ESCAPE_EVADES := _Balance.DUEL_ESCAPE_EVADES
const GUARD_HP_BONUS := _Balance.DUEL_GUARD_HP_BONUS
## 상대 AI가 지난 합을 읽어 맞받아치는 확률
const ENEMY_COUNTER_RATE := _Balance.DUEL_ENEMY_COUNTER_RATE
const PLAYER_AUTO_COUNTER_RATE := _Balance.DUEL_PLAYER_AUTO_COUNTER_RATE
const SAFETY_BOUTS := 80
## 동료(제자·인물)는 합이 끝났을 때 체력이 이 비율 아래면 부상으로 물러난다 (쓰러지지 않으면 문파 손실 없음)
const ALLY_RETREAT_RATIO := _Balance.DUEL_ALLY_RETREAT_RATIO
const WARD_HIT := _Balance.DUEL_WARD_HIT
const CAPTURE_RATIO := _Balance.CAPTURE_RATIO
## 합격을 펼칠 만큼 깊은 인연
const COMBO_BOND := _Balance.DUEL_COMBO_BOND
## 한 사람씩 맞서는 형식 (나머지는 여럿이 한꺼번에)
const SINGLE_FORMATS: PackedStringArray = ["duel", "chase", "stealth", "standoff", "tournament"]

var setup: CombatSetup
var format: String = "duel"
var weather: String = "clear"
## 판정 맥락 (DuelRules.make_context): 날씨·전장·형식·조건·기습·생포 대상·중독
var ctx: Dictionary = {}
var friends: Array[CombatUnit] = []
var foes: Array[CombatUnit] = []
## 물러난 사람 (체력 비율·부상·장외·다리에서 떨어짐 — 쓰러지지는 않음)
var retired: Dictionary = {}
## 줄에서 지금 나서 있는 첫 사람의 자리
var friend_index: int = 0
var foe_index: int = 0
var bout_total: int = 0
var bout_in_duel: int = 0
var max_bouts: int = MAX_BOUTS
var evades: int = 0
var over: bool = false
var outcome: CombatManager.Outcome = CombatManager.Outcome.RETREAT
var history: PackedStringArray = []
## 이번 합의 맞선 상대 배치 (prepare_bout에서 정함). 여럿이 나서면 나머지는 plans에
var enemy_plan: Array[DuelCard] = []
## 이번 합의 다른 사람들 배치 {unit: Array[DuelCard]}와 대상 {unit: CombatUnit}
var plans: Dictionary = {}
var unit_targets: Dictionary = {}
## 플레이어가 칸마다 고른 상대 (포위·진형)
var player_targets: Array = []
## 지난 합에 낸 유형: {"friend": [...], "foe": [...]} (맞선 두 사람)
var last_types: Dictionary = {"friend": [], "foe": []}
## 상대의 버릇 기록 {인물 id: {bouts, first: {유형: 횟수}}} (GameManager.duel_memory)
var memory: Dictionary = {}
## 초식 숙련 {무공 id: 쓴 횟수} (GameManager.art_mastery)
var mastery: Dictionary = {}
var rng := RandomNumberGenerator.new()
## 우두머리 목표의 호위 (1대1 형식에서 우두머리에게 체력만 보태고 겨루지 않는다)
var guards: Array[CombatUnit] = []
## 호위 목표의 지킬 인물 (줄에 서지 않는다)
var ward: CombatUnit = null
## 주인공의 인연 (원한·가호·합격·인연의 개입·배신)
var bonds: Array[RelationshipData] = []

## 추격: 거리 (0 붙잡힘 · CHASE_END 놓침). 잠입: 발각 게이지와 경보
var distance: int = _Balance.CHASE_START
var detection: int = 0
var alarm: bool = false
## 비무대회: 이긴 판 수
var tournament_round: int = 0
## 사건: 일어난 사건 번호, 고르기를 기다리는 선택 {title, lines, options: [{id, label, description}], event}, 이번 합의 사건 대사
var fired_events: Dictionary = {}
var pending_choice: Dictionary = {}
var event_lines: PackedStringArray = []
## 사건 선택지의 효과 (전투가 끝나면 GameManager가 기연 효과처럼 반영)
var choice_effects: Array = []
## 예고 절초: 마지막 칸에 나올 초식 {unit: {card, bout(나올 합 번호)}}
var telegraphs: Dictionary = {}
## 호위 목표: 이미 지킬 인물을 다치게 한 패배 (한 사람이 진 것은 한 번만 센다)
var ward_counted: Dictionary = {}
## 평가·도전용 기록: 주인공이 받은 피해, 쓴 유형, 빈틈을 냈는지, 무산시킨 절초 수, 받아 낸 상대 무공 id
var hero_damage_taken: int = 0
var used_types: Dictionary = {}
var left_gap: bool = false
var nullified: int = 0
var studied_arts: Array = []
var captured: bool = false


func _init(combat_setup: CombatSetup, player: CharacterData, duel_memory: Dictionary = {}, art_mastery: Dictionary = {}, relationships: Array[RelationshipData] = []) -> void:
	setup = combat_setup
	format = setup.format if Battlefield.FORMATS.has(setup.format) else "duel"
	weather = setup.weather
	bonds = relationships
	memory = duel_memory
	mastery = art_mastery
	max_bouts = setup.max_bouts if setup.max_bouts > 0 else MAX_BOUTS
	rng.randomize()
	var hero := CombatUnit.new(player, true)
	hero.cards = _hero_cards(player)
	_apply_hero_conditions(hero)
	# 기본 줄: 아군이 앞, 주인공이 대장. 비무대회는 혼자 나선다
	if format != "tournament":
		for ally in setup.allies:
			var unit := CombatUnit.new(ally, false, true)
			unit.cards = DuelCard.cards_for(ally)
			_apply_unit_setup(unit)
			if setup.objective == "protect" and ally.id == setup.objective_target:
				ward = unit
			else:
				friends.append(unit)
	# 주인공이 직접 해내야 하는 목표·형식은 선봉으로 나선다
	if setup.objective in ["escape", "survive", "endure", "disarm", "capture", "catch"] or format in ["siege", "formation", "chase", "stealth", "standoff"]:
		friends.push_front(hero)
	else:
		friends.append(hero)
	var strength: float = ScenarioRules.enemy_strength_scale()
	var enemy_units: Array[CombatUnit] = []
	for enemy in setup.enemies:
		enemy_units.append(_make_foe(enemy, strength))
	for entry in setup.reinforcements:
		enemy_units.append(_make_foe(entry["character"], strength))
	if setup.objective == "defeat_target" and format in ["duel", "stealth"]:
		for unit in enemy_units:
			if unit.character.id == setup.objective_target:
				foes.append(unit)
			else:
				guards.append(unit)
		if foes.is_empty():
			foes = enemy_units
			guards.clear()
		else:
			var boss: CombatUnit = foes[0]
			boss.max_hp = int(boss.max_hp * (1.0 + GUARD_HP_BONUS * guards.size()))
			boss.hp = boss.max_hp
	else:
		foes = enemy_units
	ctx = {
		"weather": weather, "stage": setup.stage, "format": format, "conditions": setup.conditions,
		"ambush_side": -1, "capture": null, "poisoned": [hero] if setup.has_condition("poisoned") else [],
	}
	if setup.objective == "capture":
		for unit in foes:
			if unit.character.id == setup.objective_target:
				ctx["capture"] = unit
	if format == "standoff" and player.charisma >= _Balance.STANDOFF_PRESENCE_CHARISMA:
		hero.momentum = 1
	history.append("── %s ──" % setup.title)
	history.append(Battlefield.describe(setup))
	if ward:
		history.append("%s은(는) 싸우지 않습니다. 우리 쪽이 대결에서 질 때마다 적이 뚫고 들어와 다칩니다." % ward.display_name)
	if not guards.is_empty():
		history.append("호위 %d명이 우두머리를 지킵니다 (우두머리 체력 +%d%%). 우두머리만 쓰러뜨리면 이깁니다." % [guards.size(), int(GUARD_HP_BONUS * 100 * guards.size())])
	if format == "tournament":
		_preview(current_foe())
	_refresh_rows()
	_announce_pair()


## 주인공의 초식: 맨손이면 검법을 빼고, 여럿과 싸우면 휩쓸기를 더한다
func _hero_cards(player: CharacterData) -> Array[DuelCard]:
	var cards: Array[DuelCard] = DuelCard.cards_for(player, mastery)
	if setup.has_condition("unarmed"):
		var swords: Array = player.martial_arts.filter(func(a: MartialArtData) -> bool: return a.category == MartialArtData.Category.SWORD).map(func(a: MartialArtData) -> String: return a.id)
		cards = cards.filter(func(c: DuelCard) -> bool: return not c.art_id in swords)
	if format in ["siege", "formation"]:
		cards.append(DuelCard.sweep_card())
	return cards


func _apply_hero_conditions(hero: CombatUnit) -> void:
	if setup.has_condition("wounded"):
		hero.hp = maxi(1, int(hero.max_hp * _Balance.WOUNDED_HP))
		hero.slot_bonus -= 1
	if setup.has_condition("exhausted"):
		var cap: int = int(hero.character.internal_energy_max * _Balance.EXHAUSTED_ENERGY)
		hero.character.internal_energy_current = mini(hero.character.internal_energy_current, cap)


## 전투 데이터의 특성·지시·졸개를 인물에게 붙인다
func _apply_unit_setup(unit: CombatUnit) -> void:
	var id: String = unit.character.id
	unit.traits = setup.traits_of(id)
	unit.order = str(setup.orders.get(id, "attack"))
	if setup.mooks.has(id) and format in ["siege", "formation"] and not unit.is_ally:
		unit.slot_cap = _Balance.MOOK_SLOTS
		unit.max_hp = maxi(1, int(unit.max_hp * _Balance.MOOK_HP))
		unit.hp = unit.max_hp
		unit.damage_scale *= _Balance.MOOK_DAMAGE


func _make_foe(character: CharacterData, strength: float) -> CombatUnit:
	var unit := CombatUnit.new(character, false)
	unit.scale_stats(setup.enemy_hp_scale * strength, setup.enemy_damage_scale * strength)
	unit.cards = DuelCard.cards_for(character)
	_apply_unit_setup(unit)
	return unit


func get_player() -> CombatUnit:
	for unit in friends:
		if unit.is_player:
			return unit
	return friends[-1]


func current_friend() -> CombatUnit:
	return friends[friend_index] if friend_index < friends.size() else null


func current_foe() -> CombatUnit:
	return foes[foe_index] if foe_index < foes.size() else null


func is_single() -> bool:
	return format in SINGLE_FORMATS


## 서 있는(쓰러지거나 물러나지 않은) 사람인지
func is_standing(unit: CombatUnit) -> bool:
	return unit != null and unit.is_alive() and not retired.has(unit)


## 지금 나서 있는 우리 쪽·상대 쪽 (1대1 형식은 한 사람씩, 포위·진형은 여럿)
func active_friends() -> Array[CombatUnit]:
	return _active(friends, friend_index, 1 if is_single() else (_Balance.SIEGE_FRIENDS if format == "siege" else _Balance.FORMATION_SIZE))


func active_foes() -> Array[CombatUnit]:
	var count: int = 1
	if format == "siege":
		count = 2 if setup.stage == "alley" else _Balance.SIEGE_FOES
	elif format == "formation":
		count = _Balance.FORMATION_SIZE
	return _active(foes, foe_index, count)


func _active(line: Array[CombatUnit], start: int, count: int) -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for i in range(start, line.size()):
		if result.size() >= count:
			break
		if is_standing(line[i]) or (count == 1 and i == start):
			result.append(line[i])
	return result


## 플레이어가 배치하는 사람: 여럿이 나서는 형식이면 주인공(나서 있으면), 1대1이면 맞선 사람
func controlled() -> CombatUnit:
	if not is_single():
		var hero: CombatUnit = get_player()
		if hero in active_friends():
			return hero
		var actives: Array[CombatUnit] = active_friends()
		return actives[0] if not actives.is_empty() else null
	return current_friend()


## 주인공이 선봉으로 나설지(true), 대장으로 뒤에 설지(false). 첫 합 전에만 바꿀 수 있다.
func set_player_first(first: bool) -> void:
	if bout_total > 0 or friends.size() < 2:
		return
	var hero: CombatUnit = get_player()
	friends.erase(hero)
	if first:
		friends.push_front(hero)
	else:
		friends.append(hero)
	_refresh_rows()
	_announce_pair()


## 동료 지시 바꾸기 (포위·진형)
func set_order(unit: CombatUnit, order: String) -> void:
	if DuelAI.ORDERS.has(order) and unit in friends and not unit.is_player:
		unit.order = order


## 진형의 앞·뒷줄: 데이터에 정한 줄을 따르고, 나머지는 나선 순서대로 앞 FORMATION_FRONT명. 앞줄이 다 쓰러지면 모두 앞줄
func _refresh_rows() -> void:
	for pair in [[active_friends(), friends], [active_foes(), foes]]:
		var actives: Array = pair[0]
		for unit in pair[1]:
			unit.front = true
		if format != "formation":
			continue
		var fronts: int = 0
		for unit in actives:
			var row: String = str(setup.rows.get(unit.character.id, ""))
			if row.is_empty():
				row = "front" if fronts < _Balance.FORMATION_FRONT else "back"
			unit.front = row == "front"
			if unit.front:
				fronts += 1
		if not actives.any(func(u: CombatUnit) -> bool: return u.front and is_standing(u)):
			for unit in actives:
				unit.front = true


func _announce_pair() -> void:
	if current_friend() and current_foe():
		_apply_bonds()
		if is_single():
			history.append("▶ %s 대 %s" % [current_friend().display_name, current_foe().display_name])
		else:
			history.append("▶ %s 대 %s" % [_names(active_friends()), _names(active_foes())])


func _names(units: Array[CombatUnit]) -> String:
	return "·".join(units.map(func(u: CombatUnit) -> String: return u.display_name + ("" if u.front or format != "formation" else "(뒷줄)")))


## 지금 겨루는 사람들에게 인연을 적용한다.
## - 주인공이 인연 있는 상대(원한·연적 등)와 겨루면 그 인연만큼 피해가 달라진다.
## - 맞는 쪽 가호: 인연 있는 동료는 그 인연만큼, 주인공은 줄에 함께 선 가장 깊은 인연만큼 피해를 덜 받는다.
## - 합격: 주인공 줄에 아직 서 있는 깊은 인연의 동료마다 합격 초식이 손패에 든다.
func _apply_bonds() -> void:
	var foe: CombatUnit = current_foe()
	for friend in friends:
		if friend.is_player:
			friend.bond_attack = RelationshipManager.get_combat_damage_bonus(bonds, foe.character.id) if foe else 1.0
			friend.bond_guard = RelationshipManager.get_defense_modifier(bonds, _standing_partners().map(func(u: CombatUnit) -> String: return u.character.id))
			friend.cards = friend.cards.filter(func(c: DuelCard) -> bool: return not c.effects.has("combo"))
			for partner in _standing_partners():
				var rel: RelationshipData = RelationshipManager.get_bond_with(bonds, partner.character.id)
				if rel and rel.bond_strength >= COMBO_BOND and rel.get_combat_defense_modifier() > 1.0:
					friend.cards.append(DuelCard.combo(partner.character))
		else:
			friend.bond_attack = 1.0
			friend.bond_guard = RelationshipManager.get_defense_modifier(bonds, [friend.character.id])


## 주인공 줄에서 아직 서 있는(쓰러지거나 물러나지 않은) 동료
func _standing_partners() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in friends:
		if unit.is_ally and is_standing(unit):
			result.append(unit)
	return result


# ── 배치 ──

## 이번 합의 상대(와 동료) 배치를 정한다. 상대는 우리 쪽이 지난 합에 낸 유형을 읽는다.
func prepare_bout() -> void:
	if over or not pending_choice.is_empty() or current_foe() == null:
		return
	_refresh_rows()
	plans.clear()
	unit_targets.clear()
	var hero_last: Array = last_types["friend"]
	var counter_rate: float = ENEMY_COUNTER_RATE + _Balance.TOURNEY_READ_STEP * tournament_round
	if setup.stage == "shrine" and bout_total == 0:
		counter_rate = 0.0
	var options: Dictionary = {"ctx": ctx}
	if format == "stealth" and bout_total == 0 and not alarm:
		# 경계 전: 막기·운기뿐
		options["allowed"] = [DuelCard.Type.GUARD, DuelCard.Type.FOCUS]
	for foe in active_foes():
		var foe_options: Dictionary = options.duplicate()
		foe_options["style"] = DuelAI.style_of(foe.character)
		if foe.has_trait("mirror"):
			foe_options["mirror"] = hero_last
		var plan: Array[DuelCard] = DuelAI.plan(foe, hero_last, _traits_of(foe), counter_rate, rng, foe_options)
		if telegraphs.has(foe) and int(telegraphs[foe]["bout"]) == bout_total + 1 and not plan.is_empty():
			plan[-1] = telegraphs[foe]["card"]
		if foe == current_foe():
			enemy_plan = plan
		else:
			plans[foe] = plan
		unit_targets[foe] = DuelAI.choose_target(foe, null, active_friends(), rng, format == "formation")
	# 예고 절초: 다음 합 마지막 칸을 미리 알린다
	for foe in active_foes():
		var due: int = bout_total + 2
		if foe.has_trait("telegraph") and (_bouts_with(foe) + 2) % _Balance.TELEGRAPH_EVERY == 0 and not (telegraphs.has(foe) and int(telegraphs[foe]["bout"]) == due):
			var card: DuelCard = _telegraph_card(foe)
			telegraphs[foe] = {"card": card, "bout": due}
			history.append("※ %s이(가) 기를 모은다 — 다음 합 마지막 칸에 「%s」!" % [foe.display_name, card.display_name])
	for ally in active_friends():
		if ally == controlled():
			continue
		plans[ally] = DuelAI.plan(ally, last_types["foe"], {}, PLAYER_AUTO_COUNTER_RATE, rng, {"ctx": ctx, "style": DuelAI.style_of(ally.character)})
		unit_targets[ally] = DuelAI.choose_target(ally, null, active_foes(), rng, format == "formation")
	var me: CombatUnit = controlled()
	player_targets.clear()
	if me:
		var default_target: CombatUnit = DuelAI.choose_target(me, null, active_foes(), rng, format == "formation") if not is_single() else current_foe()
		for i in me.slot_count():
			player_targets.append(default_target)


func _bouts_with(foe: CombatUnit) -> int:
	return bout_in_duel if is_single() else bout_total


## 예고 절초: 그 사람의 가장 센 공격 초식을 기세 없이, 위력을 높여서
func _telegraph_card(foe: CombatUnit) -> DuelCard:
	var best: DuelCard = null
	for card in foe.cards:
		if card.is_offensive() and (best == null or card.power > best.power):
			best = card
	var effects: Array[String] = ["telegraph", "pierce"]
	var name: String = best.display_name if best and not best.art_id.is_empty() else "필살의 일격"
	return DuelCard.make("telegraph_" + foe.character.id, name, DuelCard.Type.STRIKE, int((best.power if best else 30) * _Balance.TELEGRAPH_POWER), 0, effects)


func _traits_of(unit: CombatUnit) -> Dictionary:
	var id: String = _npc_id(unit)
	return NpcAgent.get_traits(id) if NpcRoster.has_npc(id) else {}


## 플레이어가 칸의 상대를 고른다 (포위·진형)
func set_target(slot: int, target: CombatUnit) -> void:
	if slot >= 0 and target in active_foes():
		while player_targets.size() <= slot:
			player_targets.append(target)
		player_targets[slot] = target


func target_of(slot: int) -> CombatUnit:
	if slot < player_targets.size() and player_targets[slot] != null and is_standing(player_targets[slot]):
		return player_targets[slot]
	var actives: Array[CombatUnit] = active_foes()
	return actives[0] if not actives.is_empty() else null


func plan_of(unit: CombatUnit) -> Array:
	if unit == current_foe():
		return enemy_plan
	return plans.get(unit, [])


# ── 정보 ──

## 지혜에 따라 상대 배치가 얼마나 보이는지: 0 없음, 1 첫 칸 유형, 2 모든 칸 유형, 3 모든 칸 초식 (안개·대숲은 한 단계 덜, 사당의 첫 합은 안 보임)
func reveal_level() -> int:
	var viewer: CombatUnit = controlled()
	var wisdom: int = viewer.character.wisdom if viewer else 0
	var level: int = 0 if wisdom < 13 else (1 if wisdom < 19 else (2 if wisdom < 25 else 3))
	if weather == "fog":
		level -= 1
	if setup.stage == "bamboo":
		level -= 1
	if setup.stage == "shrine" and bout_total == 0:
		level = 0
	return clampi(level, 0, 3)


## 칸마다 보이는 상대 배치: "?" · 유형 · 초식 이름. 예고 절초는 늘 보인다
func revealed_plan(unit: CombatUnit = null) -> PackedStringArray:
	if unit == null:
		unit = current_foe()
	var plan: Array = plan_of(unit)
	var level: int = reveal_level()
	var result: PackedStringArray = []
	for i in plan.size():
		var card: DuelCard = plan[i]
		if level >= 3 or card.effects.has("telegraph"):
			result.append("%s·%s" % [card.display_name, card.get_type_name()])
		elif level >= 2 or (level == 1 and i == 0):
			result.append(card.get_type_name())
		else:
			result.append("?")
	return result


## 보이는 상대 유형 (칸마다 int, 안 보이면 -1): 사전 점검용. 칸마다 고른 상대의 배치를 본다
func visible_enemy_types() -> Array:
	var level: int = reveal_level()
	var result: Array = []
	var me: CombatUnit = controlled()
	var slots: int = me.slot_count() if me else enemy_plan.size()
	for i in slots:
		var foe: CombatUnit = target_of(i) if not is_single() else current_foe()
		var plan: Array = plan_of(foe) if foe else []
		if i >= plan.size():
			result.append(-1)
			continue
		var card: DuelCard = plan[i]
		result.append(int(card.type) if level >= 2 or (level == 1 and i == 0) or card.effects.has("telegraph") else -1)
	return result


## 상대의 버릇 (전에 겨뤄 본 인물만): "첫 칸에 강공을 자주 냄 (3합 중 2번)"
func habit_text(unit: CombatUnit = null) -> String:
	if unit == null:
		unit = current_foe()
	if unit == null:
		return ""
	var record: Dictionary = memory.get(_npc_id(unit), {})
	if record.is_empty():
		return ""
	var first: Dictionary = record.get("first", {})
	var best: int = -1
	for type in first:
		if best < 0 or first[type] > first[best]:
			best = int(type)
	if best < 0:
		return ""
	return "첫 칸에 %s을(를) 자주 냄 (%d합 중 %d번)" % [DuelCard.TYPE_NAMES[best], int(record.get("bouts", 0)), int(first[best])]


## 비무대회의 관전: 다음 상대가 앞 경기에서 낸 수를 버릇으로 남긴다
func _preview(foe: CombatUnit) -> void:
	if foe == null:
		return
	var watch := RandomNumberGenerator.new()
	watch.seed = rng.randi()
	for i in 3:
		var plan: Array[DuelCard] = DuelAI.plan(foe, [], _traits_of(foe), 0.0, watch, {"style": DuelAI.style_of(foe.character)})
		_remember(foe, plan.map(func(c: DuelCard) -> int: return int(c.type)))
	history.append("관전: %s의 지난 경기 — %s" % [foe.display_name, habit_text(foe)])


static func _npc_id(unit: CombatUnit) -> String:
	# 같은 졸개가 여럿이면 id 뒤에 _번호가 붙는다
	var id: String = unit.character.id
	if NpcRoster.has_npc(id):
		return id
	var cut: int = id.rfind("_")
	return id.left(cut) if cut > 0 and NpcRoster.has_npc(id.left(cut)) else id


# ── 교전 ──

## 한 합: 플레이어 배치(빈 칸은 null 또는 짧은 배열)와 상대 배치로 칸마다 판정한다. 기록 줄을 돌려준다.
func run_bout(player_plan: Array) -> PackedStringArray:
	var lines: PackedStringArray = []
	if over or not pending_choice.is_empty():
		return lines
	if enemy_plan.is_empty():
		prepare_bout()
	event_lines.clear()
	var me: CombatUnit = controlled()
	var foe: CombatUnit = current_foe()
	bout_total += 1
	bout_in_duel += 1
	if is_single():
		lines.append("── %d합 — %s 대 %s ──" % [bout_total, me.display_name, foe.display_name])
	else:
		lines.append("── %d합 — %s 대 %s ──" % [bout_total, _names(active_friends()), _names(active_foes())])
	if setup.has_condition("poisoned") and get_player() in active_friends():
		var hero: CombatUnit = get_player()
		hero.character.internal_energy_current = maxi(0, hero.character.internal_energy_current - _Balance.POISON_DRAIN)
		lines.append("   독이 돈다 — %s 내공 -%d" % [hero.display_name, _Balance.POISON_DRAIN])
	ctx["ambush_side"] = 0 if format == "stealth" and bout_total == 1 and not alarm else -1
	if format == "standoff":
		_run_standoff(player_plan, me, foe, lines)
	else:
		_run_fight(player_plan, me, lines)
	enemy_plan.clear()
	plans.clear()
	for unit in telegraphs.keys():
		if int(telegraphs[unit]["bout"]) <= bout_total:
			telegraphs.erase(unit)
	if not over:
		_end_of_bout(lines)
		_after_bout(lines)
	if not over:
		_check_events(lines)
	history.append_array(lines)
	return lines


func _run_fight(player_plan: Array, me: CombatUnit, lines: PackedStringArray) -> void:
	var friends_now: Array[CombatUnit] = active_friends()
	var foes_now: Array[CombatUnit] = active_foes()
	var slots: int = player_plan.size()
	for unit in foes_now + friends_now:
		slots = maxi(slots, plan_of(unit).size())
	var my_types: Array = []
	var foe_types: Array = []
	for i in slots:
		var actions: Array = []
		for unit in friends_now:
			if not is_standing(unit):
				continue
			if unit == me:
				var card: DuelCard = player_plan[i] if i < player_plan.size() else null
				actions.append({"unit": unit, "card": card, "target": target_of(i) if not is_single() else current_foe(), "side": 0, "absent": i >= unit.slot_count()})
			else:
				var plan: Array = plan_of(unit)
				actions.append({"unit": unit, "card": plan[i] if i < plan.size() else null, "target": unit_targets.get(unit), "side": 0, "absent": i >= plan.size()})
		for unit in foes_now:
			if not is_standing(unit):
				continue
			var plan: Array = plan_of(unit)
			var target: CombatUnit = me if is_single() else unit_targets.get(unit)
			actions.append({"unit": unit, "card": plan[i] if i < plan.size() else null, "target": target, "side": 1, "absent": i >= plan.size()})
		var friend_count: int = actions.filter(func(a: Dictionary) -> bool: return a["side"] == 0).size()
		if friend_count == 0 or friend_count == actions.size():
			break
		var result: Dictionary = DuelRules.resolve_multi(i, actions, ctx)
		lines.append_array(result["lines"])
		var my_card: DuelCard = player_plan[i] if i < player_plan.size() else null
		my_types.append(int(my_card.type) if my_card else -1)
		var foe_card: DuelCard = enemy_plan[i] if i < enemy_plan.size() else null
		foe_types.append(int(foe_card.type) if foe_card else -1)
		_record_slot(i, me, my_card, result, lines)
		for unit in friends_now + foes_now:
			_tick_slot_statuses(unit)
		if over or captured or not is_standing(me) or not foes_now.any(func(u: CombatUnit) -> bool: return is_standing(u)):
			break
		if is_single() and not is_standing(current_foe()):
			break
	last_types = {"friend": my_types, "foe": foe_types}
	for unit in foes_now:
		if unit == current_foe():
			_remember(unit, foe_types)
		else:
			_remember(unit, plan_of(unit).map(func(c: DuelCard) -> int: return int(c.type)))


## 한 칸의 결과를 목표·게이지·기록에 반영한다
func _record_slot(slot: int, me: CombatUnit, my_card: DuelCard, result: Dictionary, lines: PackedStringArray) -> void:
	var hero: CombatUnit = get_player()
	hero_damage_taken += int(result["taken"].get(hero, 0))
	if me == hero:
		if (my_card == null and slot < me.slot_count()) or (my_card != null and result["cards"].get(hero) == null):
			left_gap = true
		elif my_card:
			used_types[int(my_card.type)] = true
		var executed: DuelCard = result["cards"].get(hero)
		if executed and not executed.art_id.is_empty():
			mastery[executed.art_id] = int(mastery.get(executed.art_id, 0)) + 1
	if setup.objective == "escape" and format != "chase" and me.is_player:
		evades += int(result["evaded_by"].get(me, 0))
	if result["captured"]:
		captured = true
	for unit in result["fallen_off"]:
		retired[unit] = true
	# 상대 절초를 회피·상성으로 무산시키면 무공을 배우고, 무기 떨구기 목표에 센다
	for hit in result["applied"]:
		if hit["nullified"] and hit["to"].is_player and not hit["from"].is_ally and not hit["from"].is_player:
			nullified += 1
			var art_id: String = hit["card"].art_id
			if not art_id.is_empty() and not art_id in studied_arts:
				studied_arts.append(art_id)
			lines.append("   %s의 절초 「%s」을(를) 받아 냈다 (%d)" % [hit["from"].display_name, hit["card"].display_name, nullified])
	match format:
		"stealth":
			_update_detection(hero, result, lines)
		"chase":
			_update_distance(hero, result, lines)


## 잠입: 강공은 소리가 나고, 막기에 막혀도 들킨다
func _update_detection(hero: CombatUnit, result: Dictionary, lines: PackedStringArray) -> void:
	if alarm:
		return
	var executed: DuelCard = result["cards"].get(hero)
	var before: int = detection
	if executed and executed.type == DuelCard.Type.STRIKE:
		detection += 1
	for hit in result["applied"]:
		if hit["from"] == hero and hit["defense"] and hit["defense"].type == DuelCard.Type.GUARD:
			detection += 1
	if detection > before:
		lines.append("   발각 %d/%d" % [mini(detection, _Balance.STEALTH_ALARM), _Balance.STEALTH_ALARM])
	if detection >= _Balance.STEALTH_ALARM:
		_raise_alarm(lines)


func _raise_alarm(lines: PackedStringArray) -> void:
	alarm = true
	lines.append("   경보가 울린다! 숨어 있던 자들이 뛰쳐나온다")
	var strength: float = ScenarioRules.enemy_strength_scale()
	var index: int = foe_index + 1
	for character in setup.hidden_foes:
		foes.insert(mini(index, foes.size()), _make_foe(character, strength))
		index += 1
	for foe in foes:
		foe.momentum = mini(DuelRules.MAX_MOMENTUM, foe.momentum + 1)


## 추격: 쫓기는 쪽이 회피·속공으로 이기면 멀어지고, 쫓는 쪽이 강공·술로 맞히면 가까워진다
func _update_distance(hero: CombatUnit, result: Dictionary, lines: PackedStringArray) -> void:
	var runner: CombatUnit = hero if setup.objective != "catch" else current_foe()
	if runner == null:
		return
	var hunter_side: Array = result["cards"].keys().filter(func(u: CombatUnit) -> bool: return u != runner)
	var change: int = 0
	var run_card: DuelCard = result["cards"].get(runner)
	if int(result["evaded_by"].get(runner, 0)) > 0 or (run_card and run_card.type == DuelCard.Type.QUICK and int(result["dealt"].get(runner, 0)) > int(result["taken"].get(runner, 0))):
		change += _Balance.CHASE_RUNNER_WIN
	for hit in result["applied"]:
		if hit["to"] == runner and not hit["evaded"] and hit["from"] in hunter_side:
			change -= _Balance.CHASE_HUNTER_HEAVY if hit["card"].type in [DuelCard.Type.STRIKE, DuelCard.Type.TRICK] else _Balance.CHASE_RUNNER_HIT
			break
	if run_card and run_card.type == DuelCard.Type.FOCUS:
		change -= _Balance.CHASE_FOCUS
	if change != 0:
		distance = clampi(distance + change, 0, _Balance.CHASE_END)
		lines.append("   거리 %+d → %d/%d" % [change, distance, _Balance.CHASE_END])


## 대치: 피해 없이 칸마다 상성으로 기세를 겨룬다
func _run_standoff(player_plan: Array, me: CombatUnit, foe: CombatUnit, lines: PackedStringArray) -> void:
	var slots: int = maxi(player_plan.size(), enemy_plan.size())
	for i in slots:
		var ca: DuelCard = player_plan[i] if i < player_plan.size() else null
		var cb: DuelCard = enemy_plan[i] if i < enemy_plan.size() else null
		lines.append_array(DuelRules.resolve_standoff(i, me, ca, foe, cb, ctx))
		if me == get_player():
			if ca == null:
				left_gap = true
			else:
				used_types[int(ca.type)] = true
		if me.momentum >= _Balance.STANDOFF_GOAL or foe.momentum >= _Balance.STANDOFF_GOAL:
			break
	lines.append("   기세 — %s %d · %s %d (먼저 %d)" % [me.display_name, me.momentum, foe.display_name, foe.momentum, _Balance.STANDOFF_GOAL])
	var decided: bool = me.momentum >= _Balance.STANDOFF_GOAL or foe.momentum >= _Balance.STANDOFF_GOAL or bout_in_duel >= _Balance.STANDOFF_BOUTS
	if not decided:
		return
	var edge: int = signi(me.momentum - foe.momentum)
	if setup.standoff_then.is_empty():
		match edge:
			1:
				lines.append("%s이(가) 기세에 눌려 물러섭니다!" % foe.display_name)
				_finish(CombatManager.Outcome.VICTORY, lines)
			-1:
				lines.append("%s의 기세에 눌렸습니다…" % foe.display_name)
				_finish(CombatManager.Outcome.DEFEAT, lines)
			_:
				lines.append("팽팽한 대치 끝에 서로 물러섭니다.")
				_finish(CombatManager.Outcome.RETREAT, lines)
		return
	# 대치 뒤 칼을 뽑는다: 이긴 쪽이 기세를 안고 시작
	format = setup.standoff_then
	ctx["format"] = format
	me.momentum = _Balance.STANDOFF_CARRY if edge > 0 else 0
	foe.momentum = _Balance.STANDOFF_CARRY if edge < 0 else 0
	bout_in_duel = 0
	lines.append("대치가 끝나고 칼을 뽑는다 — %s" % ("우리가 기세를 쥐었다 (기세 %d)" % _Balance.STANDOFF_CARRY if edge > 0 else ("상대가 기세를 쥐었다" if edge < 0 else "기세는 팽팽")))
	if format in ["siege", "formation"]:
		get_player().cards.append(DuelCard.sweep_card())


## 칸이 끝날 때: 기절 저항과 미끄러짐이 준다 (기절 자체는 다음 칸에서 쓰인다)
static func _tick_slot_statuses(unit: CombatUnit) -> void:
	for status in ["stun_immune", "slipped"]:
		if unit.statuses.has(status):
			unit.statuses[status] -= 1
			if unit.statuses[status] <= 0:
				unit.statuses.erase(status)


## 옛 이름 (시험용)
static func _tick_stun_immunity(unit: CombatUnit) -> void:
	_tick_slot_statuses(unit)


## 상대가 낸 유형을 버릇으로 남긴다
func _remember(foe: CombatUnit, types: Array) -> void:
	var id: String = _npc_id(foe)
	var record: Dictionary = memory.get(id, {"bouts": 0, "first": {}})
	record["bouts"] = int(record["bouts"]) + 1
	if not types.is_empty() and int(types[0]) >= 0:
		var first: Dictionary = record["first"]
		first[int(types[0])] = int(first.get(int(types[0]), 0)) + 1
	memory[id] = record


## 합이 끝날 때: 불길, 장외, 맞선 사람들의 기록 줄
func _end_of_bout(lines: PackedStringArray) -> void:
	var everyone: Array[CombatUnit] = active_friends() + active_foes()
	if setup.stage == "burning":
		for unit in everyone:
			if is_standing(unit):
				var burn: int = maxi(1, int(unit.max_hp * _Balance.FIRE_BURN))
				unit.take_damage(burn)
				if unit.is_player:
					hero_damage_taken += burn
		lines.append("   불길이 번진다 — 모두 체력 -%d%%" % roundi(_Balance.FIRE_BURN * 100))
	if setup.stage == "arena":
		for unit in everyone:
			if unit.is_alive() and not retired.has(unit) and unit.get_hp_ratio() < _Balance.RING_OUT_RATIO:
				retired[unit] = true
				lines.append("   %s 장외!" % unit.display_name)
	var parts: PackedStringArray = []
	for unit in everyone:
		parts.append("%s 체력 %d/%d · 내공 %d · 기세 %d" % [unit.display_name, unit.hp, unit.max_hp, unit.character.internal_energy_current, unit.momentum])
	lines.append("   " + "  |  ".join(parts))


func _after_bout(lines: PackedStringArray) -> void:
	var friend: CombatUnit = current_friend()
	var foe: CombatUnit = current_foe()
	# 1대1: 합을 다 쓰면 체력 비율이 낮은 쪽이 물러난다 (추격·대치는 게이지로 겨룬다)
	if is_single() and format != "chase" and is_standing(friend) and is_standing(foe) and bout_in_duel >= max_bouts:
		var loser: CombatUnit = foe if friend.get_hp_ratio() >= foe.get_hp_ratio() else friend
		retired[loser] = true
		lines.append("   %d합이 지나 %s이(가) 물러납니다 (체력 비율)" % [max_bouts, loser.display_name])
	for unit in active_friends():
		if unit.is_ally and is_standing(unit) and unit.get_hp_ratio() < ALLY_RETREAT_RATIO:
			retired[unit] = true
			lines.append("   %s이(가) 크게 다쳐 물러납니다" % unit.display_name)
	# 호위: 우리 쪽이 지면 상대가 뚫고 들어와 지킬 인물을 친다
	if ward:
		for unit in active_friends():
			if not is_standing(unit) and not ward_counted.has(unit):
				ward_counted[unit] = true
				ward.take_damage(maxi(1, int(ward.max_hp * WARD_HIT)))
				lines.append("   적이 뚫고 들어와 %s이(가) 다칩니다 (체력 %d/%d)" % [ward.display_name, ward.hp, ward.max_hp])
	if _check_objectives(lines):
		return
	# 다음 사람
	var foe_changed: bool = false
	var friend_changed: bool = false
	while foe_index < foes.size() and not is_standing(foes[foe_index]):
		foe_index += 1
		foe_changed = true
	while friend_index < friends.size() and not is_standing(friends[friend_index]):
		friend_index += 1
		friend_changed = true
	if foe_index >= foes.size() or not foes.any(func(u: CombatUnit) -> bool: return is_standing(u)):
		_finish(CombatManager.Outcome.VICTORY, lines)
		return
	if friend_index >= friends.size() or not get_player().is_alive():
		_finish(CombatManager.Outcome.DEFEAT, lines)
		return
	if _check_rounds(lines):
		return
	if format == "tournament" and foe_changed:
		_next_match(lines)
	if foe_changed or friend_changed:
		bout_in_duel = 0
		_refresh_rows()
		if is_single():
			current_friend().momentum = 0
			current_foe().momentum = 0
			_apply_bonds()
			lines.append("▶ %s 대 %s" % [current_friend().display_name, current_foe().display_name])
		else:
			_apply_bonds()
			lines.append("▶ %s 대 %s" % [_names(active_friends()), _names(active_foes())])


## 승패가 갈리는 목표를 본다. 끝났으면 true
func _check_objectives(lines: PackedStringArray) -> bool:
	var hero: CombatUnit = get_player()
	if ward and not ward.is_alive():
		lines.append("지켜야 할 %s이(가) 쓰러졌습니다…" % ward.display_name)
		_finish(CombatManager.Outcome.DEFEAT, lines)
		return true
	if not hero.is_alive():
		_finish(CombatManager.Outcome.DEFEAT, lines)
		return true
	match setup.objective:
		"escape":
			if format == "chase" and distance >= _Balance.CHASE_END:
				lines.append("추격을 따돌렸습니다!")
				_finish(CombatManager.Outcome.VICTORY, lines)
				return true
			if format != "chase" and evades >= ESCAPE_EVADES:
				lines.append("공격을 %d번 흘리고 포위를 빠져나왔습니다!" % evades)
				_finish(CombatManager.Outcome.VICTORY, lines)
				return true
		"catch":
			if distance >= _Balance.CHASE_END:
				lines.append("%s을(를) 놓쳤습니다…" % current_foe().display_name)
				_finish(CombatManager.Outcome.DEFEAT, lines)
				return true
		"defeat_target":
			var boss: Array = foes.filter(func(u: CombatUnit) -> bool: return u.character.id == setup.objective_target)
			if not boss.is_empty() and not is_standing(boss[0]):
				lines.append("우두머리 %s이(가) 무너지자 남은 자들이 달아났습니다!" % boss[0].display_name)
				_finish(CombatManager.Outcome.VICTORY, lines)
				return true
		"capture":
			var target: CombatUnit = ctx.get("capture")
			if captured:
				_finish(CombatManager.Outcome.VICTORY, lines)
				return true
			if target and not target.is_alive():
				lines.append("%s의 목숨을 거두고 말았습니다. 사로잡지 못했습니다…" % target.display_name)
				_finish(CombatManager.Outcome.DEFEAT, lines)
				return true
			if target and retired.has(target):
				lines.append("%s이(가) 달아났습니다…" % target.display_name)
				_finish(CombatManager.Outcome.DEFEAT, lines)
				return true
		"endure":
			if hero_damage_taken >= setup.objective_count:
				lines.append("받은 피해가 %d에 이르렀습니다. 버텨 내지 못했습니다…" % hero_damage_taken)
				_finish(CombatManager.Outcome.DEFEAT, lines)
				return true
		"disarm":
			if nullified >= setup.objective_count:
				lines.append("절초를 %d번 무산시키자 상대가 무기를 떨어뜨립니다!" % nullified)
				_finish(CombatManager.Outcome.VICTORY, lines)
				return true
		"hold_line":
			if format == "formation" and not active_friends().any(func(u: CombatUnit) -> bool: return u.front and is_standing(u)):
				lines.append("앞줄이 무너졌습니다…")
				_finish(CombatManager.Outcome.DEFEAT, lines)
				return true
	# 추격: 붙잡히면(쫓기다) / 따라잡으면(쫓다) 그 자리에서 칼을 맞댄다
	if format == "chase" and distance <= 0:
		lines.append("붙잡혔다 — 그 자리에서 칼을 맞댑니다!" if setup.objective == "escape" else "따라잡았다 — 이제 겨룰 차례!")
		format = "duel"
		ctx["format"] = format
		if setup.objective == "catch":
			setup.objective = "defeat_all"
	return false


## 합 수로 갈리는 목표 (사람이 바뀐 뒤에 본다). 끝났으면 true
func _check_rounds(lines: PackedStringArray) -> bool:
	match setup.objective:
		"survive", "hold_line":
			if bout_total >= setup.objective_rounds:
				lines.append("%d합을 버텨 냈습니다!" % setup.objective_rounds)
				_finish(CombatManager.Outcome.VICTORY, lines)
				return true
		"endure":
			if bout_total >= setup.objective_rounds:
				lines.append("%d합을 버텨 냈습니다! (받은 피해 %d)" % [setup.objective_rounds, hero_damage_taken])
				_finish(CombatManager.Outcome.VICTORY, lines)
				return true
		"timed":
			if bout_total >= setup.objective_rounds:
				lines.append("%d합 안에 끝내지 못했습니다…" % setup.objective_rounds)
				_finish(CombatManager.Outcome.DEFEAT, lines)
				return true
	return false


## 비무대회: 다음 판 — 조금 쉬고, 다음 상대를 관전한다
func _next_match(lines: PackedStringArray) -> void:
	tournament_round = foe_index
	var hero: CombatUnit = get_player()
	hero.heal(int(hero.max_hp * _Balance.TOURNEY_HP_RECOVER))
	var energy: int = int(hero.character.internal_energy_max * _Balance.TOURNEY_ENERGY_RECOVER)
	hero.character.internal_energy_current = mini(hero.character.internal_energy_max, hero.character.internal_energy_current + energy)
	hero.statuses.clear()
	lines.append("── 비무대회 %d회전 승리! 숨을 고른다 (체력·내공 조금 회복) ──" % tournament_round)
	_preview(current_foe())


func _finish(result: CombatManager.Outcome, lines: PackedStringArray) -> void:
	if over:
		return
	over = true
	outcome = result
	if format == "tournament" or setup.format == "tournament":
		tournament_round = foes.filter(func(u: CombatUnit) -> bool: return not is_standing(u)).size()
	lines.append("── 전투 끝: %s ──" % {CombatManager.Outcome.VICTORY: "승리", CombatManager.Outcome.DEFEAT: "패배", CombatManager.Outcome.RETREAT: "후퇴"}[result])


func retreat() -> void:
	if not over:
		pending_choice = {}
		_finish(CombatManager.Outcome.RETREAT, history)


# ── 사건 ──

func _check_events(lines: PackedStringArray) -> void:
	for i in setup.events.size():
		if fired_events.has(i) or not pending_choice.is_empty():
			continue
		var event: Dictionary = setup.events[i]
		if not _event_ready(event):
			continue
		fired_events[i] = true
		_fire_event(i, event, lines)
		if over:
			return


func _event_ready(event: Dictionary) -> bool:
	var when: Dictionary = event.get("when", {})
	if when.has("bout") and bout_total < int(when["bout"]):
		return false
	if when.has("player_hp_below") and get_player().get_hp_ratio() >= float(when["player_hp_below"]):
		return false
	if when.has("enemy_hp_below"):
		var npc: String = str(event.get("npc", ""))
		var pool: Array = active_foes() if npc.is_empty() or event["type"] in ["bond_intervene", "betrayal"] else foes.filter(func(u: CombatUnit) -> bool: return _npc_id(u) == npc or u.character.id == npc)
		if not pool.any(func(u: CombatUnit) -> bool: return is_standing(u) and u.get_hp_ratio() < float(when["enemy_hp_below"])):
			return false
	return true


func _fire_event(index: int, event: Dictionary, lines: PackedStringArray) -> void:
	var said: PackedStringArray = []
	for line in event.get("lines", []):
		said.append(str(line))
	match str(event["type"]):
		"reinforce":
			var character: CharacterData = NpcRoster.create_character(str(event["npc"]), get_player().character)
			character.id = "%s_event_%d" % [str(event["npc"]), index]
			if event.has("name"):
				character.display_name = str(event["name"])
			for key in event.get("stats", {}):
				character.set(key, int(character.get(key)) + int(event["stats"][key]))
			character.restore_internal_energy()
			foes.append(_make_foe(character, ScenarioRules.enemy_strength_scale()))
			said.append("%s이(가) 가세합니다!" % character.display_name)
		"betrayal":
			var npc: String = str(event["npc"])
			var traitor: Array = friends.filter(func(u: CombatUnit) -> bool: return u.character.id == npc and is_standing(u))
			var rel: RelationshipData = RelationshipManager.get_bond_with(bonds, npc)
			if traitor.is_empty() or (event.has("bond_below") and rel and rel.bond_strength >= int(event["bond_below"])):
				return
			var unit: CombatUnit = traitor[0]
			var at: int = friends.find(unit)
			friends.remove_at(at)
			if at < friend_index:
				friend_index -= 1
			unit.is_ally = false
			unit.order = "attack"
			foes.insert(mini(foe_index + (0 if not is_single() else 1), foes.size()), unit)
			said.append("%s이(가) 칼끝을 돌립니다 — 배신!" % unit.display_name)
		"bond_intervene":
			var npc: String = str(event["npc"])
			var rel: RelationshipData = RelationshipManager.get_bond_with(bonds, npc)
			if rel == null or rel.bond_strength < int(event.get("min_bond", _Balance.INTERVENE_BOND)):
				return
			var hero: CombatUnit = get_player()
			hero.heal(int(hero.max_hp * 0.25))
			hero.momentum = mini(DuelRules.MAX_MOMENTUM, hero.momentum + _Balance.INTERVENE_MOMENTUM)
			said.append("%s이(가) 뛰어들어 막아섭니다! (체력 회복, 기세 +%d)" % [rel.target_name, _Balance.INTERVENE_MOMENTUM])
		"parley", "decision":
			pending_choice = {"event": index, "title": str(event.get("title", "설득" if event["type"] == "parley" else "결단")), "lines": said, "options": _choice_options(event)}
	if said.is_empty():
		return
	for line in said:
		lines.append("◆ " + line)
		event_lines.append(line)


func _choice_options(event: Dictionary) -> Array:
	var options: Array = event.get("choices", []).duplicate(true)
	if options.is_empty():
		if event["type"] == "parley":
			options = [
				{"label": "칼을 거두라고 설득한다", "description": "매력 %d 이상이면 상대가 물러난다" % _Balance.PARLEY_CHARISMA, "action": "withdraw_foe",
					"check": {"stat": "charisma", "min": _Balance.PARLEY_CHARISMA}, "fail_lines": ["말이 통하지 않는다!"], "effects": [{"type": "character", "field": "morality", "add": 3}]},
				{"label": "끝까지 싸운다", "action": "fight"},
			]
		else:
			options = [
				{"label": "목숨을 건다", "description": "체력 %d%%를 내주고 기세를 끝까지 끌어올린다" % roundi(_Balance.ALL_IN_HP_COST * 100), "action": "all_in"},
				{"label": "버틴다", "action": "hold"},
				{"label": "물러선다", "description": "후퇴 (손실 절반)", "action": "retreat"},
			]
	for i in options.size():
		options[i]["id"] = str(i)
	return options


## 사건 선택지를 고른다 (id 또는 번호)
func choose(option_id: Variant) -> PackedStringArray:
	var lines: PackedStringArray = []
	if pending_choice.is_empty():
		return lines
	var options: Array = pending_choice["options"]
	var index: int = clampi(int(str(option_id)), 0, options.size() - 1)
	var option: Dictionary = options[index]
	pending_choice = {}
	var action: String = str(option.get("action", "fight"))
	lines.append("▷ %s" % option["label"])
	var check: Dictionary = option.get("check", {})
	if not check.is_empty() and int(get_player().character.get(str(check["stat"]))) < int(check["min"]):
		action = str(option.get("fail_action", "fight"))
		for line in option.get("fail_lines", ["뜻대로 되지 않았다."]):
			lines.append("◆ " + str(line))
	else:
		for line in option.get("lines", []):
			lines.append("◆ " + str(line))
		choice_effects.append_array(option.get("effects", []))
	match action:
		"withdraw_foe":
			for foe in foes:
				if is_standing(foe):
					retired[foe] = true
			lines.append("상대가 칼을 거두고 물러납니다.")
			_finish(CombatManager.Outcome.VICTORY, lines)
		"all_in":
			var hero: CombatUnit = get_player()
			hero.hp = maxi(1, hero.hp - int(hero.max_hp * _Balance.ALL_IN_HP_COST))
			hero.momentum = DuelRules.MAX_MOMENTUM
			lines.append("%s이(가) 목숨을 걸었다 — 기세 최고조!" % hero.display_name)
		"retreat":
			_finish(CombatManager.Outcome.RETREAT, lines)
	history.append_array(lines)
	return lines


## 자동으로 고를 선택지: 사건의 auto, 없으면 판정을 통과하는 첫 선택지, 그것도 없으면 첫 선택지
func auto_choice() -> int:
	if pending_choice.is_empty():
		return 0
	var event: Dictionary = setup.events[int(pending_choice["event"])]
	if event.has("auto"):
		return int(event["auto"])
	var options: Array = pending_choice["options"]
	var hero: CombatUnit = get_player()
	for i in options.size():
		var check: Dictionary = options[i].get("check", {})
		var action: String = str(options[i].get("action", ""))
		# 물러서지 않고, 체력이 넉넉할 때만 목숨을 건다
		if action == "retreat" or (action == "all_in" and hero.get_hp_ratio() < _Balance.ALL_IN_HP_COST + 0.3):
			continue
		if check.is_empty() or int(hero.character.get(str(check["stat"]))) >= int(check["min"]):
			return i
	return 0


# ── 자동 ──

## 자동 배치 (자동 전투·결과만 보기): 상대가 지난 합에 낸 유형을 읽어 맞받는다. 목표에 맞게 유형을 고른다
func auto_plan() -> Array[DuelCard]:
	var me: CombatUnit = controlled()
	var options: Dictionary = {"ctx": ctx, "style": ""}
	var target: CombatUnit = ctx.get("capture")
	if setup.objective == "capture" and target and target.get_hp_ratio() <= CAPTURE_RATIO + 0.15:
		options["allowed"] = [DuelCard.Type.GUARD, DuelCard.Type.TRICK]
	elif format == "chase":
		options["allowed"] = [DuelCard.Type.EVADE, DuelCard.Type.QUICK, DuelCard.Type.GUARD] if setup.objective == "escape" else [DuelCard.Type.STRIKE, DuelCard.Type.TRICK, DuelCard.Type.QUICK]
	elif format == "stealth" and not alarm:
		options["allowed"] = [DuelCard.Type.QUICK, DuelCard.Type.TRICK, DuelCard.Type.EVADE, DuelCard.Type.FOCUS]
	elif setup.objective in ["endure", "disarm"]:
		options["allowed"] = [DuelCard.Type.GUARD, DuelCard.Type.EVADE, DuelCard.Type.QUICK, DuelCard.Type.FOCUS]
	var plan: Array[DuelCard] = DuelAI.plan(me, last_types["foe"], {}, PLAYER_AUTO_COUNTER_RATE, rng, options)
	# 예고된 절초는 마지막 칸에서 흘린다 (회피, 다리 위면 막기)
	if not plan.is_empty() and telegraphs.values().any(func(t: Dictionary) -> bool: return int(t["bout"]) == bout_total + 1):
		var dodge: Array = me.cards.filter(func(c: DuelCard) -> bool: return c.type == (DuelCard.Type.GUARD if setup.stage == "bridge" else DuelCard.Type.EVADE))
		if not dodge.is_empty():
			plan[-1] = dodge[0]
	if not is_single():
		for i in plan.size():
			set_target(i, DuelAI.choose_target(me, plan[i], active_foes(), rng, format == "formation"))
	return plan


## 끝까지 자동으로 치른다 (결과만 보기·시뮬레이터)
func play_to_end() -> void:
	var guard: int = 0
	while not over and guard < SAFETY_BOUTS:
		guard += 1
		if not pending_choice.is_empty():
			choose(auto_choice())
			continue
		prepare_bout()
		run_bout(auto_plan())
	if not over:
		_finish(CombatManager.Outcome.RETREAT, history)


## 쓰러진(체력 0) 아군 id (문파 제자 손실)
func fallen_ally_ids() -> Array:
	var result: Array = []
	for unit in friends:
		if unit.is_ally and not unit.is_alive():
			result.append(unit.character.id)
	return result


# ── 평가 ──

## 끝난 뒤의 평가: 완승 · 승리 · 신승 · 패배 · 후퇴
func rating() -> String:
	match outcome:
		CombatManager.Outcome.VICTORY:
			var ratio: float = get_player().get_hp_ratio()
			if ratio >= _Balance.RATING_FLAWLESS:
				return "완승"
			return "승리" if ratio >= _Balance.RATING_NARROW else "신승"
		CombatManager.Outcome.DEFEAT:
			return "패배"
	return "후퇴"


## 선택 도전을 이뤘는지 (이긴 판만)
func challenge_met() -> bool:
	if setup.challenge.is_empty() or outcome != CombatManager.Outcome.VICTORY:
		return false
	var value: int = int(setup.challenge.get("value", 0))
	match str(setup.challenge.get("type", "")):
		"within_bouts":
			return bout_total <= value
		"damage_below":
			return hero_damage_taken < value
		"no_trick":
			return not used_types.has(int(DuelCard.Type.TRICK))
		"no_focus":
			return not used_types.has(int(DuelCard.Type.FOCUS))
		"no_gap":
			return not left_gap
	return false


## GameManager.finish_combat에 넘길 요약: 평가·도전·사건 효과·받아 낸 무공·비무대회 성적 플래그
func summary() -> Dictionary:
	var placement_flag: String = ""
	if setup.format == "tournament":
		placement_flag = str(setup.placement_flags.get(str(tournament_round), ""))
	return {
		"rating": rating(),
		"challenge": Battlefield.challenge_text(setup.challenge) if not setup.challenge.is_empty() else "",
		"challenge_met": challenge_met(),
		"effects": choice_effects,
		"studied_arts": studied_arts,
		"placement_flag": placement_flag,
		"rounds_won": tournament_round,
	}
