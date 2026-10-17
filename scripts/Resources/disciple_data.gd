class_name DiscipleData
extends Resource

## 플레이어 문파의 제자 한 명. 명단은 SectData.disciples, 규칙은 DiscipleRoster.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 시설 담당 (DiscipleRoster.ASSIGNMENTS의 키, 없으면 "")
const NO_ASSIGNMENT := ""

@export var id: String = ""
@export var display_name: String = "무명"
@export var level: int = 1
@export var experience: int = 0
@export var strength: int = 10
@export var agility: int = 10
@export var wisdom: int = 10
@export var assignment: String = NO_ASSIGNMENT
## 방어전에 먼저 데려갈 제자
@export var deployed: bool = false
## 참전한 전투 수
@export var battles: int = 0
## 마지막으로 개별 수련한 계절 (-1이면 없음)
@export var last_train_turn: int = -1


func get_power() -> int:
	return strength + agility + level * 2


func get_next_level_experience() -> int:
	return _Balance.DISCIPLE_EXP_PER_LEVEL * level


## 경험치를 더하고 오른 레벨 수를 돌려준다. 레벨마다 무력·신법·지혜 +1
func gain_experience(amount: int) -> int:
	if amount <= 0 or level >= _Balance.DISCIPLE_MAX_LEVEL:
		return 0
	experience += amount
	var gained: int = 0
	while level < _Balance.DISCIPLE_MAX_LEVEL and experience >= get_next_level_experience():
		experience -= get_next_level_experience()
		level += 1
		strength += 1
		agility += 1
		wisdom += 1
		gained += 1
	if level >= _Balance.DISCIPLE_MAX_LEVEL:
		experience = 0
	return gained
