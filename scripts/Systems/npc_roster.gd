class_name NpcRoster
extends RefCounted

## NPC 명부. data/npcs/*.json 한 파일이 한 명이다.
##
## 필드: id, display_name, title, sect_id, role(CharacterData.Role 이름), description,
##       level, stats{능력치}, scaling(선택), initial_bond(선택)
## scaling: { base_level, level_offset, per_level{능력치: 레벨당 증가} }
##   → 레벨 = max(base_level, 플레이어 레벨 + level_offset), 능력치는 base_level 대비 증가
## initial_bond: { type(RelationshipData.BondType 이름), strength, stage } — 새 게임 시작 관계
## martial_arts: [{ id(MartialArtLibrary), min_level }] — 해당 레벨 이상이면 그 무공을 쓴다
## war_specialty: 문파전 장수로 참전할 때 보너스를 주는 명령 (CHARGE, DEFEND, FLANK)

const NPC_DIR := "res://data/npcs/"
const STAT_FIELDS: PackedStringArray = [
	"strength", "agility", "wisdom", "charisma", "internal_energy_max", "age", "morality",
]

static var _npcs: Dictionary = {}
static var _loaded: bool = false


static func get_all() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for id in _npcs:
		result.append(_npcs[id])
	return result


static func has_npc(npc_id: String) -> bool:
	_ensure_loaded()
	return _npcs.has(npc_id)


static func get_npc(npc_id: String) -> Dictionary:
	_ensure_loaded()
	return _npcs.get(npc_id, {})


static func get_display_name(npc_id: String) -> String:
	return get_npc(npc_id).get("display_name", "무명")


## NPC 데이터로 캐릭터를 만든다. player를 주면 scaling에 따라 레벨을 맞춘다.
static func create_character(npc_id: String, player: CharacterData = null) -> CharacterData:
	var data: Dictionary = get_npc(npc_id)
	var character := CharacterData.new()
	if data.is_empty():
		push_warning("명부에 없는 NPC: %s" % npc_id)
		character.id = npc_id
		return character

	character.id = npc_id
	character.display_name = data["display_name"]
	character.role = CharacterData.Role.get(data.get("role", "WANDERER"), CharacterData.Role.WANDERER)
	character.level = int(data.get("level", 1))
	var stats: Dictionary = data.get("stats", {})
	for key in stats:
		character.set(key, int(stats[key]))

	var scaling: Dictionary = data.get("scaling", {})
	if player != null and not scaling.is_empty():
		var base_level: int = int(scaling.get("base_level", character.level))
		character.level = maxi(base_level, player.level + int(scaling.get("level_offset", 0)))
		var growth: int = character.level - base_level
		var per_level: Dictionary = scaling.get("per_level", {})
		for key in per_level:
			character.set(key, int(character.get(key)) + int(per_level[key]) * growth)

	for entry in data.get("martial_arts", []):
		if character.level >= int(entry.get("min_level", 1)):
			var art: MartialArtData = MartialArtLibrary.create_art(entry["id"])
			if art:
				character.learn_martial_art(art)

	character.restore_internal_energy()
	return character


## 어느 문파에도 속하지 않은 인물의 sect_id (낭인 등)
const NO_SECT := "none"


## 강호 정세의 인물 목록에 보일 인물인지. scaling만 있고 시작 관계가 없는 인물은 이름 없는 졸개로 본다.
## 플레이어와 함께 성장하는 이름 있는 인물은 "named": true로 목록에 올린다.
static func is_listed(npc: Dictionary) -> bool:
	if npc.get("named", false) == true or npc.has("initial_bond"):
		return true
	return not npc.has("scaling")


static func validate_npc_dict(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in ["id", "display_name", "sect_id"]:
		if not data.get(key) is String or String(data.get(key)).is_empty():
			errors.append("'%s'가 비어 있음" % key)
	if not CharacterData.Role.has(data.get("role", "")):
		errors.append("알 수 없는 역할: %s" % data.get("role"))
	for key in data.get("stats", {}):
		if not key in STAT_FIELDS:
			errors.append("알 수 없는 능력치: %s" % key)
	for key in data.get("scaling", {}).get("per_level", {}):
		if not key in STAT_FIELDS:
			errors.append("알 수 없는 성장 능력치: %s" % key)
	for entry in data.get("martial_arts", []):
		if not entry is Dictionary or not MartialArtLibrary.has_art(str(entry.get("id", ""))):
			errors.append("알 수 없는 무공: %s" % entry)
	if data.has("war_specialty") and not data["war_specialty"] in ["CHARGE", "DEFEND", "FLANK"]:
		errors.append("알 수 없는 장수 특기: %s" % data["war_specialty"])
	if data.has("portrait") and not ResourceLoader.exists("res://assets/art/" + str(data["portrait"])):
		errors.append("초상화 그림이 없음: assets/art/%s" % data["portrait"])
	if data.has("dialogue"):
		errors.append_array(DialogueLines.validate(data["dialogue"]))
	var bond: Variant = data.get("initial_bond")
	if bond != null and not RelationshipData.BondType.has(bond.get("type", "")):
		errors.append("알 수 없는 관계 유형: %s" % bond.get("type"))
	return errors


## extra_dirs(시나리오 전용 인물 등)가 있으면 이어서 읽는다.
static func reload_data(dir_path: String = NPC_DIR, extra_dirs: Array = []) -> void:
	_npcs.clear()
	_loaded = true
	var entries: Array[Dictionary] = ModLoader.load_json_dir(dir_path)
	for extra in extra_dirs:
		if DirAccess.dir_exists_absolute(str(extra)):
			entries.append_array(ModLoader.load_json_dir(str(extra)))
	for data in entries:
		var errors: PackedStringArray = validate_npc_dict(data)
		if _npcs.has(data.get("id")):
			errors.append("중복된 id")
		if not errors.is_empty():
			push_warning("NPC 정의 오류 (%s): %s" % [data["_path"], "; ".join(errors)])
			continue
		_npcs[data["id"]] = data


static func _ensure_loaded() -> void:
	if not _loaded:
		reload_data()
