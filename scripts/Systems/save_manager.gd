class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://save_slot_1.json"


static func save_game(state: Dictionary) -> Dictionary:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return {"success": false, "message": "세이브 파일을 쓸 수 없습니다."}
	file.store_string(JSON.stringify(state, "\t"))
	return {"success": true, "message": "게임을 저장했습니다."}


static func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"success": false, "message": "저장된 게임이 없습니다."}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"success": false, "message": "세이브 파일이 손상되었습니다."}
	return {"success": true, "message": "게임을 불러왔습니다.", "data": json.data}


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func serialize_character(character: CharacterData) -> Dictionary:
	return {
		"id": character.id,
		"display_name": character.display_name,
		"role": character.role,
		"strength": character.strength,
		"agility": character.agility,
		"wisdom": character.wisdom,
		"charisma": character.charisma,
		"internal_energy_max": character.internal_energy_max,
		"internal_energy_current": character.internal_energy_current,
		"level": character.level,
		"experience": character.experience,
		"age": character.age,
		"morality": character.morality,
	}


static func serialize_sect(sect: SectData) -> Dictionary:
	return {
		"sect_name": sect.sect_name,
		"leader_name": sect.leader_name,
		"gold": sect.gold,
		"food": sect.food,
		"reputation": sect.reputation,
		"research_points": sect.research_points,
		"disciple_count": sect.disciple_count,
		"max_disciples": sect.max_disciples,
		"library_level": sect.library_level,
		"training_ground_level": sect.training_ground_level,
		"treasury_level": sect.treasury_level,
	}


static func serialize_relationships(relationships: Array[RelationshipData]) -> Array:
	var result: Array = []
	for rel in relationships:
		result.append({
			"target_id": rel.target_id,
			"target_name": rel.target_name,
			"bond_type": rel.bond_type,
			"bond_strength": rel.bond_strength,
			"stage": rel.stage,
		})
	return result


static func serialize_legacy(records: Array[LegacyData]) -> Array:
	var result: Array = []
	for legacy in records:
		result.append({
			"predecessor_name": legacy.predecessor_name,
			"generation": legacy.generation,
			"legacy_points": legacy.legacy_points,
			"summary": legacy.summary,
			"ending_reached": legacy.ending_reached,
		})
	return result


static func deserialize_character(data: Dictionary) -> CharacterData:
	var character := CharacterData.new()
	character.id = data.get("id", "")
	character.display_name = data.get("display_name", "무명")
	character.role = data.get("role", CharacterData.Role.YOUNG_DISCIPLE)
	character.strength = data.get("strength", 10)
	character.agility = data.get("agility", 10)
	character.wisdom = data.get("wisdom", 10)
	character.charisma = data.get("charisma", 10)
	character.internal_energy_max = data.get("internal_energy_max", 100)
	character.internal_energy_current = data.get("internal_energy_current", 100)
	character.level = data.get("level", 1)
	character.experience = data.get("experience", 0)
	character.age = data.get("age", 18)
	character.morality = data.get("morality", 50)
	return character


static func deserialize_sect(data: Dictionary) -> SectData:
	var sect := SectData.new()
	sect.sect_name = data.get("sect_name", "청운검파")
	sect.leader_name = data.get("leader_name", "")
	sect.gold = data.get("gold", 500)
	sect.food = data.get("food", 300)
	sect.reputation = data.get("reputation", 50)
	sect.research_points = data.get("research_points", 0)
	sect.disciple_count = data.get("disciple_count", 12)
	sect.max_disciples = data.get("max_disciples", 30)
	sect.library_level = data.get("library_level", 1)
	sect.training_ground_level = data.get("training_ground_level", 1)
	sect.treasury_level = data.get("treasury_level", 1)
	return sect


static func deserialize_relationships(data: Array) -> Array[RelationshipData]:
	var result: Array[RelationshipData] = []
	for entry in data:
		var rel := RelationshipData.new()
		rel.target_id = entry.get("target_id", "")
		rel.target_name = entry.get("target_name", "")
		rel.bond_type = entry.get("bond_type", RelationshipData.BondType.MASTER_DISCIPLE)
		rel.bond_strength = entry.get("bond_strength", 0)
		rel.stage = entry.get("stage", 0)
		result.append(rel)
	return result


static func deserialize_legacy(data: Array) -> Array[LegacyData]:
	var result: Array[LegacyData] = []
	for entry in data:
		var legacy := LegacyData.new()
		legacy.predecessor_name = entry.get("predecessor_name", "")
		legacy.generation = entry.get("generation", 1)
		legacy.legacy_points = entry.get("legacy_points", 0)
		legacy.summary = entry.get("summary", "")
		legacy.ending_reached = entry.get("ending_reached", "")
		result.append(legacy)
	return result