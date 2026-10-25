class_name ScenarioRules
extends RefCounted

## 현재 시나리오의 게임 길이·난이도 파라미터.
## 기본값은 여기 DEFAULTS에 두고, 시나리오 데이터와 새 게임 "세부 설정"이 덮어쓴다.
## 게임 코드는 이 클래스의 접근 함수로만 파라미터를 읽는다.

const DEFAULTS: Dictionary = {
	## 제한 연수. 0이면 제한 없음
	"time_limit_years": 0,
	"legacy_enabled": true,
	## 최대 세대 수. 0이면 제한 없음
	"max_generations": 0,
	"income_scale": 1.0,
	"upkeep_scale": 1.0,
	"exp_scale": 1.0,
	## 계절마다 기연이 일어날 확률 (발생 후보가 있을 때)
	"event_rate": 1.0,
	"world_growth_scale": 1.0,
	"enemy_strength_scale": 1.0,
	## 세력 AI의 호전성: 세력끼리의 공격과 플레이어 침공 가중치에 곱한다. 0이면 싸우지 않는다
	"ai_aggression": 1.0,
	## 승리 결말에 도달하면 시나리오를 끝낸다 (단기 시나리오용)
	"end_on_victory": false,
	## 문파 살림이 무너지면(해산·곳간·명성) 게임이 끝나는지. 이야기 중심 시나리오는 끈다
	"sect_game_over": true,
}

## 값 검증 범위: [최소, 최대]
const RANGES: Dictionary = {
	"time_limit_years": [0, 200],
	"max_generations": [0, 20],
	"income_scale": [0.1, 5.0],
	"upkeep_scale": [0.0, 5.0],
	"exp_scale": [0.1, 5.0],
	"event_rate": [0.0, 1.0],
	"world_growth_scale": [0.0, 5.0],
	"enemy_strength_scale": [0.3, 3.0],
	"ai_aggression": [0.0, 3.0],
}

## 새 게임 화면 "세부 설정"에서 고를 수 있는 값. 첫 항목은 항상 "시나리오 기본"
const UI_OPTIONS: Array[Dictionary] = [
	{"param": "time_limit_years", "label": "제한 연수", "options": [["5년", 5], ["10년", 10], ["20년", 20], ["30년", 30], ["없음", 0]]},
	{"param": "exp_scale", "label": "성장 속도", "options": [["느리게", 0.75], ["보통", 1.0], ["빠르게", 1.5]]},
	{"param": "event_rate", "label": "기연 빈도", "options": [["드물게", 0.5], ["보통", 0.8], ["자주", 1.0]]},
	{"param": "income_scale", "label": "경제", "options": [["궁핍", 0.8], ["보통", 1.0], ["풍족", 1.25]]},
	{"param": "enemy_strength_scale", "label": "적 강도", "options": [["약함", 0.8], ["보통", 1.0], ["강함", 1.25]]},
]

static var params: Dictionary = DEFAULTS.duplicate()


static func reset() -> void:
	params = DEFAULTS.duplicate()


## 덮어쓸 값을 검사해 적용한다. 잘못된 항목은 적용하지 않고 오류 목록으로 돌려준다.
static func apply(overrides: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = validate(overrides)
	if not errors.is_empty():
		return errors
	for key in overrides:
		params[key] = _coerce(key, overrides[key])
	return errors


static func validate(overrides: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in overrides:
		if not DEFAULTS.has(key):
			errors.append("알 수 없는 파라미터: %s" % key)
			continue
		var value: Variant = overrides[key]
		if DEFAULTS[key] is bool:
			if not value is bool:
				errors.append("%s는 true/false여야 함" % key)
			continue
		if not (value is int or value is float):
			errors.append("%s는 숫자여야 함" % key)
			continue
		var bounds: Array = RANGES[key]
		if value < bounds[0] or value > bounds[1]:
			errors.append("%s 범위 초과: %s (%s~%s)" % [key, value, bounds[0], bounds[1]])
	return errors


static func _coerce(key: String, value: Variant) -> Variant:
	if DEFAULTS[key] is bool:
		return bool(value)
	if DEFAULTS[key] is int:
		return int(value)
	return float(value)


static func time_limit_years() -> int:
	return params["time_limit_years"]


static func has_time_limit() -> bool:
	return time_limit_years() > 0


## 현재 연차를 뺀 남은 연수. 제한이 없으면 큰 값.
static func years_left(current_year: int) -> int:
	if not has_time_limit():
		return 9999
	return time_limit_years() - current_year


static func legacy_enabled() -> bool:
	return params["legacy_enabled"]


static func max_generations() -> int:
	return params["max_generations"]


static func income_scale() -> float:
	return params["income_scale"]


static func upkeep_scale() -> float:
	return params["upkeep_scale"]


static func exp_scale() -> float:
	return params["exp_scale"]


static func event_rate() -> float:
	return params["event_rate"]


static func world_growth_scale() -> float:
	return params["world_growth_scale"]


static func enemy_strength_scale() -> float:
	return params["enemy_strength_scale"]


static func ai_aggression() -> float:
	return params["ai_aggression"]


static func end_on_victory() -> bool:
	return params["end_on_victory"]


static func sect_game_over() -> bool:
	return params["sect_game_over"]
