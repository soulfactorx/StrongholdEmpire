class_name CombatUnit
extends RefCounted

var character: CharacterData
var display_name: String
var is_player: bool = false
var grid_pos: Vector2i = Vector2i.ZERO
var hp: int = 100
var max_hp: int = 100
var action_points: int = 4
var max_action_points: int = 4
var active_martial_art: MartialArtData = null
var target_id: String = ""
var damage_scale: float = 1.0


func _init(char: CharacterData, player: bool = false) -> void:
	character = char
	display_name = char.display_name
	is_player = player
	max_hp = 80 + char.strength * 3 + char.level * 5
	hp = max_hp
	max_action_points = 3 + int(char.agility / 5.0)
	action_points = max_action_points
	if not char.martial_arts.is_empty():
		active_martial_art = char.martial_arts[0]


func get_speed() -> int:
	return character.agility + (active_martial_art.move_bonus if active_martial_art else 0)


func scale_stats(hp_scale: float, new_damage_scale: float) -> void:
	max_hp = maxi(1, int(max_hp * hp_scale))
	hp = max_hp
	damage_scale = new_damage_scale


func get_attack_damage(base_damage: int) -> int:
	return maxi(1, int((base_damage + character.strength) * damage_scale))


func restore_action_points() -> void:
	action_points = max_action_points


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)


func is_alive() -> bool:
	return hp > 0


func get_hp_ratio() -> float:
	return float(hp) / float(max_hp)