class_name SectAI
extends RefCounted

## 세력 AI: 강호 세력이 계절마다 행동 하나를 고른다 — 성장, 다른 세력 공격, 플레이어 침공, 외교.
## 성향별 가중치(GameBalance.AI_WEIGHTS)와 플레이어에 대한 태도로 정한다. 굴복한 세력은 움직이지 않는다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

enum Action { GROW, ATTACK, INVADE, DIPLOMACY }


## 이 세력의 행동별 가중치. 할 수 없는 행동은 0
static func get_weights(
	sect: SectData,
	world_sects: Array[SectData],
	turn: int,
	year: int,
	invasion_scale: float
) -> Array[float]:
	var base: Array = _Balance.AI_WEIGHTS[SectData.Alignment.find_key(sect.alignment)]
	var aggression: float = ScenarioRules.ai_aggression()
	var weights: Array[float] = [float(base[0]), float(base[1]) * aggression, 0.0, float(base[3])]
	if _attack_targets(sect, world_sects).is_empty():
		weights[Action.ATTACK] = 0.0
	if can_invade(sect, turn, year):
		var hostility: float = clampf(-sect.attitude / 50.0, 0.0, 2.0)
		weights[Action.INVADE] = float(base[2]) * aggression * hostility * invasion_scale
	if sect.attitude < _Balance.AI_DIPLOMACY_MIN_ATTITUDE or sect.attitude >= 100:
		weights[Action.DIPLOMACY] = 0.0
	return weights


static func can_invade(sect: SectData, turn: int, year: int) -> bool:
	if sect.allied or sect.subjugated or year <= _Balance.AI_INVASION_GRACE_YEARS:
		return false
	if sect.attitude >= _Balance.AI_INVASION_MAX_ATTITUDE:
		return false
	return sect.last_invasion_turn < 0 or turn - sect.last_invasion_turn >= _Balance.AI_INVASION_COOLDOWN


static func _attack_targets(sect: SectData, world_sects: Array[SectData]) -> Array[SectData]:
	var result: Array[SectData] = []
	for other in world_sects:
		if other != sect and not other.subjugated and other.disciple_count >= _Balance.AI_ATTACK_MIN_TARGET_DISCIPLES:
			result.append(other)
	return result


static func _pick(weights: Array[float]) -> int:
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return Action.GROW
	var roll: float = randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll < 0.0:
			return i
	return Action.GROW


## 한 계절의 세력 행동. invasion_scale이 0이면 침공하지 않는다 (기연 빈도 0인 시험·시뮬레이션).
## 결과: {news: 강호 소식 목록, invader: 플레이어를 침공한 세력 id 또는 ""}. 침공은 계절에 한 세력만.
static func run_season(
	world_sects: Array[SectData],
	turn: int,
	year: int,
	invasion_scale: float = 1.0
) -> Dictionary:
	var news: PackedStringArray = []
	var invader: String = ""
	var order: Array[SectData] = world_sects.duplicate()
	order.shuffle()
	for sect in order:
		if sect.subjugated:
			continue
		var scale: float = invasion_scale if invader.is_empty() else 0.0
		match _pick(get_weights(sect, world_sects, turn, year, scale)):
			Action.GROW:
				var growth: int = _Balance.AI_GROWTH_DISCIPLES_SMALL if sect.disciple_count * 2 < sect.max_disciples else _Balance.AI_GROWTH_DISCIPLES
				sect.disciple_count = mini(sect.max_disciples, sect.disciple_count + growth)
				sect.reputation += _Balance.AI_GROWTH_REPUTATION
			Action.ATTACK:
				news.append(_attack(sect, world_sects))
			Action.INVADE:
				invader = sect.id
				sect.last_invasion_turn = turn
				news.append("%s이(가) 우리 문파를 침공해 왔습니다!" % sect.sect_name)
			Action.DIPLOMACY:
				sect.attitude = mini(100, sect.attitude + _Balance.AI_DIPLOMACY_ATTITUDE)
				news.append("%s이(가) 사절을 보내 왔습니다. (태도 %d)" % [sect.sect_name, sect.attitude])
	return {"news": news, "invader": invader}


## 다른 세력을 친다. 다른 성향을 더 자주 노린다. 소식 문구를 돌려준다.
static func _attack(sect: SectData, world_sects: Array[SectData]) -> String:
	var targets: Array[SectData] = _attack_targets(sect, world_sects)
	var weights: Array[float] = []
	for target in targets:
		weights.append(1.0 if target.alignment != sect.alignment else _Balance.AI_SAME_ALIGNMENT_ATTACK)
	var target: SectData = targets[_pick(weights)]
	var attack: float = SectWarManager.get_sect_power(sect) * randf_range(1.0 - _Balance.AI_WAR_LUCK, 1.0 + _Balance.AI_WAR_LUCK)
	var defense: float = (
		SectWarManager.get_sect_power(target) * _Balance.AI_WAR_DEFENDER_BONUS
		* randf_range(1.0 - _Balance.AI_WAR_LUCK, 1.0 + _Balance.AI_WAR_LUCK)
	)
	var winner: SectData = sect if attack > defense else target
	var loser: SectData = target if winner == sect else sect
	var lost: int = mini(_Balance.AI_WAR_LOSS, maxi(0, loser.disciple_count - _Balance.AI_MIN_DISCIPLES))
	loser.disciple_count -= lost
	loser.reputation = maxi(0, loser.reputation - _Balance.AI_WAR_REPUTATION)
	winner.disciple_count = mini(winner.max_disciples, winner.disciple_count + mini(lost, _Balance.AI_WAR_ABSORB))
	winner.reputation += _Balance.AI_WAR_REPUTATION
	if winner == sect:
		return "%s이(가) %s을(를) 쳐서 이겼습니다. (%s 제자 -%d)" % [sect.sect_name, target.sect_name, target.sect_name, lost]
	return "%s이(가) %s을(를) 쳤다가 물러났습니다. (%s 제자 -%d)" % [sect.sect_name, target.sect_name, sect.sect_name, lost]
