class_name SectWarManager
extends RefCounted

## 문파전 규칙. 3라운드 동안 양측이 명령을 내고, 상성·진형·장수로 전력을 비교한다.
##
## 상성: 돌격 > 측면 공격 > 방어 > 돌격. 후퇴는 전력이 줄지만 패배 시 제자 손실을 줄인다.
## 같은 명령을 연달아 쓰면 약해지고, 라운드마다 전장의 변수(운)가 작용한다.
## 적은 전투 시작 전에 성향별 전술 가중치로 세 라운드의 명령을 정해 둔다(작전 계획).
## 지난 전투에서 본 아군 명령은 일정 확률로 맞받아치는 수로 대비한다.
## 정찰하면 그 계획을 한 라운드씩 미리 볼 수 있다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

enum Command { CHARGE, DEFEND, FLANK, RETREAT }
enum Formation { NONE, CRANE, FISH, CIRCLE }

const COMMAND_NAMES: Dictionary = {
	Command.CHARGE: "돌격",
	Command.DEFEND: "방어",
	Command.FLANK: "측면 공격",
	Command.RETREAT: "후퇴",
}

## 키 명령이 값 명령을 이긴다
const COMMAND_BEATS: Dictionary = {
	Command.CHARGE: Command.FLANK,
	Command.FLANK: Command.DEFEND,
	Command.DEFEND: Command.CHARGE,
}

const FORMATION_NAMES: Dictionary = {
	Formation.NONE: "진형 없음",
	Formation.CRANE: "학익진",
	Formation.FISH: "어린진",
	Formation.CIRCLE: "방원진",
}

## 진형이 강화하는 명령
const FORMATION_BOOSTS: Dictionary = {
	Formation.CRANE: Command.FLANK,
	Formation.FISH: Command.CHARGE,
	Formation.CIRCLE: Command.DEFEND,
}


static func get_military_power(sect: SectData, character: CharacterData) -> int:
	var power: int = sect.disciple_count * 3 + DiscipleRoster.get_war_power_bonus(sect)
	power += sect.training_ground_level * 8
	power += int(character.get_combat_power() * RoleManager.get_role_combat_bonus(character.role))
	power += sect.reputation / 5
	return power


## 적 문파의 전력. 문주 NPC의 능력치와 문파 규모로 계산한다.
static func get_sect_power(sect: SectData) -> int:
	var leader: CharacterData = NpcRoster.create_character(sect.leader_id)
	return roundi(get_military_power(sect, leader) * ScenarioRules.enemy_strength_scale())


## 문파의 전술 가중치 { Command: 가중치 }. 문파 데이터 war_tactics가 있으면 그것을 쓴다.
static func get_tactics(sect: SectData) -> Dictionary:
	var raw: Dictionary = SectRegistry.get_sect_info(sect.id).get("war_tactics", {})
	if raw.is_empty():
		raw = _Balance.WAR_TACTICS.get(SectData.Alignment.find_key(sect.alignment), {})
	var weights: Dictionary = {}
	for key in raw:
		weights[Command.get(key)] = float(raw[key])
	return weights


static func get_formation(sect: SectData) -> Formation:
	var name: String = SectRegistry.get_sect_info(sect.id).get(
		"war_formation", _Balance.WAR_FORMATIONS.get(SectData.Alignment.find_key(sect.alignment), "NONE")
	)
	return Formation.get(name, Formation.NONE)


## 가장 많이 쓰는 명령 (정세 표시용)
static func get_preferred_command(sect: SectData) -> Command:
	var tactics: Dictionary = get_tactics(sect)
	var best: Command = Command.DEFEND
	for command in tactics:
		if tactics[command] > tactics.get(best, 0.0):
			best = command
	return best


## 적의 작전 계획: 라운드별 명령과 진형. 정찰 여부는 revealed에 기록한다.
## 지난 전투에서 본 아군 명령이 있으면 그 라운드는 일정 확률로 그 명령을 이기는 수를 고른다.
static func plan_battle(enemy: SectData) -> Dictionary:
	var tactics: Dictionary = get_tactics(enemy)
	var commands: Array = []
	for i in _Balance.WAR_ROUNDS:
		var counter: int = -1
		if i < enemy.observed_commands.size():
			counter = _counter_of(enemy.observed_commands[i])
		if counter >= 0 and randf() < _Balance.WAR_ADAPT_CHANCE:
			commands.append(counter)
		else:
			commands.append(_pick_weighted(tactics))
	var revealed: Array = []
	revealed.resize(_Balance.WAR_ROUNDS)
	revealed.fill(false)
	return {
		"target": enemy.id,
		"enemy_commands": commands,
		"enemy_formation": get_formation(enemy),
		"revealed": revealed,
		"scout_count": 0,
	}


## command를 이기는 명령. 후퇴처럼 이길 수 없는 명령이면 -1
static func _counter_of(command: int) -> int:
	for candidate in COMMAND_BEATS:
		if COMMAND_BEATS[candidate] == command:
			return candidate
	return -1


static func _pick_weighted(weights: Dictionary) -> Command:
	var total: float = 0.0
	for key in weights:
		total += weights[key]
	var roll: float = randf() * total
	for key in weights:
		roll -= weights[key]
		if roll < 0.0:
			return key
	return weights.keys()[-1]


static func get_scout_cost(plan: Dictionary, character: CharacterData) -> int:
	var cost: int = _Balance.WAR_SCOUT_COST + int(plan.get("scout_count", 0)) * _Balance.WAR_SCOUT_COST_STEP
	if character.role in [CharacterData.Role.SPY, CharacterData.Role.ASSASSIN]:
		cost /= 2
	return cost


## 정찰: 아직 모르는 첫 라운드의 적 명령을 공개한다. 공개한 라운드 번호(0부터)를 돌려주고, 다 알면 -1.
static func reveal_next(plan: Dictionary) -> int:
	var revealed: Array = plan["revealed"]
	for i in revealed.size():
		if not revealed[i]:
			revealed[i] = true
			plan["scout_count"] = int(plan.get("scout_count", 0)) + 1
			return i
	return -1


## 명령 상성 배율
static func matchup_multiplier(own: Command, opponent: Command) -> float:
	if own == Command.RETREAT:
		return _Balance.WAR_RETREAT_POWER
	if opponent == Command.RETREAT:
		return 1.0
	if COMMAND_BEATS[own] == opponent:
		return _Balance.WAR_ADVANTAGE
	if COMMAND_BEATS[opponent] == own:
		return _Balance.WAR_DISADVANTAGE
	return 1.0


## 진형은 한 명령을 강화하고, 그 명령을 이기는 명령(진형의 약점)을 약화한다.
## 예: 학익진은 측면을 강화하고, 측면을 이기는 돌격을 약화한다.
static func formation_multiplier(formation: Formation, command: Command) -> float:
	if formation == Formation.NONE or command == Command.RETREAT:
		return 1.0
	var boosted: Command = FORMATION_BOOSTS[formation]
	if command == boosted:
		return _Balance.WAR_FORMATION_BONUS
	if COMMAND_BEATS[command] == boosted:
		return _Balance.WAR_FORMATION_PENALTY
	return 1.0


## 장수 정보: { id, name, power, specialty(Command 또는 -1) }
static func describe_general(npc_id: String) -> Dictionary:
	var data: Dictionary = NpcRoster.get_npc(npc_id)
	var character: CharacterData = NpcRoster.create_character(npc_id)
	var specialty: int = -1
	if data.has("war_specialty"):
		specialty = Command.get(data["war_specialty"], -1)
	return {
		"id": npc_id,
		"name": data.get("display_name", npc_id),
		"power": int(character.get_combat_power() * _Balance.WAR_GENERAL_POWER_RATIO),
		"specialty": specialty,
	}


## 한 라운드 판정. 양측 기본 전력에 상성·진형·장수 특기·연속 사용 배율과 전장의 변수를 곱한다.
## *_previous: 앞 라운드에 쓴 명령 (첫 라운드는 -1). luck: 전장의 변수 폭 (0이면 운 없음)
static func resolve_round(
	player_power: int,
	player_command: Command,
	player_formation: Formation,
	general: Dictionary,
	enemy_power: int,
	enemy_command: Command,
	enemy_formation: Formation,
	round_index: int,
	player_previous: int = -1,
	enemy_previous: int = -1,
	luck: float = _Balance.WAR_LUCK
) -> Dictionary:
	var player_mult: float = matchup_multiplier(player_command, enemy_command)
	player_mult *= formation_multiplier(player_formation, player_command)
	player_mult *= _repeat_multiplier(player_command, player_previous)
	if not general.is_empty() and general.get("specialty", -1) == player_command:
		player_mult *= _Balance.WAR_GENERAL_SPECIALTY_BONUS
	var enemy_mult: float = matchup_multiplier(enemy_command, player_command)
	enemy_mult *= formation_multiplier(enemy_formation, enemy_command)
	enemy_mult *= _repeat_multiplier(enemy_command, enemy_previous)
	if luck > 0.0:
		player_mult *= randf_range(1.0 - luck, 1.0 + luck)
		enemy_mult *= randf_range(1.0 - luck, 1.0 + luck)

	var player_score: int = int(player_power * player_mult)
	var enemy_score: int = int(enemy_power * enemy_mult)
	var outcome: int = 0
	if player_score > enemy_score:
		outcome = 1
	elif player_score < enemy_score:
		outcome = -1
	var result_text: String = "승" if outcome == 1 else ("패" if outcome == -1 else "무승부")
	return {
		"round": round_index + 1,
		"player_command": player_command,
		"enemy_command": enemy_command,
		"player_score": player_score,
		"enemy_score": enemy_score,
		"outcome": outcome,
		"log": "라운드 %d: %s vs 적 %s | 전력 %d vs %d — %s" % [
			round_index + 1,
			COMMAND_NAMES[player_command],
			COMMAND_NAMES[enemy_command],
			player_score,
			enemy_score,
			result_text,
		],
	}


static func _repeat_multiplier(command: Command, previous: int) -> float:
	if command != Command.RETREAT and command == previous:
		return _Balance.WAR_REPEAT_PENALTY
	return 1.0


## 문파전 전체를 판정하고 결과를 양측 문파에 반영한다.
## plan: plan_battle()의 작전 계획, general: describe_general() 결과 또는 빈 딕셔너리
static func resolve_battle(
	player_sect: SectData,
	player_character: CharacterData,
	enemy_sect: SectData,
	commands: Array[Command],
	plan: Dictionary = {},
	player_formation: Formation = Formation.NONE,
	general: Dictionary = {},
	ally_power: int = 0
) -> Dictionary:
	if plan.is_empty() or plan.get("target") != enemy_sect.id:
		plan = plan_battle(enemy_sect)
	# 동맹 세력의 원군(ally_power)도 아군 전력에 더한다.
	var player_power: int = get_military_power(player_sect, player_character) + int(general.get("power", 0)) + ally_power
	var enemy_power: int = get_sect_power(enemy_sect)
	var wins: int = 0
	var losses: int = 0
	var retreats: int = 0
	var rounds: Array[Dictionary] = []
	var logs: PackedStringArray = []

	var enemy_commands: Array = plan["enemy_commands"]
	for i in commands.size():
		var enemy_command: Command = enemy_commands[i % enemy_commands.size()]
		var round_result: Dictionary = resolve_round(
			player_power, commands[i], player_formation, general,
			enemy_power, enemy_command, plan["enemy_formation"], i,
			commands[i - 1] if i > 0 else -1,
			enemy_commands[(i - 1) % enemy_commands.size()] if i > 0 else -1
		)
		rounds.append(round_result)
		logs.append(round_result["log"])
		if commands[i] == Command.RETREAT:
			retreats += 1
		if round_result["outcome"] == 1:
			wins += 1
		elif round_result["outcome"] == -1:
			losses += 1

	# 적은 이번에 본 아군 명령을 기억해 다음 전투에 대비한다.
	enemy_sect.observed_commands.clear()
	for command in commands:
		enemy_sect.observed_commands.append(command)

	if wins > losses:
		var rep_gain: int = _Balance.WAR_WIN_REPUTATION + wins * _Balance.WAR_WIN_REPUTATION_PER_ROUND
		var gold_gain: int = _Balance.WAR_WIN_GOLD + wins * _Balance.WAR_WIN_GOLD_PER_ROUND
		player_sect.reputation += rep_gain
		player_sect.gold += gold_gain
		player_character.gain_experience(_Balance.WAR_WIN_EXP)
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
			"rounds": rounds,
		}

	# 패배(또는 무승부): 후퇴한 라운드마다, 그리고 방원진이면 제자 손실이 1씩 준다.
	var disciple_loss: int = _Balance.WAR_LOSS_DISCIPLES + losses - retreats
	if player_formation == Formation.CIRCLE:
		disciple_loss -= 1
	disciple_loss = maxi(1, disciple_loss)
	var rep_loss: int = _Balance.WAR_LOSS_REPUTATION + losses * _Balance.WAR_LOSS_REPUTATION_PER_ROUND
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
		"rounds": rounds,
	}


## 해가 바뀔 때 강호 세력이 제자를 모으고 명성을 회복한다. 굴복한 세력은 멈춘다.
static func grow_world_sects(sects: Array[SectData]) -> void:
	for sect in sects:
		if sect.subjugated:
			continue
		var growth: int = roundi(_Balance.WORLD_SECT_YEARLY_GROWTH * ScenarioRules.world_growth_scale())
		sect.disciple_count = mini(sect.max_disciples, sect.disciple_count + growth)
		sect.reputation += 1
