class_name CombatUnit
extends RefCounted

## 대결에 나선 한 사람: 체력·배율·상태와 초식 배치 대결의 기세·초식.

const STATUS_NAMES: Dictionary = {
	"stunned": "기절",
	"stun_immune": "기절 저항",
}

var character: CharacterData
var display_name: String
var is_player: bool = false
## 주인공 편에서 함께 싸우는 동료 (제자·인연 인물)
var is_ally: bool = false
var hp: int = 100
var max_hp: int = 100
var damage_scale: float = 1.0
## 상태 이름 → 남은 칸 수 (기절은 다음 칸에서 쓰이고, 기절 저항은 칸마다 준다)
var statuses: Dictionary = {}
## 초식 배치 대결: 기세(0~5, 절초에 쓴다)와 쓸 수 있는 초식
var momentum: int = 0
var cards: Array[DuelCard] = []
## 인연 배율: 지금 상대에게 주는 피해(원한·연모 등), 받는 피해를 나누는 가호(함께 싸우는 깊은 인연)
var bond_attack: float = 1.0
var bond_guard: float = 1.0
## 전투 다양화: 특성(광폭·예고 절초 등, Battlefield.TRAITS), 진형 앞줄 여부, 동료 지시(DuelAI.ORDERS)
var traits: Array = []
var front: bool = true
var order: String = "attack"
## 칸 수 보정(부상 -1, 광폭 +1)과 상한(졸개 2, 0이면 없음)
var slot_bonus: int = 0
var slot_cap: int = 0
## 광폭이 시작됐는지, 단계 전환으로 다시 일어났는지
var enraged: bool = false
var second_phase: bool = false


func _init(char: CharacterData, player: bool = false, ally: bool = false) -> void:
	character = char
	display_name = char.display_name
	is_player = player
	is_ally = ally
	max_hp = 80 + char.strength * 3 + char.level * 5
	hp = max_hp


func scale_stats(hp_scale: float, new_damage_scale: float) -> void:
	max_hp = maxi(1, int(max_hp * hp_scale))
	hp = max_hp
	damage_scale = new_damage_scale


func add_status(status: String, turns: int) -> void:
	statuses[status] = maxi(statuses.get(status, 0), turns)


func has_status(status: String) -> bool:
	return statuses.get(status, 0) > 0


func get_status_text() -> String:
	var names: PackedStringArray = []
	for status in statuses:
		if status == "stun_immune":
			continue
		names.append("%s %d" % [STATUS_NAMES.get(status, status), statuses[status]])
	return ", ".join(names)


## 한 합에 놓을 수 있는 칸 수: 경지에 따라 3~6
func slot_count() -> int:
	var level: int = character.level
	var count: int = 3 + (1 if level >= 5 else 0) + (1 if level >= 10 else 0) + (1 if level >= 15 else 0) + slot_bonus
	if slot_cap > 0:
		count = mini(count, slot_cap)
	return clampi(count, 1, 7)


func has_trait(trait_name: String) -> bool:
	return trait_name in traits


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)


func is_alive() -> bool:
	return hp > 0


func get_hp_ratio() -> float:
	return float(hp) / float(max_hp)
