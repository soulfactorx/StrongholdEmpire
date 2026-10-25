class_name DuelAI
extends RefCounted

## 초식 배치: AI가 한 합의 칸을 채운다. 적과, 자동 전투의 아군이 쓴다.
## - 성향(NpcAgent 성향: 야망 → 강공, 신중 → 막기·회피, 탐욕 → 술)에 따라 유형을 고른다.
## - 상대가 지난 합에 그 칸에 낸 유형을 보고, counter_rate 확률로 그것을 이기는 유형을 고른다.
## - 내공이 모자라면 운기로 채우고, 기세가 차면 절초를 노린다.
## - 무공 초식은 한 합에 한 번씩만, 기본 동작은 여러 번 쓸 수 있다 (사람도 같은 규칙).

## 성향 → 유형 가중치에 더할 값 (성향 0~100을 100으로 나눠 곱한다)
const TRAIT_TYPES: Dictionary = {
	"ambition": {DuelCard.Type.STRIKE: 2.0},
	"caution": {DuelCard.Type.GUARD: 1.5, DuelCard.Type.EVADE: 1.0},
	"greed": {DuelCard.Type.TRICK: 1.5, DuelCard.Type.QUICK: 0.5},
	"benevolence": {DuelCard.Type.GUARD: 0.5, DuelCard.Type.FOCUS: 0.5},
	"loyalty": {DuelCard.Type.QUICK: 1.0},
}
## 무인의 성격(인물 데이터 combat_style, 없으면 무공으로 짐작) → 유형 가중치에 더할 값
const STYLE_TYPES: Dictionary = {
	"sword": {DuelCard.Type.QUICK: 1.0, DuelCard.Type.EVADE: 0.6},
	"fist": {DuelCard.Type.STRIKE: 1.0, DuelCard.Type.GUARD: 0.6},
	"hidden": {DuelCard.Type.TRICK: 1.4},
	"poison": {DuelCard.Type.TRICK: 1.0, DuelCard.Type.FOCUS: 0.4},
	"taoist": {DuelCard.Type.FOCUS: 0.6, DuelCard.Type.GUARD: 0.6},
	"mook": {},
}
## 동료 지시 (진형·포위): 이름과 유형 가중치
const ORDERS: Dictionary = {
	"attack": {"name": "공세", "weights": {DuelCard.Type.STRIKE: 1.0, DuelCard.Type.QUICK: 1.0}},
	"defend": {"name": "수비", "weights": {DuelCard.Type.GUARD: 1.5, DuelCard.Type.EVADE: 1.2}},
	"cover": {"name": "엄호", "weights": {DuelCard.Type.GUARD: 2.5}},
	"support": {"name": "보조", "weights": {DuelCard.Type.FOCUS: 1.5, DuelCard.Type.GUARD: 0.5}},
}
const BASE_WEIGHTS: Dictionary = {
	DuelCard.Type.STRIKE: 1.0, DuelCard.Type.QUICK: 1.0, DuelCard.Type.GUARD: 0.6,
	DuelCard.Type.EVADE: 0.5, DuelCard.Type.FOCUS: 0.3, DuelCard.Type.TRICK: 0.8,
}


## 이 칸에 놓을 수 있는지: 무공 초식과 합격은 한 합에 한 번
static func can_place(card: DuelCard, plan: Array) -> bool:
	if card.art_id.is_empty() and not card.effects.has("combo"):
		return true
	return not plan.any(func(c: Variant) -> bool: return c != null and c.id == card.id)


## 한 합의 배치. opponent_last: 상대가 지난 합에 칸마다 낸 유형 (int 또는 -1). traits: NpcAgent 성향
## options: {ctx(전장·조건 금지), allowed(쓸 수 있는 유형만), style(무인의 성격), mirror(모방: 따라 낼 유형들)}
## 지시(unit.order)와 광폭(unit.enraged)도 본다
static func plan(unit: CombatUnit, opponent_last: Array = [], traits: Dictionary = {}, counter_rate: float = 0.5, rng: RandomNumberGenerator = null, options_in: Dictionary = {}) -> Array[DuelCard]:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var weights: Dictionary = BASE_WEIGHTS.duplicate()
	for trait_key in traits:
		for type in TRAIT_TYPES.get(trait_key, {}):
			weights[type] = weights[type] + TRAIT_TYPES[trait_key][type] * float(traits[trait_key]) / 100.0
	var style: Dictionary = STYLE_TYPES.get(str(options_in.get("style", "")), {})
	for type in style:
		weights[type] = weights[type] + style[type]
	if not unit.is_player and ORDERS.has(unit.order) and (unit.is_ally or unit.order != "attack"):
		var order_weights: Dictionary = ORDERS[unit.order]["weights"]
		for type in order_weights:
			weights[type] = weights[type] + order_weights[type]
	if unit.enraged:
		weights[DuelCard.Type.GUARD] = 0.0
		weights[DuelCard.Type.STRIKE] = weights[DuelCard.Type.STRIKE] + 1.0
	var ctx: Dictionary = options_in.get("ctx", {})
	var allowed: Array = options_in.get("allowed", [])
	var mirror: Array = options_in.get("mirror", [])
	var result: Array[DuelCard] = []
	var energy: int = unit.character.internal_energy_current
	var momentum: int = unit.momentum
	for slot in unit.slot_count():
		var want: int = -1
		if slot < mirror.size() and int(mirror[slot]) >= 0:
			want = int(mirror[slot])
		elif slot < opponent_last.size() and int(opponent_last[slot]) >= 0 and rng.randf() < counter_rate:
			want = DuelRules.counter_of(int(opponent_last[slot]))
		var options: Array[DuelCard] = unit.cards.filter(func(c: DuelCard) -> bool:
			var usable: bool = c.cost <= energy and c.momentum_cost <= momentum and can_place(c, result)
			return usable and DuelRules.banned_reason(c, ctx).is_empty() and (allowed.is_empty() or c.type in allowed)
		)
		if options.is_empty():
			options = unit.cards.filter(func(c: DuelCard) -> bool: return c.cost == 0 and (allowed.is_empty() or c.type in allowed) and DuelRules.banned_reason(c, ctx).is_empty())
		var pick: DuelCard = null
		# 기세가 차면 절초부터
		var finishers: Array[DuelCard] = options.filter(func(c: DuelCard) -> bool: return c.momentum_cost > 0)
		if not finishers.is_empty() and want < 0:
			pick = _strongest(finishers)
		elif energy < unit.character.internal_energy_max * 0.25 and rng.randf() < 0.6:
			pick = _first_of(options, DuelCard.Type.FOCUS)
		if pick == null and want >= 0:
			pick = _strongest(options.filter(func(c: DuelCard) -> bool: return c.type == want))
		if pick == null:
			pick = _weighted(options, weights, rng)
		if pick == null:
			pick = options[0] if not options.is_empty() else unit.cards[0]
		result.append(pick)
		energy -= pick.cost
		momentum -= pick.momentum_cost
		if pick.type == DuelCard.Type.FOCUS:
			energy += DuelRules.FOCUS_ENERGY
			momentum += 1
	return result


static func _first_of(options: Array[DuelCard], type: DuelCard.Type) -> DuelCard:
	for card in options:
		if card.type == type:
			return card
	return null


static func _strongest(options: Array) -> DuelCard:
	var best: DuelCard = null
	for card in options:
		if best == null or card.power * (1.0 + 0.1 * card.tier) > best.power * (1.0 + 0.1 * best.tier):
			best = card
	return best


## 유형 가중치로 하나를 뽑고, 같은 유형 안에서는 강한 초식을 쓴다
static func _weighted(options: Array[DuelCard], weights: Dictionary, rng: RandomNumberGenerator) -> DuelCard:
	if options.is_empty():
		return null
	var types: Array = []
	var total: float = 0.0
	for card in options:
		if not card.type in types:
			types.append(card.type)
			total += float(weights.get(card.type, 0.5))
	var roll: float = rng.randf() * total
	for type in types:
		roll -= float(weights.get(type, 0.5))
		if roll <= 0.0:
			return _strongest(options.filter(func(c: DuelCard) -> bool: return c.type == type))
	return _strongest(options)


## 무인의 성격: 인물 데이터의 combat_style, 없으면 가장 많이 익힌 무공 갈래로 짐작
static func style_of(character: CharacterData) -> String:
	var style: String = str(NpcRoster.get_npc(character.id).get("combat_style", "")) if NpcRoster.has_npc(character.id) else ""
	if not style.is_empty():
		return style
	var counts: Dictionary = {}
	for art in character.martial_arts:
		var key: String = "sword" if art.category == MartialArtData.Category.SWORD else (
			"hidden" if art.category == MartialArtData.Category.HIDDEN else (
			"taoist" if art.category == MartialArtData.Category.INTERNAL else "fist"))
		counts[key] = int(counts.get(key, 0)) + 1
	var best: String = ""
	for key in counts:
		if best.is_empty() or counts[key] > counts[best]:
			best = key
	return best


## 겨룰 상대 고르기: 진형에서 술이 아니면 앞줄만, 체력 비율이 가장 낮은 상대 (가끔 다른 상대)
static func choose_target(unit: CombatUnit, card: DuelCard, opponents: Array, rng: RandomNumberGenerator, formation: bool = false) -> CombatUnit:
	var pool: Array = opponents.filter(func(o: CombatUnit) -> bool: return o.is_alive())
	if pool.is_empty():
		return null
	if formation and (card == null or card.type != DuelCard.Type.TRICK):
		var fronts: Array = pool.filter(func(o: CombatUnit) -> bool: return o.front)
		if not fronts.is_empty():
			pool = fronts
	if rng.randf() < 0.2:
		return pool[rng.randi() % pool.size()]
	var best: CombatUnit = pool[0]
	for other in pool:
		# 주인공을 먼저 노린다 (같으면)
		if other.get_hp_ratio() < best.get_hp_ratio() - 0.05 or (other.is_player and absf(other.get_hp_ratio() - best.get_hp_ratio()) <= 0.05):
			best = other
	return best