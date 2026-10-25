class_name FactionStrategy
extends RefCounted

## 강호 세력(NPC 진영)의 전략. 세력 AI가 계절마다 행동을 고를 때 성향별 가중치에 전략 배율을 곱한다.
## 문파 데이터의 "strategy"로 정하고, 새 게임 화면에서 세력마다 바꿀 수 있다. 없으면 성향별 기본값.

## 전략 id → {title, description, multipliers: [성장, 공격, 침공, 외교, 확장, 내실]} (SectAI.Action 순서)
const STRATEGIES: Dictionary = {
	"expansion": {
		"title": "영토 확장",
		"description": "주인 없는 땅을 먼저 차지하고, 맞닿은 세력의 땅을 노립니다.",
		"multipliers": [0.8, 1.0, 0.8, 0.5, 3.0, 0.6],
	},
	"military": {
		"title": "무력 강병",
		"description": "다른 세력과 우리 문파를 자주 칩니다. 전쟁으로 세를 불립니다.",
		"multipliers": [0.8, 2.2, 1.8, 0.3, 1.0, 1.0],
	},
	"economy": {
		"title": "내실 부강",
		"description": "제자를 기르고 연무장을 넓히며 금고를 채웁니다. 좀처럼 먼저 싸우지 않습니다.",
		"multipliers": [2.0, 0.4, 0.3, 1.0, 0.8, 2.5],
	},
	"diplomacy": {
		"title": "합종연횡",
		"description": "사절을 보내 관계를 다지고, 싸움은 피합니다.",
		"multipliers": [1.2, 0.5, 0.3, 3.0, 0.8, 0.8],
	},
	"opportunist": {
		"title": "기회주의",
		"description": "약해진 세력과 땅을 노려 빈틈을 칩니다.",
		"multipliers": [0.8, 1.6, 1.4, 0.6, 1.6, 0.6],
	},
}
## 새 게임 화면에서 고르는 "무작위"
const RANDOM := "random"

const DEFAULT_BY_ALIGNMENT: Dictionary = {
	SectData.Alignment.RIGHTEOUS: "diplomacy",
	SectData.Alignment.UNORTHODOX: "opportunist",
	SectData.Alignment.DEMONIC: "military",
}


static func is_valid(strategy_id: String) -> bool:
	return STRATEGIES.has(strategy_id)


static func get_ids() -> Array:
	return STRATEGIES.keys()


static func default_for(alignment: SectData.Alignment) -> String:
	return DEFAULT_BY_ALIGNMENT.get(alignment, "expansion")


## 세력의 전략 id (비어 있으면 성향별 기본값)
static func of(sect: SectData) -> String:
	return sect.strategy if is_valid(sect.strategy) else default_for(sect.alignment)


static func get_title(strategy_id: String) -> String:
	return STRATEGIES.get(strategy_id, {}).get("title", "?")


static func get_description(strategy_id: String) -> String:
	return STRATEGIES.get(strategy_id, {}).get("description", "")


static func get_multipliers(sect: SectData) -> Array:
	return STRATEGIES[of(sect)]["multipliers"]


## "무작위"를 실제 전략으로 바꾼다.
static func resolve(strategy_id: String) -> String:
	if strategy_id == RANDOM:
		var ids: Array = get_ids()
		return ids[randi() % ids.size()]
	return strategy_id
