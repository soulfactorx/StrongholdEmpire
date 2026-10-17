class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://save_slot_1.json"
const SAVE_VERSION := 8


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
		"martial_arts": serialize_martial_arts(character.martial_arts),
	}


static func serialize_martial_arts(arts: Array[MartialArtData]) -> Array:
	var result: Array = []
	for art in arts:
		var effects: Array = []
		for effect in art.special_effects:
			effects.append(int(effect))
		result.append({
			"id": art.id,
			"display_name": art.display_name,
			"category": art.category,
			"element": art.element,
			"yin_yang": art.yin_yang,
			"special_effects": effects,
			"research_cost": art.research_cost,
			"complexity": art.complexity,
			"internal_cost": art.internal_cost,
			"action_cost": art.action_cost,
			"damage": art.damage,
			"range": art.range,
			"heal_amount": art.heal_amount,
			"move_bonus": art.move_bonus,
			"description": art.description,
		})
	return result


static func serialize_sect(sect: SectData) -> Dictionary:
	return {
		"id": sect.id,
		"alignment": sect.alignment,
		"leader_id": sect.leader_id,
		"attitude": sect.attitude,
		"subjugated": sect.subjugated,
		"observed_commands": sect.observed_commands,
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
		"apothecary_level": sect.apothecary_level,
		"meditation_hall_level": sect.meditation_hall_level,
		"shortage_seasons": sect.shortage_seasons,
	}


static func serialize_sects(sects: Array[SectData]) -> Array:
	var result: Array = []
	for sect in sects:
		result.append(serialize_sect(sect))
	return result


static func deserialize_sects(data: Array) -> Array[SectData]:
	var result: Array[SectData] = []
	for entry in data:
		result.append(deserialize_sect(entry))
	return result


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
	character.martial_arts = deserialize_martial_arts(data.get("martial_arts", []))
	return character


static func deserialize_martial_arts(data: Array) -> Array[MartialArtData]:
	var result: Array[MartialArtData] = []
	for entry in data:
		var art := MartialArtData.new()
		art.id = entry.get("id", "")
		art.display_name = entry.get("display_name", "미명무공")
		art.category = int(entry.get("category", MartialArtData.Category.SWORD))
		art.element = int(entry.get("element", MartialArtData.FiveElement.NONE))
		art.yin_yang = int(entry.get("yin_yang", MartialArtData.YinYang.BALANCED))
		for effect in entry.get("special_effects", []):
			art.special_effects.append(int(effect) as MartialArtData.SpecialEffect)
		art.research_cost = int(entry.get("research_cost", 30))
		art.complexity = int(entry.get("complexity", 1))
		art.internal_cost = int(entry.get("internal_cost", 15))
		art.action_cost = int(entry.get("action_cost", 2))
		art.damage = int(entry.get("damage", 10))
		art.range = int(entry.get("range", 1))
		art.heal_amount = int(entry.get("heal_amount", 0))
		art.move_bonus = int(entry.get("move_bonus", 0))
		art.description = entry.get("description", "")
		result.append(art)
	return result


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
	sect.apothecary_level = data.get("apothecary_level", 0)
	sect.meditation_hall_level = data.get("meditation_hall_level", 0)
	sect.shortage_seasons = data.get("shortage_seasons", 0)
	sect.id = data.get("id", "")
	sect.alignment = int(data.get("alignment", SectData.Alignment.RIGHTEOUS))
	sect.leader_id = data.get("leader_id", "")
	sect.attitude = int(data.get("attitude", 0))
	sect.subjugated = data.get("subjugated", false)
	for command in data.get("observed_commands", []):
		sect.observed_commands.append(int(command))
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