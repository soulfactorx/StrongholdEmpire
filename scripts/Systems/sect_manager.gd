class_name SectManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")


## 계절 유지비를 낸다. 모자라면 제자 이탈·명성 하락이 생기고 연속 부족 계절이 늘어난다.
static func pay_upkeep(sect: SectData) -> Dictionary:
	var food_cost: int = sect.get_food_upkeep()
	var gold_cost: int = sect.get_gold_upkeep()
	var parts: PackedStringArray = ["유지비: 식량 -%d, 금화 -%d" % [food_cost, gold_cost]]
	var shortage: bool = false
	var deserted: int = 0

	sect.food -= food_cost
	if sect.food < 0:
		shortage = true
		var deficit: int = -sect.food
		sect.food = 0
		deserted = mini(
			sect.disciple_count,
			maxi(1, ceili(float(deficit) / _Balance.DESERTION_FOOD_PER_DISCIPLE))
		)
		sect.disciple_count -= deserted
		parts.append("식량 부족! 제자 %d명이 떠났습니다" % deserted)

	sect.gold -= gold_cost
	if sect.gold < 0:
		shortage = true
		sect.gold = 0
		var rep_loss: int = mini(sect.reputation, _Balance.GOLD_SHORTAGE_REPUTATION_LOSS)
		sect.reputation -= rep_loss
		parts.append("금화 부족! 급여가 밀려 명성 -%d" % rep_loss)

	if shortage:
		sect.shortage_seasons += 1
		parts.append(
			"(연속 부족 %d/%d계절)" % [sect.shortage_seasons, _Balance.SHORTAGE_GAME_OVER_SEASONS]
		)
	else:
		sect.shortage_seasons = 0

	return {
		"shortage": shortage,
		"deserted": deserted,
		"food_cost": food_cost,
		"gold_cost": gold_cost,
		"message": ", ".join(parts),
	}


static func train_disciples(sect: SectData, character: CharacterData) -> Dictionary:
	if sect.disciple_count >= sect.max_disciples:
		return {"success": false, "message": "제자 정원이 가득 찼습니다."}
	if not sect.spend_resources(_Balance.TRAIN_GOLD, _Balance.TRAIN_FOOD):
		return {"success": false, "message": "자원이 부족합니다. (금화 30, 식량 20 필요)"}

	sect.disciple_count += 1
	character.strength += 1
	character.agility += 1
	character.wisdom += 1
	character.gain_experience(10)
	return {"success": true, "message": "제자 훈련 완료! 문파 전력이 강해졌습니다."}


## 시설 정보: 이름과 효과 설명. 수치는 GameBalance.FACILITIES
const FACILITY_INFO: Dictionary = {
	"library": {"name": "서고", "effect": "연구점 수입과 무공 연구 성공률"},
	"training_ground": {"name": "무술장", "effect": "식량 수입, 문파전 전력, 제자 전투력"},
	"treasury": {"name": "금고", "effect": "금화 수입"},
	"apothecary": {"name": "약방", "effect": "계절마다 내공 회복"},
	"meditation_hall": {"name": "연공실", "effect": "계절마다 수련 경험치"},
}


static func get_facility_ids() -> Array:
	return _Balance.FACILITIES.keys()


static func get_facility_level(sect: SectData, facility: String) -> int:
	return int(sect.get(facility + "_level"))


## 다음 단계로 확장하는 비용. 최대 레벨이면 -1
static func get_upgrade_cost(sect: SectData, facility: String) -> int:
	var spec: Array = _Balance.FACILITIES[facility]
	var level: int = get_facility_level(sect, facility)
	if level >= spec[1]:
		return -1
	return spec[2] + spec[3] * (level - spec[0])


static func upgrade_facility(sect: SectData, facility: String) -> Dictionary:
	if not _Balance.FACILITIES.has(facility):
		return {"success": false, "message": "알 수 없는 시설입니다."}
	var name: String = FACILITY_INFO[facility]["name"]
	var cost: int = get_upgrade_cost(sect, facility)
	if cost < 0:
		return {"success": false, "message": "%s은(는) 이미 최고 수준입니다." % name}
	if not sect.spend_resources(cost):
		return {"success": false, "message": "금화가 부족합니다. (%d 필요)" % cost}
	var level: int = get_facility_level(sect, facility) + 1
	sect.set(facility + "_level", level)
	var verb: String = "지었습니다" if level == 1 and _Balance.FACILITIES[facility][0] == 0 else "확장했습니다"
	return {
		"success": true,
		"message": "%s을(를) %s (Lv.%d). %s 상승, 계절 유지비 금화 +%d" % [
			name, verb, level, FACILITY_INFO[facility]["effect"], _Balance.FACILITY_UPKEEP_GOLD,
		],
	}


## 이번 계절 수입 (적용 전 계산값). 역할 보정과 시나리오 수입 배율을 반영한다.
static func compute_seasonal_income(sect: SectData, character: CharacterData, season: String) -> Dictionary:
	var role_bonus: float = RoleManager.get_role_management_bonus(character.role)
	var bonus: Array = _Balance.SEASON_INCOME_BONUS.get(season, [0, 0, 0])
	var gold: float = (_Balance.BASE_GOLD_INCOME + sect.treasury_level * _Balance.TREASURY_GOLD_PER_LEVEL) * role_bonus
	var food: float = (_Balance.BASE_FOOD_INCOME + sect.training_ground_level * _Balance.TRAINING_FOOD_PER_LEVEL) * role_bonus
	var research: float = (
		sect.library_level * _Balance.LIBRARY_RESEARCH_PER_LEVEL
		+ int(character.wisdom * _Balance.WISDOM_RESEARCH_RATIO)
	) * role_bonus
	var scale: float = ScenarioRules.income_scale()
	# 서고·금고에 배치한 제자의 몫
	var roster_bonus: Dictionary = DiscipleRoster.get_income_bonus(sect)
	return {
		"gold": roundi((int(gold) + bonus[0]) * scale) + roster_bonus["gold"],
		"food": roundi((int(food) + bonus[1]) * scale),
		"research": roundi((int(research) + bonus[2]) * scale) + roster_bonus["research"],
	}


## 해마다 재고 손실: 안전량을 넘는 금화·식량의 일부가 사라진다.
static func apply_yearly_losses(sect: SectData) -> Dictionary:
	var gold_loss: int = int(maxi(0, sect.gold - _Balance.GOLD_SAFE_AMOUNT) * _Balance.GOLD_LOSS_RATE)
	var food_loss: int = int(maxi(0, sect.food - _Balance.FOOD_SAFE_AMOUNT) * _Balance.FOOD_SPOIL_RATE)
	sect.gold -= gold_loss
	sect.food -= food_loss
	var parts: PackedStringArray = []
	if gold_loss > 0:
		parts.append("쌓아 둔 재물을 노린 도둑과 관부의 수탈로 금화 -%d" % gold_loss)
	if food_loss > 0:
		parts.append("곳간의 곡식이 상해 식량 -%d" % food_loss)
	return {"gold_loss": gold_loss, "food_loss": food_loss, "message": ", ".join(parts)}


## 해마다 제자 수에 비례해 명성이 오른다.
static func apply_yearly_reputation(sect: SectData) -> int:
	var gain: int = sect.disciple_count / _Balance.DISCIPLES_PER_YEARLY_REPUTATION
	sect.reputation += gain
	return gain
