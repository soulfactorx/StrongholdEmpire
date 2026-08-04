extends Control

const MAX_ROUNDS := 3

var _commands: Array[SectWarManager.Command] = []

@onready var power_label: Label = %PowerLabel
@onready var round_label: Label = %RoundLabel
@onready var log_label: Label = %LogLabel
@onready var charge_button: Button = %ChargeButton
@onready var defend_button: Button = %DefendButton
@onready var flank_button: Button = %FlankButton
@onready var retreat_button: Button = %RetreatButton
@onready var execute_button: Button = %ExecuteButton


func _ready() -> void:
	_update_display()


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
	round_label.text = "지휘 명령: %d / %d" % [_commands.size(), MAX_ROUNDS]
	execute_button.disabled = _commands.size() < MAX_ROUNDS


func _add_command(command: SectWarManager.Command, name: String) -> void:
	if _commands.size() >= MAX_ROUNDS:
		log_label.text = "이미 3개 명령이 선택되었습니다."
		return
	_commands.append(command)
	log_label.text = "%s 명령 추가." % name
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
	var result: Dictionary = GameManager.resolve_sect_war(_commands)
	var logs: PackedStringArray = result.get("logs", PackedStringArray())
	log_label.text = result["message"] + "\n" + "\n".join(logs)
	_commands.clear()
	_update_display()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")