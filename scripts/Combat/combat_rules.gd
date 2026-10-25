class_name CombatRules
extends RefCounted

## 전투 공통 규칙: 오행 상극, 회심, 날씨 배율. 한 칸 판정은 DuelRules가 한다.
## 지형(Terrain)은 전투 데이터의 terrain 항목과 전장 생성이 쓴다 (초식 배치 대결에서는 배경 정보).

const _Balance = preload("res://scripts/Systems/game_balance.gd")

enum Terrain { PLAIN, FOREST, WATER, HIGH }

const TERRAIN_NAMES: Dictionary = {
	Terrain.PLAIN: "평지",
	Terrain.FOREST: "수풀",
	Terrain.WATER: "물",
	Terrain.HIGH: "고지",
}

## 오행 상극: 키가 값을 이긴다 (목극토, 토극수, 수극화, 화극금, 금극목)
const ELEMENT_OVERCOMES: Dictionary = {
	MartialArtData.FiveElement.WOOD: MartialArtData.FiveElement.EARTH,
	MartialArtData.FiveElement.EARTH: MartialArtData.FiveElement.WATER,
	MartialArtData.FiveElement.WATER: MartialArtData.FiveElement.FIRE,
	MartialArtData.FiveElement.FIRE: MartialArtData.FiveElement.METAL,
	MartialArtData.FiveElement.METAL: MartialArtData.FiveElement.WOOD,
}

const NEIGHBORS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

## 회심을 쓸지 여부. 정확한 피해 값을 시험하는 테스트에서는 끈다.
static var randomness: bool = true
## 비: 화 초식 배율, 수 초식 배율
const RAIN_FIRE := 0.7
const RAIN_WATER := 1.2


static func element_modifier(attacker: MartialArtData.FiveElement, defender: MartialArtData.FiveElement) -> float:
	if ELEMENT_OVERCOMES.get(attacker) == defender:
		return _Balance.ELEMENT_ADVANTAGE
	if ELEMENT_OVERCOMES.get(defender) == attacker:
		return _Balance.ELEMENT_DISADVANTAGE
	return 1.0


## 회심(치명타) 확률: 신법이 높을수록 오른다.
static func crit_chance(attacker: CombatUnit) -> float:
	return minf(_Balance.CRIT_MAX, _Balance.CRIT_BASE + attacker.character.agility * _Balance.CRIT_PER_AGILITY)
