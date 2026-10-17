class_name StartingRoles
extends RefCounted

## 새 게임 시작 역할 정의. 능력치는 CharacterData 필드명과 같다.

const DEFAULT_ID := "young_disciple"

const ROLES: Array[Dictionary] = [
	{
		"id": "young_disciple",
		"title": "막내 제자",
		"description": "청운검파에 갓 입문한 제자. 스승과의 유대와 기연으로 성장합니다.\n스파이·관리자·낭인 등 가장 많은 갈림길이 열려 있습니다.",
		"role": CharacterData.Role.YOUNG_DISCIPLE,
		"default_name": "이청풍",
		"stats": {
			"strength": 12, "agility": 14, "wisdom": 16, "charisma": 11,
			"internal_energy_max": 120, "age": 18, "morality": 55,
		},
	},
	{
		"id": "wanderer",
		"title": "낭인",
		"description": "어느 문파에도 얽매이지 않은 떠돌이 무인. 청운검파에 객으로 머뭅니다.\n무공과 경지를 쌓아 전설이 되는 길을 노립니다.",
		"role": CharacterData.Role.WANDERER,
		"default_name": "독고휘",
		"stats": {
			"strength": 15, "agility": 15, "wisdom": 11, "charisma": 9,
			"internal_energy_max": 130, "age": 24, "morality": 50,
		},
		"experience": 50,
	},
	{
		"id": "leader",
		"title": "문주",
		"description": "몰락해 가는 청운검파를 물려받은 젊은 문주. 문파 경영과 전쟁 지휘가 중심입니다.\n명성과 덕망을 쌓아 정파를 통일하세요.",
		"role": CharacterData.Role.LEADER,
		"default_name": "청운도",
		"stats": {
			"strength": 13, "agility": 11, "wisdom": 15, "charisma": 16,
			"internal_energy_max": 150, "age": 32, "morality": 60,
		},
		"experience": 150,
		"sect": {"gold": 400, "reputation": 45},
	},
]


static func get_by_id(role_id: String) -> Dictionary:
	for entry in ROLES:
		if entry["id"] == role_id:
			return entry
	return ROLES[0]


static func create_character(role_id: String, display_name: String) -> CharacterData:
	var entry: Dictionary = get_by_id(role_id)
	var character := CharacterData.new()
	character.id = "player_001"
	character.display_name = display_name.strip_edges()
	if character.display_name.is_empty():
		character.display_name = entry["default_name"]
	character.role = entry["role"]
	var stats: Dictionary = entry["stats"]
	for key in stats:
		character.set(key, stats[key])
	character.restore_internal_energy()
	character.gain_experience(entry.get("experience", 0))
	return character


static func apply_sect_setup(role_id: String, sect: SectData, character: CharacterData) -> void:
	var entry: Dictionary = get_by_id(role_id)
	var overrides: Dictionary = entry.get("sect", {})
	for key in overrides:
		sect.set(key, overrides[key])
	if character.role == CharacterData.Role.LEADER:
		sect.leader_name = character.display_name
