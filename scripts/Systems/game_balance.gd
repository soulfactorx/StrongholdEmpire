class_name GameBalance
extends RefCounted

# 내정
const TRAIN_GOLD := 30
const TRAIN_FOOD := 20
const UPGRADE_LIBRARY_GOLD := 80
const UPGRADE_TRAINING_GOLD := 60
const UPGRADE_TREASURY_GOLD := 70

# 유지비 (계절마다)
const FOOD_PER_DISCIPLE := 2
const GOLD_PER_DISCIPLE := 1
## 시설 레벨 1을 넘는 단계마다 드는 금화
const FACILITY_UPKEEP_GOLD := 3
## 식량이 모자라면 모자란 식량 이 값마다 제자 1명이 떠난다 (최소 1명)
const DESERTION_FOOD_PER_DISCIPLE := 6
## 금화가 모자라면 명성이 떨어진다
const GOLD_SHORTAGE_REPUTATION_LOSS := 3

# 문파전 / 강호 세력
const WAR_ENEMY_DISCIPLE_LOSS := 3
const WAR_ENEMY_REPUTATION_LOSS := 5
const WAR_ATTITUDE_LOSS := 10
## 적 문파 제자가 이 수 이하로 줄면 굴복한다
const SUBJUGATE_DISCIPLE_THRESHOLD := 5
const SUBJUGATE_REPUTATION_BONUS := 15
const SUBJUGATE_GOLD_BONUS := 100
const WORLD_SECT_YEARLY_GROWTH := 2

# 판 평가 (시대 종결·엔딩 화면)
const SCORE_PER_LEVEL := 10
const SCORE_PER_ART := 15
const SCORE_PER_SUBJUGATION := 60
const SCORE_PER_DISCIPLE := 3
const SCORE_PER_GENERATION := 30
const SCORE_ENDING := 100
const SCORE_VICTORY := 150
## 점수 이상이면 해당 등급 (높은 순)
const SCORE_GRADES: Array = [
	[500, "강호제패"],
	[350, "일대종사"],
	[220, "명문의 기틀"],
	[120, "이름 있는 문파"],
]

# 게임오버
const SHORTAGE_GAME_OVER_SEASONS := 3

# 무공 연구
const BASE_RESEARCH_COST := 20
const RESEARCH_COST_PER_COMPLEXITY := 8
const BASE_SUCCESS_RATE := 50
const LIBRARY_SUCCESS_BONUS := 5
const WISDOM_SUCCESS_MULTIPLIER := 2
const COMPLEXITY_PENALTY := 8
const MIN_SUCCESS_RATE := 10
const MAX_SUCCESS_RATE := 95

# 역할 전환
const MANAGER_LEVEL_REQ := 3
const MANAGER_WISDOM_REQ := 18
const MANAGER_REPUTATION_REQ := 55
const LEADER_LEVEL_REQ := 5
const LEADER_REPUTATION_REQ := 75
const LEADER_DISCIPLE_REQ := 18

# 성장
const EXP_PER_LEVEL_STEP := 25  # 누적 경험치 요구량: 25 * L * (L - 1)
const MAX_LEVEL := 20
const YEARLY_TRAINING_EXP := 40
const LEVEL_UP_STAT_GAIN := 1
const LEVEL_UP_INTERNAL_GAIN := 10

# 전투
const SPAR_EXP := 30
const BASE_ATTACK_DAMAGE := 8
const ENEMY_BASE_ATTACK_DAMAGE := 10
## 무공 피해에 더하는 무력 비율
const ART_STRENGTH_RATIO := 0.3

# 전투 — 아군 제자
## 문파 방어 전투에 함께 나서는 제자 수 (보유 제자 수를 넘지 않음)
const DEFENSE_ALLY_COUNT := 2
## 무술장 레벨 1을 넘는 단계마다 제자의 무력·신법 증가
const ALLY_TRAINING_STAT_BONUS := 1

# 전투 — 지형
const FOREST_MOVE_COST := 2
const WATER_MOVE_COST := 3
const HIGH_MOVE_COST := 2
## 수풀에 선 대상이 받는 피해 배율
const FOREST_DEFENSE := 0.75
## 물에 선 공격자가 주는 피해 배율
const WATER_ATTACK := 0.8
## 고지에 선 공격자가 주는 피해 배율과 무공 사거리 보너스
const HIGH_ATTACK := 1.25
const HIGH_RANGE_BONUS := 1

# 전투 — 무공 효과
const AMBUSH_MULTIPLIER := 1.5
const ELEMENT_ADVANTAGE := 1.2
const ELEMENT_DISADVANTAGE := 0.85
const EMPOWER_MULTIPLIER := 1.25
const EMPOWER_TURNS := 2
const STUN_TURNS := 1
## 기절이 풀린 직후 다시 기절하지 않는 기간
const STUN_IMMUNE_TURNS := 2
const KNOCKBACK_WALL_BONUS := 0.2

# 전투 — 내공 폭주: 시전 후 내공이 최대치의 이 비율 미만이면 확률적으로 반동
const OVERLOAD_THRESHOLD := 0.25
const OVERLOAD_CHANCE := 30
const OVERLOAD_DAMAGE_PER_COST := 1.5

# 레거시
const RETIRE_AGE := 55
const RETIRE_LEVEL := 10

