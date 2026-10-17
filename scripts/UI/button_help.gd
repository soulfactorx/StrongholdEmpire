class_name ButtonHelp
extends RefCounted

## 버튼 기능 설명: 버튼을 길게 누르거나(터치) 마우스를 올려 두면(PC) 말풍선으로 보여 준다.
## 장면 버튼은 노드 이름으로, 코드로 만든 버튼은 글자(앞부분 일치)로 찾는다. 버튼에 "help" 메타를 주면 그것이 우선한다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 노드 이름 → 설명 (수치는 GameBalance에서 읽어 바뀌어도 맞게 한다)
static func _by_name() -> Dictionary:
	return {
		# 메인 메뉴
		"ContinueButton": "가장 최근 저장으로 이어서 합니다.",
		"NewGameButton": "시나리오와 시작 역할을 골라 새로 시작합니다. 처음이라면 「입문 수련」을 고르세요.",
		"LoadButton": "저장 슬롯(자동 저장 포함)을 골라 불러옵니다.",
		"QuitButton": "게임을 끝냅니다.",
		# 경영 화면
		"AdvanceTurnButton": "계절을 넘깁니다. 수입·유지비가 정산되고, 기연이 일어나고, 강호 세력이 움직입니다.",
		"TrainButton": "금화 %d·식량 %d로 제자를 1명 들이고 문주의 무력·신법·지혜 +1, 경험치 +10." % [_Balance.TRAIN_GOLD, _Balance.TRAIN_FOOD],
		"FacilityButton": "서고·무술장·금고·약방·연공실을 짓거나 넓힙니다. 넓힐수록 효과와 유지비가 함께 늘어납니다.",
		"ElixirButton": "금화 %d로 영약을 사 최대 내공 +%d. 계절에 한 번." % [_Balance.ELIXIR_GOLD, _Balance.ELIXIR_INTERNAL_GAIN],
		"FeastButton": "금화 %d·식량 %d로 연회를 열어 명성 +%d (문주면 불만도 -%d). 계절에 한 번." % [
			_Balance.FEAST_GOLD, _Balance.FEAST_FOOD, _Balance.FEAST_REPUTATION, _Balance.FEAST_DISCONTENT_RELIEF,
		],
		"MartialArtButton": "무공 연구소: 무공 창조, 비급 연구, 강화, 비전 지정, 상대 무공 분석.",
		"RoleButton": "조건을 채운 다른 역할로 바꿉니다(이적·배신·강등 포함). 역할마다 할 수 있는 일이 다릅니다.",
		"CombatButton": "라이벌과 연습 비무를 합니다. 이기면 경험치 +%d와 유대. 계절에 한 번." % _Balance.SPAR_EXP,
		"SectWarButton": "강호 세력 하나와 문파전을 치릅니다. 정찰·명령·진형으로 겨루고, 이기면 상대가 약해집니다.",
		"EndingButton": "엔딩별 조건과 진행 상황, 세대 전승을 봅니다.",
		"WorldButton": "강호 세력과 주요 인물, 강호 소식을 보고 외교를 합니다.",
		"DiscipleButton": "제자마다 배치·출전 지정·개별 수련·무공 전수를 합니다.",
		"BondButton": "인물과 대화·선물·비무로 유대를 쌓습니다. 계절마다 횟수가 정해져 있습니다.",
		"SaveButton": "저장 슬롯을 골라 저장합니다. (철인 모드는 자동 저장만)",
		"HelpButton": "규칙과 단축키를 모아 둔 플레이 가이드를 엽니다.",
		"OptionsButton": "음량·글자 크기·전투 속도·전체 화면을 바꿉니다.",
		"MainMenuButton": "메인 메뉴로 나갑니다. 저장하지 않은 진행은 사라집니다.",
		# 무공 연구소
		"CreateButton": "고른 범주·속성·음양·특수 효과로 새 무공을 연구합니다. 연구점이 들고, 실패할 수 있습니다.",
		"ResearchPresetButton": "목록에서 고른 비급을 연구점으로 익힙니다.",
		"EnhanceButton": "익힌 무공 하나의 위력을 연구점으로 올립니다.",
		"SecretButton": "익힌 무공 하나를 문파 비전으로 정합니다. 제자에게 전수하기 쉬워집니다.",
		"AnalyzeButton": "겪어 본 상대 무공의 속성을 분석해, 상극 속성 무공 창조 성공률을 올립니다.",
		# 문파전
		"ScoutButton": "금화로 적의 명령 계획을 미리 봅니다. 볼수록 비용이 오릅니다.",
		"ChargeButton": "돌격: 측면 공격에 강하고 방어에 약합니다.",
		"DefendButton": "방어: 돌격에 강하고 측면 공격에 약합니다.",
		"FlankButton": "측면 공격: 방어에 강하고 돌격에 약합니다.",
		"RetreatButton": "후퇴: 손실을 줄이고 물러납니다.",
		"ResetButton": "고른 명령을 모두 지웁니다.",
		"ExecuteButton": "고른 명령 %d개로 문파전을 치릅니다." % _Balance.WAR_ROUNDS,
		# 전투
		"ModeMoveButton": "이동: 옥색 칸을 눌러 움직입니다. 칸마다 행동력이 듭니다.",
		"ModeAttackButton": "기본 공격: 붙어 있는 적을 누릅니다. 차례에 한 번, 행동력 1.",
		"UndoMoveButton": "공격·무공을 쓰기 전이면 방금 이동을 되돌립니다.",
		"EndTurnButton": "아군 턴을 마칩니다. 적이 모두 움직인 뒤 다음 라운드의 아군 턴이 됩니다.",
		"NextAllyButton": "행동력이 남은 다음 아군을 고릅니다. 아군 칸을 눌러도 고를 수 있습니다.",
		"HistoryButton": "이번 전투에서 오간 이동·공격·피해·체력 변화를 라운드별로 봅니다.",
		"PreviewConfirmButton": "미리 본 대로 공격·무공을 실행합니다.",
		"PreviewCancelButton": "실행하지 않고 돌아갑니다. 행동력·내공은 그대로입니다.",
		# 공용
		"BackButton": "이전 화면으로 돌아갑니다.",
		"SuccessionButton": "후계자를 정해 다음 세대로 이어 갑니다.",
		"StartButton": "고른 시나리오와 역할로 게임을 시작합니다.",
		"SettingsToggle": "게임 길이·난이도 같은 세부 설정을 펼치거나 접습니다.",
	}


## 버튼 글자 앞부분 → 설명 (코드로 만든 버튼)
static func _by_text() -> Dictionary:
	return {
		"대화": "유대 +%d (매력이 높을수록 더). 원한이면 원한이 누그러집니다." % _Balance.TALK_BOND,
		"선물": "금화 %d로 유대 +%d." % [_Balance.GIFT_GOLD, _Balance.GIFT_BOND],
		"비무 신청": "그 인물과 비무합니다. 이기면 유대 +%d." % _Balance.SPAR_BOND_WIN,
		"배치": "누를 때마다 서고 → 무술장 → 금고 → 없음 순으로 배치를 바꿉니다.",
		"출전": "문파 방어전에 함께 싸울 제자로 지정하거나 해제합니다.",
		"수련 (금화": "금화를 들여 이 제자만 경험치를 얻습니다. 계절에 한 번.",
		"무공 전수": "주인공이 익힌 무공 하나를 이 제자에게 가르칩니다. 연구점이 듭니다.",
		"외교": "사절·동맹·혼담·도전장·공물 중에서 고릅니다. 태도가 높아야 맺을 수 있는 것이 있습니다.",
		"닫기": "창을 닫습니다.",
	}


## 버튼 설명. 없으면 ""
static func text_for(button: Button) -> String:
	if button.has_meta("help"):
		return str(button.get_meta("help"))
	var by_name: Dictionary = _by_name()
	if by_name.has(button.name):
		return by_name[button.name]
	for prefix in _by_text():
		if button.text.begins_with(prefix):
			return _by_text()[prefix]
	return ""


## 설명이 있는 버튼에 길게 누르기·마우스 올림 말풍선을 붙인다. (한 번만)
static func attach(button: Button) -> void:
	if button.has_meta("help_attached"):
		return
	button.set_meta("help_attached", true)
	LongPressTip.attach_button(button, func() -> String: return text_for(button))
