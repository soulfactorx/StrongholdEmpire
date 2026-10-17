class_name SectWarManager
extends RefCounted

enum Command { CHARGE, DEFEND, FLANK, RETREAT }

const COMMAND_NAMES: Dictionary = {
	Command.CHARGE: "돌격",
	Command.DEFEND: "방어",
	Command.FLANK: "측면 공격",
	Command.RETREAT: "후퇴",
}

const ENEMY_COMMANDS: Array[Command] = [
	Command.DEFEND, Command.CHARGE, Command.FLANK, Command.CHARGE,
]


static func get_military_power(sect: SectData, character: CharacterData) -> int:
	var power: int = sect.disciple_count * 3
	power += sect.training_ground_level * 8
	power += int(character.get_combat_power() * RoleManager.get_role_combat_bonus(character.role))
	power += sect.reputation / 5
	return power


static func simulate_round(
	player_sect: SectData,
	player_character: CharacterData,
	player_command: Command,
	enemy_power: int,
	round_index: int
) -> Dictionary:
	var player_power: int = get_military_power(player_sect, player_character)
	var enemy_cmd: Command = ENEMY_COMMANDS[round_index % ENEMY_COMMANDS.size()]

	var player_bonus: float = _command_bonus(player_command, enemy_cmd, true)
	var enemy_bonus: float = _command_bonus(enemy_cmd, player_command, false)

	var player_score: int = int(player_power * player_bonus)
	var enemy_score: int = int(enemy_power * enemy_bonus)

	var log: String = "라운드 %d: %s vs 적 %s | 전력 %d vs %d" % [
		round_index + 1,
		COMMAND_NAMES[player_command],
		COMMAND_NAMES[enemy_cmd],
		player_score,
		enemy_score,
	]

	if player_score > enemy_score:
		return {"player_win": true, "margin": player_score - enemy_score, "log": log}
	if player_score < enemy_score:
		return {"player_win": false, "margin": enemy_score - player_score, "log": log}
	return {"player_win": null, "margin": 0, "log": log + " (무승부)"}


static func resolve_battle(
	player_sect: SectData,
	player_character: CharacterData,
	commands: Array[Command]
) -> Dictionary:
	var enemy_power: int = 60 + player_sect.reputation / 2
	var wins: int = 0
	var losses: int = 0
	var logs: PackedStringArray = []

	for i in commands.size():
		var round_result: Dictionary = simulate_round(
			player_sect, player_character, commands[i], enemy_power, i
		)
		logs.append(round_result["log"])
		if round_result["player_win"] == true:
			wins += 1
		elif round_result["player_win"] == false:
			losses += 1

	if wins > losses:
		var rep_gain: int = 8 + wins * 3
		var gold_gain: int = 40 + wins * 15
		player_sect.reputation += rep_gain
		player_sect.gold += gold_gain
		player_character.gain_experience(25)
		return {
			"success": true,
			"victory": true,
			"message": "문파전 승리! 명성 +%d, 금화 +%d" % [rep_gain, gold_gain],
			"logs": logs,
		}

	var disciple_loss: int = 2 + losses
	var rep_loss: int = 5 + losses * 2
	player_sect.disciple_count = maxi(1, player_sect.disciple_count - disciple_loss)
	player_sect.reputation = maxi(0, player_sect.reputation - rep_loss)
	return {
		"success": true,
		"victory": false,
		"message": "문파전 패배... 제자 -%d, 명성 -%d" % [disciple_loss, rep_loss],
		"logs": logs,
	}


static func _command_bonus(own: Command, opponent: Command, is_player: bool) -> float:
	var bonus: float = 1.0
	match own:
		Command.CHARGE:
			bonus = 1.2 if opponent == Command.DEFEND else 1.1
		Command.DEFEND:
			bonus = 1.15 if opponent == Command.CHARGE else 0.95
		Command.FLANK:
			bonus = 1.25 if opponent == Command.DEFEND else 1.05
		Command.RETREAT:
			bonus = 0.7
	if is_player:
		bonus *= 1.02
	return bonus