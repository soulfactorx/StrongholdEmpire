class_name RoleActions
extends RefCounted

## 역할별 고유 행동과 역할 자원(불만도·신임도·노출도·현상금·신용도 등).
## 상태는 GameManager.role_state 딕셔너리 하나에 담고, 이 클래스는 규칙만 담당한다.
## gm은 GameManager 노드다. (정적 함수라 오토로드 이름을 직접 쓰지 않는다)

const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 기연 조건·효과의 role_state에서 쓸 수 있는 숫자 필드
const NUMERIC_FIELDS: PackedStringArray = [
	"discontent", "trust", "exposure", "bounty", "failures", "intel_count",
]

## 행동 정의. target: "" (대상 없음), "sect"(강호 세력), "department", "job", "location"
const ACTIONS: Dictionary = {
	"council": {
		"role": CharacterData.Role.LEADER, "title": "문파 회의 소집", "target": "",
		"description": "원로와 제자들의 의견을 듣습니다. 내부 불만도가 내려갑니다.",
	},
	"envoy": {
		"role": CharacterData.Role.LEADER, "title": "사절 파견", "target": "sect",
		"description": "예물을 들려 사절을 보냅니다. 그 세력의 태도가 좋아집니다.",
	},
	"department": {
		"role": CharacterData.Role.MANAGER, "title": "부서 지정", "target": "department",
		"description": "맡을 부서를 정합니다. 부서마다 계절 효과가 다릅니다.",
	},
	"proposal": {
		"role": CharacterData.Role.MANAGER, "title": "문주에게 건의", "target": "",
		"description": "문파 운영을 건의합니다. 받아들여지면 명성과 신임이, 아니면 신임이 떨어집니다.",
	},
	"teaching": {
		"role": CharacterData.Role.YOUNG_DISCIPLE, "title": "스승에게 가르침", "target": "",
		"description": "스승께 가르침을 청합니다. 유대가 깊을수록 깨달음을 얻기 쉽습니다.",
	},
	"outing": {
		"role": CharacterData.Role.YOUNG_DISCIPLE, "title": "외출", "target": "",
		"description": "산문 밖으로 나가 봅니다. 기연을 만날 수도 있습니다.",
	},
	"job_board": {
		"role": CharacterData.Role.WANDERER, "title": "의뢰 게시판", "target": "job",
		"description": "토벌·호위·수색 의뢰를 받습니다. 타지에서는 보상이 크고 위험합니다.",
	},
	"travel": {
		"role": CharacterData.Role.WANDERER, "title": "이동", "target": "location",
		"description": "다른 세력의 땅으로 거처를 옮깁니다. 그곳 의뢰를 하면 그 세력의 신용을 얻습니다.",
	},
	"intel": {
		"role": CharacterData.Role.SPY, "title": "정보 수집", "target": "sect",
		"description": "세력의 전력과 이번 계절 작전을 알아냅니다. 노출도 +%d" % _Balance.EXPOSURE_INTEL,
	},
	"sabotage": {
		"role": CharacterData.Role.SPY, "title": "사보타주", "target": "sect",
		"description": "세력의 제자와 금고에 타격을 줍니다. 노출도 +%d" % _Balance.EXPOSURE_SABOTAGE,
	},
	"assassination": {
		"role": CharacterData.Role.ASSASSIN, "title": "표적 의뢰", "target": "",
		"description": "표적 의뢰를 받아 잠입 전투를 벌입니다. 현상금 +%d" % _Balance.BOUNTY_PER_CONTRACT,
	},
	"lie_low": {
		"role": CharacterData.Role.ASSASSIN, "title": "은신", "target": "",
		"description": "금화 %d로 몸을 숨겨 현상금을 %d 낮춥니다." % [_Balance.LIE_LOW_GOLD, _Balance.LIE_LOW_BOUNTY],
	},
	"contract": {
		"role": CharacterData.Role.MERCENARY, "title": "계약 수주", "target": "sect",
		"description": "세력의 임무를 맡고 선금을 받습니다. %d계절 안에 이행해야 합니다." % _Balance.CONTRACT_SEASONS,
	},
	"fulfill": {
		"role": CharacterData.Role.MERCENARY, "title": "계약 이행", "target": "",
		"description": "맡은 임무를 수행합니다. 성공하면 잔금과 신용을 얻습니다.",
	},
	"breach": {
		"role": CharacterData.Role.MERCENARY, "title": "계약 위반", "target": "",
		"description": "의뢰주를 팔아넘기고 금화 %d를 챙깁니다. 신용과 태도가 크게 떨어집니다." % _Balance.CONTRACT_BREACH_GOLD,
	},
}

const DEPARTMENTS: Dictionary = {
	"finance": {"title": "재정", "description": "계절 금화 수입 +%d%%" % int(_Balance.DEPT_FINANCE_GOLD_BONUS * 100)},
	"training": {"title": "수련", "description": "계절마다 수련 경험치 +%d" % _Balance.DEPT_TRAINING_EXP},
	"intel": {"title": "정보", "description": "문파전 정찰 비용 %d%%" % int(_Balance.DEPT_INTEL_SCOUT_SCALE * 100)},
}

const JOBS: Dictionary = {
	"hunt": {"title": "토벌", "description": "도적 무리를 토벌합니다. (전술 전투)"},
	"escort": {"title": "호위", "description": "상단을 호위합니다. 전투력이 높을수록 성공하기 쉽습니다."},
	"search": {"title": "수색", "description": "잃어버린 비급·물건을 찾습니다. 연구점이나 경험을 얻습니다."},
}


static func create_state() -> Dictionary:
	return {
		"discontent": 0,
		"trust": _Balance.MANAGER_START_TRUST,
		"department": "",
		"exposure": 0,
		"bounty": 0,
		"failures": 0,
		"intel_count": 0,
		"spy_target": "",
		"location": "",
		"credit": {},
		"contract": {},
		"last_action_turn": -1,
		"actions_used": 0,
	}


## 세이브에서 읽은 값을 기본값 위에 덮는다. (JSON 숫자는 실수로 읽히므로 정수로 되돌린다)
static func restore_state(data: Dictionary) -> Dictionary:
	var state: Dictionary = create_state()
	for key in data:
		state[key] = data[key]
	for key in NUMERIC_FIELDS:
		state[key] = int(state[key])
	state["last_action_turn"] = int(state["last_action_turn"])
	state["actions_used"] = int(state["actions_used"])
	var credit: Dictionary = {}
	for sect_id in state["credit"]:
		credit[sect_id] = int(state["credit"][sect_id])
	state["credit"] = credit
	if not state["contract"].is_empty():
		state["contract"]["reward"] = int(state["contract"]["reward"])
		state["contract"]["advance"] = int(state["contract"].get("advance", 0))
		state["contract"]["due"] = int(state["contract"]["due"])
	return state


static func get_actions(role: CharacterData.Role) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action_id in ACTIONS:
		if ACTIONS[action_id]["role"] == role:
			var entry: Dictionary = ACTIONS[action_id].duplicate()
			entry["id"] = action_id
			result.append(entry)
	return result


static func get_credit(state: Dictionary, sect_id: String) -> int:
	return int(state["credit"].get(sect_id, 0))


static func change_credit(state: Dictionary, sect_id: String, amount: int) -> void:
	state["credit"][sect_id] = clampi(get_credit(state, sect_id) + amount, -_Balance.CREDIT_LIMIT, _Balance.CREDIT_LIMIT)


## 이번 계절에 역할 행동을 더 할 수 있는지
static func can_act(state: Dictionary, turn: int) -> bool:
	return state["last_action_turn"] != turn or state["actions_used"] < _Balance.ROLE_ACTIONS_PER_SEASON


static func _consume_action(state: Dictionary, turn: int) -> void:
	if state["last_action_turn"] != turn:
		state["last_action_turn"] = turn
		state["actions_used"] = 0
	state["actions_used"] += 1


## 대상을 고르는 행동의 선택지: [{id, title, description}]
static func get_targets(gm: Node, action_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state: Dictionary = gm.role_state
	match str(ACTIONS.get(action_id, {}).get("target", "")):
		"sect":
			for sect in gm.world_sects:
				if sect.subjugated:
					continue
				var detail: String = "%s · 태도 %s(%d)" % [sect.get_alignment_name(), sect.get_attitude_text(), sect.attitude]
				if action_id == "contract":
					var credit: int = get_credit(state, sect.id)
					if credit < _Balance.CONTRACT_MIN_CREDIT:
						continue
					detail += " · 신용 %d · 보수 %d" % [credit, _contract_reward(credit)]
				result.append({"id": sect.id, "title": sect.sect_name, "description": detail})
		"department":
			for dept_id in DEPARTMENTS:
				var title: String = DEPARTMENTS[dept_id]["title"]
				if state["department"] == dept_id:
					title += " (현재)"
				result.append({"id": dept_id, "title": title, "description": DEPARTMENTS[dept_id]["description"]})
		"job":
			for job_id in JOBS:
				result.append({"id": job_id, "title": JOBS[job_id]["title"], "description": JOBS[job_id]["description"]})
		"location":
			if not str(state["location"]).is_empty():
				result.append({"id": "", "title": "정처 없는 길" if gm.player_sect.id == "none" else gm.player_sect.sect_name, "description": "본거지로 돌아갑니다." if gm.player_sect.id != "none" else "어느 세력의 땅도 아닌 길로 나섭니다."})
			for sect in gm.world_sects:
				if sect.id != state["location"]:
					result.append({
						"id": sect.id,
						"title": "%s의 땅" % sect.sect_name,
						"description": "보상 ×%.1f, 위험 증가 · 신용 %d" % [_Balance.JOB_AWAY_REWARD_SCALE, get_credit(state, sect.id)],
					})
	return result


## 역할 행동을 실행한다. 결과: success, message, 그리고 필요하면 combat(CombatSetup)·event(기연)
static func perform(gm: Node, action_id: String, target: String = "") -> Dictionary:
	var state: Dictionary = gm.role_state
	var character: CharacterData = gm.player_character
	if not ACTIONS.has(action_id):
		return _fail("알 수 없는 행동입니다.")
	var action: Dictionary = ACTIONS[action_id]
	if action["role"] != character.role:
		return _fail("%s만 할 수 있는 행동입니다." % CharacterData.get_role_display_name(action["role"]))
	var turn: int = gm._get_turn_index()
	if not can_act(state, turn):
		return _fail("이번 계절에는 이미 역할 행동을 했습니다.")
	if action["target"] != "" and not _target_allowed(gm, action_id, target):
		return _fail("대상을 고르세요.")
	var result: Dictionary
	match action_id:
		"council": result = _do_council(gm, target)
		"envoy": result = _do_envoy(gm, target)
		"department": result = _do_department(gm, target)
		"proposal": result = _do_proposal(gm, target)
		"teaching": result = _do_teaching(gm, target)
		"outing": result = _do_outing(gm, target)
		"job_board": result = _do_job_board(gm, target)
		"travel": result = _do_travel(gm, target)
		"intel": result = _do_intel(gm, target)
		"sabotage": result = _do_sabotage(gm, target)
		"assassination": result = _do_assassination(gm, target)
		"lie_low": result = _do_lie_low(gm, target)
		"contract": result = _do_contract(gm, target)
		"fulfill": result = _do_fulfill(gm, target)
		"breach": result = _do_breach(gm, target)
	if result["success"] or result.get("consumed", false):
		_consume_action(state, turn)
	return result


static func _target_allowed(gm: Node, action_id: String, target: String) -> bool:
	for entry in get_targets(gm, action_id):
		if entry["id"] == target:
			return true
	return false


static func _fail(message: String) -> Dictionary:
	return {"success": false, "message": message}


## 성공 확률(%)로 판정한다.
static func _roll(chance: int) -> bool:
	return randi_range(1, 100) <= chance


# ── 문주 ──

static func _do_council(gm: Node, _target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	if not gm.player_sect.spend_resources(_Balance.COUNCIL_GOLD):
		return _fail("금화가 부족합니다. (%d 필요)" % _Balance.COUNCIL_GOLD)
	var before: int = state["discontent"]
	state["discontent"] = maxi(0, before - _Balance.COUNCIL_DISCONTENT_RELIEF)
	return {"success": true, "message": "문파 회의를 열어 원로와 제자들의 말을 들었습니다. 불만도 %d → %d (금화 -%d)" % [
		before, state["discontent"], _Balance.COUNCIL_GOLD,
	]}


static func _do_envoy(gm: Node, target: String) -> Dictionary:
	var sect: SectData = gm.get_world_sect(target)
	if not gm.player_sect.spend_resources(_Balance.ENVOY_GOLD):
		return _fail("금화가 부족합니다. (%d 필요)" % _Balance.ENVOY_GOLD)
	sect.attitude = clampi(sect.attitude + _Balance.ENVOY_ATTITUDE, -100, 100)
	return {"success": true, "message": "%s에 사절을 보냈습니다. 태도 %s(%d) (금화 -%d)" % [
		sect.sect_name, sect.get_attitude_text(), sect.attitude, _Balance.ENVOY_GOLD,
	]}


# ── 중간관리자 ──

static func _do_department(gm: Node, target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	if state["department"] == target:
		return _fail("이미 %s 부서를 맡고 있습니다." % DEPARTMENTS[target]["title"])
	state["department"] = target
	return {"success": true, "message": "%s 부서를 맡았습니다. %s" % [
		DEPARTMENTS[target]["title"], DEPARTMENTS[target]["description"],
	]}


static func get_proposal_chance(gm: Node) -> int:
	return clampi(int(gm.role_state["trust"]) + gm.player_character.wisdom, 5, _Balance.PROPOSAL_MAX_CHANCE)


static func _do_proposal(gm: Node, _target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	if _roll(get_proposal_chance(gm)):
		gm.player_sect.reputation += _Balance.PROPOSAL_REPUTATION
		state["trust"] = mini(100, state["trust"] + _Balance.PROPOSAL_TRUST_GAIN)
		return {"success": true, "message": "건의가 받아들여졌습니다. 명성 +%d, 신임도 %d" % [
			_Balance.PROPOSAL_REPUTATION, state["trust"],
		]}
	state["trust"] = maxi(0, state["trust"] - _Balance.PROPOSAL_TRUST_LOSS)
	state["failures"] += 1
	return {"success": false, "consumed": true, "message": "건의가 물리쳐졌습니다. 신임도 %d (실패 %d/%d)" % [
		state["trust"], state["failures"], _Balance.DEMOTION_FAILURES,
	]}


# ── 막내 제자 ──

static func _do_teaching(gm: Node, _target: String) -> Dictionary:
	var character: CharacterData = gm.player_character
	var parts: PackedStringArray = ["경험치 +%d" % _Balance.TEACH_EXP]
	var master: RelationshipData = RelationshipManager.get_bond_with(gm.player_relationships, "npc_master")
	if master:
		master.increase_bond(_Balance.TEACH_BOND)
		parts.append("스승과의 유대 +%d" % _Balance.TEACH_BOND)
		if _roll(master.bond_strength / 2):
			character.wisdom += 1
			parts.append("깨달음을 얻어 지혜 +1")
	character.gain_experience(_Balance.TEACH_EXP)
	return {"success": true, "message": "스승께 가르침을 청했습니다. " + ", ".join(parts)}


static func _do_outing(gm: Node, _target: String) -> Dictionary:
	if gm.pending_event.is_empty():
		var event: Dictionary = EventManager.check_turn_events(
			gm.player_character, gm.player_sect, gm.player_relationships,
			gm.get_current_season(), gm.triggered_event_ids, gm.story_flags
		)
		if not event.is_empty():
			return {"success": true, "event": event, "message": "외출 길에 뜻밖의 일을 만났습니다."}
	if randi() % 2 == 0:
		gm.player_sect.gold += _Balance.OUTING_GOLD
		return {"success": true, "message": "저잣거리 심부름으로 금화 +%d를 벌었습니다." % _Balance.OUTING_GOLD}
	gm.player_character.gain_experience(_Balance.OUTING_EXP)
	return {"success": true, "message": "산길을 걸으며 견문을 넓혔습니다. 경험치 +%d" % _Balance.OUTING_EXP}


# ── 낭인 ──

static func _away_scale(state: Dictionary) -> float:
	return 1.0 if str(state["location"]).is_empty() else _Balance.JOB_AWAY_REWARD_SCALE


static func get_escort_chance(gm: Node) -> int:
	var chance: int = (
		_Balance.JOB_ESCORT_BASE_CHANCE
		+ (gm.player_character.get_combat_power() - _Balance.JOB_ESCORT_POWER_BASE) * _Balance.JOB_ESCORT_POWER_SCALE
	)
	if not str(gm.role_state["location"]).is_empty():
		chance -= _Balance.JOB_AWAY_RISK
	return clampi(chance, 10, 95)


## 타지에서 의뢰를 마치면 그 세력의 신용이 오른다.
static func _gain_local_credit(state: Dictionary, parts: PackedStringArray, gm: Node) -> void:
	var location: String = state["location"]
	if location.is_empty():
		return
	change_credit(state, location, _Balance.JOB_CREDIT_GAIN)
	var sect: SectData = gm.get_world_sect(location)
	if sect:
		parts.append("%s 신용 %d" % [sect.sect_name, get_credit(state, location)])


static func _do_job_board(gm: Node, target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	var scale: float = _away_scale(state)
	var parts: PackedStringArray = []
	match target:
		"hunt":
			_gain_local_credit(state, parts, gm)
			var setup: CombatSetup = CombatManager.create_bandit_hunt(
				gm.player_character, roundi(_Balance.JOB_HUNT_GOLD * scale)
			)
			return {"success": true, "combat": setup, "message": "토벌 의뢰를 받았습니다. " + ", ".join(parts)}
		"escort":
			if _roll(get_escort_chance(gm)):
				var gold: int = roundi(_Balance.JOB_ESCORT_GOLD * scale)
				gm.player_sect.gold += gold
				parts.append("금화 +%d" % gold)
				_gain_local_credit(state, parts, gm)
				return {"success": true, "message": "상단을 무사히 호위했습니다. " + ", ".join(parts)}
			var character: CharacterData = gm.player_character
			character.internal_energy_current = character.internal_energy_current / 2
			state["failures"] += 1
			return {"success": false, "consumed": true, "message": "호위 도중 습격을 막지 못했습니다. 부상으로 내공이 절반으로 줄었습니다."}
		_:
			if randi() % 2 == 0:
				var research: int = roundi(_Balance.JOB_SEARCH_RESEARCH * scale)
				gm.player_sect.research_points += research
				parts.append("잃어버린 비급 조각을 찾아 연구점 +%d" % research)
			else:
				var exp_gain: int = roundi(_Balance.JOB_SEARCH_EXP * scale)
				gm.player_character.gain_experience(exp_gain)
				parts.append("험한 산을 뒤져 경험치 +%d" % exp_gain)
			_gain_local_credit(state, parts, gm)
			return {"success": true, "message": "수색 의뢰를 마쳤습니다. " + ", ".join(parts)}


static func _do_travel(gm: Node, target: String) -> Dictionary:
	gm.role_state["location"] = target
	return {"success": true, "message": "%s(으)로 거처를 옮겼습니다." % get_location_name(gm)}


static func get_location_name(gm: Node) -> String:
	var location: String = gm.role_state["location"]
	if location.is_empty():
		return "정처 없는 길" if gm.player_sect.id == "none" else gm.player_sect.sect_name
	var sect: SectData = gm.get_world_sect(location)
	return "%s의 땅" % sect.sect_name if sect else gm.player_sect.sect_name


# ── 스파이 ──

static func _add_exposure(state: Dictionary, amount: int) -> void:
	state["exposure"] = clampi(state["exposure"] + amount, 0, _Balance.EXPOSURE_MAX)


static func _do_intel(gm: Node, target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	var sect: SectData = gm.get_world_sect(target)
	# 이번 계절 그 세력의 작전을 모두 알아낸다. (문파전 화면에서 정찰한 것과 같음)
	var plan: Dictionary = gm.prepare_war(target)
	var commands: PackedStringArray = []
	for i in plan["revealed"].size():
		plan["revealed"][i] = true
		commands.append(SectWarManager.COMMAND_NAMES[plan["enemy_commands"][i]])
	gm.player_sect.research_points += _Balance.INTEL_RESEARCH
	_add_exposure(state, _Balance.EXPOSURE_INTEL)
	state["intel_count"] += 1
	state["spy_target"] = target
	var parts: PackedStringArray = [
		"%s: 전력 %d, 제자 %d, 금화 %d" % [sect.sect_name, SectWarManager.get_sect_power(sect), sect.disciple_count, sect.gold],
		"이번 계절 작전 [%s]" % ", ".join(commands),
		"연구점 +%d" % _Balance.INTEL_RESEARCH,
		"노출도 %d" % state["exposure"],
	]
	if state["intel_count"] >= _Balance.SPY_MISSION_INTEL and not gm.story_flags.get("spy_mission_complete", false):
		EventManager.set_flag(gm.story_flags, "spy_mission_complete")
		parts.append("임무 완수 — 문파로 복귀할 수 있습니다")
	return {"success": true, "message": "정보 수집 성공. " + ", ".join(parts)}


static func _do_sabotage(gm: Node, target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	var sect: SectData = gm.get_world_sect(target)
	var lost_disciples: int = mini(_Balance.SABOTAGE_DISCIPLES, maxi(0, sect.disciple_count - 1))
	var lost_gold: int = mini(_Balance.SABOTAGE_GOLD, sect.gold)
	sect.disciple_count -= lost_disciples
	sect.gold -= lost_gold
	_add_exposure(state, _Balance.EXPOSURE_SABOTAGE)
	state["spy_target"] = target
	EventManager.set_flag(gm.story_flags, "sabotaged_%s" % target)
	return {"success": true, "message": "%s 사보타주 성공: 제자 -%d, 금화 -%d. 노출도 %d" % [
		sect.sect_name, lost_disciples, lost_gold, state["exposure"],
	]}


# ── 암살자 ──

static func _do_assassination(gm: Node, _target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	state["bounty"] += _Balance.BOUNTY_PER_CONTRACT
	return {
		"success": true,
		"combat": CombatManager.create_assassination(gm.player_character),
		"message": "표적 의뢰를 받았습니다. 현상금 %d" % state["bounty"],
	}


static func _do_lie_low(gm: Node, _target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	if state["bounty"] <= 0:
		return _fail("쫓는 자가 없어 숨을 필요가 없습니다.")
	if not gm.player_sect.spend_resources(_Balance.LIE_LOW_GOLD):
		return _fail("금화가 부족합니다. (%d 필요)" % _Balance.LIE_LOW_GOLD)
	state["bounty"] = maxi(0, state["bounty"] - _Balance.LIE_LOW_BOUNTY)
	return {"success": true, "message": "한 계절 몸을 숨겼습니다. 현상금 %d (금화 -%d)" % [
		state["bounty"], _Balance.LIE_LOW_GOLD,
	]}


# ── 의뢰인 ──

static func _contract_reward(credit: int) -> int:
	return roundi(_Balance.CONTRACT_REWARD * (1.0 + credit / 200.0))


static func get_contract_chance(gm: Node) -> int:
	return clampi(
		_Balance.CONTRACT_BASE_CHANCE + gm.player_character.level * _Balance.CONTRACT_LEVEL_CHANCE,
		10,
		_Balance.CONTRACT_MAX_CHANCE
	)


static func _do_contract(gm: Node, target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	if not state["contract"].is_empty():
		return _fail("이미 맡은 계약이 있습니다. 이행하거나 위반하세요.")
	var sect: SectData = gm.get_world_sect(target)
	var reward: int = _contract_reward(get_credit(state, target))
	var advance: int = roundi(reward * _Balance.CONTRACT_ADVANCE_RATIO)
	gm.player_sect.gold += advance
	state["contract"] = {
		"sect": target,
		"reward": reward,
		"advance": advance,
		"due": gm._get_turn_index() + _Balance.CONTRACT_SEASONS,
	}
	return {"success": true, "message": "%s의 임무를 맡았습니다. 선금 +%d, 보수 %d, %d계절 안에 이행" % [
		sect.sect_name, advance, reward, _Balance.CONTRACT_SEASONS,
	]}


static func _do_fulfill(gm: Node, _target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	var contract: Dictionary = state["contract"]
	if contract.is_empty():
		return _fail("맡은 계약이 없습니다.")
	var sect: SectData = gm.get_world_sect(contract["sect"])
	var sect_name: String = sect.sect_name if sect else "의뢰주"
	state["contract"] = {}
	if _roll(get_contract_chance(gm)):
		var rest: int = contract["reward"] - contract["advance"]
		gm.player_sect.gold += rest
		change_credit(state, contract["sect"], _Balance.CONTRACT_CREDIT_GAIN)
		if sect:
			sect.attitude = clampi(sect.attitude + 5, -100, 100)
		gm.player_character.gain_experience(20)
		return {"success": true, "message": "%s의 임무를 완수했습니다. 잔금 +%d, 신용 %d" % [
			sect_name, rest, get_credit(state, contract["sect"]),
		]}
	change_credit(state, contract["sect"], -_Balance.CONTRACT_FAIL_CREDIT)
	state["failures"] += 1
	return {"success": false, "consumed": true, "message": "%s의 임무에 실패했습니다. 신용 %d" % [
		sect_name, get_credit(state, contract["sect"]),
	]}


static func _do_breach(gm: Node, _target: String) -> Dictionary:
	var state: Dictionary = gm.role_state
	var contract: Dictionary = state["contract"]
	if contract.is_empty():
		return _fail("맡은 계약이 없습니다.")
	state["contract"] = {}
	gm.player_sect.gold += _Balance.CONTRACT_BREACH_GOLD
	var message: String = _apply_breach(gm, contract["sect"])
	return {"success": true, "message": "의뢰주를 팔아넘기고 금화 +%d를 챙겼습니다. %s" % [_Balance.CONTRACT_BREACH_GOLD, message]}


## 계약 위반의 대가: 신용과 태도가 떨어진다.
static func _apply_breach(gm: Node, sect_id: String) -> String:
	var state: Dictionary = gm.role_state
	change_credit(state, sect_id, -_Balance.CONTRACT_BREACH_CREDIT)
	EventManager.set_flag(gm.story_flags, "breached_contract")
	var sect: SectData = gm.get_world_sect(sect_id)
	if sect == null:
		return ""
	sect.attitude = clampi(sect.attitude - _Balance.CONTRACT_BREACH_ATTITUDE, -100, 100)
	return "%s 신용 %d, 태도 %d" % [sect.sect_name, get_credit(state, sect_id), sect.attitude]


# ── 계절 처리 ──

## 부서(재정)의 계절 금화 보너스. 예상 수지에도 쓴다.
static func get_income_gold_bonus(state: Dictionary, role: CharacterData.Role, base_gold: int) -> int:
	if role == CharacterData.Role.MANAGER and state["department"] == "finance":
		return roundi(base_gold * _Balance.DEPT_FINANCE_GOLD_BONUS)
	return 0


## 정찰 비용 배율 (정보 부서)
static func get_scout_scale(state: Dictionary, role: CharacterData.Role) -> float:
	if role == CharacterData.Role.MANAGER and state["department"] == "intel":
		return _Balance.DEPT_INTEL_SCOUT_SCALE
	return 1.0


## 계절이 바뀔 때 역할 자원을 갱신하고 보고 문구를 돌려준다.
static func on_season(gm: Node) -> String:
	var state: Dictionary = gm.role_state
	var character: CharacterData = gm.player_character
	var parts: PackedStringArray = []
	# 노출도·현상금은 역할이 바뀌어도 남고, 시간이 지나면 잊힌다.
	state["exposure"] = maxi(0, state["exposure"] - _Balance.EXPOSURE_DECAY)
	state["bounty"] = maxi(0, state["bounty"] - _Balance.BOUNTY_DECAY)
	match character.role:
		CharacterData.Role.LEADER:
			var rise: int = _Balance.DISCONTENT_PER_SEASON
			if gm.player_sect.shortage_seasons > 0:
				rise += _Balance.DISCONTENT_SHORTAGE
			state["discontent"] = mini(_Balance.DISCONTENT_OUSTED, state["discontent"] + rise)
			if state["discontent"] >= _Balance.DISCONTENT_REBELLION:
				parts.append("문파 내 불만이 높습니다 (%d)" % state["discontent"])
		CharacterData.Role.MANAGER:
			if not str(state["department"]).is_empty():
				state["trust"] = mini(100, state["trust"] + _Balance.DEPT_TRUST_PER_SEASON)
				if state["department"] == "training":
					character.gain_experience(_Balance.DEPT_TRAINING_EXP)
					parts.append("수련 부서 경험치 +%d" % _Balance.DEPT_TRAINING_EXP)
		CharacterData.Role.MERCENARY:
			var contract: Dictionary = state["contract"]
			if not contract.is_empty() and gm._get_turn_index() > int(contract["due"]):
				state["contract"] = {}
				parts.append("계약 기한을 넘겼습니다. " + _apply_breach(gm, contract["sect"]))
	return ", ".join(parts)


## 역할 자원이 한계에 이르렀을 때의 결과: 정체 발각(엔딩), 축출, 강등.
## 강제 전환이 필요하면 {role, message, flag}를 돌려준다.
static func check_consequences(gm: Node) -> Dictionary:
	var state: Dictionary = gm.role_state
	var character: CharacterData = gm.player_character
	if state["exposure"] >= _Balance.EXPOSURE_MAX and not gm.story_flags.get("spy_exposed", false):
		EventManager.set_flag(gm.story_flags, "spy_exposed")
	match character.role:
		CharacterData.Role.LEADER:
			if state["discontent"] >= _Balance.DISCONTENT_OUSTED:
				return {
					"role": CharacterData.Role.WANDERER,
					"flag": "ousted_leader",
					"message": "쌓인 불만이 터져 원로회가 문주를 내쳤습니다. 낭인이 되어 산문을 나섭니다.",
				}
		CharacterData.Role.MANAGER:
			if state["trust"] <= 0 or state["failures"] >= _Balance.DEMOTION_FAILURES:
				return {
					"role": CharacterData.Role.YOUNG_DISCIPLE,
					"flag": "demoted",
					"message": "잇따른 실책으로 문주의 신임을 잃어 막내 제자로 강등되었습니다.",
				}
	return {}


## 역할이 바뀔 때 역할 자원을 정리한다.
static func on_role_changed(state: Dictionary, new_role: CharacterData.Role) -> void:
	state["failures"] = 0
	match new_role:
		CharacterData.Role.LEADER:
			state["discontent"] = 0
		CharacterData.Role.MANAGER:
			state["trust"] = _Balance.MANAGER_START_TRUST
			state["department"] = ""
		CharacterData.Role.SPY:
			state["intel_count"] = 0
	if not new_role in [CharacterData.Role.WANDERER, CharacterData.Role.MERCENARY]:
		state["location"] = ""
	if new_role != CharacterData.Role.MERCENARY:
		state["contract"] = {}


## 경영 화면에 보여 줄 역할 자원 요약
static func describe(gm: Node) -> String:
	var state: Dictionary = gm.role_state
	var lines: PackedStringArray = []
	match gm.player_character.role:
		CharacterData.Role.LEADER:
			lines.append("내부 불만도 %d / %d (%d 이상이면 반란 위험)" % [
				state["discontent"], _Balance.DISCONTENT_OUSTED, _Balance.DISCONTENT_REBELLION,
			])
		CharacterData.Role.MANAGER:
			var dept: String = str(state["department"])
			lines.append("문주 신임도 %d · 부서 %s · 건의 성공률 %d%% · 실책 %d/%d" % [
				state["trust"],
				DEPARTMENTS[dept]["title"] if DEPARTMENTS.has(dept) else "없음",
				get_proposal_chance(gm),
				state["failures"], _Balance.DEMOTION_FAILURES,
			])
		CharacterData.Role.YOUNG_DISCIPLE:
			lines.append("막내 제자는 시설을 확장할 수 없습니다.")
		CharacterData.Role.WANDERER:
			lines.append("거처 %s · 호위 성공률 %d%%" % [get_location_name(gm), get_escort_chance(gm)])
		CharacterData.Role.SPY:
			lines.append("노출도 %d / %d · 수집한 정보 %d/%d" % [
				state["exposure"], _Balance.EXPOSURE_MAX, state["intel_count"], _Balance.SPY_MISSION_INTEL,
			])
		CharacterData.Role.ASSASSIN:
			lines.append("현상금 %d (%d 이상이면 추격대가 붙음)" % [state["bounty"], _Balance.BOUNTY_PURSUIT])
		CharacterData.Role.MERCENARY:
			var contract: Dictionary = state["contract"]
			if contract.is_empty():
				lines.append("맡은 계약 없음 · 이행 성공률 %d%%" % get_contract_chance(gm))
			else:
				var sect: SectData = gm.get_world_sect(contract["sect"])
				lines.append("계약: %s · 보수 %d · 남은 계절 %d · 성공률 %d%%" % [
					sect.sect_name if sect else "?", contract["reward"],
					int(contract["due"]) - gm._get_turn_index(), get_contract_chance(gm),
				])
	if not can_act(state, gm._get_turn_index()):
		lines.append("이번 계절 역할 행동을 마쳤습니다.")
	return "\n".join(lines)
