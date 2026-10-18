class_name NpcAgent
extends RefCounted

## 인물 AI: 문파의 직책 인물(문주·교두·의원 등)이 계절마다 성향·능력치·처지에 맞는 일을 한다.
## - 플레이어 문파: 플레이어가 문주가 아니면(총관·막내 제자) NPC 문주가 문파 살림을 맡는다
##   (제자 모집·시설 확장·연회·땅 평정·사절·재물 아끼기 중 성향과 형편에 맞는 것). 교두는 제자를 가르치고, 의원은 문파 사람을 돌본다.
## - 강호 세력: 문주의 성향을 세력 AI 가중치에 곱한다 (SectAI.get_weights).
## 인물의 성향(trait)과 취향(likes)은 인물 JSON의 "traits"·"likes"로 정하고, 없으면 능력치에서 끌어낸다.
## gm은 GameManager 노드다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

## false면 계절 진행에서 인물 AI가 움직이지 않는다 (다른 시스템을 시험할 때 문파 수치를 고정하려고 쓴다)
static var active: bool = true

const TRAIT_NAMES: Dictionary = {
	"ambition": "야망", "caution": "신중", "benevolence": "인정", "greed": "탐욕", "loyalty": "의리",
}
const LIKE_NAMES: Dictionary = {"talk": "담소", "gift": "선물", "spar": "비무"}
const POST_NAMES: Dictionary = {
	"leader": "문주", "instructor": "교두", "healer": "의원", "elder": "장로", "steward": "총관", "heir": "후계자",
}


# ── 성향과 취향 ──

## 성향 0~100: 야망(넓히고 싸우려 함), 신중(아끼고 대비함), 인정(베풀고 화친함), 탐욕(재물을 좇음), 의리(약속을 지킴)
static func get_traits(npc_id: String) -> Dictionary:
	var npc: Dictionary = NpcRoster.get_npc(npc_id)
	var stats: Dictionary = npc.get("stats", {})
	var strength: int = int(stats.get("strength", 10))
	var wisdom: int = int(stats.get("wisdom", 10))
	var charisma: int = int(stats.get("charisma", 10))
	var morality: int = int(stats.get("morality", 50))
	var traits: Dictionary = {
		"ambition": clampi(int((strength + charisma) * 2.5) - 10 + (10 if npc.get("role", "") == "LEADER" else 0), 0, 100),
		"caution": clampi(wisdom * 4 - 10, 0, 100),
		"benevolence": clampi(morality, 0, 100),
		"greed": clampi(100 - morality, 0, 100),
		"loyalty": clampi(40 + morality / 3, 0, 100),
	}
	var custom: Dictionary = npc.get("traits", {})
	for key in custom:
		if TRAIT_NAMES.has(key):
			traits[key] = clampi(int(custom[key]), 0, 100)
	return traits


## 좋아하는 상호작용 (talk·gift·spar). 없으면 능력치·성향에서: 매력 → 담소, 탐욕 → 선물, 무력 → 비무
static func get_likes(npc_id: String) -> Array:
	var npc: Dictionary = NpcRoster.get_npc(npc_id)
	if npc.has("likes"):
		return Array(npc["likes"]).filter(func(like: Variant) -> bool: return LIKE_NAMES.has(str(like)))
	var stats: Dictionary = npc.get("stats", {})
	var traits: Dictionary = get_traits(npc_id)
	var scores: Dictionary = {
		"talk": int(stats.get("charisma", 10)) * 3,
		"gift": traits["greed"] / 2,
		"spar": int(stats.get("strength", 10)) * 3,
	}
	var best: String = "talk"
	for key in scores:
		if scores[key] > scores[best]:
			best = key
	return [best]


static func likes(npc_id: String, kind: String) -> bool:
	return kind in get_likes(npc_id)


## "야망 70 · 신중 40 · 인정 60 · 탐욕 40 · 의리 60 | 좋아함: 선물" (화면용)
static func describe(npc_id: String) -> String:
	var traits: Dictionary = get_traits(npc_id)
	var parts: PackedStringArray = []
	for key in TRAIT_NAMES:
		parts.append("%s %d" % [TRAIT_NAMES[key], traits[key]])
	var liked: PackedStringArray = []
	for like in get_likes(npc_id):
		liked.append(LIKE_NAMES[like])
	var favorite: String = str(NpcRoster.get_npc(npc_id).get("favorite", ""))
	return "%s | 좋아함: %s%s" % [" · ".join(parts), ", ".join(liked), " (%s)" % favorite if not favorite.is_empty() else ""]


## 세력 AI 행동 가중치에 곱할 문주 성향 배율 [성장, 공격, 침공, 외교, 확장, 내실] (0.75~1.25)
static func leader_multipliers(leader_id: String) -> Array:
	if leader_id.is_empty() or not NpcRoster.has_npc(leader_id):
		return [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
	var t: Dictionary = get_traits(leader_id)
	var f := func(value: int) -> float: return 0.75 + value / 200.0
	return [
		f.call(t["caution"]), f.call(t["ambition"]), f.call((t["ambition"] + t["greed"]) / 2),
		f.call(t["benevolence"]), f.call(t["ambition"]), f.call(t["caution"]),
	]


# ── 직책 ──

## 문파의 직책 인물 [{npc, post}]. 문파 데이터의 "officers", 없으면 문주만
static func get_officers(sect: SectData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var info: Dictionary = SectRegistry.get_sect_info(sect.id)
	for entry in info.get("officers", []):
		if entry is Dictionary and NpcRoster.has_npc(str(entry.get("npc", ""))) and POST_NAMES.has(str(entry.get("post", ""))):
			result.append({"npc": str(entry["npc"]), "post": str(entry["post"])})
	if result.is_empty() and NpcRoster.has_npc(sect.leader_id):
		result.append({"npc": sect.leader_id, "post": "leader"})
	return result


## 플레이어 문파의 살림을 NPC 문주가 맡는지 (플레이어가 문주가 아니고, 문파 일에 몸담는 역할일 때)
static func npc_runs_sect(gm: Node) -> bool:
	var role: CharacterData.Role = gm.player_character.role
	return role != CharacterData.Role.LEADER and RoleDashboard.get_layout(role)["sect"]


# ── 계절 행동 ──

## 플레이어 문파 직책 인물들의 한 계절. 보고: [{npc_id, name, post, action, detail}]
static func run_season(gm: Node) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	if not active:
		return reports
	var sect: SectData = gm.player_sect
	for officer in get_officers(sect):
		var npc_id: String = officer["npc"]
		var post: String = officer["post"]
		var outcome: Dictionary = {}
		match post:
			"leader":
				if npc_runs_sect(gm):
					outcome = _lead(gm, npc_id)
			"instructor":
				outcome = _instruct(gm, npc_id)
			"healer":
				outcome = _heal(gm, npc_id)
		if outcome.is_empty():
			continue
		reports.append({
			"npc_id": npc_id, "name": NpcRoster.get_display_name(npc_id), "post": POST_NAMES[post],
			"action": outcome["action"], "detail": outcome["detail"],
		})
	return reports


## 손대지 않고 남겨 둘 금화: 세 계절치 유지비 + 100. 신중할수록 더 남긴다.
static func _reserve(sect: SectData, traits: Dictionary) -> int:
	return int((sect.get_gold_upkeep() * 3 + 100) * (0.8 + traits["caution"] / 250.0))


## 문주: 할 수 있는 일마다 성향과 형편으로 점수를 매겨 가장 높은 것을 한다.
static func _lead(gm: Node, npc_id: String) -> Dictionary:
	var sect: SectData = gm.player_sect
	var t: Dictionary = get_traits(npc_id)
	var reserve: int = _reserve(sect, t)
	var spare: int = sect.gold - reserve
	var options: Array[Dictionary] = []
	# 제자 모집: 정원이 빌수록, 야망이 클수록
	if sect.disciple_count < sect.max_disciples and spare >= _Balance.TRAIN_GOLD and sect.food >= _Balance.TRAIN_FOOD * 3:
		var room: float = float(sect.max_disciples - sect.disciple_count) / sect.max_disciples
		options.append({"id": "recruit", "score": 20.0 + room * 40.0 + t["ambition"] * 0.15})
	# 시설 확장: 신중할수록, 재물이 넉넉할수록
	var facility: String = _preferred_facility(sect, t, spare)
	if not facility.is_empty():
		options.append({"id": "facility", "facility": facility, "score": 15.0 + t["caution"] * 0.35 + (15.0 if spare > 400 else 0.0)})
	# 연회: 인정이 많을수록, 명성이 낮을수록
	if gm.can_do_seasonal("last_feast_turn") and spare >= _Balance.FEAST_GOLD and sect.food >= _Balance.FEAST_FOOD * 3:
		options.append({"id": "feast", "score": t["benevolence"] * 0.35 + (25.0 if sect.reputation < 40 else 0.0)})
	# 땅 평정: 야망이 클수록
	var region: String = _pacify_target(gm, spare)
	if not region.is_empty():
		options.append({"id": "pacify", "region": region, "score": t["ambition"] * 0.8})
	# 사절: 적대 세력이 있고 인정·신중이 클수록
	var hostile: SectData = _most_hostile(gm)
	if hostile and spare >= _Balance.DIPLOMAT_ENVOY_GOLD:
		options.append({"id": "envoy", "sect": hostile, "score": t["benevolence"] * 0.25 + t["caution"] * 0.2 + clampf(-hostile.attitude / 3.0, 0.0, 20.0)})
	# 재물 아끼기: 늘 할 수 있다. 신중할수록, 금고가 빌수록
	options.append({"id": "save", "score": 10.0 + t["caution"] * 0.3 + (30.0 if spare < 0 else 0.0)})
	var best: Dictionary = options[0]
	var best_score: float = -1.0
	for option in options:
		var score: float = option["score"] + randf() * 12.0
		if score > best_score:
			best = option
			best_score = score
	return _do_lead(gm, best)


static func _do_lead(gm: Node, option: Dictionary) -> Dictionary:
	var sect: SectData = gm.player_sect
	match option["id"]:
		"recruit":
			sect.spend_resources(_Balance.TRAIN_GOLD, _Balance.TRAIN_FOOD)
			sect.disciple_count += 1
			return {"action": "제자 모집", "detail": "새 제자를 들였습니다. 제자 %d / %d (금화 -%d, 식량 -%d)" % [
				sect.disciple_count, sect.max_disciples, _Balance.TRAIN_GOLD, _Balance.TRAIN_FOOD,
			]}
		"facility":
			var result: Dictionary = SectManager.upgrade_facility(sect, option["facility"])
			return {"action": "시설 확장", "detail": result["message"]}
		"feast":
			sect.spend_resources(_Balance.FEAST_GOLD, _Balance.FEAST_FOOD)
			sect.reputation += _Balance.FEAST_REPUTATION
			EventManager.set_flag(gm.story_flags, "last_feast_turn", gm._get_turn_index())
			return {"action": "문파 연회", "detail": "강호 인사를 불러 연회를 열었습니다. 명성 +%d (금화 -%d, 식량 -%d)" % [
				_Balance.FEAST_REPUTATION, _Balance.FEAST_GOLD, _Balance.FEAST_FOOD,
			]}
		"pacify":
			var region_id: String = option["region"]
			var cost: Dictionary = WorldMap.pacify_cost(region_id)
			sect.spend_resources(cost["gold"], cost["food"])
			EventManager.set_flag(gm.story_flags, "last_pacify_turn", gm._get_turn_index())
			WorldMap.transfer(gm.map_state, region_id, sect.id, [sect])
			var name: String = WorldMap.get_region(region_id)["name"]
			gm.add_world_news("%s이(가) %s을(를) 차지했습니다." % [sect.sect_name, name])
			return {"action": "땅 평정", "detail": "%s을(를) 평정했습니다. (금화 -%d, 식량 -%d)" % [name, cost["gold"], cost["food"]]}
		"envoy":
			var target: SectData = option["sect"]
			sect.spend_resources(_Balance.DIPLOMAT_ENVOY_GOLD)
			target.attitude = mini(100, target.attitude + _Balance.DIPLOMAT_ENVOY_ATTITUDE)
			target.last_diplomacy_turn = gm._get_turn_index()
			return {"action": "사절 파견", "detail": "%s에 사절을 보냈습니다. 태도 %d (금화 -%d)" % [
				target.sect_name, target.attitude, _Balance.DIPLOMAT_ENVOY_GOLD,
			]}
	return {"action": "재물 아끼기", "detail": "금고를 지키며 다음 계절을 대비했습니다. (금화 %d)" % sect.gold}


## 성향에 맞는 시설 (지혜·신중 → 서고, 탐욕 → 금고, 야망 → 무술장, 인정 → 약방). 금화가 모자라면 ""
static func _preferred_facility(sect: SectData, t: Dictionary, spare: int) -> String:
	var weights: Dictionary = {
		"library": t["caution"], "treasury": t["greed"], "training_ground": t["ambition"],
		"apothecary": t["benevolence"] * 0.8, "meditation_hall": (t["ambition"] + t["caution"]) * 0.4,
	}
	var best: String = ""
	var best_weight: float = -1.0
	for facility in weights:
		var cost: int = SectManager.get_upgrade_cost(sect, facility)
		if cost < 0 or cost > spare:
			continue
		if weights[facility] > best_weight:
			best = facility
			best_weight = weights[facility]
	return best


## 평정할 만한 빈 땅 (맞닿고, 전력이 주둔 병력 이상, 비용을 낼 수 있고, 이번 계절에 평정하지 않았으면)
static func _pacify_target(gm: Node, spare: int) -> String:
	if gm.map_state.is_empty() or not gm.can_do_seasonal("last_pacify_turn"):
		return ""
	var sect: SectData = gm.player_sect
	var leader: CharacterData = NpcRoster.create_character(sect.leader_id) if NpcRoster.has_npc(sect.leader_id) else gm.player_character
	var power: int = SectWarManager.get_military_power(sect, leader)
	for region_id in WorldMap.frontier(gm.map_state, sect.id, true):
		var cost: Dictionary = WorldMap.pacify_cost(region_id)
		if int(WorldMap.get_region(region_id)["defense"]) <= power and cost["gold"] <= spare and cost["food"] * 3 <= sect.food:
			return region_id
	return ""


static func _most_hostile(gm: Node) -> SectData:
	var result: SectData = null
	for other in gm.world_sects:
		if other.subjugated or other.attitude >= 0 or other.last_diplomacy_turn == gm._get_turn_index():
			continue
		if result == null or other.attitude < result.attitude:
			result = other
	return result


## 교두: 경지가 가장 낮은 제자 하나를 가르친다 (금화 없이, 교두 무력에 따라 경험치)
static func _instruct(gm: Node, npc_id: String) -> Dictionary:
	var sect: SectData = gm.player_sect
	var pupil: DiscipleData = null
	for disciple in sect.disciples:
		if disciple.level >= _Balance.DISCIPLE_MAX_LEVEL:
			continue
		if pupil == null or disciple.level < pupil.level or (disciple.level == pupil.level and disciple.experience < pupil.experience):
			pupil = disciple
	if pupil == null:
		return {}
	var strength: int = int(NpcRoster.get_npc(npc_id).get("stats", {}).get("strength", 10))
	var amount: int = _Balance.DISCIPLE_TRAIN_EXP / 2 + strength / 2
	var gained: int = pupil.gain_experience(amount)
	return {"action": "제자 지도", "detail": "%s에게 검을 가르쳤습니다. 경험치 +%d%s" % [
		pupil.display_name, amount, " — 경지가 올라 Lv.%d" % pupil.level if gained > 0 else "",
	]}


## 의원: 문파 사람(주인공)의 내공을 돌본다. 다 차 있으면 약초를 거둬 식량을 보탠다.
static func _heal(gm: Node, npc_id: String) -> Dictionary:
	var character: CharacterData = gm.player_character
	var wisdom: int = int(NpcRoster.get_npc(npc_id).get("stats", {}).get("wisdom", 10))
	var missing: int = character.internal_energy_max - character.internal_energy_current
	if missing > 0:
		var amount: int = mini(missing, 10 + wisdom)
		character.internal_energy_current += amount
		return {"action": "치료", "detail": "%s의 상한 기혈을 다스렸습니다. 내공 +%d" % [character.display_name, amount]}
	var food: int = 3 + wisdom / 4
	gm.player_sect.food += food
	return {"action": "약초 채집", "detail": "약초와 산나물을 거둬들였습니다. 식량 +%d" % food}


## 인물 보고를 읽기 좋은 줄로
static func format_reports(reports: Array) -> String:
	var lines: PackedStringArray = []
	for report in reports:
		lines.append("· %s(%s) %s\n    %s" % [report.get("name", "?"), report.get("post", ""), report.get("action", ""), report.get("detail", "")])
	return "\n".join(lines)


## 계절 동향: 우리 문파 인물과 강호 세력이 한 일을 한 글로
static func format_season(npc_reports: Array, faction_reports: Array) -> String:
	var parts: PackedStringArray = []
	if not npc_reports.is_empty():
		parts.append("■ 우리 문파 인물\n" + format_reports(npc_reports))
	parts.append("■ 강호 세력\n" + SectAI.format_reports(faction_reports))
	return "\n\n".join(parts)
