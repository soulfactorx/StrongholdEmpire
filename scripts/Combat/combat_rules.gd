class_name CombatRules
extends RefCounted

## 전투 규칙(지형, 이동, 피해 계산, 오행 상극, 내공 폭주).
## 화면과 분리해 두어 테스트에서 바로 호출할 수 있다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

enum Terrain { PLAIN, FOREST, WATER, HIGH }

const TERRAIN_NAMES: Dictionary = {
	Terrain.PLAIN: "평지",
	Terrain.FOREST: "수풀",
	Terrain.WATER: "물",
	Terrain.HIGH: "고지",
}

## 오행 상극: 키가 값을 이긴다 (목극토, 토극수, 수극화, 화극금, 금극목)
const ELEMENT_OVERCOMES: Dictionary = {
	MartialArtData.FiveElement.WOOD: MartialArtData.FiveElement.EARTH,
	MartialArtData.FiveElement.EARTH: MartialArtData.FiveElement.WATER,
	MartialArtData.FiveElement.WATER: MartialArtData.FiveElement.FIRE,
	MartialArtData.FiveElement.FIRE: MartialArtData.FiveElement.METAL,
	MartialArtData.FiveElement.METAL: MartialArtData.FiveElement.WOOD,
}

const NEIGHBORS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]


static func move_cost(terrain: Terrain) -> int:
	match terrain:
		Terrain.FOREST:
			return _Balance.FOREST_MOVE_COST
		Terrain.WATER:
			return _Balance.WATER_MOVE_COST
		Terrain.HIGH:
			return _Balance.HIGH_MOVE_COST
	return 1


static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## start에서 budget 이내로 갈 수 있는 칸과 그 비용. (start 자신은 제외)
## is_passable(pos) -> bool, terrain_of(pos) -> Terrain
static func reachable_tiles(
	start: Vector2i,
	budget: int,
	is_passable: Callable,
	terrain_of: Callable
) -> Dictionary:
	var costs: Dictionary = _dijkstra(start, budget, is_passable, terrain_of, Callable())
	costs.erase(start)
	return costs


## start에서 is_goal(pos)를 만족하는 가장 가까운 칸까지의 경로 (start 제외, 비용 기준).
## 도달할 수 없으면 빈 배열.
static func find_path(
	start: Vector2i,
	is_goal: Callable,
	is_passable: Callable,
	terrain_of: Callable
) -> Array[Vector2i]:
	var parents: Dictionary = {}
	var costs: Dictionary = _dijkstra(start, 1 << 20, is_passable, terrain_of, is_goal, parents)
	var goal: Variant = parents.get("_goal")
	var path: Array[Vector2i] = []
	if goal == null:
		return path
	var node: Vector2i = goal
	while node != start:
		path.push_front(node)
		node = parents[node]
	return path


## 경로를 따라 budget 안에서 갈 수 있는 마지막 칸과 쓴 비용
static func walk_path(path: Array[Vector2i], budget: int, terrain_of: Callable) -> Dictionary:
	var spent: int = 0
	var last_index: int = -1
	for i in path.size():
		var cost: int = move_cost(terrain_of.call(path[i]))
		if spent + cost > budget:
			break
		spent += cost
		last_index = i
	return {"index": last_index, "cost": spent}


static func _dijkstra(
	start: Vector2i,
	budget: int,
	is_passable: Callable,
	terrain_of: Callable,
	is_goal: Callable,
	parents: Dictionary = {}
) -> Dictionary:
	var costs: Dictionary = {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		# 격자가 작으므로 단순 선형 탐색으로 최소 비용 칸을 꺼낸다.
		var best_index: int = 0
		for i in range(1, frontier.size()):
			if costs[frontier[i]] < costs[frontier[best_index]]:
				best_index = i
		var current: Vector2i = frontier[best_index]
		frontier.remove_at(best_index)
		if is_goal.is_valid() and current != start and is_goal.call(current):
			parents["_goal"] = current
			return costs
		for step in NEIGHBORS:
			var next: Vector2i = current + step
			if not is_passable.call(next):
				continue
			var new_cost: int = costs[current] + move_cost(terrain_of.call(next))
			if new_cost > budget:
				continue
			if not costs.has(next) or new_cost < costs[next]:
				costs[next] = new_cost
				parents[next] = current
				if not frontier.has(next):
					frontier.append(next)
	return costs


static func element_modifier(attacker: MartialArtData.FiveElement, defender: MartialArtData.FiveElement) -> float:
	if ELEMENT_OVERCOMES.get(attacker) == defender:
		return _Balance.ELEMENT_ADVANTAGE
	if ELEMENT_OVERCOMES.get(defender) == attacker:
		return _Balance.ELEMENT_DISADVANTAGE
	return 1.0


static func get_art_range(art: MartialArtData, attacker_terrain: Terrain) -> int:
	if art == null:
		return 1
	var bonus: int = _Balance.HIGH_RANGE_BONUS if attacker_terrain == Terrain.HIGH and art.range > 1 else 0
	return art.range + bonus


## 공격 피해 계산. art가 null이면 기본 공격.
## 반환: { damage: int, notes: PackedStringArray }
static func calculate_damage(
	attacker: CombatUnit,
	defender: CombatUnit,
	art: MartialArtData,
	attacker_terrain: Terrain,
	defender_terrain: Terrain,
	relationship_bonus: float = 1.0
) -> Dictionary:
	var notes: PackedStringArray = []
	var damage: float
	if art == null:
		damage = attacker.get_basic_attack_base()
	else:
		damage = art.damage + attacker.character.strength * _Balance.ART_STRENGTH_RATIO
		if art.special_effects.has(MartialArtData.SpecialEffect.AMBUSH) and defender.hp == defender.max_hp:
			damage *= _Balance.AMBUSH_MULTIPLIER
			notes.append("기습")
		var element_mod: float = element_modifier(art.element, defender.get_active_element())
		if element_mod > 1.0:
			notes.append("오행 상극 우위")
		elif element_mod < 1.0:
			notes.append("오행 상극 열세")
		damage *= element_mod

	damage *= attacker.damage_scale * relationship_bonus
	if attacker.has_status("empowered"):
		damage *= _Balance.EMPOWER_MULTIPLIER
		notes.append("기세")
	if attacker_terrain == Terrain.HIGH:
		damage *= _Balance.HIGH_ATTACK
		notes.append("고지")
	elif attacker_terrain == Terrain.WATER:
		damage *= _Balance.WATER_ATTACK
		notes.append("물속")
	if defender_terrain == Terrain.FOREST:
		damage *= _Balance.FOREST_DEFENSE
		notes.append("수풀 엄폐")
	return {"damage": maxi(1, int(damage)), "notes": notes}


## 무공 시전 후 내공 폭주 판정. 반동 피해(없으면 0)를 돌려준다.
static func roll_overload(character: CharacterData, art: MartialArtData) -> int:
	if character.internal_energy_current >= character.internal_energy_max * _Balance.OVERLOAD_THRESHOLD:
		return 0
	if randi_range(1, 100) > _Balance.OVERLOAD_CHANCE:
		return 0
	return maxi(1, int(art.internal_cost * _Balance.OVERLOAD_DAMAGE_PER_COST))
