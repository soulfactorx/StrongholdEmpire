class_name SectWarManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

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


## 적 문파의 전력. 문주 NPC의 능력치와 문파 규모로 계산한다.
static func get_sect_power(sect: SectData) -> int:
	var leader: CharacterData = NpcRoster.create_character(sect.leader_id)
	return get_military_power(sect, leader)


static func resolve_battle(
	player_sect: SectData,
	player_character: CharacterData,
	enemy_sect: SectData,
	commands: Array[Command]
) -> Dictionary:
	var enemy_power: int = get_sect_power(enemy_sect)
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
		var enemy_loss: int = _Balance.WAR_ENEMY_DISCIPLE_LOSS + wins
		enemy_sect.disciple_count = maxi(0, enemy_sect.disciple_count - enemy_loss)
		enemy_sect.reputation = maxi(0, enemy_sect.reputation - _Balance.WAR_ENEMY_REPUTATION_LOSS)
		enemy_sect.attitude = maxi(-100, enemy_sect.attitude - _Balance.WAR_ATTITUDE_LOSS)
		var message: String = "%s와의 문파전 승리! 명성 +%d, 금화 +%d (적 제자 -%d)" % [
			enemy_sect.sect_name, rep_gain, gold_gain, enemy_loss,
		]
		var subjugated: bool = false
		if enemy_sect.disciple_count <= _Balance.SUBJUGATE_DISCIPLE_THRESHOLD:
			subjugated = true
			enemy_sect.subjugated = true
			player_sect.reputation += _Balance.SUBJUGATE_REPUTATION_BONUS
			player_sect.gold += _Balance.SUBJUGATE_GOLD_BONUS
			message += "\n%s이(가) 굴복했습니다! 명성 +%d, 금화 +%d" % [
				enemy_sect.sect_name, _Balance.SUBJUGATE_REPUTATION_BONUS, _Balance.SUBJUGATE_GOLD_BONUS,
			]
		return {
			"success": true,
			"victory": true,
			"subjugated": subjugated,
			"message": message,
			"logs": logs,
		}

	var disciple_loss: int = 2 + losses
	var rep_loss: int = 5 + losses * 2
	player_sect.disciple_count = maxi(1, player_sect.disciple_count - disciple_loss)
	player_sect.reputation = maxi(0, player_sect.reputation - rep_loss)
	enemy_sect.attitude = maxi(-100, enemy_sect.attitude - _Balance.WAR_ATTITUDE_LOSS / 2)
	return {
		"success": true,
		"victory": false,
		"subjugated": false,
		"message": "%s와의 문파전 패배... 제자 -%d, 명성 -%d" % [
			enemy_sect.sect_name, disciple_loss, rep_loss,
		],
		"logs": logs,
	}


## 해가 바뀔 때 강호 세력이 제자를 모으고 명성을 회복한다. 굴복한 세력은 멈춘다.
static func grow_world_sects(sects: Array[SectData]) -> void:
	for sect in sects:
		if sect.subjugated:
			continue
		sect.disciple_count = mini(sect.max_disciples, sect.disciple_count + _Balance.WORLD_SECT_YEARLY_GROWTH)
		sect.reputation += 1


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