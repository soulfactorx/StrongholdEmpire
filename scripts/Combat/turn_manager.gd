class_name TurnManager
extends RefCounted

## 턴 진행: 아군 턴과 적군 턴을 번갈아 한다.
## 아군 턴에는 살아 있는 아군 누구든 골라 행동할 수 있고, [턴 종료]를 누르면 적군 턴으로 넘어간다.
## 적군 턴에는 적이 신법(속도) 순서로 하나씩 움직인다. 적군 턴이 끝나면 다음 라운드의 아군 턴이 된다.

enum Phase { PLAYER, ENEMY }

var units: Array[CombatUnit] = []
var phase: Phase = Phase.PLAYER
var round_number: int = 1


func setup(combat_units: Array[CombatUnit]) -> void:
	units = combat_units
	round_number = 1
	phase = Phase.PLAYER
	for unit in get_friendlies():
		unit.restore_action_points()


func is_player_phase() -> bool:
	return phase == Phase.PLAYER


func get_friendlies() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in units:
		if unit.is_alive() and unit.is_friendly():
			result.append(unit)
	return result


## 이번 적군 턴에 움직일 적: 빠른 순서
func get_enemy_order() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in units:
		if unit.is_alive() and not unit.is_friendly():
			result.append(unit)
	result.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool: return a.get_speed() > b.get_speed())
	return result


## 아군 턴을 마치고 적군 턴을 시작한다. 적의 행동력을 채운다.
func begin_enemy_phase() -> void:
	phase = Phase.ENEMY
	for unit in get_enemy_order():
		unit.restore_action_points()


## 적군 턴을 마치고 다음 라운드의 아군 턴을 시작한다. 아군의 행동력을 채운다.
func begin_player_phase() -> void:
	round_number += 1
	phase = Phase.PLAYER
	for unit in get_friendlies():
		unit.restore_action_points()
