class_name SectAI
extends RefCounted

## 세력 AI: 강호 세력이 계절마다 행동 하나를 고른다 — 성장, 다른 세력 공격, 플레이어 침공, 외교,
## 지도의 빈 땅 차지(확장), 무술장 확장(내실).
## 성향별 가중치(GameBalance.AI_WEIGHTS)에 세력 전략(FactionStrategy) 배율을 곱하고, 플레이어에 대한 태도를 본다.
## 굴복한 세력은 움직이지 않는다. 계절마다 세력별로 무엇을 했는지 보고(reports)를 남긴다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

enum Action { GROW, ATTACK, INVADE, DIPLOMACY, EXPAND, FORTIFY }
const ACTION_TITLES: Array[String] = ["세력 키우기", "다른 세력 공격", "우리 문파 침공", "외교 사절", "영토 확장", "무술장 확장"]

## false면 계절 진행에서 세력 AI가 움직이지 않는다. 다른 시스템을 시험할 때 강호 세력 수치를 고정하려고 쓴다.
static var active: bool = true


## 이 세력의 행동별 가중치. 할 수 없는 행동은 0
## map_state가 있으면(GameManager.map_state) 확장할 빈 땅을 본다.
static func get_weights(
	sect: SectData,
	world_sects: Array[SectData],
	turn: int,
	year: int,
	invasion_scale: float,
	map_state: Dictionary = {}
) -> Array[float]:
	var base: Array = _Balance.AI_WEIGHTS[SectData.Alignment.find_key(sect.alignment)]
	var aggression: float = ScenarioRules.ai_aggression()
	var weights: Array[float] = [
		float(base[0]), float(base[1]) * aggression, 0.0, float(base[3]), _Balance.AI_EXPAND_WEIGHT, _Balance.AI_FORTIFY_WEIGHT,
	]
	if _attack_targets(sect, world_sects).is_empty():
		weights[Action.ATTACK] = 0.0
	if can_invade(sect, turn, year):
		var hostility: float = clampf(-sect.attitude / 50.0, 0.0, 2.0)
		weights[Action.INVADE] = float(base[2]) * aggression * hostility * invasion_scale
	if sect.attitude < _Balance.AI_DIPLOMACY_MIN_ATTITUDE or sect.attitude >= 100:
		weights[Action.DIPLOMACY] = 0.0
	if _expand_targets(sect, map_state).is_empty():
		weights[Action.EXPAND] = 0.0
	if sect.gold < _Balance.AI_FORTIFY_GOLD or sect.training_ground_level >= _Balance.AI_FORTIFY_MAX_LEVEL:
		weights[Action.FORTIFY] = 0.0
	var multipliers: Array = FactionStrategy.get_multipliers(sect)
	# 문주의 성향: 야망이 크면 공격·확장, 신중하면 성장·내실, 인정이 많으면 외교 (NpcAgent)
	var temper: Array = NpcAgent.leader_multipliers(sect.leader_id)
	for i in weights.size():
		weights[i] *= float(multipliers[i]) * float(temper[i])
	return weights


## 차지할 수 있는 빈 땅: 맞닿아 있고 주둔 병력이 세력 전력 이하
static func _expand_targets(sect: SectData, map_state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if map_state.is_empty():
		return result
	var power: int = SectWarManager.get_sect_power(sect)
	for region_id in WorldMap.frontier(map_state, sect.id, true):
		if int(WorldMap.get_region(region_id)["defense"]) <= power:
			result.append(region_id)
	return result


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
## map_state가 있으면 땅에서 나는 금화를 거두고, 확장·영토 쟁탈을 한다.
## 결과: {news: 강호 소식 목록, invader: 플레이어를 침공한 세력 id 또는 "",
##        reports: [{sect_id, sect_name, strategy, action, detail}] — 세력마다 이번 계절에 한 일}. 침공은 계절에 한 세력만.
static func run_season(
	world_sects: Array[SectData],
	turn: int,
	year: int,
	invasion_scale: float = 1.0,
	map_state: Dictionary = {}
) -> Dictionary:
	var news: PackedStringArray = []
	var reports: Array[Dictionary] = []
	var invader: String = ""
	var order: Array[SectData] = world_sects.duplicate()
	order.shuffle()
	for sect in order:
		var report: Dictionary = {
			"sect_id": sect.id, "sect_name": sect.sect_name, "leader": sect.leader_name,
			"strategy": FactionStrategy.get_title(FactionStrategy.of(sect)), "action": "", "detail": "",
		}
		reports.append(report)
		if sect.subjugated:
			report["action"] = "굴복"
			report["detail"] = "우리 문파에 굴복해 움직이지 않습니다."
			continue
		if not map_state.is_empty():
			var income: Dictionary = WorldMap.income(map_state, sect.id)
			sect.gold += income["gold"]
			sect.food += income["food"]
		var scale: float = invasion_scale if invader.is_empty() else 0.0
		var action: int = _pick(get_weights(sect, world_sects, turn, year, scale, map_state))
		report["action"] = ACTION_TITLES[action]
		match action:
			Action.GROW:
				var growth: int = _Balance.AI_GROWTH_DISCIPLES_SMALL if sect.disciple_count * 2 < sect.max_disciples else _Balance.AI_GROWTH_DISCIPLES
				var before: int = sect.disciple_count
				sect.disciple_count = mini(sect.max_disciples, sect.disciple_count + growth)
				sect.reputation += _Balance.AI_GROWTH_REPUTATION
				report["detail"] = "제자를 모으고 이름을 알렸습니다. (제자 %+d → %d, 명성 +%d)" % [
					sect.disciple_count - before, sect.disciple_count, _Balance.AI_GROWTH_REPUTATION,
				]
			Action.ATTACK:
				var line: String = _attack(sect, world_sects, map_state)
				news.append(line)
				report["detail"] = line
			Action.INVADE:
				invader = sect.id
				sect.last_invasion_turn = turn
				var line: String = "%s이(가) 우리 문파를 침공해 왔습니다!" % sect.sect_name
				news.append(line)
				report["detail"] = line
			Action.DIPLOMACY:
				sect.attitude = mini(100, sect.attitude + _Balance.AI_DIPLOMACY_ATTITUDE)
				var line: String = "%s이(가) 사절을 보내 왔습니다. (태도 %d)" % [sect.sect_name, sect.attitude]
				news.append(line)
				report["detail"] = line
			Action.EXPAND:
				var line: String = _expand(sect, world_sects, map_state)
				news.append(line)
				report["detail"] = line
			Action.FORTIFY:
				sect.gold -= _Balance.AI_FORTIFY_GOLD
				sect.training_ground_level += 1
				report["detail"] = "금화 %d을 들여 무술장을 %d단계로 넓혔습니다." % [_Balance.AI_FORTIFY_GOLD, sect.training_ground_level]
	return {"news": news, "invader": invader, "reports": reports}


## 맞닿은 빈 땅 하나를 차지한다. 주둔 병력이 약한 곳부터.
static func _expand(sect: SectData, world_sects: Array[SectData], map_state: Dictionary) -> String:
	var targets: Array[String] = _expand_targets(sect, map_state)
	targets.sort_custom(func(a: String, b: String) -> bool:
		return int(WorldMap.get_region(a)["defense"]) < int(WorldMap.get_region(b)["defense"])
	)
	var region_id: String = targets[0]
	WorldMap.transfer(map_state, region_id, sect.id, world_sects)
	return "%s이(가) 주인 없는 땅 %s을(를) 차지했습니다." % [sect.sect_name, WorldMap.get_region(region_id)["name"]]


## 다른 세력을 친다. 다른 성향을 더 자주 노리고, 지도가 있으면 맞닿은 세력을 더 자주 노린다.
## 기회주의 전략은 약한 세력을 노린다. 이기면 진 세력의 맞닿은 땅 하나를 빼앗는다. 소식 문구를 돌려준다.
static func _attack(sect: SectData, world_sects: Array[SectData], map_state: Dictionary = {}) -> String:
	var targets: Array[SectData] = _attack_targets(sect, world_sects)
	var weights: Array[float] = []
	var opportunist: bool = FactionStrategy.of(sect) == "opportunist"
	for target in targets:
		var weight: float = 1.0 if target.alignment != sect.alignment else _Balance.AI_SAME_ALIGNMENT_ATTACK
		if not map_state.is_empty() and not _border_regions(map_state, sect.id, target.id).is_empty():
			weight *= 3.0
		if opportunist:
			weight *= 100.0 / maxf(20.0, float(SectWarManager.get_sect_power(target)))
		weights.append(weight)
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
		var line: String = "%s이(가) %s을(를) 쳐서 이겼습니다. (%s 제자 -%d)" % [sect.sect_name, target.sect_name, target.sect_name, lost]
		var taken: Array[String] = []
		if not map_state.is_empty():
			taken = _border_regions(map_state, sect.id, target.id)
		if not taken.is_empty():
			WorldMap.transfer(map_state, taken[0], sect.id, world_sects)
			line += " %s 땅을 빼앗았습니다." % WorldMap.get_region(taken[0])["name"]
		return line
	return "%s이(가) %s을(를) 쳤다가 물러났습니다. (%s 제자 -%d)" % [sect.sect_name, target.sect_name, sect.sect_name, lost]


## target의 땅 중 attacker 땅과 맞닿고 빼앗을 수 있는 곳
static func _border_regions(map_state: Dictionary, attacker_id: String, target_id: String) -> Array[String]:
	var result: Array[String] = []
	for region_id in WorldMap.regions_of(map_state, target_id):
		if WorldMap.can_be_taken(map_state, region_id) and WorldMap.borders(map_state, region_id, attacker_id):
			result.append(region_id)
	return result


## 세력 동향 보고를 읽기 좋은 줄로: "남궁세가 [영토 확장] 영토 확장 — 자세한 내용"
static func format_reports(reports: Array) -> String:
	var lines: PackedStringArray = []
	for report in reports:
		var leader: String = str(report.get("leader", ""))
		lines.append("· %s%s [%s 전략] %s\n    %s" % [
			report.get("sect_name", "?"), "(문주 %s)" % leader if not leader.is_empty() else "",
			report.get("strategy", "?"), report.get("action", ""), report.get("detail", ""),
		])
	return "\n".join(lines) if not lines.is_empty() else "아직 강호 세력이 움직이지 않았습니다."
