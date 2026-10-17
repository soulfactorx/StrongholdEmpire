class_name CombatUnit
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

const STATUS_NAMES: Dictionary = {
	"stunned": "기절",
	"empowered": "기세",
	"stun_immune": "기절 저항",
}

var character: CharacterData
var display_name: String
var is_player: bool = false
## 플레이어가 조종하는 아군 (제자 등)
var is_ally: bool = false
var grid_pos: Vector2i = Vector2i.ZERO
var hp: int = 100
var max_hp: int = 100
var action_points: int = 4
## 이번 차례에 남은 기본 공격 횟수
var basic_attacks_left: int = _Balance.BASIC_ATTACKS_PER_TURN
var max_action_points: int = 4
## 오행 판정과 속도에 쓰는 대표 무공 (가장 최근에 쓴 무공)
var active_martial_art: MartialArtData = null
var damage_scale: float = 1.0
## 상태 이름 → 남은 턴 수. 자기 턴이 끝날 때 1씩 줄어든다.
var statuses: Dictionary = {}


func _init(char: CharacterData, player: bool = false, ally: bool = false) -> void:
	character = char
	display_name = char.display_name
	is_player = player
	is_ally = ally
	max_hp = 80 + char.strength * 3 + char.level * 5
	hp = max_hp
	max_action_points = 3 + int(char.agility / 5.0)
	action_points = max_action_points
	if not char.martial_arts.is_empty():
		active_martial_art = char.martial_arts[0]


## 플레이어 편(주인공 또는 아군)인지
func is_friendly() -> bool:
	return is_player or is_ally


func get_speed() -> int:
	return character.agility + (active_martial_art.move_bonus if active_martial_art else 0)


func get_martial_arts() -> Array[MartialArtData]:
	return character.martial_arts


func get_active_element() -> MartialArtData.FiveElement:
	if active_martial_art == null:
		return MartialArtData.FiveElement.NONE
	return active_martial_art.element


## 기본 공격의 기준 피해 (배율 적용 전)
func get_basic_attack_base() -> int:
	var base: int = _Balance.BASE_ATTACK_DAMAGE if is_friendly() else _Balance.ENEMY_BASE_ATTACK_DAMAGE
	return base + character.strength


func scale_stats(hp_scale: float, new_damage_scale: float) -> void:
	max_hp = maxi(1, int(max_hp * hp_scale))
	hp = max_hp
	damage_scale = new_damage_scale


func add_status(status: String, turns: int) -> void:
	statuses[status] = maxi(statuses.get(status, 0), turns)


func has_status(status: String) -> bool:
	return statuses.get(status, 0) > 0


func tick_statuses() -> void:
	for status in statuses.keys():
		statuses[status] -= 1
		if statuses[status] <= 0:
			statuses.erase(status)


func get_status_text() -> String:
	var names: PackedStringArray = []
	for status in statuses:
		if status == "stun_immune":
			continue
		names.append("%s %d" % [STATUS_NAMES.get(status, status), statuses[status]])
	return ", ".join(names)


func restore_action_points() -> void:
	action_points = max_action_points
	basic_attacks_left = _Balance.BASIC_ATTACKS_PER_TURN


## 기본 공격을 할 수 있는지 (행동력 1과 이번 차례의 남은 횟수)
func can_basic_attack() -> bool:
	return action_points >= 1 and basic_attacks_left > 0


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)


func is_alive() -> bool:
	return hp > 0


func get_hp_ratio() -> float:
	return float(hp) / float(max_hp)
