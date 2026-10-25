class_name DuelRules
extends RefCounted

## 초식 배치 대결의 한 칸 판정. 같은 칸에 놓은 초식을 모두 동시에 펼친다 (1대1, 포위·진형의 여럿).
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


## 판정 맥락: 날씨·전장·형식·조건과 그 합의 사정. 문자열을 주면 날씨로 본다 (옛 호출과 시험).
## {weather, stage, format, conditions, ambush_side(기습하는 쪽 0·1, 없으면 -1), capture(사로잡을 상대), poisoned(중독된 인물들)}
static func make_context(value: Variant = "clear") -> Dictionary:
	if value is Dictionary:
		return value
	return {"weather": str(value), "stage": "", "format": "duel", "conditions": PackedStringArray(), "ambush_side": -1}


## 1대1 한 칸 (연전·추격·잠입·비무대회와 시험). a는 우리 쪽, b는 상대 쪽.
## 반환: {lines, damage: {a, b} 받은 피해, evaded: {a, b} 흘린 공격 수} + resolve_multi의 결과
static func resolve_slot(slot: int, a: CombatUnit, ca: DuelCard, b: CombatUnit, cb: DuelCard, context: Variant = "clear") -> Dictionary:
	var actions: Array = [
		{"unit": a, "card": ca, "target": b, "side": 0},
		{"unit": b, "card": cb, "target": a, "side": 1},
	]
	var result: Dictionary = resolve_multi(slot, actions, make_context(context))
	result["damage"] = {"a": int(result["taken"].get(a, 0)), "b": int(result["taken"].get(b, 0))}
	result["evaded"] = {"a": int(result["evaded_by"].get(a, 0)), "b": int(result["evaded_by"].get(b, 0))}
	return result


## 한 칸을 판정한다. actions: [{unit, card(null이면 빈 칸), target(공격 대상), side(0 우리·1 상대)}]
## 1) 내공·기세·기절·전장 제약을 보고 펼칠 수 있는 초식만 남긴다 (못 펼치면 빈틈)
## 2) 공격마다 대상의 그 칸 초식으로 상성을 따진다. 대상이 다른 사람을 노리는 공격 초식이면 빈틈으로 맞는다
## 3) 빠른 순서로 피해를 주고(쓰러진 사람의 초식은 나오지 않음), 운기·기세를 정리한다
## 반환: {lines, taken·dealt·evaded_by: {unit: 수}, applied: [적용된 타격], cards: {unit: 펼친 초식}, captured, fallen_off: [unit]}
static func resolve_multi(slot: int, actions: Array, ctx: Dictionary) -> Dictionary:
	var lines: PackedStringArray = []
	ctx["slot"] = slot
	var cards: Dictionary = {}
	var targets: Dictionary = {}
	var sides: Dictionary = {}
	# 칸 수가 모자라 이 칸에 아무것도 놓을 수 없는 사람 (빈틈이 아니라 그냥 맞는다)
	var absent: Dictionary = {}
	for action in actions:
		var unit: CombatUnit = action["unit"]
		sides[unit] = int(action.get("side", 0))
		cards[unit] = _ready_card(unit, action.get("card"), lines, ctx)
		if action.get("absent", false):
			absent[unit] = true
	# 대상 정리: 쓰러졌거나 이 칸에 없는 대상은 맞은편의 첫 사람으로, 진형의 앞줄이 뒷줄을 가린다
	for action in actions:
		var unit: CombatUnit = action["unit"]
		var card: DuelCard = cards[unit]
		if card == null or not card.is_offensive():
			continue
		var target: CombatUnit = action.get("target")
		var foes: Array = actions.filter(func(x: Dictionary) -> bool: return sides[x["unit"]] != sides[unit] and x["unit"].is_alive()).map(func(x: Dictionary) -> CombatUnit: return x["unit"])
		if foes.is_empty():
			continue
		if target == null or not target in foes:
			target = foes[0]
		if str(ctx.get("format", "")) == "formation" and card.type != DuelCard.Type.TRICK:
			if not unit.front and _has_front(actions, sides[unit]):
				lines.append("   %s은(는) 뒷줄이라 「%s」이(가) 닿지 않음 (뒷줄은 술만)" % [unit.display_name, card.display_name])
				cards[unit] = null
				continue
			if not target.front and _has_front(actions, sides[target]):
				var fronts: Array = foes.filter(func(f: CombatUnit) -> bool: return f.front)
				if not fronts.is_empty():
					lines.append("   앞줄 %s이(가) %s을(를) 가로막음" % [fronts[0].display_name, target.display_name])
					target = fronts[0]
		targets[unit] = target
	lines.append(_slot_header(slot, actions, cards, targets))
	# 타격 목록
	var hits: Array[Dictionary] = []
	for action in actions:
		var unit: CombatUnit = action["unit"]
		var card: DuelCard = cards[unit]
		if not targets.has(unit):
			continue
		var main: CombatUnit = targets[unit]
		var victims: Array = [main]
		if card.effects.has("sweep"):
			for x in actions:
				if sides[x["unit"]] != sides[unit] and x["unit"] != main and x["unit"].is_alive():
					victims.append(x["unit"])
		for victim in victims:
			var defense: DuelCard = cards.get(victim)
			var facing: bool = defense == null or not defense.is_offensive() or targets.get(victim) == unit
			var scale: float = 1.0 if victim == main else _Balance.SWEEP_SPLASH
			var result: Dictionary = _hit(unit, card, victim, defense if facing else null, ctx, scale, sides[unit], absent.has(victim))
			if not facing and defense != null:
				result["note"] = "다른 상대를 보다 빈틈" if result["note"].is_empty() else result["note"].replace("빈틈", "다른 상대를 보다 빈틈")
			hits.append({
				"from": unit, "to": victim, "card": card, "damage": result["damage"], "note": result["note"],
				"evaded": result["evaded"], "speed": _speed(unit, card, ctx), "counter": false,
				"defense": defense if facing else null,
				"nullified": (card.momentum_cost > 0 or card.effects.has("telegraph")) and (result["evaded"] or (facing and defense != null and advantage(defense, card) == 1)),
			})
			# 막기가 속공을 받아친다
			if facing and defense and defense.type == DuelCard.Type.GUARD and card.type == DuelCard.Type.QUICK:
				var counter: int = maxi(1, int((COUNTER_BASE + victim.character.strength * COUNTER_RATIO) * victim.damage_scale))
				hits.append({"from": victim, "to": unit, "card": defense, "damage": counter, "note": "반격", "evaded": false, "speed": -1, "counter": true, "defense": card, "nullified": false})
	hits.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["speed"] > y["speed"])
	var taken: Dictionary = {}
	var dealt: Dictionary = {}
	var evaded_by: Dictionary = {}
	var applied: Array[Dictionary] = []
	var hit_by: Dictionary = {}
	var outcome: Dictionary = {"captured": false, "fallen_off": []}
	for action in actions:
		taken[action["unit"]] = 0
		dealt[action["unit"]] = 0
		evaded_by[action["unit"]] = 0
	for hit in hits:
		var source: CombatUnit = hit["from"]
		var target: CombatUnit = hit["to"]
		if not source.is_alive() or not target.is_alive() or target in outcome["fallen_off"] or outcome["captured"]:
			continue
		var card: DuelCard = hit["card"]
		if hit["evaded"]:
			evaded_by[target] += 1
			lines.append("   %s이(가) 「%s」을(를) 흘려 냄 (%s)" % [target.display_name, card.display_name, hit["note"]])
			if str(ctx.get("stage", "")) == "ice":
				source.add_status("slipped", 2)
				lines.append("   %s 빙판에 미끄러짐 — 다음 칸이 느려짐" % source.display_name)
			applied.append(hit)
			continue
		# 생포: 몰아붙인 상대를 막기 반격·기절 초식으로 사로잡는다
		if ctx.get("capture") == target and (hit["counter"] or card.effects.has("stun")) and target.get_hp_ratio() <= _Balance.CAPTURE_RATIO:
			outcome["captured"] = true
			lines.append("   %s이(가) %s을(를) 제압해 사로잡았다!" % [source.display_name, target.display_name])
			applied.append(hit)
			continue
		var amount: int = hit["damage"]
		var note: String = hit["note"]
		# 협공: 같은 칸에 이미 우리 편에게 맞은 대상
		if str(ctx.get("format", "")) == "formation" and hit_by.get(target, []).any(func(u: CombatUnit) -> bool: return u != source and sides[u] == sides[source]):
			amount = int(amount * (1.0 + _Balance.FLANK_BONUS))
			note = "협공" if note.is_empty() else note + ", 협공"
		hit_by[target] = hit_by.get(target, []) + [source]
		dealt[source] += amount
		# 엄호: 막기를 놓은 엄호 동료가 피해를 나눠 받는다
		var coverer: CombatUnit = _coverer(actions, cards, sides, target)
		if coverer and not hit["counter"]:
			var share: int = int(amount * _Balance.COVER_SHARE)
			amount -= share
			coverer.take_damage(share)
			taken[coverer] += share
			lines.append("   %s이(가) 막아서며 %d를 대신 받음" % [coverer.display_name, share])
		target.take_damage(amount)
		taken[target] += amount
		applied.append(hit)
		lines.append("   %s → %s %d%s" % [source.display_name, target.display_name, amount, " (%s)" % note if not note.is_empty() else ""])
		if card.effects.has("stun") and not target.has_status("stun_immune") and target.is_alive():
			target.add_status("stunned", 1)
			target.add_status("stun_immune", 3)
			lines.append("   %s 기절 — 다음 칸이 막힘" % target.display_name)
		if card.effects.has("momentum"):
			source.momentum = mini(MAX_MOMENTUM, source.momentum + 1)
		_after_damage(target, card, ctx, lines, outcome)
	# 운기: 내공·기세 (회복 무공이면 체력도). 독무 앞에서는 다친다
	for action in actions:
		var unit: CombatUnit = action["unit"]
		var card: DuelCard = cards[unit]
		if card and card.type == DuelCard.Type.FOCUS and unit.is_alive():
			var energy: int = FOCUS_ENERGY + unit.character.wisdom / 2
			if unit in ctx.get("poisoned", []):
				energy /= 2
			unit.character.internal_energy_current = mini(unit.character.internal_energy_max, unit.character.internal_energy_current + energy)
			unit.momentum = mini(MAX_MOMENTUM, unit.momentum + 1)
			var note: String = "내공 +%d, 기세 +1" % energy
			if card.effects.has("heal") and card.power > 0:
				unit.heal(card.power)
				note += ", 체력 +%d" % card.power
			lines.append("   %s 운기 — %s" % [unit.display_name, note])
			if actions.any(func(x: Dictionary) -> bool: return sides[x["unit"]] != sides[unit] and x["unit"].is_alive() and x["unit"].has_trait("poison_mist")):
				var poison: int = maxi(1, int(unit.max_hp * _Balance.POISON_MIST))
				unit.take_damage(poison)
				taken[unit] += poison
				lines.append("   독무가 스며 %s 체력 -%d" % [unit.display_name, poison])
	# 기세: 이 칸에서 준 피해가 받은 피해보다 크면 오르고, 작으면 내린다
	for action in actions:
		var unit: CombatUnit = action["unit"]
		if dealt[unit] > taken[unit]:
			unit.momentum = mini(MAX_MOMENTUM, unit.momentum + 1)
		elif taken[unit] > dealt[unit]:
			unit.momentum = maxi(0, unit.momentum - 1)
	# 포위 압박: 여럿에게 둘러싸인 주인공은 기세가 빨리 오른다
	if str(ctx.get("format", "")) == "siege":
		var around: int = actions.filter(func(x: Dictionary) -> bool: return sides[x["unit"]] == 1 and x["unit"].is_alive()).size()
		for action in actions:
			var unit: CombatUnit = action["unit"]
			if unit.is_player and unit.is_alive() and around >= _Balance.SIEGE_PRESSURE_FOES:
				unit.momentum = mini(MAX_MOMENTUM, unit.momentum + 1)
	return {
		"lines": lines, "taken": taken, "dealt": dealt, "evaded_by": evaded_by, "applied": applied,
		"cards": cards, "captured": outcome["captured"], "fallen_off": outcome["fallen_off"],
	}


## 맞은 뒤: 다리에서 떨어짐, 광폭, 단계 전환, 쓰러짐
static func _after_damage(target: CombatUnit, card: DuelCard, ctx: Dictionary, lines: PackedStringArray, outcome: Dictionary) -> void:
	if not target.is_alive() and target.has_trait("two_phase") and not target.second_phase:
		target.second_phase = true
		target.hp = maxi(1, int(target.max_hp * _Balance.SECOND_PHASE_HP))
		target.momentum = mini(MAX_MOMENTUM, target.momentum + _Balance.ENRAGE_MOMENTUM)
		lines.append("   %s이(가) 쓰러졌다가 다시 일어선다! 기운이 한층 사나워졌다" % target.display_name)
		return
	if not target.is_alive():
		lines.append("   %s 쓰러짐!" % target.display_name)
		return
	if target.has_trait("enrage") and not target.enraged and target.get_hp_ratio() < _Balance.ENRAGE_RATIO:
		target.enraged = true
		target.slot_bonus += 1
		target.momentum = mini(MAX_MOMENTUM, target.momentum + _Balance.ENRAGE_MOMENTUM)
		lines.append("   %s이(가) 광폭해진다 — 칸 +1, 기세 +%d" % [target.display_name, _Balance.ENRAGE_MOMENTUM])
	if str(ctx.get("stage", "")) == "bridge" and card.type == DuelCard.Type.STRIKE and target.get_hp_ratio() < _Balance.BRIDGE_FALL_RATIO:
		outcome["fallen_off"].append(target)
		lines.append("   %s이(가) 다리 아래로 떨어진다!" % target.display_name)


## 진형에서 이 편의 앞줄이 서 있는지
static func _has_front(actions: Array, side: int) -> bool:
	return actions.any(func(x: Dictionary) -> bool: return int(x.get("side", 0)) == side and x["unit"].front and x["unit"].is_alive())


## 대상 대신 피해를 나눠 받을 엄호 동료 (엄호 지시 + 이 칸에 막기)
static func _coverer(actions: Array, cards: Dictionary, sides: Dictionary, target: CombatUnit) -> CombatUnit:
	for action in actions:
		var unit: CombatUnit = action["unit"]
		var card: DuelCard = cards.get(unit)
		if unit != target and sides[unit] == sides[target] and unit.is_alive() and unit.order == "cover" and card and card.type == DuelCard.Type.GUARD:
			return unit
	return null


static func _slot_header(slot: int, actions: Array, cards: Dictionary, targets: Dictionary) -> String:
	var parts: PackedStringArray = []
	for action in actions:
		var unit: CombatUnit = action["unit"]
		var text: String = "%s 「%s」" % [unit.display_name, _card_name(cards[unit])]
		if actions.size() > 2 and targets.has(unit):
			text += "→%s" % targets[unit].display_name
		parts.append(text)
	if actions.size() == 2:
		return "[%d칸] %s ↔ %s" % [slot + 1, parts[0], parts[1]]
	return "[%d칸] %s" % [slot + 1, " · ".join(parts)]


## 대치 한 칸: 피해 없이 상성으로 기세를 겨룬다. 운기는 기세 +1.
static func resolve_standoff(slot: int, a: CombatUnit, ca: DuelCard, b: CombatUnit, cb: DuelCard, ctx: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	ca = _ready_card(a, ca, lines, ctx)
	cb = _ready_card(b, cb, lines, ctx)
	lines.append("[%d칸] %s 「%s」 ↔ %s 「%s」" % [slot + 1, a.display_name, _card_name(ca), b.display_name, _card_name(cb)])
	var edge: int = advantage(ca, cb)
	if edge == 0 and ca and cb and ca.type == cb.type:
		edge = signi(_speed(a, ca, ctx) - _speed(b, cb, ctx))
	for pair in [[a, ca], [b, cb]]:
		if pair[1] and pair[1].type == DuelCard.Type.FOCUS:
			pair[0].momentum = mini(MAX_MOMENTUM, pair[0].momentum + 1)
	if edge > 0:
		_shift_momentum(a, b)
		lines.append("   %s의 기세가 %s을(를) 누른다" % [a.display_name, b.display_name])
	elif edge < 0:
		_shift_momentum(b, a)
		lines.append("   %s의 기세가 %s을(를) 누른다" % [b.display_name, a.display_name])
	else:
		lines.append("   팽팽하다")
	return lines


static func _shift_momentum(winner: CombatUnit, loser: CombatUnit) -> void:
	winner.momentum = mini(MAX_MOMENTUM, winner.momentum + 1)
	loser.momentum = maxi(0, loser.momentum - 1)


## 이 맥락에서 쓸 수 없는 초식인지 (전장·조건): 이유, 쓸 수 있으면 ""
static func banned_reason(card: DuelCard, ctx: Dictionary) -> String:
	if card == null:
		return ""
	var stage: String = str(ctx.get("stage", ""))
	if card.type == DuelCard.Type.EVADE and stage == "bridge":
		return "외나무다리에서는 피할 곳이 없다"
	if card.type == DuelCard.Type.FOCUS and stage == "burning":
		return "연기 속에서는 운기할 수 없다"
	if card.type == DuelCard.Type.TRICK and (stage == "arena" or "honor" in ctx.get("conditions", PackedStringArray())):
		return "술은 금지"
	return ""


## 칸에 놓은 초식을 펼칠 수 있는지 보고 대가를 치른다. 못 펼치면 null (빈틈)
static func _ready_card(unit: CombatUnit, card: DuelCard, lines: PackedStringArray, ctx: Dictionary = {}) -> DuelCard:
	if card == null:
		return null
	if unit.has_status("stunned"):
		unit.statuses.erase("stunned")
		lines.append("   %s은(는) 기절해 「%s」을(를) 펼치지 못함" % [unit.display_name, card.display_name])
		return null
	var banned: String = banned_reason(card, ctx)
	if not banned.is_empty():
		lines.append("   %s 「%s」 헛손질 — %s" % [unit.display_name, card.display_name, banned])
		return null
	if unit.character.internal_energy_current < card.cost:
		lines.append("   %s 내공 부족 — 「%s」 헛손질" % [unit.display_name, card.display_name])
		return null
	if unit.momentum < card.momentum_cost and not card.effects.has("telegraph"):
		lines.append("   %s 기세 부족 — 절초 「%s」 헛손질" % [unit.display_name, card.display_name])
		return null
	unit.character.internal_energy_current -= card.cost
	if not card.effects.has("telegraph"):
		unit.momentum -= card.momentum_cost
	return card


static func _card_name(card: DuelCard) -> String:
	return "빈틈" if card == null else "%s·%s" % [card.display_name, card.get_type_name()]


## 같은 칸에서 누가 먼저 치는지: 카드 속도 × 10 + 신법 (밤·눈·지붕·빙판에 따라 달라진다)
static func _speed(unit: CombatUnit, card: DuelCard, context: Variant = "clear") -> int:
	if card == null:
		return 0
	var ctx: Dictionary = make_context(context)
	var weather: String = str(ctx.get("weather", "clear"))
	var stage: String = str(ctx.get("stage", ""))
	var speed: int = card.speed
	if weather == "night" and card.type == DuelCard.Type.EVADE:
		speed += 1
	elif (weather == "snow" or stage == "ice") and card.type == DuelCard.Type.STRIKE:
		speed -= 1
	if stage == "rooftop":
		if card.type in [DuelCard.Type.EVADE, DuelCard.Type.QUICK]:
			speed += 1
		elif card.type == DuelCard.Type.STRIKE:
			speed -= 1
	if unit.has_status("slipped"):
		speed -= 1
	return speed * 10 + unit.character.agility


## attacker가 card로 defender(그 칸의 초식 defense)에게 주는 피해 {damage, note, evaded}
## scale: 휩쓸기의 곁가지 등 배율, side: 공격하는 쪽 (잠입 기습), out_of_slots: 맞는 쪽이 칸 수가 모자라 그 칸이 없음 (빈틈 배율 없음)
static func _hit(attacker: CombatUnit, card: DuelCard, defender: CombatUnit, defense: DuelCard, context: Variant = "clear", scale: float = 1.0, side: int = -2, out_of_slots: bool = false) -> Dictionary:
	if card == null or not card.is_offensive():
		return {"damage": 0, "note": "", "effects": [], "evaded": false}
	var ctx: Dictionary = make_context(context)
	var weather: String = str(ctx.get("weather", "clear"))
	var stage: String = str(ctx.get("stage", ""))
	var damage: float = (card.power * (1.0 + TIER_DAMAGE * card.tier) + attacker.character.strength * STRENGTH_RATIO) * scale
	var notes: PackedStringArray = []
	if card.effects.has("ambush") and defender.hp == defender.max_hp:
		damage *= _Balance.AMBUSH_MULTIPLIER
		notes.append("기습")
	if side >= 0 and int(ctx.get("ambush_side", -1)) == side:
		damage *= _Balance.STEALTH_AMBUSH
		notes.append("암습")
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
	if stage == "boat" and card.type == DuelCard.Type.STRIKE and int(ctx.get("slot", 0)) % 2 == 1:
		damage *= _Balance.BOAT_SWAY
		notes.append("흔들림")
	if stage == "bamboo" and card.type == DuelCard.Type.TRICK:
		damage *= _Balance.BAMBOO_TRICK
		notes.append("대숲")
	if attacker.second_phase:
		damage *= _Balance.SECOND_PHASE_POWER
	if card.effects.has("telegraph"):
		notes.append("예고 절초")
	if defender.has_trait("iron_body") and card.type == DuelCard.Type.QUICK:
		damage *= _Balance.IRON_BODY_QUICK
		notes.append("금강불괴")
	damage *= 1.0 + MOMENTUM_DAMAGE * attacker.momentum
	damage *= attacker.damage_scale * attacker.bond_attack / defender.bond_guard
	# 상성
	if defense == null and out_of_slots:
		notes.append("칸 밖")
	elif defense == null:
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
				elif _speed(defender, defense, ctx) >= _speed(attacker, card, ctx):
					return {"damage": 0, "note": "회피", "effects": [], "evaded": true}
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
	return {"damage": maxi(1, int(damage)), "note": ", ".join(notes), "effects": card.effects, "evaded": false}


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


## 배치 사전 점검 (초보자의 실수 막기): 칸마다 확실히 빈틈이 되거나 불리한 곳을 알려 준다.
## unit의 지금 내공·기세에서 앞 칸부터 차례로 소모를 따진다 (운기는 내공·기세를 채운다고 본다. 이겨서 오르는 기세는 셈하지 않는다).
## enemy_types: 보이는 상대 유형 (칸마다 int, 모르면 -1).
## 반환: [{slot, serious(확실한 빈틈), text}]
static func plan_warnings(unit: CombatUnit, plan: Array, enemy_types: Array = [], ctx: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var energy: int = unit.character.internal_energy_current
	var momentum: int = unit.momentum
	for i in plan.size():
		var card: DuelCard = plan[i]
		if card == null:
			result.append({"slot": i, "serious": true, "text": "%d칸이 비어 빈틈이 됩니다 (받는 피해 %d%%)" % [i + 1, roundi(GAP_TAKEN * 100)]})
			continue
		var banned: String = banned_reason(card, ctx)
		if not banned.is_empty():
			result.append({"slot": i, "serious": true, "text": "%d칸 「%s」: %s — 빈틈이 됩니다" % [i + 1, card.display_name, banned]})
			continue
		if card.cost > energy:
			result.append({"slot": i, "serious": true, "text": "%d칸 「%s」: 내공이 모자라 빈틈이 됩니다 (내공 %d 필요, 이때 %d). 앞 칸에 운기조식을 두세요" % [i + 1, card.display_name, card.cost, energy]})
		elif card.momentum_cost > momentum and not card.effects.has("telegraph"):
			result.append({"slot": i, "serious": false, "text": "%d칸 「%s」: 기세 %d가 필요한데 확실한 기세는 %d입니다. 앞 칸에서 이기지 못하면 빈틈이 됩니다" % [i + 1, card.display_name, card.momentum_cost, momentum]})
		else:
			energy -= card.cost
			momentum -= card.momentum_cost
		if card.type == DuelCard.Type.FOCUS:
			energy = mini(unit.character.internal_energy_max, energy + FOCUS_ENERGY + unit.character.wisdom / 2)
			momentum = mini(MAX_MOMENTUM, momentum + 1)
		var seen: int = int(enemy_types[i]) if i < enemy_types.size() else -1
		if seen >= 0:
			var theirs: DuelCard.Type = seen
			var mine: DuelCard.Type = card.type
			if _beats(theirs, mine):
				result.append({"slot": i, "serious": false, "text": "%d칸: 상대의 %s이(가) 내 %s을(를) 이깁니다. %s을(를) 두면 유리합니다" % [
					i + 1, DuelCard.TYPE_NAMES[theirs], DuelCard.TYPE_NAMES[mine], DuelCard.TYPE_NAMES[counter_of(theirs)]]})
	var focus: int = plan.filter(func(c: Variant) -> bool: return c != null and c.type == DuelCard.Type.FOCUS).size()
	if focus >= 2 and focus * 2 >= plan.size():
		result.append({"slot": -1, "serious": false, "text": "운기조식이 %d칸입니다. 그 칸들은 무방비라 피해를 %d%% 받습니다" % [focus, roundi(FOCUS_TAKEN * 100)]})
	return result


## 유형 a가 유형 b를 이기는지 (상성 안내용)
static func _beats(a: DuelCard.Type, b: DuelCard.Type) -> bool:
	return advantage(DuelCard.make("", "", a, 0), DuelCard.make("", "", b, 0)) == 1
