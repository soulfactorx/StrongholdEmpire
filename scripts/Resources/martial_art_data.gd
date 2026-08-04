class_name MartialArtData
extends Resource

enum Category {
	SWORD,
	PALM,
	FIST,
	LEG,
	FINGER,
	HIDDEN,
	QINGGONG,
	INTERNAL,
}

enum FiveElement {
	NONE,
	WOOD,
	FIRE,
	EARTH,
	METAL,
	WATER,
}

enum YinYang {
	YIN,
	YANG,
	BALANCED,
}

enum SpecialEffect {
	SPEED,
	DESTRUCTION,
	AMBUSH,
	CONTROL,
	HEAL,
	MOVE,
	RANGE,
	BUFF,
}

@export var id: String = ""
@export var display_name: String = "미명무공"
@export var category: Category = Category.SWORD
@export var element: FiveElement = FiveElement.NONE
@export var yin_yang: YinYang = YinYang.BALANCED
@export var special_effects: Array[SpecialEffect] = []

@export_group("연구")
@export var research_cost: int = 30
@export var complexity: int = 1

@export_group("전투")
@export var internal_cost: int = 15
@export var action_cost: int = 2
@export var damage: int = 10
@export var range: int = 1
@export var heal_amount: int = 0
@export var move_bonus: int = 0
@export var description: String = ""


func get_category_name() -> String:
	match category:
		Category.SWORD:
			return "검법"
		Category.PALM:
			return "장법"
		Category.FIST:
			return "권법"
		Category.LEG:
			return "퇴법"
		Category.FINGER:
			return "지법"
		Category.HIDDEN:
			return "암기"
		Category.QINGGONG:
			return "경공"
		Category.INTERNAL:
			return "내공심법"
		_:
			return "알 수 없음"


func get_element_name() -> String:
	match element:
		FiveElement.WOOD:
			return "목"
		FiveElement.FIRE:
			return "화"
		FiveElement.EARTH:
			return "토"
		FiveElement.METAL:
			return "금"
		FiveElement.WATER:
			return "수"
		_:
			return "무"


func get_yin_yang_name() -> String:
	match yin_yang:
		YinYang.YIN:
			return "음"
		YinYang.YANG:
			return "양"
		_:
			return "균형"


func get_effects_text() -> String:
	if special_effects.is_empty():
		return "없음"
	var names: PackedStringArray = []
	for effect in special_effects:
		names.append(_effect_name(effect))
	return ", ".join(names)


func _effect_name(effect: SpecialEffect) -> String:
	match effect:
		SpecialEffect.SPEED:
			return "속도"
		SpecialEffect.DESTRUCTION:
			return "파괴력"
		SpecialEffect.AMBUSH:
			return "기습"
		SpecialEffect.CONTROL:
			return "제어"
		SpecialEffect.HEAL:
			return "회복"
		SpecialEffect.MOVE:
			return "이동"
		SpecialEffect.RANGE:
			return "범위"
		SpecialEffect.BUFF:
			return "강화"
		_:
			return "?"


func get_summary() -> String:
	return "%s [%s·%s·%s] 데미지 %d" % [
		display_name,
		get_category_name(),
		get_element_name(),
		get_yin_yang_name(),
		damage,
	]