class_name CombatSetup
extends RefCounted

## 전투 한 판의 구성. 전투 씬은 이 값만 보고 전장을 만든다.

var id: String = ""
var title: String = "전술 전투"
var enemies: Array[CharacterData] = []
var enemy_positions: Array[Vector2i] = []
var player_position: Vector2i = Vector2i(2, 5)
var blocked_tiles: Array[Vector2i] = []
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


func add_enemy(character: CharacterData, position: Vector2i) -> void:
	enemies.append(character)
	enemy_positions.append(position)
