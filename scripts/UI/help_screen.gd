extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

@onready var help_label: Label = %HelpLabel


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	help_label.text = """[ 강호제패 플레이 가이드 ]

■ 문파 경영
  계절을 진행하며 자원을 모으고 시설을 확장합니다.
  기연 이벤트가 발생하면 선택지를 고르세요.

■ 무공 창조
  카테고리·오행·음양·효과를 조합해 나만의 무공을 만듭니다.
  data/martial_arts/ 폴더에 JSON을 추가하면 모드 무공이 로드됩니다.

■ 역할 전환
  성장에 따라 중간관리자, 스파이, 문주, 낭인 등으로 전환됩니다.
  [역할 전환] 버튼에서 조건 충족 시 선택 가능합니다.

■ 문파전 / 전술 전투
  문파전: 3라운드 지휘 명령 (돌격·방어·측면·후퇴)
  결투: 그리드 위 1:1 전투, 무공 시전 가능

■ 엔딩 / 레거시
  5가지 엔딩 분기. 달성 후 세대 전승으로 후계자 플레이 가능.

■ 저장
  메인 메뉴에서 저장/불러오기 (1슬롯)"""


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")