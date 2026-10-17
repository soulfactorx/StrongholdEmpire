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
const WAR_ROUNDS := 3
## 명령 상성: 이기는 명령·지는 명령의 전력 배율 (돌격 > 측면 > 방어 > 돌격)
const WAR_ADVANTAGE := 1.3
const WAR_DISADVANTAGE := 0.8
## 후퇴한 라운드의 전력 배율. 대신 패배 시 제자 손실이 라운드당 1 줄어든다
const WAR_RETREAT_POWER := 0.6
## 진형이 강화하는 명령의 배율과, 그 명령을 이기는 명령(진형의 약점)의 배율
const WAR_FORMATION_BONUS := 1.15
const WAR_FORMATION_PENALTY := 0.95
## 같은 명령을 연달아 쓰면 읽혀서 약해진다 ("같은 수는 두 번 통하지 않는다")
const WAR_REPEAT_PENALTY := 0.85
## 전장의 변수: 라운드마다 양측 전력에 ±이 비율만큼 운이 작용한다
const WAR_LUCK := 0.1
## 적은 지난 문파전에서 본 아군 명령을 기억하고, 라운드마다 이 확률로 그 명령을 이기는 수를 준비한다
const WAR_ADAPT_CHANCE := 0.4
## 정찰 비용 (한 번 할 때마다 STEP씩 비싸짐). 스파이·암살자는 절반
const WAR_SCOUT_COST := 40
const WAR_SCOUT_COST_STEP := 20
## 장수: 유대가 이 이상인 사제·혈맹 인물이 참전. 전투력의 일부와 특기 명령 보너스
const WAR_GENERAL_MIN_BOND := 50
const WAR_GENERAL_POWER_RATIO := 0.5
const WAR_GENERAL_SPECIALTY_BONUS := 1.1
## 성향별 기본 전술(명령 선택 가중치)과 진형. 문파 데이터의 war_tactics·war_formation이 우선.
## 진형의 약점(강화 명령을 이기는 명령)이 그 성향이 덜 쓰는 명령에 오도록 골랐다.
## 바꾸면 스모크 테스트의 문파전 밸런스 검사(고정 조합 승률 60% 이하)로 확인한다.
const WAR_TACTICS: Dictionary = {
	"RIGHTEOUS": {"CHARGE": 0.25, "DEFEND": 0.4, "FLANK": 0.3, "RETREAT": 0.05},
	"UNORTHODOX": {"CHARGE": 0.4, "DEFEND": 0.15, "FLANK": 0.4, "RETREAT": 0.05},
	"DEMONIC": {"CHARGE": 0.35, "DEFEND": 0.2, "FLANK": 0.4, "RETREAT": 0.05},
}
const WAR_FORMATIONS: Dictionary = {
	"RIGHTEOUS": "CRANE",
	"UNORTHODOX": "FISH",
	"DEMONIC": "FISH",
}
## 승리 보상과 패배 손실
const WAR_WIN_REPUTATION := 8
const WAR_WIN_REPUTATION_PER_ROUND := 3
const WAR_WIN_GOLD := 40
const WAR_WIN_GOLD_PER_ROUND := 15
const WAR_WIN_EXP := 25
const WAR_LOSS_DISCIPLES := 2
const WAR_LOSS_REPUTATION := 5
const WAR_LOSS_REPUTATION_PER_ROUND := 2
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

