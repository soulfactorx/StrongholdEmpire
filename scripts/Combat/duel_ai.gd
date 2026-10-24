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
static func plan(unit: CombatUnit, opponent_last: Array = [], traits: Dictionary = {}, counter_rate: float = 0.5, rng: RandomNumberGenerator = null) -> Array[DuelCard]:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var weights: Dictionary = BASE_WEIGHTS.duplicate()
	for trait_key in traits:
		for type in TRAIT_TYPES.get(trait_key, {}):
			weights[type] = weights[type] + TRAIT_TYPES[trait_key][type] * float(traits[trait_key]) / 100.0
	var result: Array[DuelCard] = []
	var energy: int = unit.character.internal_energy_current
	var momentum: int = unit.momentum
	for slot in unit.slot_count():
		var want: int = -1
		if slot < opponent_last.size() and int(opponent_last[slot]) >= 0 and rng.randf() < counter_rate:
			want = DuelRules.counter_of(int(opponent_last[slot]))
		var options: Array[DuelCard] = unit.cards.filter(func(c: DuelCard) -> bool:
			return c.cost <= energy and c.momentum_cost <= momentum and can_place(c, result)
		)
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
			pick = unit.cards[0]
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
