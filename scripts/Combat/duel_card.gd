class_name DuelCard
extends RefCounted

## 초식 카드: 초식 배치 대결에서 칸에 놓는 한 수.
## 누구나 가진 기본 동작(베기·내려찍기·막기·피하기·운기조식)과, 익힌 무공에서 바뀐 초식이 있다.
## 유형끼리 상성이 있다: 강공은 막기를 깨고, 막기는 속공을 받아치고, 속공은 강공을 끊는다.
## 회피는 강공·속공을 흘리지만 술(암기·독)에 약하고, 술은 막기·회피를 뚫지만 속공에 끊긴다. 기(운기)는 무방비다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

enum Type { STRIKE, QUICK, GUARD, EVADE, FOCUS, TRICK }

const TYPE_NAMES: Dictionary = {
	Type.STRIKE: "강공", Type.QUICK: "속공", Type.GUARD: "막기",
	Type.EVADE: "회피", Type.FOCUS: "기", Type.TRICK: "술",
}
## 유형별 기본 속도 (같은 칸에서 누가 먼저 치는지: 카드 속도 × 10 + 신법)
const TYPE_SPEED: Dictionary = {
	Type.STRIKE: 1, Type.QUICK: 3, Type.GUARD: 2, Type.EVADE: 3, Type.FOCUS: 0, Type.TRICK: 2,
}

var id: String = ""
var display_name: String = ""
var type: Type = Type.QUICK
## 피해(공격 유형) 또는 회복(기 유형)
var power: int = 0
var speed: int = 1
## 내공 소모
var cost: int = 0
## 필요한 기세 (절초). 0이면 아무 때나
var momentum_cost: int = 0
var element: MartialArtData.FiveElement = MartialArtData.FiveElement.NONE
## 효과: stun(맞으면 상대의 다음 칸이 막힘), pierce(막기를 무시), ambush(상대 체력이 가득하면 1.5배),
## momentum(맞히면 기세 +1 더), heal(기 유형: power만큼 회복), combo(합격: 인연 깊은 동료와 함께 펼침),
## sweep(휩쓸기: 그 칸의 적 모두), telegraph(예고 절초: 기세 없이 나온다)
var effects: Array[String] = []
## 바뀌기 전 무공 id (기본 동작은 "")
var art_id: String = ""
## 숙련 단계 (0~3, 단계마다 피해 +10%). 그 무공을 MASTERY_PER_TIER번 쓸 때마다 한 단계
var tier: int = 0
const MASTERY_PER_TIER := 8


func is_offensive() -> bool:
	return type in [Type.STRIKE, Type.QUICK, Type.TRICK]


func get_type_name() -> String:
	return TYPE_NAMES[type]


## 카드 한 줄 설명: "유혼쾌영검 [속공] 피해 18 · 속도 3 · 내공 15"
func describe() -> String:
	var parts: PackedStringArray = ["%s [%s]" % [display_name, get_type_name()]]
	if type == Type.FOCUS:
		parts.append("회복 %d" % power if power > 0 else "내공·기세 회복")
	elif type == Type.GUARD:
		parts.append("받는 피해 감소, 속공 반격")
	elif type == Type.EVADE:
		parts.append("느린 공격을 흘림")
	else:
		parts.append("피해 %d" % power)
	parts.append("속도 %d" % speed)
	if cost > 0:
		parts.append("내공 %d" % cost)
	if momentum_cost > 0:
		parts.append("기세 %d" % momentum_cost)
	if tier > 0:
		parts.append("숙련 %d단" % tier)
	return " · ".join(parts)


static func make(card_id: String, card_name: String, card_type: Type, card_power: int, card_cost: int = 0, card_effects: Array[String] = []) -> DuelCard:
	var card := DuelCard.new()
	card.id = card_id
	card.display_name = card_name
	card.type = card_type
	card.power = card_power
	card.speed = TYPE_SPEED[card_type]
	card.cost = card_cost
	card.effects = card_effects
	return card


## 휩쓸기: 여럿과 싸울 때(포위·진형)만 쓰는 기본 동작. 그 칸의 적 모두를 친다 (고른 상대는 온전히, 나머지는 일부)
static func sweep_card() -> DuelCard:
	var effects: Array[String] = ["sweep"]
	return make("basic_sweep", "휩쓸기", Type.STRIKE, 10, 10, effects)


## 누구나 가진 기본 동작
static func basic_cards() -> Array[DuelCard]:
	return [
		make("basic_slash", "베기", Type.QUICK, 8),
		make("basic_chop", "내려찍기", Type.STRIKE, 14, 5),
		make("basic_guard", "막기", Type.GUARD, 0),
		make("basic_evade", "피하기", Type.EVADE, 0),
		make("basic_focus", "운기조식", Type.FOCUS, 0),
	]


## 합격: 줄에 함께 선 깊은 인연의 동료와 펼치는 강공 절초 (막기를 깨고 기세 2가 든다)
const COMBO_MOMENTUM := _Balance.DUEL_COMBO_MOMENTUM
const COMBO_POWER := _Balance.DUEL_COMBO_POWER


static func combo(partner: CharacterData) -> DuelCard:
	var effects: Array[String] = ["pierce", "combo"]
	var card: DuelCard = make("combo_" + partner.id, "합격 · %s" % partner.display_name, Type.STRIKE, COMBO_POWER + partner.strength, 0, effects)
	card.momentum_cost = COMBO_MOMENTUM
	return card


## 무공을 초식 카드로 바꾼다. 무공 데이터의 card_type이 있으면 그 유형, 없으면 성격으로 정한다.
static func from_art(art: MartialArtData) -> DuelCard:
	var card := DuelCard.new()
	card.id = art.id
	card.art_id = art.id
	card.display_name = art.display_name
	card.type = _type_for(art)
	card.power = art.heal_amount if card.type == Type.FOCUS else art.damage
	card.speed = TYPE_SPEED[card.type] + (1 if art.special_effects.has(MartialArtData.SpecialEffect.SPEED) else 0)
	card.cost = art.internal_cost
	card.element = art.element
	if art.special_effects.has(MartialArtData.SpecialEffect.CONTROL):
		card.effects.append("stun")
	if art.special_effects.has(MartialArtData.SpecialEffect.DESTRUCTION):
		card.effects.append("pierce")
	if art.special_effects.has(MartialArtData.SpecialEffect.AMBUSH):
		card.effects.append("ambush")
	if art.special_effects.has(MartialArtData.SpecialEffect.BUFF):
		card.effects.append("momentum")
	if card.type == Type.FOCUS:
		card.effects.append("heal")
	# 강한 초식은 기세를 모아야 펼칠 수 있는 절초가 된다
	if card.is_offensive():
		if art.damage >= 45:
			card.momentum_cost = 3
		elif art.damage >= 32:
			card.momentum_cost = 2
	return card


static func _type_for(art: MartialArtData) -> Type:
	if not art.card_type.is_empty() and Type.has(art.card_type):
		return Type[art.card_type]
	if art.heal_amount > 0:
		return Type.FOCUS
	if art.category == MartialArtData.Category.HIDDEN or art.range >= 3 or art.special_effects.has(MartialArtData.SpecialEffect.CONTROL):
		return Type.TRICK
	if art.category == MartialArtData.Category.QINGGONG:
		return Type.EVADE
	if art.special_effects.has(MartialArtData.SpecialEffect.SPEED) or art.category in [MartialArtData.Category.LEG, MartialArtData.Category.FINGER]:
		return Type.QUICK
	if art.special_effects.has(MartialArtData.SpecialEffect.DESTRUCTION) or art.action_cost >= 3 or art.damage >= 22:
		return Type.STRIKE
	return Type.QUICK


## 이 인물이 쓸 수 있는 모든 초식: 기본 동작 + 익힌 무공 (mastery: {무공 id: 쓴 횟수} → 숙련 단계)
static func cards_for(character: CharacterData, mastery: Dictionary = {}) -> Array[DuelCard]:
	var result: Array[DuelCard] = basic_cards()
	for art in character.martial_arts:
		var card: DuelCard = from_art(art)
		card.tier = clampi(int(mastery.get(art.id, 0)) / MASTERY_PER_TIER, 0, 3)
		result.append(card)
	return result
