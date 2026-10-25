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
	_validate_variety(data, errors)
	return errors


## 전투 다양화 필드 (docs/전투_다양화_설계.md): 형식·전장·조건·특성·줄·지시·사건·도전·숨은 증원
static func _validate_variety(data: Dictionary, errors: PackedStringArray) -> void:
	var format: String = str(data.get("format", "duel"))
	if not Battlefield.FORMATS.has(format):
		errors.append("알 수 없는 전투 형식: %s" % format)
	if data.has("stage") and not Battlefield.STAGES.has(str(data["stage"])):
		errors.append("알 수 없는 전장 규칙: %s" % data["stage"])
	for condition in data.get("conditions", []):
		if not Battlefield.CONDITIONS.has(str(condition)):
			errors.append("알 수 없는 조건: %s" % condition)
	for group in ["enemies", "allies", "hidden", "reinforcements"]:
		var units: Variant = data.get(group, [])
		if not units is Array:
			continue
		for unit in units:
			if not unit is Dictionary:
				continue
			for t in unit.get("traits", []):
				if not Battlefield.TRAITS.has(str(t)):
					errors.append("알 수 없는 특성: %s" % t)
			if unit.has("row") and not str(unit["row"]) in ["front", "back"]:
				errors.append("줄은 front·back: %s" % unit["row"])
			if unit.has("order") and not DuelAI.ORDERS.has(str(unit["order"])):
				errors.append("알 수 없는 지시: %s" % unit["order"])
	_validate_units(data.get("hidden", []), "hidden", errors)
	if data.has("standoff_then") and not Battlefield.FORMATS.has(str(data["standoff_then"])):
		errors.append("알 수 없는 대치 뒤 형식: %s" % data["standoff_then"])
	if data.has("standoff_then") and format != "standoff":
		errors.append("standoff_then은 대치 형식에만")
	if data.has("placement_flags") and format != "tournament":
		errors.append("placement_flags는 비무대회 형식에만")
	var challenge: Variant = data.get("challenge", {})
	if not challenge is Dictionary or (not challenge.is_empty() and not Battlefield.CHALLENGES.has(str(challenge.get("type", "")))):
		errors.append("알 수 없는 도전: %s" % challenge)
	var events: Variant = data.get("events", [])
	if not events is Array:
		errors.append("events는 배열이어야 함")
		return
	for event in events:
		if not event is Dictionary or not str(event.get("type", "")) in Battlefield.EVENT_TYPES:
			errors.append("알 수 없는 사건: %s" % event)
			continue
		var when: Variant = event.get("when", {})
		if not when is Dictionary or when.is_empty() or not when.keys().all(func(k: Variant) -> bool: return str(k) in Battlefield.EVENT_WHEN):
			errors.append("사건 when은 bout·player_hp_below·enemy_hp_below 중 하나: %s" % event.get("type"))
		match str(event["type"]):
			"reinforce":
				_validate_units([event], "사건 증원", errors)
			"betrayal", "bond_intervene":
				if not NpcRoster.has_npc(str(event.get("npc", ""))):
					errors.append("사건 인물이 명부에 없음: %s" % event.get("npc"))
				if event["type"] == "betrayal" and not data.get("allies", []).any(func(u: Variant) -> bool: return u is Dictionary and u.get("npc") == event.get("npc")):
					errors.append("배신할 인물이 아군에 없음: %s" % event.get("npc"))
		for choice in event.get("choices", []):
			if not choice is Dictionary or str(choice.get("label", "")).is_empty() or not str(choice.get("action", "fight")) in Battlefield.CHOICE_ACTIONS:
				errors.append("사건 선택지는 label과 action(%s)이 필요: %s" % [", ".join(Battlefield.CHOICE_ACTIONS), choice])
			elif choice.has("check") and not str(choice["check"].get("stat", "")) in STAT_KEYS:
				errors.append("선택지 판정 자질: %s" % choice["check"])
			if choice is Dictionary:
				for effect in choice.get("effects", []):
					EventManager._validate_effect(effect, errors)


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
		"survive", "timed", "hold_line":
			if int(objective.get("rounds", 0)) < 2:
				errors.append("%s 목표에 rounds(2 이상) 필요" % objective["type"])
		"endure":
			if int(objective.get("rounds", 0)) < 2 or int(objective.get("damage", 0)) < 1:
				errors.append("버텨 내기 목표에 rounds(2 이상)와 damage 필요")
		"disarm":
			if int(objective.get("count", 0)) < 1:
				errors.append("무기 떨구기 목표에 count 필요")
		"capture", "catch":
			if objective.has("target") and not data.get("enemies", []).any(func(u: Variant) -> bool: return u is Dictionary and u.get("npc") == objective.get("target")):
				errors.append("목표 인물이 적에 없음: %s" % objective.get("target"))
			elif objective["type"] == "capture" and not objective.has("target"):
				errors.append("생포 목표에 target 필요")
		"escape":
			# tiles는 옛 격자 전투의 탈출 칸 (선택, 대결에서는 쓰지 않는다)
			var tiles: Variant = objective.get("tiles", [])
			if not tiles is Array:
				errors.append("탈출 목표의 tiles는 배열이어야 함")
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
		# 좌표는 옛 격자 전투 호환용이라 없어도 된다
		if unit.has("position"):
			_validate_pos(unit.get("position"), label, errors)
		for key in unit.get("stats", {}):
			if not key in STAT_KEYS:
				errors.append("알 수 없는 자질: %s" % key)


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
		setup.add_enemy(_create_unit(enemies[i], player, i, enemies), _to_pos(enemies[i].get("position", [12, 5])))
	var allies: Array = data.get("allies", [])
	for i in allies.size():
		setup.add_ally(_create_unit(allies[i], player, i, allies), _to_pos(allies[i].get("position", [2, 4])))
	var reinforcements: Array = data.get("reinforcements", [])
	for i in reinforcements.size():
		setup.add_reinforcement(int(reinforcements[i]["round"]), _create_unit(reinforcements[i], player, i + enemies.size(), enemies + reinforcements), _to_pos(reinforcements[i].get("position", [15, 5])))
	setup.weather = str(data.get("weather", "clear"))
	_apply_objective(setup, data.get("objective", {}))
	_apply_variety(setup, data, player)
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
		"survive", "timed", "hold_line":
			setup.objective_rounds = int(objective["rounds"])
		"endure":
			setup.objective_rounds = int(objective["rounds"])
			setup.objective_count = int(objective["damage"])
		"disarm":
			setup.objective_count = int(objective["count"])
		"capture", "catch":
			for character in setup.enemies:
				if character.id == str(objective.get("target", "")):
					setup.objective_target = character.id
					setup.objective_target_name = character.display_name
		"escape":
			for pos in objective.get("tiles", []):
				setup.exit_tiles.append(_to_pos(pos))


## 형식·전장·조건·특성·줄·지시·졸개·사건·도전·숨은 증원
static func _apply_variety(setup: CombatSetup, data: Dictionary, player: CharacterData) -> void:
	setup.format = str(data.get("format", "duel"))
	setup.stage = str(data.get("stage", ""))
	for condition in data.get("conditions", []):
		setup.conditions.append(str(condition))
	setup.standoff_then = str(data.get("standoff_then", ""))
	setup.placement_flags = data.get("placement_flags", {}).duplicate()
	setup.challenge = data.get("challenge", {}).duplicate()
	setup.events = data.get("events", []).duplicate(true)
	if data.has("max_bouts"):
		setup.max_bouts = int(data["max_bouts"])
	var groups: Array = [[data.get("enemies", []), setup.enemies], [data.get("allies", []), setup.allies]]
	var reinforce_entries: Array = data.get("reinforcements", [])
	var reinforce_chars: Array = setup.reinforcements.map(func(r: Dictionary) -> CharacterData: return r["character"])
	groups.append([reinforce_entries, reinforce_chars])
	var hidden: Array = data.get("hidden", [])
	for i in hidden.size():
		var lurker: CharacterData = _create_unit(hidden[i], player, i, hidden)
		lurker.id = "%s_hidden_%d" % [str(hidden[i]["npc"]), i]
		setup.hidden_foes.append(lurker)
	groups.append([hidden, setup.hidden_foes])
	for pair in groups:
		var entries: Array = pair[0]
		var characters: Array = pair[1]
		for i in mini(entries.size(), characters.size()):
			var entry: Dictionary = entries[i]
			var id: String = characters[i].id
			if entry.has("traits"):
				setup.traits[id] = Array(entry["traits"]).map(func(t: Variant) -> String: return str(t))
			if entry.has("row"):
				setup.rows[id] = str(entry["row"])
			if entry.has("order"):
				setup.orders[id] = str(entry["order"])
			if entry.get("mook", NpcRoster.get_npc(str(entry["npc"])).get("combat_style", "") == "mook"):
				setup.mooks[id] = true


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
