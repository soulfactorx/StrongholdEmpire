class_name CharacterData
extends Resource

const _Balance = preload("res://scripts/Systems/game_balance.gd")

signal leveled_up(new_level: int)

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

@export_group("기본 자질")
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
## 초상화로 쓸 명부 인물 id (등장인물 선택 플레이). 비우면 신분 초상화
@export var portrait_id: String = ""
@export var morality: int = 55

@export_group("무공")
@export var martial_arts: Array[MartialArtData] = []


## 성향: 도덕 GOOD_MORALITY 이상이면 협(선), EVIL_MORALITY 이하면 마(악), 그 사이 중립
const GOOD_MORALITY := 65
const EVIL_MORALITY := 35


func get_alignment() -> String:
	if morality >= GOOD_MORALITY:
		return "good"
	if morality <= EVIL_MORALITY:
		return "evil"
	return "neutral"


func get_alignment_name() -> String:
	return {"good": "선(협객)", "neutral": "중립", "evil": "악(마도)"}[get_alignment()]


func get_role_name() -> String:
	return get_role_display_name(role)


static func get_role_display_name(role: Role) -> String:
	match role:
		Role.LEADER:
			return "문주"
		Role.MANAGER:
			return "총관"
		Role.YOUNG_DISCIPLE:
			return "막내 제자"
		Role.WANDERER:
			return "낭인"
		Role.SPY:
			return "간자"
		Role.ASSASSIN:
			return "자객"
		Role.MERCENARY:
			return "청부객"
		_:
			return "알 수 없음"


func get_combat_power() -> int:
	return strength + agility + int(internal_energy_current * 0.1)


static func get_experience_for_level(target_level: int) -> int:
	return _Balance.EXP_PER_LEVEL_STEP * target_level * (target_level - 1)


func get_next_level_experience() -> int:
	return get_experience_for_level(level + 1)


## 누적 수련을 더하고 도달한 만큼 경지업한다. 오른 경지 수를 반환한다.
func gain_experience(amount: int) -> int:
	if amount <= 0:
		return 0
	# 시나리오의 성장 속도 배율
	experience += maxi(1, roundi(amount * ScenarioRules.exp_scale()))
	var levels_gained: int = 0
	while level < _Balance.MAX_LEVEL and experience >= get_next_level_experience():
		level += 1
		levels_gained += 1
		strength += _Balance.LEVEL_UP_STAT_GAIN
		agility += _Balance.LEVEL_UP_STAT_GAIN
		wisdom += _Balance.LEVEL_UP_STAT_GAIN
		internal_energy_max += _Balance.LEVEL_UP_INTERNAL_GAIN
		restore_internal_energy()
		leveled_up.emit(level)
	return levels_gained


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


## 보유 무공 목록 (무공마다 범주·오행·전투 수치·효과)
func get_martial_arts_detail() -> String:
	if martial_arts.is_empty():
		return "아직 익힌 무공이 없습니다. 장경각에서 창안하거나 비급을 참오하세요."
	var lines: PackedStringArray = []
	for art in martial_arts:
		lines.append(art.get_detail_text())
	return "\n".join(lines)


func get_martial_arts_text() -> String:
	if martial_arts.is_empty():
		return "습득 무공 없음"
	var names: PackedStringArray = []
	for art in martial_arts:
		names.append(art.display_name)
	return ", ".join(names)