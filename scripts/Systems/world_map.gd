class_name WorldMap
extends RefCounted

## 강호 지도: 지역과 이웃 관계, 지역 주인(세력 id, 비면 주인 없는 땅).
## 지역 정의는 data/map/regions.json (형식은 docs/지도_데이터_형식.md),
## 판마다 바뀌는 주인·본거지는 GameManager.map_state({owners, homes})에 담는다.
## 세력마다 본거지(home)가 하나 있고, 본거지는 빼앗기지 않는다. 본거지 밖 지역은 계절마다 은자·식량을 더 낸다.

const MAP_PATH := "res://data/map/regions.json"
const _Balance = preload("res://scripts/Systems/game_balance.gd")

static var _regions: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _spare_homes: Array = []
static var _size: Vector2 = Vector2(900, 700)
static var _loaded: bool = false


static func reload_data(path: String = MAP_PATH) -> void:
	_regions.clear()
	_by_id.clear()
	_spare_homes = []
	_loaded = true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("지도 데이터를 열 수 없음: %s" % path)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		push_warning("지도 데이터 형식 오류: %s" % path)
		return
	var errors: PackedStringArray = validate_map_dict(data)
	for error in errors:
		push_warning("지도 데이터 오류: %s" % error)
	if not errors.is_empty():
		return
	var size: Array = data.get("size", [900, 700])
	_size = Vector2(float(size[0]), float(size[1]))
	_spare_homes = data.get("spare_homes", [])
	for entry in data["regions"]:
		var region: Dictionary = {
			"id": str(entry["id"]), "name": str(entry["name"]),
			"pos": Vector2(float(entry["pos"][0]), float(entry["pos"][1])),
			"home": str(entry.get("home", "")), "gold": int(entry.get("gold", 0)), "food": int(entry.get("food", 0)),
			"defense": int(entry.get("defense", 50)), "description": str(entry.get("description", "")),
			"neighbors": Array(entry.get("neighbors", [])).map(func(id: Variant) -> String: return str(id)),
		}
		_regions.append(region)
		_by_id[region["id"]] = region


static func validate_map_dict(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	var regions: Variant = data.get("regions")
	if not regions is Array or regions.is_empty():
		errors.append("regions 목록이 비어 있음")
		return errors
	var ids: Dictionary = {}
	for entry in regions:
		if not entry is Dictionary or str(entry.get("id", "")).is_empty() or str(entry.get("name", "")).is_empty():
			errors.append("지역에 id·name 필요: %s" % [entry])
			continue
		if ids.has(entry["id"]):
			errors.append("중복된 지역 id: %s" % entry["id"])
		ids[entry["id"]] = entry
		var pos: Variant = entry.get("pos")
		if not pos is Array or pos.size() != 2:
			errors.append("%s: pos는 [x, y]" % entry["id"])
	for id in ids:
		for other in ids[id].get("neighbors", []):
			if not ids.has(other):
				errors.append("%s: 없는 이웃 %s" % [id, other])
			elif not id in ids[other].get("neighbors", []):
				errors.append("%s ↔ %s: 이웃 관계가 한쪽에만 있음" % [id, other])
	for id in data.get("spare_homes", []):
		if not ids.has(id):
			errors.append("spare_homes에 없는 지역: %s" % id)
	return errors


static func _ensure_loaded() -> void:
	if not _loaded:
		reload_data()


static func get_regions() -> Array[Dictionary]:
	_ensure_loaded()
	return _regions


static func get_region(region_id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(region_id, {})


static func has_region(region_id: String) -> bool:
	_ensure_loaded()
	return _by_id.has(region_id)


## 두 지역 사이 거리 (이웃을 따라 몇 걸음). 갈 수 없으면 -1
static func distance(from_id: String, to_id: String) -> int:
	if from_id == to_id:
		return 0
	var seen: Dictionary = {from_id: 0}
	var queue: Array[String] = [from_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for other in get_region(current).get("neighbors", []):
			if seen.has(other):
				continue
			seen[other] = seen[current] + 1
			if other == to_id:
				return seen[other]
			queue.append(other)
	return -1


static func get_size() -> Vector2:
	_ensure_loaded()
	return _size


## 새 판의 지도 상태 {owners: {지역: 세력 id 또는 ""}, homes: {세력 id: 본거지 지역}}.
## 등장하는 세력은 본거지를 갖고, 나머지 땅은 주인이 없다.
## 지도에 본거지가 없는 세력(시나리오 전용 세력 등)은 spare_homes에서 빈 곳을 받는다.
static func create_state(sect_ids: Array) -> Dictionary:
	_ensure_loaded()
	var owners: Dictionary = {}
	var homes: Dictionary = {}
	for region in _regions:
		var home: String = region["home"]
		owners[region["id"]] = home if home in sect_ids else ""
		if home in sect_ids:
			homes[home] = region["id"]
	for sect_id in sect_ids:
		if homes.has(sect_id):
			continue
		for spare in _spare_homes:
			if owners.get(spare, "x") == "":
				owners[spare] = sect_id
				homes[sect_id] = spare
				break
	return {"owners": owners, "homes": homes}


## 저장한 상태를 지금 지도에 맞춘다 (없는 지역은 버리고, 새 지역은 주인 없는 땅으로)
static func restore_state(data: Dictionary) -> Dictionary:
	_ensure_loaded()
	var owners: Dictionary = {}
	var saved: Dictionary = data.get("owners", {})
	for region in _regions:
		owners[region["id"]] = str(saved.get(region["id"], ""))
	var homes: Dictionary = {}
	var saved_homes: Dictionary = data.get("homes", {})
	for sect_id in saved_homes:
		if _by_id.has(str(saved_homes[sect_id])):
			homes[str(sect_id)] = str(saved_homes[sect_id])
	return {"owners": owners, "homes": homes}


static func get_home(state: Dictionary, sect_id: String) -> String:
	return str(state.get("homes", {}).get(sect_id, ""))


static func get_owner(state: Dictionary, region_id: String) -> String:
	return str(state.get("owners", {}).get(region_id, ""))


static func regions_of(state: Dictionary, sect_id: String) -> Array[String]:
	var result: Array[String] = []
	if sect_id.is_empty():
		return result
	for region in get_regions():
		if get_owner(state, region["id"]) == sect_id:
			result.append(region["id"])
	return result


static func count(state: Dictionary, sect_id: String) -> int:
	return regions_of(state, sect_id).size()


## 그 세력의 땅과 맞닿아 있는지
static func borders(state: Dictionary, region_id: String, sect_id: String) -> bool:
	for neighbor in get_region(region_id).get("neighbors", []):
		if get_owner(state, neighbor) == sect_id:
			return true
	return false


## 그 세력 땅에 맞닿은 남의 땅·빈 땅. neutral_only면 주인 없는 땅만
static func frontier(state: Dictionary, sect_id: String, neutral_only: bool = false) -> Array[String]:
	var result: Array[String] = []
	for region in get_regions():
		var owner: String = get_owner(state, region["id"])
		if owner == sect_id or (neutral_only and not owner.is_empty()):
			continue
		if borders(state, region["id"], sect_id):
			result.append(region["id"])
	return result


## 본거지를 뺀 땅에서 나는 계절 수입 {gold, food}
static func income(state: Dictionary, sect_id: String) -> Dictionary:
	var home: String = get_home(state, sect_id)
	var gold: int = 0
	var food: int = 0
	for region_id in regions_of(state, sect_id):
		if region_id == home:
			continue
		gold += int(get_region(region_id)["gold"])
		food += int(get_region(region_id)["food"])
	return {"gold": gold, "food": food}


## 빼앗을 수 있는 땅인지 (본거지는 빼앗지 못한다)
static func can_be_taken(state: Dictionary, region_id: String) -> bool:
	var owner: String = get_owner(state, region_id)
	return owner.is_empty() or get_home(state, owner) != region_id


## 지역 주인을 바꾸고 세력의 제자 정원을 함께 옮긴다.
static func transfer(state: Dictionary, region_id: String, new_owner: String, sects: Array) -> void:
	var old_owner: String = get_owner(state, region_id)
	state["owners"][region_id] = new_owner
	for sect in sects:
		if sect == null:
			continue
		if sect.id == old_owner and not old_owner.is_empty():
			sect.max_disciples = maxi(10, sect.max_disciples - _Balance.REGION_MAX_DISCIPLES)
		elif sect.id == new_owner:
			sect.max_disciples += _Balance.REGION_MAX_DISCIPLES


## 평정 비용: 주둔 병력(defense)이 셀수록 비싸다.
static func pacify_cost(region_id: String) -> Dictionary:
	var defense: int = int(get_region(region_id).get("defense", 50))
	return {
		"gold": _Balance.REGION_PACIFY_GOLD + defense / 2,
		"food": _Balance.REGION_PACIFY_FOOD,
	}
