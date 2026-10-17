class_name SectData
extends Resource

const _Balance = preload("res://scripts/Systems/game_balance.gd")

enum Alignment { RIGHTEOUS, UNORTHODOX, DEMONIC }

@export var id: String = ""
@export var sect_name: String = "청운검파"
@export var leader_name: String = "청운검선"
@export var alignment: Alignment = Alignment.RIGHTEOUS
## 문주 NPC id (NpcRoster). 플레이어가 문주가 되면 비워 둔다.
@export var leader_id: String = ""

@export_group("외교")
## 플레이어 문파에 대한 태도 (-100 적대 ~ 100 우호)
@export var attitude: int = 0
## 문파전에서 굴복시킨 세력인지 여부
@export var subjugated: bool = false
## 지난 문파전에서 플레이어가 쓴 명령 (SectWarManager.Command). 다음 작전 계획에 반영한다
@export var observed_commands: Array[int] = []

@export_group("자원")
@export var gold: int = 500
@export var food: int = 300
@export var reputation: int = 50
@export var research_points: int = 0

@export_group("문파 규모")
@export var disciple_count: int = 12
@export var max_disciples: int = 30

## 유지비를 다 내지 못한 계절이 연속으로 몇 번인지
@export var shortage_seasons: int = 0

@export_group("시설")
@export var library_level: int = 1
@export var training_ground_level: int = 1
@export var treasury_level: int = 1
## 약방: 계절마다 주인공의 내공 회복 (0이면 없음)
@export var apothecary_level: int = 0
## 연공실: 계절마다 주인공 수련 경험치 (0이면 없음)
@export var meditation_hall_level: int = 0


func can_afford(gold_cost: int, food_cost: int = 0) -> bool:
	return gold >= gold_cost and food >= food_cost


func spend_resources(gold_cost: int, food_cost: int = 0) -> bool:
	if not can_afford(gold_cost, food_cost):
		return false
	gold -= gold_cost
	food -= food_cost
	return true


## 계절 식량 유지비 (시나리오 유지비 배율 반영)
func get_food_upkeep() -> int:
	return roundi(disciple_count * _Balance.FOOD_PER_DISCIPLE * ScenarioRules.upkeep_scale())


## 시설이 시작 레벨을 넘은 단계 수의 합 (유지비 계산용)
func get_facility_steps() -> int:
	var steps: int = 0
	for facility in _Balance.FACILITIES:
		steps += maxi(0, int(get(facility + "_level")) - int(_Balance.FACILITIES[facility][0]))
	return steps


func get_gold_upkeep() -> int:
	var facility_steps: int = get_facility_steps()
	var base: int = disciple_count * _Balance.GOLD_PER_DISCIPLE + facility_steps * _Balance.FACILITY_UPKEEP_GOLD
	return roundi(base * ScenarioRules.upkeep_scale())


func get_alignment_name() -> String:
	match alignment:
		Alignment.RIGHTEOUS:
			return "정파"
		Alignment.UNORTHODOX:
			return "사파"
		Alignment.DEMONIC:
			return "마교"
	return "무소속"


func get_attitude_text() -> String:
	if attitude >= 50:
		return "우호"
	if attitude >= 10:
		return "호의"
	if attitude > -10:
		return "중립"
	if attitude > -50:
		return "경계"
	return "적대"
