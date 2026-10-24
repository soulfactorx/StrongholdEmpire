class_name Battlefield
extends RefCounted

## 전장의 다양성: 지역에 따른 전장 모양(지형 자동 생성), 날씨·시간, 전투 목표의 이름과 설명.
## 전투 데이터(battlefield·weather·objective)와 코드 전투가 함께 쓴다.

const GRID_WIDTH := 16
const GRID_HEIGHT := 10

## 전장 모양: 이름과 설명
const KINDS: Dictionary = {
	"plain": "들판",
	"forest": "숲",
	"river": "강가",
	"mountain": "산길",
	"town": "저잣거리",
	"snow": "설원",
	"courtyard": "연무장",
}

## 지역 id → 전장 모양 (지도에 없는 지역은 들판)
const REGION_KINDS: Dictionary = {
	"tianshan": "snow", "lanzhou": "plain", "xian": "town", "taiyuan": "mountain", "taihang": "mountain",
	"luoyang": "town", "kaifeng": "town", "jinan": "river", "beijing": "town", "hefei": "plain",
	"yangzhou": "river", "hangzhou": "river", "wudang": "mountain", "hanzhong": "mountain", "chengdu": "forest",
	"wuchang": "river", "changsha": "forest", "nanchang": "river", "kunming": "forest", "qingyun": "mountain",
}

## 날씨·시간: 이름과 대결에 주는 영향 (DuelRules·DuelEngine이 적용)
const WEATHERS: Dictionary = {
	"clear": {"name": "맑음", "effect": ""},
	"night": {"name": "밤", "effect": "회피가 한 단계 빨라짐"},
	"rain": {"name": "비", "effect": "화 초식 피해 -30%, 수 초식 피해 +20%"},
	"fog": {"name": "안개", "effect": "상대 배치가 덜 보임"},
	"snow": {"name": "눈", "effect": "강공이 한 단계 느려짐"},
}

## 전투 목표: 이름
const OBJECTIVES: Dictionary = {
	"defeat_all": "적을 모두 쓰러뜨려라",
	"defeat_target": "우두머리를 쓰러뜨려라",
	"survive": "버텨라",
	"escape": "탈출하라",
	"protect": "지켜라",
}


static func kind_for_region(region_id: String) -> String:
	return str(REGION_KINDS.get(region_id, "plain"))


static func weather_name(weather: String) -> String:
	return str(WEATHERS.get(weather, WEATHERS["clear"])["name"])


## 계절과 전장에 맞는 날씨를 하나 고른다 (코드 전투용). 눈은 겨울이나 설원에서만.
static func random_weather(kind: String, season: String) -> String:
	var roll: float = randf()
	if kind == "snow" or (season == "겨울" and roll < 0.35):
		return "snow"
	if season == "여름" and roll < 0.35:
		return "rain"
	if kind == "river" and roll < 0.3:
		return "fog"
	if roll < 0.15:
		return "night"
	return "clear"


## 전장 모양에 맞게 지형과 막힌 칸을 만든다. keep: 비워 둘 칸(유닛 자리)
## 가운데(4~11열)에 지형을 두고, 양쪽 출발 자리는 비워 둔다.
static func generate(setup: CombatSetup, kind: String, keep: Array[Vector2i], rng_seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else randi()
	setup.terrain.clear()
	setup.blocked_tiles.clear()
	var forest: Array[Vector2i] = []
	var water: Array[Vector2i] = []
	var high: Array[Vector2i] = []
	var blocked: Array[Vector2i] = []
	match kind:
		"forest":
			for i in rng.randi_range(4, 6):
				_cluster(forest, Vector2i(rng.randi_range(4, 11), rng.randi_range(0, 9)), rng.randi_range(2, 4), rng)
			for i in 2:
				blocked.append(Vector2i(rng.randi_range(5, 10), rng.randi_range(1, 8)))
		"river":
			# 세로로 흐르는 강, 건널 수 있는 여울 두 곳
			var x: int = rng.randi_range(7, 8)
			var fords: Array[int] = [rng.randi_range(1, 3), rng.randi_range(6, 8)]
			for y in GRID_HEIGHT:
				var bend: int = x + (1 if y > 4 and rng.randf() < 0.5 else 0)
				if not y in fords:
					water.append(Vector2i(bend, y))
			_cluster(forest, Vector2i(rng.randi_range(4, 5), rng.randi_range(1, 8)), 3, rng)
			_cluster(forest, Vector2i(rng.randi_range(10, 11), rng.randi_range(1, 8)), 3, rng)
		"mountain":
			# 고지 능선과 바위
			var ridge_x: int = rng.randi_range(6, 9)
			for y in range(rng.randi_range(0, 2), rng.randi_range(6, 9)):
				high.append(Vector2i(ridge_x + (y % 2), y))
			for i in rng.randi_range(4, 6):
				blocked.append(Vector2i(rng.randi_range(4, 11), rng.randi_range(0, 9)))
			_cluster(forest, Vector2i(rng.randi_range(4, 11), rng.randi_range(0, 9)), 3, rng)
		"town":
			# 집(막힌 칸)이 골목을 이룬다
			for i in rng.randi_range(3, 4):
				var corner := Vector2i(rng.randi_range(4, 10), rng.randi_range(0, 8))
				var w: int = rng.randi_range(1, 2)
				var h: int = rng.randi_range(1, 2)
				for dx in w:
					for dy in h:
						blocked.append(corner + Vector2i(dx, dy))
			_cluster(high, Vector2i(rng.randi_range(5, 10), rng.randi_range(0, 9)), 2, rng)
		"snow":
			for i in rng.randi_range(3, 5):
				blocked.append(Vector2i(rng.randi_range(4, 11), rng.randi_range(0, 9)))
			_cluster(high, Vector2i(rng.randi_range(5, 10), rng.randi_range(1, 8)), 4, rng)
			_cluster(forest, Vector2i(rng.randi_range(4, 11), rng.randi_range(0, 9)), 2, rng)
		"courtyard":
			var wall_x: int = rng.randi_range(6, 9)
			for y in range(rng.randi_range(2, 3), rng.randi_range(6, 7)):
				blocked.append(Vector2i(wall_x, y))
			_cluster(forest, Vector2i(rng.randi_range(3, 5), rng.randi_range(1, 3)), 3, rng)
			_cluster(high, Vector2i(rng.randi_range(10, 12), rng.randi_range(6, 8)), 3, rng)
		_:
			_cluster(forest, Vector2i(rng.randi_range(4, 11), rng.randi_range(0, 9)), 3, rng)
			_cluster(high, Vector2i(rng.randi_range(4, 11), rng.randi_range(0, 9)), 2, rng)
	var occupied: Dictionary = {}
	for pos in keep:
		occupied[pos] = true
	for pos in blocked:
		if _inside(pos) and not occupied.has(pos) and not setup.blocked_tiles.has(pos):
			setup.blocked_tiles.append(pos)
	for pair in [[forest, CombatRules.Terrain.FOREST], [water, CombatRules.Terrain.WATER], [high, CombatRules.Terrain.HIGH]]:
		for pos in pair[0]:
			if _inside(pos) and not setup.blocked_tiles.has(pos):
				setup.terrain[pos] = pair[1]
	setup.battlefield = kind


static func _cluster(out: Array[Vector2i], center: Vector2i, size: int, rng: RandomNumberGenerator) -> void:
	var pos: Vector2i = center
	for i in size:
		out.append(pos)
		pos += CombatRules.NEIGHBORS[rng.randi_range(0, 3)]


static func _inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < GRID_WIDTH and pos.y < GRID_HEIGHT


## 전투 화면에 보일 목표 한 줄 (예: "목표: 3합 동안 버텨라 · 밤 — 회피가 한 단계 빨라짐")
static func describe(setup: CombatSetup) -> String:
	var goal: String = str(OBJECTIVES.get(setup.objective, OBJECTIVES["defeat_all"]))
	match setup.objective:
		"defeat_target":
			goal = "%s을(를) 쓰러뜨려라" % setup.objective_target_name
		"survive":
			goal = "%d합 동안 버텨라" % setup.objective_rounds
		"escape":
			goal = "공격을 %d번 흘려 빠져나가라 (주인공)" % DuelEngine.ESCAPE_EVADES
		"protect":
			goal = "%s이(가) 쓰러지지 않게 적을 물리쳐라" % setup.objective_target_name
	var parts: PackedStringArray = ["목표: " + goal]
	if setup.battlefield in KINDS:
		parts.append(str(KINDS[setup.battlefield]))
	var info: Dictionary = WEATHERS.get(setup.weather, WEATHERS["clear"])
	if setup.weather != "clear":
		parts.append("%s — %s" % [info["name"], info["effect"]])
	if not setup.reinforcements.is_empty():
		parts.append("적 증원 %d명이 뒤를 받침" % setup.reinforcements.size())
	return " · ".join(parts)
