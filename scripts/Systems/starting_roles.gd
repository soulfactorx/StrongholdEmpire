class_name StartingRoles
extends RefCounted

## 새 게임 시작 역할 정의. 능력치는 CharacterData 필드명과 같다.

const DEFAULT_ID := "young_disciple"

const ROLES: Array[Dictionary] = [
	{
		"id": "young_disciple",
		"title": "막내 제자",
		"description": "문파에 갓 입문한 막내 제자. 스승과의 유대와 기연으로 성장합니다.\n스파이·관리자·낭인 등 가장 많은 갈림길이 열려 있습니다.",
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
		"description": "어느 문파에도 속하지 않은 떠돌이 무인(무소속). 제자·시설 없이 몸 하나로 강호를 누빕니다.\n무공과 경지를 쌓아 전설이 되는 길을 노립니다.",
		"role": CharacterData.Role.WANDERER,
		"default_name": "독고휘",
		"stats": {
			"strength": 15, "agility": 15, "wisdom": 11, "charisma": 9,
			"internal_energy_max": 130, "age": 24, "morality": 50,
		},
		"experience": 50,
	},
	{
		"id": "mercenary",
		"title": "의뢰인",
		"description": "세력들의 임무를 계약으로 맡는 청부업자. 고른 문파에 거처를 두고 일감을 찾습니다.\n세력별 신용을 쌓아 객경으로 들어가거나, 계약을 깨고 한몫 챙길 수 있습니다.",
		"role": CharacterData.Role.MERCENARY,
		"default_name": "모용진",
		"stats": {
			"strength": 14, "agility": 13, "wisdom": 13, "charisma": 13,
			"internal_energy_max": 120, "age": 27, "morality": 45,
		},
		"experience": 100,
	},
	{
		"id": "manager",
		"title": "총관",
		"description": "문파의 살림을 맡은 중간관리자. 부서를 정해 문파를 굴리고 문주에게 건의합니다.\n신임을 쌓아 문주 자리를 잇거나, 실패가 쌓이면 강등됩니다.",
		"role": CharacterData.Role.MANAGER,
		"default_name": "남궁린",
		"stats": {
			"strength": 11, "agility": 11, "wisdom": 17, "charisma": 14,
			"internal_energy_max": 130, "age": 28, "morality": 55,
		},
		"experience": 120,
	},
	{
		"id": "spy",
		"title": "간자",
		"description": "소속 문파가 강호 세력 사이에 심어 둔 간자. 정보를 캐고 사보타주로 적을 흔듭니다.\n노출도가 차면 정체가 드러나니, 임무를 마치고 돌아오거나 자객의 길로 빠질 수 있습니다.",
		"role": CharacterData.Role.SPY,
		"default_name": "설무영",
		"stats": {
			"strength": 11, "agility": 17, "wisdom": 14, "charisma": 14,
			"internal_energy_max": 110, "age": 22, "morality": 50,
		},
		"experience": 80,
		"flags": ["spy_recruitment"],
	},
	{
		"id": "assassin",
		"title": "자객",
		"description": "어둠 속에서 표적을 처리하는 청부 자객. 표적 의뢰로 큰돈을 벌지만 현상금이 쌓입니다.\n은신으로 현상금을 낮추며 그림자 제국을 꿈꿉니다.",
		"role": CharacterData.Role.ASSASSIN,
		"default_name": "귀검",
		"stats": {
			"strength": 16, "agility": 16, "wisdom": 10, "charisma": 8,
			"internal_energy_max": 120, "age": 26, "morality": 35,
		},
		"experience": 100,
		"flags": ["assassin_path"],
	},
	{
		"id": "leader",
		"title": "문주",
		"description": "문파를 물려받은 젊은 문주. 문파 경영과 전쟁 지휘가 중심입니다.\n명성과 덕망을 쌓아 정파를 통일하세요.",
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


## 소속 문파 없이 시작하는 역할 (낭인)
static func is_unaffiliated(role_id: String) -> bool:
	return get_by_id(role_id)["role"] == CharacterData.Role.WANDERER


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
