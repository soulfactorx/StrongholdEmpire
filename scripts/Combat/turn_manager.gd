class_name TurnManager
extends RefCounted

var units: Array[CombatUnit] = []
var turn_order: Array[CombatUnit] = []
var current_index: int = 0
var round_number: int = 1


func setup(combat_units: Array[CombatUnit]) -> void:
	units = combat_units
	_rebuild_turn_order()
	current_index = 0


func _rebuild_turn_order() -> void:
	turn_order.clear()
	for unit in units:
		if unit.is_alive():
			turn_order.append(unit)
	turn_order.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		return a.get_speed() > b.get_speed()
	)


func get_current_unit() -> CombatUnit:
	if turn_order.is_empty():
		return null
	return turn_order[current_index]


func end_turn() -> CombatUnit:
	if turn_order.is_empty():
		return null

	var finished := get_current_unit()
	if finished:
		finished.restore_action_points()

	current_index += 1
	if current_index >= turn_order.size():
		current_index = 0
		round_number += 1
		_rebuild_turn_order()

	return get_current_unit()


func remove_unit(unit: CombatUnit) -> void:
	units.erase(unit)
	turn_order.erase(unit)
	if current_index >= turn_order.size():
		current_index = 0