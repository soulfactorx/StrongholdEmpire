class_name DuelRules
extends RefCounted

## 초식 배치 대결의 한 칸 판정. 두 사람이 같은 칸에 놓은 초식을 동시에 펼친다.
## 1) 내공·기세가 모자라거나 기절했으면 그 칸은 빈틈이다.
## 2) 상성에 따라 서로에게 주는 피해를 정하고, 빠른 쪽이 먼저 친다 (먼저 쓰러뜨리면 상대의 초식은 나오지 않는다).
## 3) 더 큰 피해를 준 쪽의 기세가 오르고, 진 쪽은 내린다. 운기(기)는 내공과 기세를 모은다.
## 운은 회심 하나뿐이다 (CombatRules.randomness가 꺼지면 없음).

const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 무력이 초식 피해에 더해지는 비율
const STRENGTH_RATIO := _Balance.DUEL_STRENGTH_RATIO
const MAX_MOMENTUM := _Balance.DUEL_MAX_MOMENTUM
## 기세 한 점마다 피해 +
const MOMENTUM_DAMAGE := _Balance.DUEL_MOMENTUM_DAMAGE
## 상성 배율
const GAP_TAKEN := _Balance.DUEL_GAP_TAKEN
const FOCUS_TAKEN := _Balance.DUEL_FOCUS_TAKEN
const GUARD_QUICK := _Balance.DUEL_GUARD_QUICK
const GUARD_TRICK := _Balance.DUEL_GUARD_TRICK
const EVADE_GRAZE := _Balance.DUEL_EVADE_GRAZE
const INTERRUPTED := _Balance.DUEL_INTERRUPTED
const TIER_DAMAGE := _Balance.DUEL_TIER_DAMAGE
## 막기가 속공을 받아칠 때의 반격 피해 (기본 + 무력 비율)
const COUNTER_BASE := _Balance.DUEL_COUNTER_BASE
const COUNTER_RATIO := _Balance.DUEL_COUNTER_RATIO
## 운기조식: 내공 회복 (기본 + 지혜)
const FOCUS_ENERGY := _Balance.DUEL_FOCUS_ENERGY


## 한 칸을 판정한다. a·b는 CombatUnit, ca·cb는 DuelCard(null이면 빈 칸).
## 반환: {lines: 기록 줄, damage: {a, b} 받은 피해, evaded: {a, b} 흘린 공격 수}
static func resolve_slot(slot: int, a: CombatUnit, ca: DuelCard, b: CombatUnit, cb: DuelCard, weather: String = "clear") -> Dictionary:
	var lines: PackedStringArray = []
	ca = _ready_card(a, ca, lines)
	cb = _ready_card(b, cb, lines)
	lines.append("[%d칸] %s 「%s」 ↔ %s 「%s」" % [slot + 1, a.display_name, _card_name(ca), b.display_name, _card_name(cb)])
	var hits: Array[Dictionary] = []
	var ab: Dictionary = _hit(a, ca, b, cb, weather)
	var ba: Dictionary = _hit(b, cb, a, ca, weather)
	if ab["damage"] > 0 or not ab["note"].is_empty():
		hits.append({"from": a, "to": b, "card": ca, "result": ab, "speed": _speed(a, ca, weather)})
	if ba["damage"] > 0 or not ba["note"].is_empty():
		hits.append({"from": b, "to": a, "card": cb, "result": ba, "speed": _speed(b, cb, weather)})
	# 막기가 속공을 받아친다
	for pair in [[a, ca, b, cb], [b, cb, a, ca]]:
		var guard_card: DuelCard = pair[1]
		var other_card: DuelCard = pair[3]
		if guard_card and guard_card.type == DuelCard.Type.GUARD and other_card and other_card.type == DuelCard.Type.QUICK:
			var guard_unit: CombatUnit = pair[0]
			var counter: int = maxi(1, int((COUNTER_BASE + guard_unit.character.strength * COUNTER_RATIO) * guard_unit.damage_scale))
			hits.append({"from": guard_unit, "to": pair[2], "card": guard_card, "result": {"damage": counter, "note": "반격", "effects": []}, "speed": -1})
	hits.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["speed"] > y["speed"])
	var taken: Dictionary = {a: 0, b: 0}
	var evaded: Dictionary = {a: 0, b: 0}
	for hit in hits:
		var source: CombatUnit = hit["from"]
		var target: CombatUnit = hit["to"]
		if not source.is_alive() or not target.is_alive():
			continue
		var amount: int = hit["result"]["damage"]
		var note: String = hit["result"]["note"]
		if amount <= 0:
			evaded[target] += 1
			lines.append("   %s이(가) 흘려 냄 (%s)" % [target.display_name, note])
			continue
		target.take_damage(amount)
		taken[target] += amount
		lines.append("   %s → %s %d%s" % [source.display_name, target.display_name, amount, " (%s)" % note if not note.is_empty() else ""])
		var card: DuelCard = hit["card"]
		if card and card.effects.has("stun") and not target.has_status("stun_immune") and target.is_alive():
			target.add_status("stunned", 1)
			target.add_status("stun_immune", 3)
			lines.append("   %s 기절 — 다음 칸이 막힘" % target.display_name)
		if card and card.effects.has("momentum"):
			source.momentum = mini(MAX_MOMENTUM, source.momentum + 1)
		if not target.is_alive():
			lines.append("   %s 쓰러짐!" % target.display_name)
	# 운기: 내공·기세 (회복 무공이면 체력도)
	for pair in [[a, ca], [b, cb]]:
		var unit: CombatUnit = pair[0]
		var card: DuelCard = pair[1]
		if card and card.type == DuelCard.Type.FOCUS and unit.is_alive():
			var energy: int = FOCUS_ENERGY + unit.character.wisdom / 2
			unit.character.internal_energy_current = mini(unit.character.internal_energy_max, unit.character.internal_energy_current + energy)
			unit.momentum = mini(MAX_MOMENTUM, unit.momentum + 1)
			var note: String = "내공 +%d, 기세 +1" % energy
			if card.effects.has("heal") and card.power > 0:
				unit.heal(card.power)
				note += ", 체력 +%d" % card.power
			lines.append("   %s 운기 — %s" % [unit.display_name, note])
	# 기세: 더 큰 피해를 준 쪽이 오른다
	if taken[b] > taken[a]:
		_shift_momentum(a, b)
	elif taken[a] > taken[b]:
		_shift_momentum(b, a)
	return {"lines": lines, "damage": {"a": taken[a], "b": taken[b]}, "evaded": {"a": evaded[a], "b": evaded[b]}}


static func _shift_momentum(winner: CombatUnit, loser: CombatUnit) -> void:
	winner.momentum = mini(MAX_MOMENTUM, winner.momentum + 1)
	loser.momentum = maxi(0, loser.momentum - 1)


## 칸에 놓은 초식을 펼칠 수 있는지 보고 대가를 치른다. 못 펼치면 null (빈틈)
static func _ready_card(unit: CombatUnit, card: DuelCard, lines: PackedStringArray) -> DuelCard:
	if card == null:
		return null
	if unit.has_status("stunned"):
		unit.statuses.erase("stunned")
		lines.append("   %s은(는) 기절해 「%s」을(를) 펼치지 못함" % [unit.display_name, card.display_name])
		return null
	if unit.character.internal_energy_current < card.cost:
		lines.append("   %s 내공 부족 — 「%s」 헛손질" % [unit.display_name, card.display_name])
		return null
	if unit.momentum < card.momentum_cost:
		lines.append("   %s 기세 부족 — 절초 「%s」 헛손질" % [unit.display_name, card.display_name])
		return null
	unit.character.internal_energy_current -= card.cost
	unit.momentum -= card.momentum_cost
	return card


static func _card_name(card: DuelCard) -> String:
	return "빈틈" if card == null else "%s·%s" % [card.display_name, card.get_type_name()]


## 같은 칸에서 누가 먼저 치는지: 카드 속도 × 10 + 신법 (밤에는 회피, 눈 속에서는 강공이 달라진다)
static func _speed(unit: CombatUnit, card: DuelCard, weather: String) -> int:
	if card == null:
		return 0
	var speed: int = card.speed
	if weather == "night" and card.type == DuelCard.Type.EVADE:
		speed += 1
	elif weather == "snow" and card.type == DuelCard.Type.STRIKE:
		speed -= 1
	return speed * 10 + unit.character.agility


## attacker가 card로 defender(그 칸의 초식 defense)에게 주는 피해 {damage, note}
static func _hit(attacker: CombatUnit, card: DuelCard, defender: CombatUnit, defense: DuelCard, weather: String) -> Dictionary:
	if card == null or not card.is_offensive():
		return {"damage": 0, "note": "", "effects": []}
	var damage: float = (card.power * (1.0 + TIER_DAMAGE * card.tier) + attacker.character.strength * STRENGTH_RATIO)
	var notes: PackedStringArray = []
	if card.effects.has("ambush") and defender.hp == defender.max_hp:
		damage *= _Balance.AMBUSH_MULTIPLIER
		notes.append("기습")
	var defense_element: MartialArtData.FiveElement = defense.element if defense else MartialArtData.FiveElement.NONE
	var element_mod: float = CombatRules.element_modifier(card.element, defense_element)
	if element_mod > 1.0:
		notes.append("오행 상극")
	damage *= element_mod
	if weather == "rain":
		if card.element == MartialArtData.FiveElement.FIRE:
			damage *= CombatRules.RAIN_FIRE
			notes.append("빗속의 화기")
		elif card.element == MartialArtData.FiveElement.WATER:
			damage *= CombatRules.RAIN_WATER
			notes.append("빗속의 수기")
	damage *= 1.0 + MOMENTUM_DAMAGE * attacker.momentum
	damage *= attacker.damage_scale * attacker.bond_attack / defender.bond_guard
	# 상성
	if defense == null:
		damage *= GAP_TAKEN
		notes.append("빈틈")
	else:
		match defense.type:
			DuelCard.Type.FOCUS:
				damage *= FOCUS_TAKEN
				notes.append("무방비")
			DuelCard.Type.GUARD:
				if card.type == DuelCard.Type.STRIKE or card.effects.has("pierce"):
					notes.append("막기를 깸")
				elif card.type == DuelCard.Type.QUICK:
					damage *= GUARD_QUICK
					notes.append("막힘")
				else:
					damage *= GUARD_TRICK
					notes.append("반쯤 막힘")
			DuelCard.Type.EVADE:
				if card.type == DuelCard.Type.TRICK:
					notes.append("회피를 읽음")
				elif _speed(defender, defense, weather) >= _speed(attacker, card, weather):
					return {"damage": 0, "note": "회피", "effects": []}
				else:
					damage *= EVADE_GRAZE
					notes.append("스침")
			DuelCard.Type.QUICK:
				if card.type in [DuelCard.Type.STRIKE, DuelCard.Type.TRICK]:
					damage *= INTERRUPTED
					notes.append("속공에 끊김")
	if CombatRules.randomness and randf() < CombatRules.crit_chance(attacker):
		damage *= _Balance.CRIT_MULTIPLIER
		notes.append("회심")
	return {"damage": maxi(1, int(damage)), "note": ", ".join(notes), "effects": card.effects}


## 두 초식의 상성 (화면 안내용): 1이면 a가 유리, -1이면 b가 유리, 0이면 비김
static func advantage(ca: DuelCard, cb: DuelCard) -> int:
	if ca == null or cb == null:
		return 0 if ca == cb else (1 if ca else -1)
	const BEATS: Dictionary = {
		DuelCard.Type.STRIKE: [DuelCard.Type.GUARD, DuelCard.Type.FOCUS],
		DuelCard.Type.QUICK: [DuelCard.Type.STRIKE, DuelCard.Type.TRICK, DuelCard.Type.FOCUS],
		DuelCard.Type.GUARD: [DuelCard.Type.QUICK],
		DuelCard.Type.EVADE: [DuelCard.Type.STRIKE, DuelCard.Type.QUICK],
		DuelCard.Type.TRICK: [DuelCard.Type.EVADE, DuelCard.Type.GUARD, DuelCard.Type.FOCUS],
		DuelCard.Type.FOCUS: [],
	}
	if cb.type in BEATS[ca.type]:
		return 1
	if ca.type in BEATS[cb.type]:
		return -1
	return 0


## 이 유형을 이기는 유형 (AI가 상대의 버릇을 읽을 때)
static func counter_of(type: DuelCard.Type) -> DuelCard.Type:
	match type:
		DuelCard.Type.STRIKE:
			return DuelCard.Type.QUICK
		DuelCard.Type.QUICK:
			return DuelCard.Type.GUARD
		DuelCard.Type.GUARD:
			return DuelCard.Type.STRIKE
		DuelCard.Type.EVADE:
			return DuelCard.Type.TRICK
		DuelCard.Type.TRICK:
			return DuelCard.Type.QUICK
	return DuelCard.Type.STRIKE
