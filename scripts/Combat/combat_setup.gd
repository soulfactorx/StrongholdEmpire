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
## 패배·후퇴 시 true로 설정할 스토리 플래그 (스토리 아크의 갈림길)
var defeat_flag: String = ""
## 세력 침공 방어전이면 침략한 세력 id
var invader_id: String = ""

## 전투 목표 (Battlefield.OBJECTIVES): defeat_all(모두 격파) · defeat_target(우두머리) · survive(버티기) ·
## escape(주인공이 탈출 칸에 닿기) · protect(아군 하나를 지키며 격파)
var objective: String = "defeat_all"
## 우두머리·지킬 아군의 캐릭터 id와 이름
var objective_target: String = ""
var objective_target_name: String = ""
## 버틸 라운드 수 (survive)
var objective_rounds: int = 0
## 탈출 칸 (escape)
var exit_tiles: Array[Vector2i] = []
## 날씨·시간 (Battlefield.WEATHERS)과 전장 모양 (Battlefield.KINDS, 배경 그림)
var weather: String = "clear"
var battlefield: String = ""
## 전장 배경으로 쓸 지역 id (비면 기본 전투 배경)
var region_id: String = ""
## 적 증원: [{round, character, position}] — 그 라운드 적군 턴이 시작될 때 나타난다
var reinforcements: Array[Dictionary] = []


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


func add_reinforcement(round_number: int, character: CharacterData, position: Vector2i) -> void:
	reinforcements.append({"round": round_number, "character": character, "position": position})


## 우두머리 목표: 적 하나를 정한다
func set_target_objective(character: CharacterData) -> void:
	objective = "defeat_target"
	objective_target = character.id
	objective_target_name = character.display_name


## 유닛이 서 있는 칸 (전장 생성에서 비워 둘 자리)
func unit_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = [player_position]
	result.append_array(enemy_positions)
	result.append_array(ally_positions)
	result.append_array(exit_tiles)
	for entry in reinforcements:
		result.append(entry["position"])
	return result
