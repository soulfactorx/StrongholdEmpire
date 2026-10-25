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
## 관계 보정(원한·라이벌 피해 가산)과 전투 후 유대 변화에 쓰는 관계 대상 id
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
## escape(빠져나가기) · protect(지키기) · capture(생포) · catch(쫓아가 붙잡기) · timed(시간 안에) ·
## endure(버텨 내기) · disarm(무기 떨구기) · hold_line(진지 사수)
var objective: String = "defeat_all"
## 우두머리·지킬 아군의 캐릭터 id와 이름
var objective_target: String = ""
var objective_target_name: String = ""
## 버틸 합 수 (survive)
var objective_rounds: int = 0
## 탈출 칸 (escape, 옛 격자 전투 호환)
var exit_tiles: Array[Vector2i] = []
## 날씨·시간 (Battlefield.WEATHERS)과 전장 모양 (Battlefield.KINDS, 배경 그림)
var weather: String = "clear"
var battlefield: String = ""
## 전장 배경으로 쓸 지역 id (비면 기본 전투 배경)
var region_id: String = ""
## 적 증원: [{round, character, position}] — 상대 줄 맨 뒤에 붙는다
var reinforcements: Array[Dictionary] = []
## 초식 배치 대결: 한 사람과 겨루는 최대 합 수 (0이면 기본 4). 넘기면 체력 비율이 낮은 쪽이 물러난다
var max_bouts: int = 0

## ── 전투 다양화 (docs/전투_다양화_설계.md) ──
## 형식 (Battlefield.FORMATS): duel 연전 · siege 포위 · formation 진형 · chase 추격 · stealth 잠입 · standoff 대치 · tournament 비무대회
var format: String = "duel"
## 전장 규칙 (Battlefield.STAGES, 비면 없음)
var stage: String = ""
## 우리 쪽 처지 (Battlefield.CONDITIONS)
var conditions: PackedStringArray = []
## 인물별 특성 {캐릭터 id: [특성]} (Battlefield.TRAITS: 광폭·예고 절초 등)
var traits: Dictionary = {}
## 인물별 진형 줄 {캐릭터 id: "front"·"back"} (진형), 동료 지시 {캐릭터 id: 지시} (DuelAI.ORDERS)
var rows: Dictionary = {}
var orders: Dictionary = {}
## 졸개 {캐릭터 id: true} — 포위·진형에서 칸이 MOOK_SLOTS개뿐
var mooks: Dictionary = {}
## 목표 수치: 시간 안에·버텨 내기의 합 수는 objective_rounds, 버텨 내기의 피해 한도·무기 떨구기 횟수는 objective_count
var objective_count: int = 0
## 추격: 내가 쫓기는지(escape) 쫓는지(catch)는 목표로 정한다
## 대치 뒤에 이어지는 형식 (비면 대치만으로 끝난다)
var standoff_then: String = ""
## 비무대회: 이긴 판 수 → 켤 플래그 {"2": "flag"}
var placement_flags: Dictionary = {}
## 싸우는 중의 사건 [{type, when, ...}] (Battlefield.EVENT_TYPES)
var events: Array = []
## 선택 도전 {type, value} (Battlefield.CHALLENGES)
var challenge: Dictionary = {}
## 숨은 증원 (잠입에서 경보가 울리면 나타남): [캐릭터]
var hidden_foes: Array[CharacterData] = []


func has_condition(condition: String) -> bool:
	return condition in conditions


func traits_of(character_id: String) -> Array:
	return traits.get(character_id, [])


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
