class_name SectData
extends Resource

@export var sect_name: String = "청운검파"
@export var leader_name: String = "청운검선"

@export_group("자원")
@export var gold: int = 500
@export var food: int = 300
@export var reputation: int = 50
@export var research_points: int = 0

@export_group("문파 규모")
@export var disciple_count: int = 12
@export var max_disciples: int = 30

@export_group("시설")
@export var library_level: int = 1
@export var training_ground_level: int = 1
@export var treasury_level: int = 1


func can_afford(gold_cost: int, food_cost: int = 0) -> bool:
	return gold >= gold_cost and food >= food_cost


func spend_resources(gold_cost: int, food_cost: int = 0) -> bool:
	if not can_afford(gold_cost, food_cost):
		return false
	gold -= gold_cost
	food -= food_cost
	return true