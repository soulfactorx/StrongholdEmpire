class_name CombatLibrary
extends RefCounted

## 데이터로 정의한 전투 (data/combats/*.json, 시나리오의 combats/ 폴더).
## 스토리 아크처럼 기연에서 이어지는 전투를 코드 없이 추가한다. 형식은 docs/전투_데이터_형식.md 참고.

const COMBAT_DIR := "res://data/combats/"
const GRID_WIDTH := 16
const GRID_HEIGHT := 10
const TERRAIN_KEYS: Dictionary = {
	"FOREST": CombatRules.Terrain.FOREST,
	"WATER": CombatRules.Terrain.WATER,
	"HIGH": CombatRules.Terrain.HIGH,
}
const REWARD_KEYS: PackedStringArray = ["experience", "gold", "reputation", "strength", "bond"]
const PENALTY_KEYS: PackedStringArray = ["gold", "reputation", "injury_ratio", "bond"]
const STAT_KEYS: PackedStringArray = ["strength", "agility", "wisdom", "charisma", "internal_energy_max"]

static var _combats: Dictionary = {}
static var _loaded: bool = false


static func has_combat(combat_id: String) -> bool:
	_ensure_loaded()
	return _combats.has(combat_id)


static func get_ids() -> Array:
	_ensure_loaded()
	return _combats.keys()


static func get_definition(combat_id: String) -> Dictionary:
	_ensure_loaded()
	return _combats.get(combat_id, {})


## 전투 폴더를 다시 읽는다. extra_dirs(시나리오 전용 전투)가 있으면 이어서 읽는다.
static func reload_data(dir_path: String = COMBAT_DIR, extra_dirs: Array = []) -> void:
	_combats.clear()
	_loaded = true
	for i in extra_dirs.size() + 1:
		var current_dir: String = dir_path if i == 0 else str(extra_dirs[i - 1])
		if not DirAccess.dir_exists_absolute(current_dir):
			if i == 0:
				push_warning("전투 폴더를 열 수 없습니다: %s" % current_dir)
			continue
		for path in EventManager.collect_json_files(current_dir):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not data is Dictionary:
				push_warning("전투 JSON 파싱 실패: %s" % path)
				continue
			var errors: PackedStringArray = validate_combat_dict(data)
			if _combats.has(data.get("id")):
				errors.append("중복된 id: %s" % data.get("id"))
			if not errors.is_empty():
				push_warning("전투 정의 오류 (%s): %s" % [path, "; ".join(errors)])
				continue
			_combats[data["id"]] = data


static func _ensure_loaded() -> void:
	if not _loaded:
		reload_data()


## 전투 정의 하나를 검사해 오류 메시지 목록을 돌려준다.
static func validate_combat_dict(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in ["id", "title"]:
		if not data.get(key) is String or String(data.get(key)).is_empty():
			errors.append("'%s'가 비어 있음" % key)
	if CombatManager.COMBAT_IDS.has(str(data.get("id", ""))):
		errors.append("코드 전투 id와 겹침: %s" % data.get("id"))
	var enemies: Variant = data.get("enemies")
	if not enemies is Array or (enemies as Array).is_empty():
		errors.append("enemies가 비어 있음")
	else:
		_validate_units(enemies, "enemies", errors)
	_validate_units(data.get("allies", []), "allies", errors)
	for pos in data.get("disciple_allies", []):
		_validate_pos(pos, "disciple_allies", errors)
	if data.has("player_position"):
		_validate_pos(data["player_position"], "player_position", errors)
	for pos in data.get("blocked", []):
		_validate_pos(pos, "blocked", errors)
	var terrain: Variant = data.get("terrain", {})
	if not terrain is Dictionary:
		errors.append("terrain은 객체여야 함")
	else:
		for kind in terrain:
			if not TERRAIN_KEYS.has(kind):
				errors.append("알 수 없는 지형: %s" % kind)
			for pos in terrain[kind]:
				_validate_pos(pos, "terrain", errors)
	for key in data.get("rewards", {}):
		if not key in REWARD_KEYS:
			errors.append("알 수 없는 보상: %s" % key)
	for key in data.get("defeat_penalty", {}):
		if not key in PENALTY_KEYS:
			errors.append("알 수 없는 패배 손실: %s" % key)
	var target: String = str(data.get("relationship_target", ""))
	if not target.is_empty() and not NpcRoster.has_npc(target):
		errors.append("명부에 없는 관계 대상: %s" % target)
	for key in ["enemy_hp_scale", "enemy_damage_scale"]:
		if data.has(key) and not ((data[key] is float or data[key] is int) and data[key] > 0):
			errors.append("%s는 0보다 큰 숫자여야 함" % key)
	if data.has("weather") and not Battlefield.WEATHERS.has(str(data["weather"])):
		errors.append("알 수 없는 날씨: %s" % data["weather"])
	if data.has("battlefield") and not Battlefield.KINDS.has(str(data["battlefield"])):
		errors.append("알 수 없는 전장: %s" % data["battlefield"])
	_validate_units(data.get("reinforcements", []), "reinforcements", errors)
	for entry in data.get("reinforcements", []):
		if entry is Dictionary and int(entry.get("round", 0)) < 2:
			errors.append("증원 round는 2 이상")
	if data.has("objective"):
		_validate_objective(data, errors)
	return errors


static func _validate_objective(data: Dictionary, errors: PackedStringArray) -> void:
	var objective: Variant = data["objective"]
	if not objective is Dictionary or not Battlefield.OBJECTIVES.has(str(objective.get("type", ""))):
		errors.append("알 수 없는 전투 목표: %s" % objective)
		return
	match str(objective["type"]):
		"defeat_target", "protect":
			var group: Array = data.get("enemies", []) if objective["type"] == "defeat_target" else data.get("allies", [])
			if not group.any(func(u: Variant) -> bool: return u is Dictionary and u.get("npc") == objective.get("target")):
				errors.append("목표 인물이 %s에 없음: %s" % ["적" if objective["type"] == "defeat_target" else "아군", objective.get("target")])
		"survive":
			if int(objective.get("rounds", 0)) < 2:
				errors.append("버티기 목표에 rounds(2 이상) 필요")
		"escape":
			var tiles: Variant = objective.get("tiles", [])
			if not tiles is Array or (tiles as Array).is_empty():
				errors.append("탈출 목표에 tiles 필요")
			else:
				for pos in tiles:
					_validate_pos(pos, "objective tiles", errors)


static func _validate_units(units: Variant, label: String, errors: PackedStringArray) -> void:
	if not units is Array:
		errors.append("%s는 배열이어야 함" % label)
		return
	for unit in units:
		if not unit is Dictionary:
			errors.append("%s 항목은 객체여야 함" % label)
			continue
		if not NpcRoster.has_npc(str(unit.get("npc", ""))):
			errors.append("명부에 없는 인물: %s" % unit.get("npc"))
		_validate_pos(unit.get("position"), label, errors)
		for key in unit.get("stats", {}):
			if not key in STAT_KEYS:
				errors.append("알 수 없는 능력치: %s" % key)


static func _validate_pos(pos: Variant, label: String, errors: PackedStringArray) -> void:
	if not pos is Array or (pos as Array).size() != 2:
		errors.append("%s 좌표는 [x, y] 형식이어야 함" % label)
		return
	var x: int = int(pos[0])
	var y: int = int(pos[1])
	if x < 0 or x >= GRID_WIDTH or y < 0 or y >= GRID_HEIGHT:
		errors.append("%s 좌표가 전장 밖: [%d, %d]" % [label, x, y])


static func _to_pos(pos: Array) -> Vector2i:
	return Vector2i(int(pos[0]), int(pos[1]))


## 정의에 따라 전투 구성을 만든다. sect가 있으면 disciple_allies 자리에 문파 제자가 합류한다.
static func create(combat_id: String, player: CharacterData, sect: SectData = null) -> CombatSetup:
	var data: Dictionary = get_definition(combat_id)
	var setup := CombatSetup.new()
	setup.id = combat_id
	setup.title = data.get("title", "전술 전투")
	if data.has("player_position"):
		setup.player_position = _to_pos(data["player_position"])
	for pos in data.get("blocked", []):
		setup.blocked_tiles.append(_to_pos(pos))
	var terrain: Dictionary = data.get("terrain", {})
	for kind in terrain:
		var tiles: Array[Vector2i] = []
		for pos in terrain[kind]:
			tiles.append(_to_pos(pos))
		setup.set_terrain(tiles, TERRAIN_KEYS[kind])
	setup.relationship_target_id = data.get("relationship_target", "")
	setup.enemy_hp_scale = float(data.get("enemy_hp_scale", 1.0))
	setup.enemy_damage_scale = float(data.get("enemy_damage_scale", 1.0))
	setup.rewards = data.get("rewards", {}).duplicate()
	setup.defeat_penalty = data.get("defeat_penalty", {}).duplicate()
	setup.victory_flag = data.get("victory_flag", "")
	setup.defeat_flag = data.get("defeat_flag", "")

	var enemies: Array = data.get("enemies", [])
	for i in enemies.size():
		setup.add_enemy(_create_unit(enemies[i], player, i, enemies), _to_pos(enemies[i]["position"]))
	var allies: Array = data.get("allies", [])
	for i in allies.size():
		setup.add_ally(_create_unit(allies[i], player, i, allies), _to_pos(allies[i]["position"]))
	var reinforcements: Array = data.get("reinforcements", [])
	for i in reinforcements.size():
		setup.add_reinforcement(int(reinforcements[i]["round"]), _create_unit(reinforcements[i], player, i + enemies.size(), enemies + reinforcements), _to_pos(reinforcements[i]["position"]))
	setup.weather = str(data.get("weather", "clear"))
	_apply_objective(setup, data.get("objective", {}))
	# 지형을 직접 그리지 않고 전장 모양만 정했으면 전장을 만든다
	if data.has("battlefield") and not data.has("terrain") and not data.has("blocked"):
		Battlefield.generate(setup, str(data["battlefield"]), setup.unit_tiles())
	elif data.has("battlefield"):
		setup.battlefield = str(data["battlefield"])
	var disciple_positions: Array[Vector2i] = []
	for pos in data.get("disciple_allies", []):
		disciple_positions.append(_to_pos(pos))
	if sect and not disciple_positions.is_empty():
		CombatManager.add_disciple_allies(setup, sect, player, disciple_positions)
	return setup


static func _apply_objective(setup: CombatSetup, objective: Dictionary) -> void:
	if objective.is_empty():
		return
	setup.objective = str(objective["type"])
	match setup.objective:
		"defeat_target", "protect":
			var group: Array[CharacterData] = setup.enemies if setup.objective == "defeat_target" else setup.allies
			for character in group:
				if character.id == str(objective["target"]):
					setup.objective_target = character.id
					setup.objective_target_name = character.display_name
		"survive":
			setup.objective_rounds = int(objective["rounds"])
		"escape":
			for pos in objective["tiles"]:
				setup.exit_tiles.append(_to_pos(pos))


static func _create_unit(entry: Dictionary, player: CharacterData, index: int, group: Array) -> CharacterData:
	var npc_id: String = entry["npc"]
	var character: CharacterData = NpcRoster.create_character(npc_id, player)
	# 같은 인물(졸개 템플릿)이 여럿이면 구별되는 id를 준다.
	var same_count: int = group.filter(func(e: Dictionary) -> bool: return e["npc"] == npc_id).size()
	if same_count > 1:
		character.id = "%s_%d" % [npc_id, index]
	if entry.has("name"):
		character.display_name = entry["name"]
	var stats: Dictionary = entry.get("stats", {})
	for key in stats:
		character.set(key, int(character.get(key)) + int(stats[key]))
	character.restore_internal_energy()
	return character
