class_name DuelEngine
extends RefCounted

## 초식 배치 대결 한 판: 연전(우리 줄과 상대 줄이 차례로 1대1), 합(한 번의 배치와 교전), 목표·날씨.
## 화면과 분리되어 있어 테스트와 밸런스 시뮬레이터가 그대로 쓴다.
##
## 흐름: prepare_bout()로 상대가 배치를 정하고(일부는 공개), 플레이어 배치로 run_bout()을 부르면 칸마다 판정한다.
## 한 사람이 쓰러지거나 한 대결의 합이 max_bouts를 넘으면(체력 비율이 낮은 쪽이 물러남) 다음 사람이 나온다.
## 목표: defeat_all(모두), defeat_target(우두머리와 바로 겨룸, 호위 하나마다 우두머리 체력 +15%),
##       survive(주인공이 선봉으로 합 수를 버팀), escape(주인공이 선봉으로 공격을 여러 번 흘리면 빠져나감),
##       protect(지킬 인물은 줄 밖에 있고, 우리 쪽이 대결에서 질 때마다 다친다. 쓰러지면 패배)

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

var setup: CombatSetup
var weather: String = "clear"
var friends: Array[CombatUnit] = []
var foes: Array[CombatUnit] = []
## 체력 비율로 져서 물러난 사람 (쓰러지지는 않음)
var retired: Dictionary = {}
var friend_index: int = 0
var foe_index: int = 0
var bout_total: int = 0
var bout_in_duel: int = 0
var max_bouts: int = MAX_BOUTS
var evades: int = 0
var over: bool = false
var outcome: CombatManager.Outcome = CombatManager.Outcome.RETREAT
var history: PackedStringArray = []
## 이번 합의 상대 배치 (prepare_bout에서 정함)
var enemy_plan: Array[DuelCard] = []
## 지난 합에 낸 유형: {"friend": [...], "foe": [...]}
var last_types: Dictionary = {"friend": [], "foe": []}
## 상대의 버릇 기록 {인물 id: {bouts, first: {유형: 횟수}, all: {유형: 횟수}}} (GameManager.duel_memory)
var memory: Dictionary = {}
## 초식 숙련 {무공 id: 쓴 횟수} (GameManager.art_mastery)
var mastery: Dictionary = {}
var rng := RandomNumberGenerator.new()
## 우두머리 목표의 호위 (우두머리에게 체력만 보태고 겨루지 않는다)
var guards: Array[CombatUnit] = []
## 호위 목표의 지킬 인물 (줄에 서지 않는다)
var ward: CombatUnit = null
## 주인공의 인연 (원한·가호·합격)
var bonds: Array[RelationshipData] = []
## 합격을 펼칠 만큼 깊은 인연
const COMBO_BOND := _Balance.DUEL_COMBO_BOND


func _init(combat_setup: CombatSetup, player: CharacterData, duel_memory: Dictionary = {}, art_mastery: Dictionary = {}, relationships: Array[RelationshipData] = []) -> void:
	setup = combat_setup
	bonds = relationships
	weather = setup.weather
	memory = duel_memory
	mastery = art_mastery
	max_bouts = setup.max_bouts if setup.max_bouts > 0 else MAX_BOUTS
	rng.randomize()
	var hero := CombatUnit.new(player, true)
	hero.cards = DuelCard.cards_for(player, mastery)
	# 기본 줄: 아군이 앞에, 주인공이 대장
	for ally in setup.allies:
		var unit := CombatUnit.new(ally, false, true)
		unit.cards = DuelCard.cards_for(ally)
		if setup.objective == "protect" and ally.id == setup.objective_target:
			ward = unit
		else:
			friends.append(unit)
	# 탈출·버티기는 주인공이 직접 빠져나가거나 막아서야 하므로 선봉으로 나선다
	if setup.objective in ["escape", "survive"]:
		friends.push_front(hero)
	else:
		friends.append(hero)
	var strength: float = ScenarioRules.enemy_strength_scale()
	var enemy_units: Array[CombatUnit] = []
	for enemy in setup.enemies:
		enemy_units.append(_make_foe(enemy, strength))
	for entry in setup.reinforcements:
		enemy_units.append(_make_foe(entry["character"], strength))
	if setup.objective == "defeat_target":
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
	history.append("── %s ── %s" % [setup.title, Battlefield.describe(setup)])
	if ward:
		history.append("%s은(는) 싸우지 않습니다. 우리 쪽이 대결에서 질 때마다 적이 뚫고 들어와 다칩니다." % ward.display_name)
	if not guards.is_empty():
		history.append("호위 %d명이 우두머리를 지킵니다 (우두머리 체력 +%d%%). 우두머리만 쓰러뜨리면 이깁니다." % [guards.size(), int(GUARD_HP_BONUS * 100 * guards.size())])
	_announce_pair()


func _make_foe(character: CharacterData, strength: float) -> CombatUnit:
	var unit := CombatUnit.new(character, false)
	unit.scale_stats(setup.enemy_hp_scale * strength, setup.enemy_damage_scale * strength)
	unit.cards = DuelCard.cards_for(character)
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
	_announce_pair()


func _announce_pair() -> void:
	if current_friend() and current_foe():
		_apply_bonds()
		history.append("▶ %s 대 %s" % [current_friend().display_name, current_foe().display_name])


## 지금 겨루는 두 사람에게 인연을 적용한다.
## - 주인공이 인연 있는 상대(원한·연적 등)와 겨루면 그 인연만큼 피해가 달라진다.
## - 맞는 쪽 가호: 인연 있는 동료는 그 인연만큼, 주인공은 줄에 함께 선 가장 깊은 인연만큼 피해를 덜 받는다.
## - 합격: 주인공 줄에 아직 서 있는 깊은 인연의 동료마다 합격 초식이 손패에 든다.
func _apply_bonds() -> void:
	var friend: CombatUnit = current_friend()
	var foe: CombatUnit = current_foe()
	friend.bond_attack = RelationshipManager.get_combat_damage_bonus(bonds, foe.character.id) if friend.is_player else 1.0
	if friend.is_player:
		friend.bond_guard = RelationshipManager.get_defense_modifier(bonds, _standing_partners().map(func(u: CombatUnit) -> String: return u.character.id))
	else:
		friend.bond_guard = RelationshipManager.get_defense_modifier(bonds, [friend.character.id])
	if friend.is_player:
		friend.cards = friend.cards.filter(func(c: DuelCard) -> bool: return not c.effects.has("combo"))
		for partner in _standing_partners():
			var rel: RelationshipData = RelationshipManager.get_bond_with(bonds, partner.character.id)
			if rel and rel.bond_strength >= COMBO_BOND and rel.get_combat_defense_modifier() > 1.0:
				friend.cards.append(DuelCard.combo(partner.character))


## 주인공 줄에서 아직 서 있는(쓰러지거나 물러나지 않은) 동료
func _standing_partners() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in friends:
		if unit.is_ally and unit.is_alive() and not retired.has(unit):
			result.append(unit)
	return result


# ── 정보 ──

## 상대 배치를 정한다 (이번 합). 상대는 우리 쪽이 지난 합에 낸 유형을 읽는다.
func prepare_bout() -> void:
	if over or current_foe() == null:
		return
	var foe: CombatUnit = current_foe()
	enemy_plan = DuelAI.plan(foe, last_types["friend"], NpcAgent.get_traits(_npc_id(foe)) if NpcRoster.has_npc(_npc_id(foe)) else {}, ENEMY_COUNTER_RATE, rng)


## 지혜에 따라 상대 배치가 얼마나 보이는지: 0 없음, 1 첫 칸 유형, 2 모든 칸 유형, 3 모든 칸 초식 (안개면 한 단계 덜)
func reveal_level() -> int:
	var wisdom: int = current_friend().character.wisdom if current_friend() else 0
	var level: int = 0 if wisdom < 13 else (1 if wisdom < 19 else (2 if wisdom < 25 else 3))
	if weather == "fog":
		level -= 1
	return clampi(level, 0, 3)


## 칸마다 보이는 상대 배치: "?" · 유형 · 초식 이름
func revealed_plan() -> PackedStringArray:
	var level: int = reveal_level()
	var result: PackedStringArray = []
	for i in enemy_plan.size():
		var card: DuelCard = enemy_plan[i]
		if level >= 3:
			result.append("%s·%s" % [card.display_name, card.get_type_name()])
		elif level >= 2 or (level == 1 and i == 0):
			result.append(card.get_type_name())
		else:
			result.append("?")
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
	if over:
		return lines
	if enemy_plan.is_empty():
		prepare_bout()
	var friend: CombatUnit = current_friend()
	var foe: CombatUnit = current_foe()
	bout_total += 1
	bout_in_duel += 1
	lines.append("── %d합 — %s 대 %s ──" % [bout_total, friend.display_name, foe.display_name])
	var slots: int = maxi(player_plan.size(), enemy_plan.size())
	var friend_types: Array = []
	var foe_types: Array = []
	for i in slots:
		var ca: DuelCard = player_plan[i] if i < player_plan.size() else null
		var cb: DuelCard = enemy_plan[i] if i < enemy_plan.size() else null
		friend_types.append(int(ca.type) if ca else -1)
		foe_types.append(int(cb.type) if cb else -1)
		var result: Dictionary = DuelRules.resolve_slot(i, friend, ca, foe, cb, weather)
		lines.append_array(result["lines"])
		if setup.objective == "escape" and friend.is_player:
			evades += int(result["evaded"]["a"])
		if ca and friend.is_player and not ca.art_id.is_empty():
			mastery[ca.art_id] = int(mastery.get(ca.art_id, 0)) + 1
		_tick_stun_immunity(friend)
		_tick_stun_immunity(foe)
		if not friend.is_alive() or not foe.is_alive():
			break
	last_types = {"friend": friend_types, "foe": foe_types}
	_remember(foe, foe_types)
	lines.append("   %s 체력 %d/%d · 내공 %d · 기세 %d  |  %s 체력 %d/%d · 기세 %d" % [
		friend.display_name, friend.hp, friend.max_hp, friend.character.internal_energy_current, friend.momentum,
		foe.display_name, foe.hp, foe.max_hp, foe.momentum,
	])
	enemy_plan.clear()
	_after_bout(lines)
	history.append_array(lines)
	return lines


## 기절 저항은 칸마다 줄어든다 (기절 자체는 다음 칸에서 쓰인다)
static func _tick_stun_immunity(unit: CombatUnit) -> void:
	if unit.statuses.has("stun_immune"):
		unit.statuses["stun_immune"] -= 1
		if unit.statuses["stun_immune"] <= 0:
			unit.statuses.erase("stun_immune")


## 상대가 낸 유형을 버릇으로 남긴다
func _remember(foe: CombatUnit, types: Array) -> void:
	var id: String = _npc_id(foe)
	var record: Dictionary = memory.get(id, {"bouts": 0, "first": {}})
	record["bouts"] = int(record["bouts"]) + 1
	if not types.is_empty() and int(types[0]) >= 0:
		var first: Dictionary = record["first"]
		first[int(types[0])] = int(first.get(int(types[0]), 0)) + 1
	memory[id] = record


func _after_bout(lines: PackedStringArray) -> void:
	var friend: CombatUnit = current_friend()
	var foe: CombatUnit = current_foe()
	if friend.is_alive() and foe.is_alive() and bout_in_duel >= max_bouts:
		# 합을 다 쓰면 체력 비율이 낮은 쪽이 물러난다
		if friend.get_hp_ratio() >= foe.get_hp_ratio():
			retired[foe] = true
			lines.append("   %d합이 지나 %s이(가) 물러납니다 (체력 비율)" % [max_bouts, foe.display_name])
		else:
			retired[friend] = true
			lines.append("   %d합이 지나 %s이(가) 물러납니다 (체력 비율)" % [max_bouts, friend.display_name])
	if friend.is_ally and friend.is_alive() and not retired.has(friend) and friend.get_hp_ratio() < ALLY_RETREAT_RATIO:
		retired[friend] = true
		lines.append("   %s이(가) 크게 다쳐 물러납니다" % friend.display_name)
	var foe_out: bool = not foe.is_alive() or retired.has(foe)
	var friend_out: bool = not friend.is_alive() or retired.has(friend)
	# 호위: 우리 쪽이 지면 상대가 뚫고 들어와 지킬 인물을 친다
	if ward and friend_out:
		ward.take_damage(maxi(1, int(ward.max_hp * WARD_HIT)))
		lines.append("   %s이(가) 뚫고 들어와 %s이(가) 다칩니다 (체력 %d/%d)" % [foe.display_name, ward.display_name, ward.hp, ward.max_hp])
	# 목표
	if ward and not ward.is_alive():
		lines.append("지켜야 할 %s이(가) 쓰러졌습니다…" % ward.display_name)
		_finish(CombatManager.Outcome.DEFEAT, lines)
		return
	if setup.objective == "escape" and evades >= ESCAPE_EVADES and get_player().is_alive():
		lines.append("공격을 %d번 흘리고 포위를 빠져나왔습니다!" % evades)
		_finish(CombatManager.Outcome.VICTORY, lines)
		return
	if setup.objective == "defeat_target" and foe_out and not guards.is_empty():
		lines.append("우두머리 %s이(가) 무너지자 호위들이 달아났습니다!" % foe.display_name)
		_finish(CombatManager.Outcome.VICTORY, lines)
		return
	if foe_out:
		foe_index += 1
	if friend_out:
		friend_index += 1
	if foe_index >= foes.size():
		_finish(CombatManager.Outcome.VICTORY, lines)
		return
	if friend_index >= friends.size() or not get_player().is_alive():
		_finish(CombatManager.Outcome.DEFEAT, lines)
		return
	if setup.objective == "survive" and bout_total >= setup.objective_rounds:
		lines.append("%d합을 버텨 냈습니다!" % setup.objective_rounds)
		_finish(CombatManager.Outcome.VICTORY, lines)
		return
	if foe_out or friend_out:
		bout_in_duel = 0
		current_friend().momentum = 0
		current_foe().momentum = 0
		_apply_bonds()
		lines.append("▶ %s 대 %s" % [current_friend().display_name, current_foe().display_name])


func _finish(result: CombatManager.Outcome, lines: PackedStringArray) -> void:
	over = true
	outcome = result
	lines.append("── 전투 끝: %s ──" % {CombatManager.Outcome.VICTORY: "승리", CombatManager.Outcome.DEFEAT: "패배", CombatManager.Outcome.RETREAT: "후퇴"}[result])


func retreat() -> void:
	if not over:
		_finish(CombatManager.Outcome.RETREAT, history)


## 자동 배치 (자동 전투·결과만 보기): 상대가 지난 합에 낸 유형을 읽어 맞받는다
func auto_plan() -> Array[DuelCard]:
	return DuelAI.plan(current_friend(), last_types["foe"], {}, PLAYER_AUTO_COUNTER_RATE, rng)


## 끝까지 자동으로 치른다 (결과만 보기·시뮬레이터)
func play_to_end() -> void:
	var guard: int = 0
	while not over and guard < SAFETY_BOUTS:
		guard += 1
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
