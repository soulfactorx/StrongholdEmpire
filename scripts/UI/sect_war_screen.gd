extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const MAX_ROUNDS := 3

var _commands: Array[SectWarManager.Command] = []
var _targets: Array[SectData] = []

@onready var title_label: Label = %Title
@onready var target_option: OptionButton = %TargetOption
@onready var enemy_label: Label = %EnemyLabel
@onready var power_label: Label = %PowerLabel
@onready var round_label: Label = %RoundLabel
@onready var log_label: Label = %LogLabel
@onready var charge_button: Button = %ChargeButton
@onready var defend_button: Button = %DefendButton
@onready var flank_button: Button = %FlankButton
@onready var retreat_button: Button = %RetreatButton
@onready var execute_button: Button = %ExecuteButton


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	_fill_targets()
	if not GameManager.can_wage_war():
		log_label.text = "이번 계절에는 이미 문파전을 치렀습니다. 다음 계절을 기다리세요."
	_update_display()


func _fill_targets() -> void:
	_targets = GameManager.get_war_targets()
	target_option.clear()
	for sect in _targets:
		target_option.add_item("%s (%s)" % [sect.sect_name, sect.get_alignment_name()])
	if not _targets.is_empty():
		target_option.select(0)


func _get_target() -> SectData:
	var index: int = target_option.selected
	if index < 0 or index >= _targets.size():
		return null
	return _targets[index]


func _update_display() -> void:
	var power: int = SectWarManager.get_military_power(
		GameManager.player_sect,
		GameManager.player_character
	)
	power_label.text = "아군 전력: %d | 제%d세대 %s (%s)" % [
		power,
		GameManager.generation,
		GameManager.player_character.display_name,
		GameManager.player_character.get_role_name(),
	]

	var target: SectData = _get_target()
	if target == null:
		title_label.text = "문파전 지휘"
		enemy_label.text = "강호의 모든 세력이 굴복했습니다."
	else:
		title_label.text = "문파전 지휘 — %s" % target.sect_name
		enemy_label.text = "%s | 문주 %s | 제자 %d | 명성 %d | 태도 %s\n적 전력: %d" % [
			target.get_alignment_name(),
			target.leader_name,
			target.disciple_count,
			target.reputation,
			target.get_attitude_text(),
			SectWarManager.get_sect_power(target),
		]

	round_label.text = "지휘 명령: %d / %d" % [_commands.size(), MAX_ROUNDS]
	execute_button.disabled = (
		_commands.size() < MAX_ROUNDS or target == null or not GameManager.can_wage_war()
	)


func _add_command(command: SectWarManager.Command, name: String) -> void:
	if _commands.size() >= MAX_ROUNDS:
		log_label.text = "이미 3개 명령이 선택되었습니다."
		return
	_commands.append(command)
	log_label.text = "%s 명령 추가." % name
	_update_display()


func _on_target_selected(_index: int) -> void:
	_update_display()


func _on_charge_pressed() -> void:
	_add_command(SectWarManager.Command.CHARGE, "돌격")


func _on_defend_pressed() -> void:
	_add_command(SectWarManager.Command.DEFEND, "방어")


func _on_flank_pressed() -> void:
	_add_command(SectWarManager.Command.FLANK, "측면")


func _on_retreat_pressed() -> void:
	_add_command(SectWarManager.Command.RETREAT, "후퇴")


func _on_reset_pressed() -> void:
	_commands.clear()
	log_label.text = "명령을 초기화했습니다."
	_update_display()


func _on_execute_pressed() -> void:
	var target: SectData = _get_target()
	if target == null:
		return
	var result: Dictionary = GameManager.resolve_sect_war(target.id, _commands)
	var logs: PackedStringArray = result.get("logs", PackedStringArray())
	log_label.text = result["message"] + "\n" + "\n".join(logs)
	_commands.clear()
	if result.get("subjugated", false):
		_fill_targets()
	_update_display()


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)
