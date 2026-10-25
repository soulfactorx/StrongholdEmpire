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
	"capture": "사로잡아라",
	"catch": "쫓아가 붙잡아라",
	"timed": "시간 안에 이겨라",
	"endure": "버텨 내라",
	"disarm": "절초를 무산시켜라",
	"hold_line": "진지를 지켜라",
}

## 전투 형식: 이름과 한 줄 설명 (docs/전투_다양화_설계.md)
const FORMATS: Dictionary = {
	"duel": {"name": "연전", "rule": "양쪽 줄에서 한 사람씩 나와 1대1로 겨룬다"},
	"siege": {"name": "포위", "rule": "적이 한꺼번에 덤빈다. 칸마다 겨룰 상대를 고르고, 나머지 공격은 막기·회피·휩쓸기로 받는다"},
	"formation": {"name": "진형", "rule": "앞줄이 서 있으면 뒷줄은 술로만 치고 맞는다. 같은 적을 함께 치면 협공, 엄호가 피해를 나눠 받는다"},
	"chase": {"name": "추격", "rule": "거리를 겨룬다. 쫓기는 쪽은 회피·속공으로 벌리고, 쫓는 쪽은 강공·술로 좁힌다"},
	"stealth": {"name": "잠입", "rule": "첫 합은 기습(피해 2배). 강공은 소리가 나고, 막기에 막혀도 들킨다. 들키면 경보와 증원"},
	"standoff": {"name": "대치", "rule": "칼을 뽑기 전 기세 싸움. 피해 없이 칸을 이긴 쪽 기세가 오르고, 먼저 기세 5에 닿으면 이긴다"},
	"tournament": {"name": "비무대회", "rule": "대진표대로 연달아 겨룬다. 판 사이 회복은 조금, 다음 상대의 버릇은 관전으로 미리 본다"},
}

## 전장 규칙: 이름과 규칙 한 줄
const STAGES: Dictionary = {
	"bridge": {"name": "외나무다리", "rule": "회피 불가(헛디딤). 강공에 맞아 체력 20% 아래가 되면 떨어진다"},
	"rooftop": {"name": "지붕 위", "rule": "회피·속공 속도 +1, 강공 속도 -1"},
	"boat": {"name": "배 위", "rule": "흔들림: 둘째·넷째·여섯째 칸의 강공 위력 -30%"},
	"burning": {"name": "불타는 장원", "rule": "합마다 모두 체력 -5%, 연기 때문에 운기 불가"},
	"bamboo": {"name": "대숲", "rule": "술 피해 +30%, 상대 배치가 한 단계 덜 보임"},
	"arena": {"name": "비무대", "rule": "술 금지. 체력 20% 아래로 밀리면 장외"},
	"ice": {"name": "빙판", "rule": "강공 속도 -1. 회피에 흘려진 쪽은 미끄러져 다음 칸 속도 -1"},
	"alley": {"name": "좁은 골목", "rule": "한꺼번에 덤빌 수 있는 적은 둘까지"},
	"shrine": {"name": "밤의 사당", "rule": "첫 합에는 양쪽 모두 상대 배치가 안 보인다"},
}

## 우리 쪽 처지: 이름과 규칙
const CONDITIONS: Dictionary = {
	"poisoned": {"name": "중독", "rule": "합마다 내공 -10, 운기의 내공 회복 절반"},
	"unarmed": {"name": "맨손", "rule": "검법 초식을 쓸 수 없다"},
	"wounded": {"name": "부상", "rule": "칸 -1, 체력 70%로 시작"},
	"exhausted": {"name": "지침", "rule": "내공 50%로 시작"},
	"honor": {"name": "정정당당", "rule": "술 금지, 빈 칸 금지 (양쪽 모두)"},
}

## 상대 특성 (우두머리 패턴): 이름과 규칙
const TRAITS: Dictionary = {
	"enrage": {"name": "광폭", "rule": "체력 절반 아래면 칸 +1, 기세 +2, 막기를 버린다"},
	"telegraph": {"name": "예고 절초", "rule": "세 합마다 마지막 칸에 큰 절초. 한 합 전에 예고한다"},
	"poison_mist": {"name": "독무", "rule": "이 상대 앞에서 운기하면 독에 다친다"},
	"iron_body": {"name": "금강불괴", "rule": "속공 피해 절반"},
	"mirror": {"name": "모방", "rule": "내가 지난 합에 낸 유형을 그대로 따라 낸다"},
	"two_phase": {"name": "단계 전환", "rule": "쓰러지면 한 번 다시 일어나 더 사나워진다"},
}

## 싸우는 중의 사건 종류
const EVENT_TYPES: PackedStringArray = ["reinforce", "betrayal", "bond_intervene", "parley", "decision", "line"]
## 사건이 일어나는 때
const EVENT_WHEN: PackedStringArray = ["bout", "player_hp_below", "enemy_hp_below"]
## 사건 선택지의 결과
const CHOICE_ACTIONS: PackedStringArray = ["fight", "withdraw_foe", "all_in", "retreat", "hold"]

## 선택 도전: 설명 (value를 넣는다)
const CHALLENGES: Dictionary = {
	"within_bouts": "%d합 안에 이기기",
	"damage_below": "받는 피해 %d 미만으로 이기기",
	"no_trick": "술 없이 이기기",
	"no_focus": "운기 없이 이기기",
	"no_gap": "빈틈 없이 이기기",
}

## 전장 모양 → 코드 전투가 고를 수 있는 전장 규칙
const KIND_STAGES: Dictionary = {
	"plain": [""], "forest": ["bamboo", ""], "river": ["boat", "bridge"], "mountain": ["bridge", ""],
	"town": ["alley", "rooftop"], "snow": ["ice"], "courtyard": ["arena"],
}


## 전장 모양에 맞는 전장 규칙 하나 (무작위, 없을 수도 있음)
static func random_stage(kind: String) -> String:
	var options: Array = KIND_STAGES.get(kind, [""])
	return str(options[randi() % options.size()])


static func challenge_text(challenge: Dictionary) -> String:
	var text: String = str(CHALLENGES.get(str(challenge.get("type", "")), ""))
	return text % int(challenge.get("value", 0)) if text.contains("%d") else text


## 코드 전투의 선택 도전 하나 (무작위)
static func random_challenge(bouts_hint: int) -> Dictionary:
	match randi() % 4:
		0:
			return {"type": "within_bouts", "value": maxi(2, bouts_hint)}
		1:
			return {"type": "no_gap"}
		2:
			return {"type": "no_focus"}
	return {"type": "no_trick"}


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
			goal = "멀리 달아나라" if setup.format == "chase" else "공격을 %d번 흘려 빠져나가라 (주인공)" % DuelEngine.ESCAPE_EVADES
		"protect":
			goal = "%s이(가) 쓰러지지 않게 적을 물리쳐라" % setup.objective_target_name
		"capture":
			goal = "%s을(를) 몰아붙인 뒤(체력 %d%% 이하) 막기 반격·기절로 사로잡아라 (죽이면 실패)" % [setup.objective_target_name, roundi(DuelEngine.CAPTURE_RATIO * 100)]
		"catch":
			goal = "%s을(를) 쫓아가 붙잡아라" % (setup.objective_target_name if not setup.objective_target_name.is_empty() else "상대")
		"timed":
			goal = "%d합 안에 적을 모두 쓰러뜨려라" % setup.objective_rounds
		"endure":
			goal = "%d합 동안 받는 피해를 %d 미만으로 버텨 내라" % [setup.objective_rounds, setup.objective_count]
		"disarm":
			goal = "상대의 절초를 회피·상성으로 %d번 무산시켜라" % setup.objective_count
		"hold_line":
			goal = "앞줄을 지키며 %d합을 버텨라" % setup.objective_rounds
	var parts: PackedStringArray = ["목표: " + goal]
	if setup.format != "duel" and FORMATS.has(setup.format):
		parts.insert(0, "%s — %s" % [FORMATS[setup.format]["name"], FORMATS[setup.format]["rule"]])
	if STAGES.has(setup.stage):
		parts.append("%s — %s" % [STAGES[setup.stage]["name"], STAGES[setup.stage]["rule"]])
	for condition in setup.conditions:
		if CONDITIONS.has(condition):
			parts.append("%s — %s" % [CONDITIONS[condition]["name"], CONDITIONS[condition]["rule"]])
	if setup.battlefield in KINDS:
		parts.append(str(KINDS[setup.battlefield]))
	var info: Dictionary = WEATHERS.get(setup.weather, WEATHERS["clear"])
	if setup.weather != "clear":
		parts.append("%s — %s" % [info["name"], info["effect"]])
	if not setup.reinforcements.is_empty():
		parts.append("적 증원 %d명이 뒤를 받침" % setup.reinforcements.size())
	if not setup.challenge.is_empty():
		parts.append("도전: " + challenge_text(setup.challenge))
	return "\n".join(parts)
