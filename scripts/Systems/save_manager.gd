class_name SaveManager
extends RefCounted

## 세이브 파일: 자동 저장 슬롯(0)과 수동 슬롯 1~SLOT_COUNT. 슬롯 1은 예전 단일 슬롯 파일과 같은 이름이다.
## 불러올 때 migrate()가 버전을 순서대로 올린다.

const SAVE_VERSION := 12
const SLOT_COUNT := 3
const AUTO_SLOT := 0

## 세이브 폴더. 테스트는 다른 폴더를 써서 실제 세이브를 건드리지 않는다.
static var save_dir: String = "user://"

## 버전별로 새로 생긴 항목과 기본값. 그 버전보다 오래된 세이브에 없으면 채운다.
## (캐릭터·문파 안의 새 필드는 deserialize_* 함수가 기본값을 넣는다)
const MIGRATIONS: Dictionary = {
	4: {"flag_turns": {}, "role_history": []},
	6: {"scenario_id": "cheonha", "scenario_overrides": {}},
	8: {"role_state": {}},
	10: {"observed_arts": {}, "analyzed_elements": []},
	11: {"challenge_target": ""},
	12: {"pending_invasion": "", "world_news": []},
}


static func get_slot_path(slot: int) -> String:
	if slot == AUTO_SLOT:
		return save_dir.path_join("save_auto.json")
	return save_dir.path_join("save_slot_%d.json" % slot)


static func is_valid_slot(slot: int) -> bool:
	return slot >= AUTO_SLOT and slot <= SLOT_COUNT


static func save_game(state: Dictionary, slot: int = 1) -> Dictionary:
	if not is_valid_slot(slot):
		return {"success": false, "message": "없는 저장 슬롯입니다."}
	DirAccess.make_dir_recursive_absolute(save_dir)
	var file := FileAccess.open(get_slot_path(slot), FileAccess.WRITE)
	if file == null:
		return {"success": false, "message": "세이브 파일을 쓸 수 없습니다."}
	file.store_string(JSON.stringify(state, "\t"))
	var where: String = "자동 저장" if slot == AUTO_SLOT else "슬롯 %d" % slot
	return {"success": true, "message": "게임을 저장했습니다. (%s)" % where}


static func load_game(slot: int = 1) -> Dictionary:
	if not is_valid_slot(slot) or not FileAccess.file_exists(get_slot_path(slot)):
		return {"success": false, "message": "저장된 게임이 없습니다."}
	var data: Variant = _read(slot)
	if not data is Dictionary:
		return {"success": false, "message": "세이브 파일이 손상되었습니다."}
	if int(data.get("version", 1)) > SAVE_VERSION:
		return {"success": false, "message": "더 새로운 버전의 게임에서 만든 세이브입니다."}
	return {"success": true, "message": "게임을 불러왔습니다.", "data": migrate(data)}


static func _read(slot: int) -> Variant:
	var file := FileAccess.open(get_slot_path(slot), FileAccess.READ)
	if file == null:
		return null
	return JSON.parse_string(file.get_as_text())


## 슬롯을 하나도 쓰지 않았으면 false. slot을 주면 그 슬롯만 본다.
static func has_save(slot: int = -1) -> bool:
	if slot >= 0:
		return FileAccess.file_exists(get_slot_path(slot))
	for i in range(AUTO_SLOT, SLOT_COUNT + 1):
		if FileAccess.file_exists(get_slot_path(i)):
			return true
	return false


static func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(get_slot_path(slot))


## 슬롯 목록에 보여 줄 요약: {exists, title, detail}. 세이브의 summary 항목을 읽는다.
static func get_slot_summary(slot: int) -> Dictionary:
	var label: String = "자동 저장" if slot == AUTO_SLOT else "슬롯 %d" % slot
	if not has_save(slot):
		return {"exists": false, "title": label, "detail": "비어 있음"}
	var data: Variant = _read(slot)
	if not data is Dictionary:
		return {"exists": true, "title": label, "detail": "손상된 세이브"}
	var summary: Dictionary = data.get("summary", {})
	var detail: String = "%s · %s (%s) · 제%d세대" % [
		summary.get("date", "?"), summary.get("name", "?"), summary.get("role", "?"), int(summary.get("generation", 1)),
	]
	if summary.get("ironman", false):
		detail += " · 철인"
	if not str(summary.get("ending", "")).is_empty():
		detail += " · " + str(summary["ending"])
	return {"exists": true, "title": "%s — 「%s」" % [label, summary.get("scenario", "")], "detail": detail}


## 오래된 세이브를 현재 버전으로 올린다. 버전마다 새로 생긴 항목에 기본값을 채운다.
static func migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data.get("version", 1))
	var steps: Array = MIGRATIONS.keys()
	steps.sort()
	for step in steps:
		if version >= step:
			continue
		var defaults: Dictionary = MIGRATIONS[step]
		for key in defaults:
			if not data.has(key):
				data[key] = defaults[key].duplicate() if defaults[key] is Dictionary or defaults[key] is Array else defaults[key]
	data["version"] = SAVE_VERSION
	return data


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


## 무공 하나(없으면 null)를 저장용 배열로 만든다.
static func _art_list(art: MartialArtData) -> Array[MartialArtData]:
	var result: Array[MartialArtData] = []
	if art:
		result.append(art)
	return result


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
			"enhance_level": art.enhance_level,
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
		"allied": sect.allied,
		"tribute": sect.tribute,
		"married": sect.married,
		"last_diplomacy_turn": sect.last_diplomacy_turn,
		"last_invasion_turn": sect.last_invasion_turn,
		"strategy": sect.strategy,
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
		"use_roster": sect.use_roster,
		"next_disciple_id": sect.next_disciple_id,
		"disciples": serialize_disciples(sect.disciples),
		"secret_art": serialize_martial_arts(_art_list(sect.secret_art)),
	}


static func serialize_disciples(disciples: Array[DiscipleData]) -> Array:
	var result: Array = []
	for disciple in disciples:
		result.append({
			"id": disciple.id,
			"display_name": disciple.display_name,
			"level": disciple.level,
			"experience": disciple.experience,
			"strength": disciple.strength,
			"agility": disciple.agility,
			"wisdom": disciple.wisdom,
			"assignment": disciple.assignment,
			"deployed": disciple.deployed,
			"battles": disciple.battles,
			"last_train_turn": disciple.last_train_turn,
			"martial_arts": serialize_martial_arts(_art_list(disciple.martial_art)),
		})
	return result


static func deserialize_disciples(data: Array) -> Array[DiscipleData]:
	var result: Array[DiscipleData] = []
	for entry in data:
		var disciple := DiscipleData.new()
		disciple.id = str(entry.get("id", ""))
		disciple.display_name = str(entry.get("display_name", "무명"))
		for key in ["level", "experience", "strength", "agility", "wisdom", "battles", "last_train_turn"]:
			disciple.set(key, int(entry.get(key, disciple.get(key))))
		disciple.assignment = str(entry.get("assignment", ""))
		disciple.deployed = bool(entry.get("deployed", false))
		var arts: Array[MartialArtData] = deserialize_martial_arts(entry.get("martial_arts", []))
		if not arts.is_empty():
			disciple.martial_art = arts[0]
		result.append(disciple)
	return result


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
		art.enhance_level = int(entry.get("enhance_level", 0))
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
	sect.allied = data.get("allied", false)
	sect.tribute = data.get("tribute", false)
	sect.married = data.get("married", false)
	sect.last_diplomacy_turn = int(data.get("last_diplomacy_turn", -1))
	sect.last_invasion_turn = int(data.get("last_invasion_turn", -1))
	sect.strategy = str(data.get("strategy", ""))
	for command in data.get("observed_commands", []):
		sect.observed_commands.append(int(command))
	var secret: Array[MartialArtData] = deserialize_martial_arts(data.get("secret_art", []))
	if not secret.is_empty():
		sect.secret_art = secret[0]
	# 제자 명단 (제자 수를 먼저 정한 뒤 켠다. 수가 다르면 명단 쪽에 맞춘다)
	if data.get("use_roster", false):
		sect.disciples = deserialize_disciples(data.get("disciples", []))
		sect.next_disciple_id = int(data.get("next_disciple_id", sect.disciples.size() + 1))
		sect.disciple_count = sect.disciples.size()
		sect.use_roster = true
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