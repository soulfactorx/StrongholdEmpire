class_name DiscipleRoster
extends RefCounted

## 플레이어 문파의 제자 명단: 생성·배치·수련·참전·전사. 명단 자체는 SectData.disciples에 있다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 배치할 수 있는 시설과 효과 설명
const ASSIGNMENTS: Dictionary = {
	"library": {"name": "서고", "effect": "지혜 %d마다 계절 연구점 +1" % _Balance.DISCIPLE_LIBRARY_WISDOM_PER_POINT},
	"training_ground": {"name": "무술장", "effect": "계절마다 수련 경험치 +%d" % _Balance.DISCIPLE_TRAINING_GROUND_EXP},
	"treasury": {"name": "금고", "effect": "지혜 %d마다 계절 금화 +1" % _Balance.DISCIPLE_TREASURY_WISDOM_PER_GOLD},
}

const SURNAMES: PackedStringArray = [
	"이", "김", "박", "최", "정", "강", "조", "윤", "장", "임", "한", "오", "서", "신", "권", "황", "안", "송", "류", "홍",
]
const GIVEN_NAMES: PackedStringArray = [
	"청운", "도경", "무진", "서하", "백린", "운학", "지산", "태령", "소연", "하진", "명우", "가람",
	"진혁", "설화", "도윤", "은결", "세현", "유하", "강비", "청아", "문호", "재운", "현무", "나래",
]


## 명단을 켜고 지금 제자 수만큼 제자를 만든다. (새 게임, 구버전 세이브, 다른 세력으로 옮겨 갈 때)
static func enable(sect: SectData) -> void:
	sect.use_roster = true
	sync(sect)


## 명단을 제자 수에 맞춘다. 늘면 새 제자를 들이고, 줄면 가장 약한 제자부터 내보낸다.
## (배치나 출전 지정이 없는 제자를 먼저 내보낸다)
static func sync(sect: SectData) -> void:
	while sect.disciples.size() < sect.disciple_count:
		sect.disciples.append(create_disciple(sect))
	while sect.disciples.size() > sect.disciple_count:
		sect.disciples.erase(_pick_leaving(sect))


static func _pick_leaving(sect: SectData) -> DiscipleData:
	var result: DiscipleData = null
	for disciple in sect.disciples:
		if result == null or _leave_order(disciple) < _leave_order(result):
			result = disciple
	return result


## 작을수록 먼저 떠난다: 맡은 일이 없는 제자 → 약한 제자
static func _leave_order(disciple: DiscipleData) -> int:
	var busy: int = 1000 if (disciple.assignment != DiscipleData.NO_ASSIGNMENT or disciple.deployed) else 0
	return busy + disciple.get_power()


static func create_disciple(sect: SectData) -> DiscipleData:
	var disciple := DiscipleData.new()
	disciple.id = "d_%d" % sect.next_disciple_id
	sect.next_disciple_id += 1
	disciple.display_name = SURNAMES[randi() % SURNAMES.size()] + GIVEN_NAMES[randi() % GIVEN_NAMES.size()]
	disciple.strength = randi_range(_Balance.DISCIPLE_STAT_MIN, _Balance.DISCIPLE_STAT_MAX)
	disciple.agility = randi_range(_Balance.DISCIPLE_STAT_MIN, _Balance.DISCIPLE_STAT_MAX)
	disciple.wisdom = randi_range(_Balance.DISCIPLE_STAT_MIN, _Balance.DISCIPLE_STAT_MAX)
	return disciple


static func get_disciple(sect: SectData, disciple_id: String) -> DiscipleData:
	for disciple in sect.disciples:
		if disciple.id == disciple_id:
			return disciple
	return null


## 특정 제자를 명단에서 뺀다 (전사 등).
static func remove_disciple(sect: SectData, disciple_id: String) -> bool:
	var disciple: DiscipleData = get_disciple(sect, disciple_id)
	if disciple == null:
		return false
	sect.disciples.erase(disciple)
	sect.disciple_count = sect.disciples.size()
	return true


# ── 배치 ──

static func get_slots(sect: SectData, facility: String) -> int:
	return SectManager.get_facility_level(sect, facility) * _Balance.DISCIPLE_SLOTS_PER_LEVEL


static func get_assigned(sect: SectData, facility: String) -> Array[DiscipleData]:
	var result: Array[DiscipleData] = []
	for disciple in sect.disciples:
		if disciple.assignment == facility:
			result.append(disciple)
	return result


## 제자를 시설에 배치한다. facility가 ""이면 배치를 푼다.
static func assign(sect: SectData, disciple_id: String, facility: String) -> Dictionary:
	var disciple: DiscipleData = get_disciple(sect, disciple_id)
	if disciple == null:
		return {"success": false, "message": "명단에 없는 제자입니다."}
	if facility == DiscipleData.NO_ASSIGNMENT:
		disciple.assignment = facility
		return {"success": true, "message": "%s의 배치를 풀었습니다." % disciple.display_name}
	if not ASSIGNMENTS.has(facility):
		return {"success": false, "message": "배치할 수 없는 곳입니다."}
	var name: String = ASSIGNMENTS[facility]["name"]
	if disciple.assignment == facility:
		return {"success": false, "message": "%s은(는) 이미 %s 담당입니다." % [disciple.display_name, name]}
	if get_assigned(sect, facility).size() >= get_slots(sect, facility):
		return {"success": false, "message": "%s 담당 자리가 없습니다. (%d자리, 시설을 확장하면 늘어납니다)" % [
			name, get_slots(sect, facility),
		]}
	disciple.assignment = facility
	return {"success": true, "message": "%s을(를) %s에 배치했습니다. (%s)" % [
		disciple.display_name, name, ASSIGNMENTS[facility]["effect"],
	]}


## 다음 배치로 돌린다: 없음 → 서고 → 무술장 → 금고 → 없음. 자리가 없는 곳은 건너뛴다.
static func cycle_assignment(sect: SectData, disciple_id: String) -> Dictionary:
	var disciple: DiscipleData = get_disciple(sect, disciple_id)
	if disciple == null:
		return {"success": false, "message": "명단에 없는 제자입니다."}
	var order: Array = [DiscipleData.NO_ASSIGNMENT] + ASSIGNMENTS.keys()
	var index: int = order.find(disciple.assignment)
	for step in range(1, order.size() + 1):
		var facility: String = order[(index + step) % order.size()]
		if facility == DiscipleData.NO_ASSIGNMENT:
			return assign(sect, disciple_id, facility)
		if get_assigned(sect, facility).size() < get_slots(sect, facility):
			return assign(sect, disciple_id, facility)
	return {"success": false, "message": "배치할 자리가 없습니다."}


## 배치로 얻는 계절 수입 보너스 {gold, research}. 예상 수지에도 쓴다.
static func get_income_bonus(sect: SectData) -> Dictionary:
	if not sect.use_roster:
		return {"gold": 0, "research": 0}
	var library_wisdom: int = 0
	var treasury_wisdom: int = 0
	for disciple in sect.disciples:
		if disciple.assignment == "library":
			library_wisdom += disciple.wisdom
		elif disciple.assignment == "treasury":
			treasury_wisdom += disciple.wisdom
	return {
		"gold": treasury_wisdom / _Balance.DISCIPLE_TREASURY_WISDOM_PER_GOLD,
		"research": library_wisdom / _Balance.DISCIPLE_LIBRARY_WISDOM_PER_POINT,
	}


## 계절 처리: 무술장 담당 제자의 수련. 보고 문구를 돌려준다.
static func on_season(sect: SectData) -> String:
	if not sect.use_roster:
		return ""
	var trained: int = 0
	var level_ups: int = 0
	for disciple in get_assigned(sect, "training_ground"):
		level_ups += disciple.gain_experience(_Balance.DISCIPLE_TRAINING_GROUND_EXP)
		trained += 1
	if trained == 0:
		return ""
	var text: String = "무술장 수련 제자 %d명" % trained
	if level_ups > 0:
		text += " (경지 상승 %d)" % level_ups
	return text


# ── 수련·출전 ──

## 개별 수련: 금화를 내고 경험치를 얻는다. 제자마다 계절에 한 번.
static func train(sect: SectData, disciple_id: String, turn: int) -> Dictionary:
	var disciple: DiscipleData = get_disciple(sect, disciple_id)
	if disciple == null:
		return {"success": false, "message": "명단에 없는 제자입니다."}
	if disciple.last_train_turn == turn:
		return {"success": false, "message": "%s은(는) 이번 계절에 이미 수련했습니다." % disciple.display_name}
	if disciple.level >= _Balance.DISCIPLE_MAX_LEVEL:
		return {"success": false, "message": "%s은(는) 더 오를 경지가 없습니다." % disciple.display_name}
	if not sect.spend_resources(_Balance.DISCIPLE_TRAIN_GOLD):
		return {"success": false, "message": "금화가 부족합니다. (%d 필요)" % _Balance.DISCIPLE_TRAIN_GOLD}
	disciple.last_train_turn = turn
	var gained: int = disciple.gain_experience(_Balance.DISCIPLE_TRAIN_EXP)
	var message: String = "%s 수련: 경험치 +%d (금화 -%d)" % [disciple.display_name, _Balance.DISCIPLE_TRAIN_EXP, _Balance.DISCIPLE_TRAIN_GOLD]
	if gained > 0:
		message += " — 경지가 올라 Lv.%d!" % disciple.level
	return {"success": true, "message": message}


static func get_deployed_count(sect: SectData) -> int:
	return sect.disciples.filter(func(d: DiscipleData) -> bool: return d.deployed).size()


## 출전 지정을 켜고 끈다. 방어전 참전 수(DEFENSE_ALLY_COUNT)까지만 지정할 수 있다.
static func toggle_deploy(sect: SectData, disciple_id: String) -> Dictionary:
	var disciple: DiscipleData = get_disciple(sect, disciple_id)
	if disciple == null:
		return {"success": false, "message": "명단에 없는 제자입니다."}
	if not disciple.deployed and get_deployed_count(sect) >= _Balance.DEFENSE_ALLY_COUNT:
		return {"success": false, "message": "출전은 %d명까지 지정할 수 있습니다." % _Balance.DEFENSE_ALLY_COUNT}
	disciple.deployed = not disciple.deployed
	return {"success": true, "message": "%s %s" % [disciple.display_name, "출전 지정" if disciple.deployed else "출전 해제"]}


## 방어전에 나설 제자: 출전 지정한 제자를 먼저, 나머지는 강한 순서
static func choose_combat_disciples(sect: SectData, count: int) -> Array[DiscipleData]:
	var ordered: Array[DiscipleData] = sect.disciples.duplicate()
	ordered.sort_custom(func(a: DiscipleData, b: DiscipleData) -> bool:
		if a.deployed != b.deployed:
			return a.deployed
		return a.get_power() > b.get_power()
	)
	return ordered.slice(0, mini(count, ordered.size()))


## 전투용 캐릭터. id는 제자 id와 같아서 전사·경험치를 명단에 되돌릴 수 있다.
static func to_character(disciple: DiscipleData, stat_bonus: int = 0) -> CharacterData:
	var character := CharacterData.new()
	character.id = disciple.id
	character.display_name = disciple.display_name
	character.role = CharacterData.Role.YOUNG_DISCIPLE
	character.level = disciple.level
	character.strength = disciple.strength + stat_bonus
	character.agility = disciple.agility + stat_bonus
	character.wisdom = disciple.wisdom
	character.charisma = 8
	character.internal_energy_max = _Balance.DISCIPLE_BASE_INTERNAL + disciple.level * _Balance.DISCIPLE_INTERNAL_PER_LEVEL
	character.restore_internal_energy()
	if disciple.martial_art:
		character.learn_martial_art(disciple.martial_art.duplicate(true))
	return character


# ── 전수 ──

## 전수받을 제자에게 필요한 레벨
static func get_transmit_level(art: MartialArtData) -> int:
	return ceili(float(art.complexity) / _Balance.TRANSMIT_COMPLEXITY_PER_LEVEL)


## 전수 비용(연구점). 문파 비전은 싸다.
static func get_transmit_cost(sect: SectData, art: MartialArtData) -> int:
	var cost: int = _Balance.TRANSMIT_RESEARCH_BASE + art.complexity * _Balance.TRANSMIT_RESEARCH_PER_COMPLEXITY
	if sect.secret_art and sect.secret_art.id == art.id:
		cost = roundi(cost * _Balance.TRANSMIT_SECRET_SCALE)
	return cost


## 주인공의 무공을 제자에게 전수한다. 제자는 무공 하나만 익히며, 새로 전수하면 바뀐다.
static func transmit(sect: SectData, disciple_id: String, art: MartialArtData) -> Dictionary:
	var disciple: DiscipleData = get_disciple(sect, disciple_id)
	if disciple == null or art == null:
		return {"success": false, "message": "전수할 제자나 무공이 없습니다."}
	if disciple.martial_art and disciple.martial_art.id == art.id:
		return {"success": false, "message": "%s은(는) 이미 [%s]을(를) 익혔습니다." % [disciple.display_name, art.display_name]}
	var need: int = get_transmit_level(art)
	if disciple.level < need:
		return {"success": false, "message": "[%s]은(는) Lv.%d 이상 제자에게만 전수할 수 있습니다." % [art.display_name, need]}
	var cost: int = get_transmit_cost(sect, art)
	if sect.research_points < cost:
		return {"success": false, "message": "연구점이 부족합니다. (%d 필요)" % cost}
	sect.research_points -= cost
	disciple.martial_art = art.duplicate(true)
	return {"success": true, "message": "%s에게 [%s]을(를) 전수했습니다. 방어전에서 이 무공을 씁니다. (연구점 -%d)" % [
		disciple.display_name, art.display_name, cost,
	]}


## 전투 뒤: 쓰러진 제자는 명단에서 빠지고, 살아남은 참전 제자는 경험을 얻는다. 전사한 제자 이름을 돌려준다.
static func apply_battle(sect: SectData, ally_ids: Array, fallen_ids: Array) -> PackedStringArray:
	var fallen_names: PackedStringArray = []
	for disciple_id in ally_ids:
		var disciple: DiscipleData = get_disciple(sect, disciple_id)
		if disciple == null:
			continue
		if disciple_id in fallen_ids:
			fallen_names.append(disciple.display_name)
			remove_disciple(sect, disciple_id)
		else:
			disciple.battles += 1
			disciple.gain_experience(_Balance.DISCIPLE_BATTLE_EXP)
	return fallen_names


## 문파전 전력 보너스: 제자 레벨 1을 넘는 단계의 합
static func get_war_power_bonus(sect: SectData) -> int:
	if not sect.use_roster:
		return 0
	var bonus: int = 0
	for disciple in sect.disciples:
		bonus += (disciple.level - 1) * _Balance.DISCIPLE_LEVEL_WAR_POWER
	return bonus
