class_name CombatSetup
extends RefCounted

## 전투 한 판의 구성. 전투 씬은 이 값만 보고 전장을 만든다.

var id: String = ""
var title: String = "전술 전투"
var enemies: Array[CharacterData] = []
var enemy_positions: Array[Vector2i] = []
## 플레이어가 차례대로 직접 조종하는 아군
var allies: Array[CharacterData] = []
var ally_positions: Array[Vector2i] = []
## 아군이 문파 제자라면 전투에서 쓰러진 수만큼 문파 제자가 줄어든다
var allies_are_disciples: bool = false
var player_position: Vector2i = Vector2i(2, 5)
var blocked_tiles: Array[Vector2i] = []
## 칸 → CombatRules.Terrain. 없는 칸은 평지.
var terrain: Dictionary = {}
## 관계 보정(원한·라이벌 피해 보너스)과 전투 후 유대 변화에 쓰는 관계 대상 id
var relationship_target_id: String = ""
## 다수의 약한 적(도적 등)을 만들 때 쓰는 적 체력·피해 배율
var enemy_hp_scale: float = 1.0
var enemy_damage_scale: float = 1.0

## 승리 보상: experience, gold, reputation, strength, bond
var rewards: Dictionary = {}
## 패배 손실: gold, reputation, injury_ratio(전투 후 남는 내공 비율), bond
var defeat_penalty: Dictionary = {}
## 승리 시 true로 설정할 스토리 플래그
var victory_flag: String = ""


func set_terrain(tiles: Array[Vector2i], kind: CombatRules.Terrain) -> void:
	for tile in tiles:
		terrain[tile] = kind


func get_terrain(tile: Vector2i) -> CombatRules.Terrain:
	return terrain.get(tile, CombatRules.Terrain.PLAIN)


func add_ally(character: CharacterData, position: Vector2i) -> void:
	allies.append(character)
	ally_positions.append(position)


func add_enemy(character: CharacterData, position: Vector2i) -> void:
	enemies.append(character)
	enemy_positions.append(position)
