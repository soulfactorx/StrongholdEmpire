class_name GameBalance
extends RefCounted

# 내정
const TRAIN_GOLD := 30
const TRAIN_FOOD := 20

# 계절 수입 (신분 보정·시나리오 수입 배율을 곱하기 전)
const BASE_GOLD_INCOME := 15
const TREASURY_GOLD_PER_LEVEL := 10
const BASE_FOOD_INCOME := 30
const TRAINING_FOOD_PER_LEVEL := 5
const LIBRARY_RESEARCH_PER_LEVEL := 3
const WISDOM_RESEARCH_RATIO := 0.5
## 계절별 보정: { 계절: [은자, 식량, 깨달음] }
const SEASON_INCOME_BONUS: Dictionary = {
	"봄": [0, 15, 0],
	"여름": [10, 0, 0],
	"가을": [0, 25, 0],
	"겨울": [0, -10, 5],
}
## 해마다 제자 이만큼마다 명성 +1 (문하생이 강호에 이름을 알린다)
const DISCIPLES_PER_YEARLY_REPUTATION := 5

# 재고 손실 (해마다): 쌓아 둔 재물은 노리는 자가 많고, 곡식은 상한다
const GOLD_SAFE_AMOUNT := 500
const GOLD_LOSS_RATE := 0.15
const FOOD_SAFE_AMOUNT := 300
const FOOD_SPOIL_RATE := 0.2

# 전각: 확장 비용 = base + step × (현재 단계 - 시작 단계). 씀씀이는 시작 단계를 넘는 단계마다
## { 전각 id: [시작 단계, 최대 단계, base 비용, step 비용] }
const FACILITIES: Dictionary = {
	"library": [1, 5, 80, 40],
	"training_ground": [1, 5, 60, 30],
	"treasury": [1, 5, 70, 35],
	"apothecary": [0, 3, 90, 45],
	"meditation_hall": [0, 3, 100, 50],
}
## 약방: 단계마다 계절 내공 회복 (최대 내공 대비)
const APOTHECARY_INTERNAL_REGEN := 0.15
## 연공실: 단계마다 계절 수련
const MEDITATION_EXP_PER_LEVEL := 8

# 제자 명단 (플레이어 문파)
## 새 제자의 무력·신법·지혜 범위
const DISCIPLE_STAT_MIN := 8
const DISCIPLE_STAT_MAX := 12
## 다음 경지까지 필요한 수련 = 이 값 × 현재 단계
const DISCIPLE_EXP_PER_LEVEL := 40
const DISCIPLE_MAX_LEVEL := 10
const DISCIPLE_BASE_INTERNAL := 60
const DISCIPLE_INTERNAL_PER_LEVEL := 10
## 개별 수련: 은자를 내고 수련을 얻는다 (제자마다 계절에 한 번)
const DISCIPLE_TRAIN_GOLD := 20
const DISCIPLE_TRAIN_EXP := 30
## 방어전에서 살아남은 참전 제자의 수련
const DISCIPLE_BATTLE_EXP := 25
## 배치: 전각 단계마다 담당 자리 하나
const DISCIPLE_SLOTS_PER_LEVEL := 1
## 서고 담당: 지혜 이만큼마다 계절 깨달음 +1 / 금고 담당: 지혜 이만큼마다 계절 은자 +1
const DISCIPLE_LIBRARY_WISDOM_PER_POINT := 5
const DISCIPLE_TREASURY_WISDOM_PER_GOLD := 4
## 연무장 담당: 계절마다 수련
const DISCIPLE_TRAINING_GROUND_EXP := 15
## 문파전 전력: 제자 경지 1을 넘는 단계마다
const DISCIPLE_LEVEL_WAR_POWER := 1

# 계절 행동 (계절마다 한 번)
const ELIXIR_GOLD := 100
const ELIXIR_INTERNAL_GAIN := 10
const FEAST_GOLD := 60
const FEAST_FOOD := 40
const FEAST_REPUTATION := 4

# 씀씀이 (계절마다)
const FOOD_PER_DISCIPLE := 2
const GOLD_PER_DISCIPLE := 1
## 전각이 시작 단계를 넘는 단계마다 드는 은자
const FACILITY_UPKEEP_GOLD := 4
## 식량이 모자라면 모자란 식량 이 값마다 제자 1명이 떠난다 (최소 1명)
const DESERTION_FOOD_PER_DISCIPLE := 6
## 은자가 모자라면 명성이 떨어진다
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
## 정찰 비용 (한 번 할 때마다 STEP씩 비싸짐). 간자·자객은 절반
const WAR_SCOUT_COST := 40
const WAR_SCOUT_COST_STEP := 20
## 장수: 유대가 이 이상인 사제·혈맹 인물이 참전. 전투력의 일부와 특기 명령 가산
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

# 판 평가 (시대 종결·결말 화면)
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

# 무공 참오
const BASE_RESEARCH_COST := 20
const RESEARCH_COST_PER_COMPLEXITY := 8
const BASE_SUCCESS_RATE := 50
const LIBRARY_SUCCESS_BONUS := 5
const WISDOM_SUCCESS_MULTIPLIER := 2
const COMPLEXITY_PENALTY := 8
const MIN_SUCCESS_RATE := 10
const MAX_SUCCESS_RATE := 95

# 세력 AI (M6-2). 강호 세력이 계절마다 행동 하나를 고른다
## 성향별 행동 가중치 [성장, 다른 세력 공격, 플레이어 침공, 외교]. 공격·침공은 시나리오 ai_aggression을 곱한다
const AI_WEIGHTS: Dictionary = {
	"RIGHTEOUS": [0.5, 0.15, 0.05, 0.3],
	"UNORTHODOX": [0.4, 0.3, 0.2, 0.1],
	"DEMONIC": [0.45, 0.3, 0.15, 0.1],
}
## 성장: 제자·명성. 정원의 절반이 안 되는 세력은 더 빨리 회복한다
const AI_GROWTH_DISCIPLES := 1
const AI_GROWTH_DISCIPLES_SMALL := 2
const AI_GROWTH_REPUTATION := 1
## 세력끼리의 전쟁: 전력에 ±운, 지키는 쪽에 가산. 진 쪽은 제자를 잃고(최소 AI_MIN_DISCIPLES), 이긴 쪽은 일부를 흡수한다
const AI_WAR_LUCK := 0.2
const AI_WAR_DEFENDER_BONUS := 1.2
const AI_WAR_LOSS := 2
const AI_WAR_ABSORB := 1
const AI_WAR_REPUTATION := 3
const AI_MIN_DISCIPLES := 3
## 제자가 이보다 적은 세력은 다른 세력이 치지 않는다 (몰락한 세력을 끝까지 짓밟지 않는다)
const AI_ATTACK_MIN_TARGET_DISCIPLES := 10
## 같은 성향 세력을 공격할 가중치 (다른 성향은 1)
const AI_SAME_ALIGNMENT_ATTACK := 0.3
## 침공: 태도가 이 값 미만인 세력만. 태도가 낮을수록 잦다 (-50이면 1배, -100이면 2배)
const AI_INVASION_MAX_ATTITUDE := -20
const AI_INVASION_COOLDOWN := 4
## 첫해에는 침공하지 않는다
const AI_INVASION_GRACE_YEARS := 1
## 침공 대응: 은자로 물리기, 산문을 내주기 (방치하면 다음 계절에 산문을 내준 것으로 처리)
const INVASION_BRIBE_GOLD := 120
const INVASION_YIELD_DISCIPLES := 3
const INVASION_YIELD_REPUTATION := 6
## 침공을 막아 내면 침략 세력이 잃는 제자
const INVASION_REPEL_LOSS := 4
## 외교: 태도가 이 이상인 세력은 플레이어에게 사절을 보내 태도를 올린다
const AI_DIPLOMACY_MIN_ATTITUDE := -50
const AI_DIPLOMACY_ATTITUDE := 5
## 확장(주인 없는 땅 차지)·내실(연무장 확장) 기본 가중치. 세력 전략(FactionStrategy) 배율을 곱한다
const AI_EXPAND_WEIGHT := 0.12
const AI_FORTIFY_WEIGHT := 0.15
## 내실: 연무장을 한 단계 넓히는 은자와 최대 단계 (확장은 세력 전력이 그 땅의 주둔 병력 이상이어야 한다)
const AI_FORTIFY_GOLD := 150
const AI_FORTIFY_MAX_LEVEL := 5

# 강호 지도
## 땅 하나마다 늘어나는 제자 정원
const REGION_MAX_DISCIPLES := 3
## 주인 없는 땅 평정 비용: 은자 = 이 값 + 주둔 병력 / 2, 식량
const REGION_PACIFY_GOLD := 60
const REGION_PACIFY_FOOD := 30
## 강호 소식은 최근 이만큼 보관한다
const WORLD_NEWS_LIMIT := 20

# 외교 (M6-1). 세력마다 계절에 한 번
const DIPLOMAT_ENVOY_GOLD := 60
const DIPLOMAT_ENVOY_ATTITUDE := 10
## 동맹: 태도가 이 이상이어야 받아들인다. 동맹을 깨면 태도·명성이 떨어진다
const ALLIANCE_MIN_ATTITUDE := 50
const ALLIANCE_ATTITUDE_GAIN := 10
const ALLIANCE_BREAK_ATTITUDE := 30
const ALLIANCE_BREAK_REPUTATION := 5
## 동맹 세력은 문파전에 자기 전력의 이 비율만큼 원군을 보낸다
const ALLY_WAR_SUPPORT_RATIO := 0.2
## 혼담: 그 세력 인물과 연애 유대가 이 이상이어야 한다. 성사되면 동맹을 맺는다
const MARRIAGE_MIN_BOND := 60
const MARRIAGE_GOLD := 150
const MARRIAGE_ATTITUDE := 30
const MARRIAGE_REPUTATION := 8
## 도전장: 보내면 명성 +, 태도 -. 그 세력과의 문파전 승패에 명성이 더 걸린다
const CHALLENGE_REPUTATION := 3
const CHALLENGE_ATTITUDE := 15
const CHALLENGE_WIN_REPUTATION := 10
const CHALLENGE_LOSS_REPUTATION := 8
## 공물: 굴복한 세력이 계절마다 바친다. 바칠수록 원망이 쌓이고, 태도가 너무 낮으면 끊는다
const TRIBUTE_GOLD := 25
const TRIBUTE_ATTITUDE_PER_SEASON := 2
const TRIBUTE_REVOLT_ATTITUDE := -80
const TRIBUTE_RELEASE_ATTITUDE := 20

# 개인 재산 (낭인·청부객·간자·자객): 문파 금고와 따로인 내 은자·식량
const PURSE_START_GOLD := 150
const PURSE_START_FOOD := 80
## 문파 일을 떠나 떠돌게 될 때 문파 금고에서 챙기는 노자 (금고에 있는 만큼까지)
const PURSE_ALLOWANCE_GOLD := 100
const PURSE_ALLOWANCE_FOOD := 50
## 계절마다 생활비: 식량을 먹고 은자를 쓴다. 식량이 모자라면 식량 1당 은자 LIVING_FOOD_PRICE로 사 먹는다
const LIVING_GOLD := 5
const LIVING_FOOD := 10
const LIVING_FOOD_PRICE := 1
## 은자마저 떨어져 굶으면 내공이 이만큼 준다
const STARVE_INTERNAL_LOSS := 30
## 이동: 개인 재산을 쓰는 신분(낭인·청부객·간자·자객)은 계절에 한 번 지도에서 다른 지역으로 옮긴다. 여비는 한 걸음에 이만큼
const TRAVEL_GOLD_PER_STEP := 5
## 무소속으로 시작할 때 있는 지역 (지도 한가운데)
const START_REGION := "luoyang"
## 간자가 계절마다 받는 활동비
const SPY_STIPEND_GOLD := 15

# 혼인: 연인과 유대 MARRIAGE_MIN_BOND 이상이면 청혼할 수 있다. 배우자는 여럿 둘 수 있다
const WEDDING_GOLD := 100
const WEDDING_REPUTATION := 3
const WEDDING_BOND := 10
## 배우자가 몸담은 세력의 태도
const WEDDING_ATTITUDE := 15
## 새 배우자를 맞으면 이미 있던 배우자의 유대가 이만큼 준다
const SPOUSE_JEALOUSY_BOND := 8

# 인연 (M5-2)
## 인물과의 상호작용(대화·선물·비무)은 계절마다 이만큼
const INTERACTIONS_PER_SEASON := 2
## 대화: 유대 +기본값 + 매력 ÷ 나눗수
const TALK_BOND := 3
const TALK_CHARISMA_DIVISOR := 10
const GIFT_GOLD := 40
const GIFT_BOND := 8
## 비무: 이기면 유대 +WIN, 져도 +LOSE
const SPAR_BOND_WIN := 5
const SPAR_BOND_LOSE := 2
## 인물이 좋아하는 상호작용(담소·선물·비무)이면 유대 증가 배율
const LIKE_BOND_MULTIPLIER := 1.5
## 이 유대 이상인 사제·혈맹·연인 인물이 방어전에 아군으로 합류한다
const BOND_ALLY_MIN := 60
const BOND_ALLY_COUNT := 1
## 배신하면 떠나온 문파 인물과의 관계가 원한으로 바뀐다. 깊던 정만큼 원한도 깊고, 최소 이 값
const BETRAY_HATRED_MIN := 30

# 전수·강화·비전·분석 (M7-2)
## 전수 비용(깨달음) = BASE + 복잡도 × PER_COMPLEXITY. 문파 비전은 SECRET_SCALE 배
const TRANSMIT_RESEARCH_BASE := 10
const TRANSMIT_RESEARCH_PER_COMPLEXITY := 5
const TRANSMIT_SECRET_SCALE := 0.5
## 전수받을 제자의 경지 요구 = 복잡도 ÷ 이 값 (올림)
const TRANSMIT_COMPLEXITY_PER_LEVEL := 2
## 강화: 문파 공동 참오. 비용 = BASE + 현재 강화 단계 × STEP
const ENHANCE_MAX_LEVEL := 3
const ENHANCE_RESEARCH_BASE := 30
const ENHANCE_RESEARCH_STEP := 20
const ENHANCE_DAMAGE := 3
const ENHANCE_HEAL := 4
const ENHANCE_INTERNAL_COST_REDUCTION := 1
## 비전으로 지정하려면 이 단계 이상 강화해야 한다
const SECRET_ART_MIN_ENHANCE := 1
## 상대 무공 분석: 분석한 속성을 이기는 속성의 무공을 창안할 때 성공률 가산
const ANALYZE_RESEARCH := 25
const COUNTER_SUCCESS_BONUS := 15

# 신분 전환
const MANAGER_LEVEL_REQ := 3
const MANAGER_WISDOM_REQ := 18
const MANAGER_REPUTATION_REQ := 55
const LEADER_LEVEL_REQ := 5
const LEADER_REPUTATION_REQ := 75
const LEADER_DISCIPLE_REQ := 18
## 청부객으로 전환할 수 있는 낭인 경지
const MERCENARY_LEVEL_REQ := 3
## 입문: 무소속이 그 세력과 신용 JOIN_CREDIT_REQ 이상이거나, 그 세력 인물과 유대 JOIN_BOND_REQ 이상(연줄)이면 제자로 들어간다
const JOIN_CREDIT_REQ := 15
const JOIN_BOND_REQ := 30
## 정파는 도덕이 이 이상이어야 받는다 (그 세력 신용이 마이너스면 어디든 거절)
const JOIN_RIGHTEOUS_MORALITY := 40
## 입문하면 그 세력 문주와 사부 인연 (이미 인연이 없을 때)
const JOIN_MASTER_BOND := 25
## 문파를 떠나기: 막내 제자는 이 경지부터. 사부 유대가 LEAVE_BLESSING_BOND 이상이면 허락받은 하산
const LEAVE_LEVEL_REQ := 2
const LEAVE_BLESSING_BOND := 40
const LEAVE_BLESSED_ATTITUDE := 10
## 탈문: 떠나온 문파의 태도, 사부·동문 유대 감소
const LEAVE_DESERT_ATTITUDE := -20
const LEAVE_DESERT_BOND := 15
## 축출된 문주가 떠나온 문파의 태도
const LEAVE_OUSTED_ATTITUDE := -30
## 이적: 그 세력과의 신용도가 이 이상이면 객경으로 들어갈 수 있다
const DEFECT_CREDIT_REQ := 40
## 배신: 도덕이 이 이하이면 적대 세력으로 넘어갈 수 있다
const BETRAY_MORALITY_REQ := 30
const BETRAY_MORALITY_LOSS := 15
## 떠나온 문파의 태도 (이적·배신)
const DEFECT_OLD_SECT_ATTITUDE := -20
const BETRAY_OLD_SECT_ATTITUDE := -70
## 강등: 신분 행동 실패가 이만큼 쌓이면 총관은 막내 제자로 내려간다
const DEMOTION_FAILURES := 3

# 신분 고유 행동 (계절마다 ROLE_ACTIONS_PER_SEASON번, 신분 행동끼리 공유)
const ROLE_ACTIONS_PER_SEASON := 1
## 문주: 내부 불만도. 계절마다 오르고, 회의·연회로 낮춘다. 100이면 축출
const DISCONTENT_PER_SEASON := 3
const DISCONTENT_SHORTAGE := 6
const DISCONTENT_REBELLION := 70
const DISCONTENT_OUSTED := 100
const FEAST_DISCONTENT_RELIEF := 8
const COUNCIL_GOLD := 40
const COUNCIL_DISCONTENT_RELIEF := 20
const ENVOY_GOLD := 60
const ENVOY_ATTITUDE := 12
## 총관: 문주 신임도와 부서
const MANAGER_START_TRUST := 50
## 문주 승계에 필요한 신임도
const MANAGER_TRUST_FOR_LEADER := 50
const DEPT_TRUST_PER_SEASON := 2
const DEPT_FINANCE_GOLD_BONUS := 0.2
const DEPT_TRAINING_EXP := 25
const DEPT_INTEL_SCOUT_SCALE := 0.5
const PROPOSAL_REPUTATION := 5
const PROPOSAL_TRUST_GAIN := 10
const PROPOSAL_TRUST_LOSS := 15
const PROPOSAL_MAX_CHANCE := 90
## 막내 제자: 가르침 (유대가 높을수록 깨달음 확률 = 유대 / 2 %)
const TEACH_EXP := 20
const TEACH_BOND := 3
## 막내 제자: 외출에서 기연이 없을 때 얻는 소득
const OUTING_GOLD := 25
const OUTING_EXP := 15
## 낭인: 의뢰 게시판. 호위 성공률 = 기본 + (전투력 - 기준) × 배율, 타지에서는 보상 증가·성공률 감소
const JOB_ESCORT_GOLD := 60
const JOB_ESCORT_BASE_CHANCE := 60
const JOB_ESCORT_POWER_BASE := 40
const JOB_ESCORT_POWER_SCALE := 2
const JOB_SEARCH_RESEARCH := 15
const JOB_SEARCH_EXP := 30
const JOB_HUNT_GOLD := 80
const JOB_AWAY_REWARD_SCALE := 1.5
const JOB_AWAY_RISK := 15
const JOB_CREDIT_GAIN := 5
## 간자: 노출도. 100이면 정체가 드러난다
const EXPOSURE_INTEL := 12
const EXPOSURE_SABOTAGE := 25
const EXPOSURE_DECAY := 5
const EXPOSURE_MAX := 100
const INTEL_RESEARCH := 10
## 정보 수집을 이만큼 하면 간자 임무 완료
const SPY_MISSION_INTEL := 3
const SABOTAGE_DISCIPLES := 3
const SABOTAGE_GOLD := 60
## 자객: 현상금. 표적 의뢰마다 오르고 계절마다 조금씩 잊힌다
const BOUNTY_PER_CONTRACT := 20
const BOUNTY_DECAY := 2
const BOUNTY_PURSUIT := 50
const ASSASSINATION_GOLD := 120
const ASSASSINATION_EXP := 40
const LIE_LOW_GOLD := 50
const LIE_LOW_BOUNTY := 20
## 청부객: 세력별 계약. 선금을 받고 기한 안에 이행한다
const CONTRACT_REWARD := 120
const CONTRACT_ADVANCE_RATIO := 0.3
const CONTRACT_SEASONS := 2
const CONTRACT_BASE_CHANCE := 45
const CONTRACT_LEVEL_CHANCE := 5
const CONTRACT_MAX_CHANCE := 95
const CONTRACT_CREDIT_GAIN := 15
const CONTRACT_FAIL_CREDIT := 10
const CONTRACT_BREACH_CREDIT := 30
const CONTRACT_BREACH_GOLD := 100
const CONTRACT_BREACH_ATTITUDE := 15
## 신용도가 이 값 미만이면 그 세력이 계약을 주지 않는다
const CONTRACT_MIN_CREDIT := -30
const CREDIT_LIMIT := 100

# 성장
const EXP_PER_LEVEL_STEP := 25  # 누적 수련 요구량: 25 * L * (L - 1)
const MAX_LEVEL := 20
const YEARLY_TRAINING_EXP := 40
const LEVEL_UP_STAT_GAIN := 1
const LEVEL_UP_INTERNAL_GAIN := 10

# 전투
const SPAR_EXP := 30
## 회심(치명타): 확률 = 기본 + 신법 × 계수 (상한), 피해 배율
const CRIT_BASE := 0.03
const CRIT_PER_AGILITY := 0.004
const CRIT_MAX := 0.25
const CRIT_MULTIPLIER := 1.5
const AMBUSH_MULTIPLIER := 1.5
const ELEMENT_ADVANTAGE := 1.2
const ELEMENT_DISADVANTAGE := 0.85

# 전투 — 아군 제자
## 문파 방어 전투에 함께 나서는 제자 수 (보유 제자 수를 넘지 않음)
const DEFENSE_ALLY_COUNT := 2
## 연무장 1단계를 넘는 단계마다 제자의 무력·신법 증가
const ALLY_TRAINING_STAT_BONUS := 1

# 전투 — 초식 배치 대결 (DuelRules·DuelEngine)
## 초식 피해에 더하는 무력 비율
const DUEL_STRENGTH_RATIO := 0.8
## 기세 상한과 기세 한 점마다 피해 증가
const DUEL_MAX_MOMENTUM := 5
const DUEL_MOMENTUM_DAMAGE := 0.05
## 상성 배율: 빈틈·운기 중 받는 피해, 막기가 속공·술을 받을 때, 회피가 빠른 공격에 스칠 때, 속공에 끊긴 강공·술
const DUEL_GAP_TAKEN := 1.2
const DUEL_FOCUS_TAKEN := 1.3
const DUEL_GUARD_QUICK := 0.25
const DUEL_GUARD_TRICK := 0.6
const DUEL_EVADE_GRAZE := 0.5
const DUEL_INTERRUPTED := 0.5
## 숙련 단계마다 피해 증가
const DUEL_TIER_DAMAGE := 0.1
## 막기의 반격 피해 = 기본 + 무력 × 비율
const DUEL_COUNTER_BASE := 6
const DUEL_COUNTER_RATIO := 0.5
## 운기조식의 내공 회복 (여기에 지혜의 절반을 더한다)
const DUEL_FOCUS_ENERGY := 20
## 한 대결(두 사람)의 합 수. 넘으면 체력 비율이 낮은 쪽이 물러난다
const DUEL_MAX_BOUTS := 4
## 탈출 목표: 주인공이 흘려야 하는 공격 수
const DUEL_ESCAPE_EVADES := 3
## 우두머리 목표: 호위 하나마다 우두머리 체력 증가
const DUEL_GUARD_HP_BONUS := 0.15
## 상대 AI·자동 배치가 지난 합의 유형을 읽어 맞받는 확률
const DUEL_ENEMY_COUNTER_RATE := 0.45
const DUEL_PLAYER_AUTO_COUNTER_RATE := 0.6
## 호위 목표: 우리 쪽이 대결에서 질 때마다 상대가 뚫고 들어와 지킬 인물이 잃는 체력 비율
const DUEL_WARD_HIT := 0.4
## 동료는 합이 끝났을 때 체력이 이 비율 아래면 부상으로 물러난다
const DUEL_ALLY_RETREAT_RATIO := 0.3
## 합격 초식을 펼칠 만큼 깊은 인연, 합격의 위력(여기에 동료 무력을 더함)과 기세
const DUEL_COMBO_BOND := 40
const DUEL_COMBO_POWER := 18
const DUEL_COMBO_MOMENTUM := 2

# 전투 — 다양화: 형식 (docs/전투_다양화_설계.md)
## 포위: 한꺼번에 나서는 우리 쪽·상대 쪽 수, 졸개의 칸 수, 압박(살아 있는 적이 이 수 이상이면 칸마다 주인공 기세 +1)
const SIEGE_FRIENDS := 2
const SIEGE_FOES := 3
const MOOK_SLOTS := 2
## 포위·진형의 졸개는 체력·피해가 더 약하다 (여럿이 한꺼번에 덤비므로)
const MOOK_HP := 0.75
const MOOK_DAMAGE := 0.7
const SIEGE_PRESSURE_FOES := 3
## 휩쓸기: 고른 상대 말고 나머지에게 주는 피해 비율
const SWEEP_SPLASH := 0.6
## 진형: 한꺼번에 나서는 수(앞 2·뒤 1), 협공 추가 피해, 엄호가 대신 받는 비율
const FORMATION_SIZE := 3
const FORMATION_FRONT := 2
const FLANK_BONUS := 0.3
const COVER_SHARE := 0.5
## 추격: 거리(0이면 붙잡힘, 끝이면 놓침)와 칸마다 변화
const CHASE_START := 5
const CHASE_END := 10
const CHASE_RUNNER_WIN := 2
const CHASE_RUNNER_HIT := 1
const CHASE_HUNTER_HEAVY := 2
const CHASE_FOCUS := 1
## 잠입: 발각 게이지 상한(경보), 첫 합 기습 배율
const STEALTH_ALARM := 5
const STEALTH_AMBUSH := 2.0
## 대치: 이기는 기세, 합 수, 위압(매력) 기준, 이긴 뒤 이어지는 대결의 첫 기세
const STANDOFF_GOAL := 5
const STANDOFF_BOUTS := 3
const STANDOFF_PRESENCE_CHARISMA := 15
const STANDOFF_CARRY := 3
## 비무대회: 판 사이 회복(체력·내공 비율), 판마다 상대가 내 수를 읽는 확률 증가
const TOURNEY_HP_RECOVER := 0.3
const TOURNEY_ENERGY_RECOVER := 0.5
const TOURNEY_READ_STEP := 0.1

# 전투 — 다양화: 목표·전장·조건·특성
## 생포: 상대 체력이 이 비율 이하일 때 막기 반격·기절로 사로잡는다
const CAPTURE_RATIO := 0.25
## 전장: 다리에서 떨어지는 체력 비율, 배의 흔들림, 불길(합마다 체력 감소), 대숲의 술, 비무대 장외
const BRIDGE_FALL_RATIO := 0.2
const BOAT_SWAY := 0.7
const FIRE_BURN := 0.05
const BAMBOO_TRICK := 1.3
const RING_OUT_RATIO := 0.2
## 조건: 중독(합마다 내공), 부상(시작 체력), 지침(시작 내공)
const POISON_DRAIN := 10
const WOUNDED_HP := 0.7
const EXHAUSTED_ENERGY := 0.5
## 상대 특성: 광폭 기준·기세, 예고 절초 주기·위력, 독무, 금강불괴, 단계 전환
const ENRAGE_RATIO := 0.5
const ENRAGE_MOMENTUM := 2
const TELEGRAPH_EVERY := 3
const TELEGRAPH_POWER := 1.3
const POISON_MIST := 0.1
const IRON_BODY_QUICK := 0.5
const SECOND_PHASE_HP := 0.4
const SECOND_PHASE_POWER := 1.2
## 사건: 인연의 개입(받는 피해 감소·기세), 결단(목숨을 건다)
const INTERVENE_BOND := 40
const INTERVENE_MOMENTUM := 2
const ALL_IN_HP_COST := 0.3
const PARLEY_CHARISMA := 14
## 평가: 완승·신승 기준(주인공 남은 체력 비율), 도전 보상
const RATING_FLAWLESS := 0.7
const RATING_NARROW := 0.25
const DUEL_CHALLENGE_REPUTATION := 2
const DUEL_CHALLENGE_RESEARCH := 3
## 상대 절초를 받아 내면 얻는 깨달음
const STUDY_RESEARCH := 1

# 후대
const RETIRE_AGE := 55
const RETIRE_LEVEL := 10

