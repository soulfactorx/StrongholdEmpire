class_name CharacterData
extends Resource

enum Role {
	LEADER,
	MANAGER,
	YOUNG_DISCIPLE,
	WANDERER,
	SPY,
	ASSASSIN,
	MERCENARY,
}

@export var id: String = ""
@export var display_name: String = "무명"
@export var role: Role = Role.YOUNG_DISCIPLE

@export_group("기본 능력치")
@export var strength: int = 10
@export var agility: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

@export_group("내공")
@export var internal_energy_max: int = 100
@export var internal_energy_current: int = 100

@export_group("성장")
@export var level: int = 1
@export var experience: int = 0
@export var age: int = 18
@export var morality: int = 55

@export_group("무공")
@export var martial_arts: Array[MartialArtData] = []


func get_role_name() -> String:
	match role:
		Role.LEADER:
			return "문주"
		Role.MANAGER:
			return "중간관리자"
		Role.YOUNG_DISCIPLE:
			return "막내 제자"
		Role.WANDERER:
			return "낭인"
		Role.SPY:
			return "스파이"
		Role.ASSASSIN:
			return "암살자"
		Role.MERCENARY:
			return "의뢰인"
		_:
			return "알 수 없음"


func get_combat_power() -> int:
	return strength + agility + int(internal_energy_current * 0.1)


func restore_internal_energy() -> void:
	internal_energy_current = internal_energy_max


func spend_internal_energy(amount: int) -> bool:
	if internal_energy_current < amount:
		return false
	internal_energy_current -= amount
	return true


func learn_martial_art(art: MartialArtData) -> void:
	if knows_martial_art(art.id):
		return
	martial_arts.append(art)


func knows_martial_art(art_id: String) -> bool:
	for art in martial_arts:
		if art.id == art_id:
			return true
	return false


func get_martial_arts_text() -> String:
	if martial_arts.is_empty():
		return "습득 무공 없음"
	var names: PackedStringArray = []
	for art in martial_arts:
		names.append(art.display_name)
	return ", ".join(names)