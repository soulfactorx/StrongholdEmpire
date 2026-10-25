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
## 플레이어 문파와 동맹인지 (문파전 원군, 공격 불가)
@export var allied: bool = false
## 굴복한 세력이 계절마다 공물을 바치는지
@export var tribute: bool = false
## 혼담으로 맺어졌는지
@export var married: bool = false
## 마지막으로 외교 행동을 한 계절 (-1이면 없음)
@export var last_diplomacy_turn: int = -1
## 세력 AI: 마지막으로 플레이어를 침공한 계절 (-1이면 없음)
@export var last_invasion_turn: int = -1
## 세력 AI 전략 (FactionStrategy id). 비면 성향별 기본값
@export var strategy: String = ""

@export_group("자원")
@export var gold: int = 500
@export var food: int = 300
@export var reputation: int = 50
@export var research_points: int = 0

@export_group("문파 규모")
## 제자 수. 명단을 쓰는 문파(플레이어 문파)는 값이 바뀌면 명단을 같은 수로 맞춘다.
## 그래서 기연·씀씀이·문파전처럼 제자 수만 바꾸는 코드도 명단과 어긋나지 않는다.
@export var disciple_count: int = 12:
	set(value):
		disciple_count = maxi(0, value)
		if use_roster:
			DiscipleRoster.sync(self)
@export var max_disciples: int = 30

## 씀씀이를 다 내지 못한 계절이 연속으로 몇 번인지
@export var shortage_seasons: int = 0

## 제자 명단 (use_roster일 때만 쓴다). 강호 세력은 제자 수만 쓴다.
var disciples: Array[DiscipleData] = []
var use_roster: bool = false
## 다음 제자 id 번호
var next_disciple_id: int = 1
## 문파 비전: 세대 전승 때 후계자가 물려받는 무공 (없으면 null)
var secret_art: MartialArtData = null

@export_group("전각")
@export var library_level: int = 1
@export var training_ground_level: int = 1
@export var treasury_level: int = 1
## 약방: 계절마다 주인공의 내공 회복 (0이면 없음)
@export var apothecary_level: int = 0
## 연공실: 계절마다 주인공 수련 (0이면 없음)
@export var meditation_hall_level: int = 0


func can_afford(gold_cost: int, food_cost: int = 0) -> bool:
	return gold >= gold_cost and food >= food_cost


func spend_resources(gold_cost: int, food_cost: int = 0) -> bool:
	if not can_afford(gold_cost, food_cost):
		return false
	gold -= gold_cost
	food -= food_cost
	return true


## 계절 식량 씀씀이 (시나리오 씀씀이 배율 반영)
func get_food_upkeep() -> int:
	return roundi(disciple_count * _Balance.FOOD_PER_DISCIPLE * ScenarioRules.upkeep_scale())


## 전각이 시작 단계를 넘은 단계 수의 합 (씀씀이 계산용)
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
