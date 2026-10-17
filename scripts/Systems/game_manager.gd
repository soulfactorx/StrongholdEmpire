extends Node

const _ModLoader = preload("res://scripts/Systems/mod_loader.gd")
const _SaveManager = preload("res://scripts/Systems/save_manager.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

const SEASONS: Array[String] = ["봄", "여름", "가을", "겨울"]

var current_year: int = 1
var current_season_index: int = 0
var generation: int = 1
var player_character: CharacterData
var player_sect: SectData
## 플레이어 문파를 제외한 강호의 세력들
var world_sects: Array[SectData] = []
var player_relationships: Array[RelationshipData] = []
var triggered_event_ids: Array[String] = []
var pending_event: Dictionary = {}
var story_flags: Dictionary = {}
## 플래그 이름 → 켜진 계절. 기연의 turns_since_flag 조건에 쓴다.
var flag_turns: Dictionary = {}
## 이번 인물이 거쳐 온 역할 이름 (CharacterData.Role 키)
var role_history: Array[String] = []
## 역할 자원과 역할 행동 기록 (RoleActions.create_state)
var role_state: Dictionary = RoleActions.create_state()
var legacy_records: Array[LegacyData] = []
## 전투에서 본 상대 무공 {무공 id: {id, name, element}} — 무공 연구소에서 분석한다. 세대를 넘어 남는다.
var observed_arts: Dictionary = {}
## 해가 시작될 때의 기록 (연간 보고서 비교용)
var year_start: Dictionary = {}
## 해가 바뀔 때 만든 연간 보고서 {title, lines}. 경영 화면이 보여 주고 비운다
var pending_year_report: Dictionary = {}
## 철인 모드 (자동 저장만, 수동 저장 불가)
var ironman: bool = false
## 우리 문파를 침공해 온 세력 id (대응을 고르기 전까지). 없으면 ""
var pending_invasion: String = ""
## 강호 소식 (세력 AI의 행동, 최근 것이 뒤에)
var world_news: Array[String] = []
## 도전장을 보낸 세력 id (문파전 승패에 명성이 더 걸린다). 없으면 ""
var challenge_target: String = ""
## 분석을 마친 오행 속성 (MartialArtData.FiveElement). 상극 무공 창조 성공률이 오른다.
var analyzed_elements: Array = []
var current_ending_id: String = ""
## 게임오버 id. 비어 있지 않으면 이야기가 끝난 상태다.
var game_over_id: String = ""
## 직전 계절 진행의 수입·유지비 요약
var last_turn_report: String = ""
var pending_role_transitions: Array[Dictionary] = []
var mod_martial_arts: Array[MartialArtData] = []
## 새 게임을 시작했거나 세이브를 불러와 진행 중인 게임이 있는지 여부
var is_game_active: bool = false
## 문파전 적 작전 계획 (SectWarManager.plan_battle). 계절이 바뀌거나 문파전을 치르면 비운다.
var pending_war_plan: Dictionary = {}
## 전투 씬이 읽어 갈 전투 구성. 전투가 끝나면 비운다.
var pending_combat: CombatSetup = null


func _ready() -> void:
	GameSettings.load_settings()
	GameSettings.apply(get_tree())
	_load_mod_data()
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	_initialize_new_game()


## 새 게임을 시작한다. role_id는 StartingRoles.ROLES의 id.
## overrides는 새 게임 "세부 설정"에서 바꾼 시나리오 파라미터다.
## ironman: 철인 모드. 자동 저장 하나만 쓰고 수동 저장을 할 수 없어 선택을 되돌릴 수 없다.
func start_new_game(
	display_name: String,
	role_id: String,
	scenario_id: String = ScenarioManager.DEFAULT_ID,
	overrides: Dictionary = {},
	ironman_mode: bool = false,
	tutorial: bool = false
) -> void:
	ScenarioManager.activate(scenario_id, overrides)
	_initialize_new_game(role_id, display_name)
	ironman = ironman_mode
	is_game_active = true
	# 길잡이: 첫 단계는 바로 보여 주고, 나머지는 계절마다 우선 기연으로 이어진다.
	if tutorial:
		EventManager.set_flag(story_flags, "tutorial")
		pending_event = EventManager.check_turn_events(
			player_character, player_sect, player_relationships, get_current_season(), triggered_event_ids, story_flags
		)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)


func _initialize_new_game(
	role_id: String = StartingRoles.DEFAULT_ID,
	display_name: String = ""
) -> void:
	_set_player_character(StartingRoles.create_character(role_id, display_name))
	player_sect = ScenarioManager.create_player_sect()
	world_sects = ScenarioManager.create_rival_sects()
	StartingRoles.apply_sect_setup(role_id, player_sect, player_character)
	DiscipleRoster.enable(player_sect)
	player_relationships = RelationshipManager.create_default_relationships()
	triggered_event_ids.clear()
	pending_event.clear()
	story_flags.clear()
	flag_turns.clear()
	role_history.clear()
	_record_role(player_character.role)
	role_state = RoleActions.create_state()
	legacy_records.clear()
	year_start = _take_year_snapshot()
	observed_arts = {}
	analyzed_elements = []
	challenge_target = ""
	pending_invasion = ""
	world_news.clear()
	pending_year_report = {}
	current_ending_id = ""
	game_over_id = ""
	last_turn_report = ""
	pending_role_transitions.clear()
	pending_combat = null
	pending_war_plan = {}
	generation = 1
	current_year = 1
	current_season_index = 0
	_sync_event_context()


## 기연 판정에 쓰는 진행 상황을 EventManager에 넘긴다. (딕셔너리·배열은 같은 객체를 공유)
func _sync_event_context() -> void:
	EventManager.world_sects = world_sects
	EventManager.current_year = current_year
	EventManager.current_turn = _get_turn_index()
	EventManager.current_generation = generation
	EventManager.role_history = role_history
	EventManager.flag_turns = flag_turns
	EventManager.role_state = role_state


func _record_role(role: CharacterData.Role) -> void:
	var role_name: String = CharacterData.Role.find_key(role)
	if not role_history.has(role_name):
		role_history.append(role_name)


func _set_player_character(character: CharacterData) -> void:
	if player_character and player_character.leveled_up.is_connected(_on_player_leveled_up):
		player_character.leveled_up.disconnect(_on_player_leveled_up)
	player_character = character
	player_character.leveled_up.connect(_on_player_leveled_up)


func _on_player_leveled_up(new_level: int) -> void:
	EventBus.action_message.emit(
		"%s의 경지가 올랐습니다! Lv.%d" % [player_character.display_name, new_level]
	)
	EventBus.character_updated.emit(player_character)


func get_current_season() -> String:
	return SEASONS[current_season_index]


## "천하대란 3년 가을"처럼 시나리오 연호를 붙인 날짜
func get_date_text() -> String:
	return "%s %d년 %s" % [ScenarioManager.get_era_name(), current_year, get_current_season()]


func advance_turn() -> void:
	if is_game_over():
		return
	# 생을 마치는 엔딩에 도달했으면 후계자를 정하기 전까지 시간이 흐르지 않는다.
	if story_flags.get("life_ended", false):
		EventBus.action_message.emit("이번 생의 이야기가 끝났습니다. [엔딩 / 레거시]에서 후계자를 정하세요.")
		return
	# 제한 연수의 마지막 겨울이 끝나면 시대가 끝난다.
	if (
		ScenarioRules.has_time_limit()
		and current_year >= ScenarioRules.time_limit_years()
		and current_season_index == SEASONS.size() - 1
	):
		last_turn_report = "%s — 시대가 저물었습니다." % get_date_text()
		_force_end("era_end")
		EventBus.turn_advanced.emit(current_year, get_current_season())
		return
	# 침공에 대응하지 않고 계절을 넘기면 산문을 내준 것으로 처리한다.
	var ignored_invasion: String = ""
	if not pending_invasion.is_empty():
		ignored_invasion = resolve_invasion("yield")["message"]
	current_season_index = (current_season_index + 1) % SEASONS.size()
	pending_war_plan = {}
	var yearly_report: String = ""
	if current_season_index == 0:
		current_year += 1
		yearly_report = _process_yearly_events()
	_sync_event_context()
	var income: String = _process_seasonal_income()
	var upkeep: Dictionary = SectManager.pay_upkeep(player_sect)
	var facility_report: String = _apply_facility_effects()
	var role_report: String = RoleActions.on_season(self)
	var disciple_report: String = DiscipleRoster.on_season(player_sect)
	var tribute_report: String = DiplomacyManager.on_season(player_sect, world_sects)
	var consequence: String = _apply_role_consequences()
	var world_report: String = _run_sect_ai()
	var report_parts: PackedStringArray = [income, upkeep["message"]]
	for part in [ignored_invasion, facility_report, disciple_report, tribute_report, role_report, consequence, yearly_report, world_report]:
		if not part.is_empty():
			report_parts.append(part)
	last_turn_report = "%s — %s" % [get_date_text(), " | ".join(report_parts)]
	refresh_role_transitions()
	_check_end_states()
	# 침공을 받은 계절에는 기연 대신 침공에 대응한다.
	if not is_game_over() and pending_invasion.is_empty():
		_try_trigger_event()
	if current_season_index == 0:
		pending_year_report = build_year_report()
		year_start = _take_year_snapshot()
	autosave()
	EventBus.turn_advanced.emit(current_year, get_current_season())
	EventBus.resources_changed.emit(player_sect)


## 세력 AI의 한 계절. 강호 소식을 쌓고, 침공이 있으면 대응을 기다린다. 계절 보고 문구를 돌려준다.
func _run_sect_ai() -> String:
	if not SectAI.active:
		return ""
	# 침공 빈도는 기연 빈도를 따른다 (기연 빈도 0인 시험·시뮬레이션에서는 침공이 없다).
	var result: Dictionary = SectAI.run_season(world_sects, _get_turn_index(), current_year, ScenarioRules.event_rate())
	for line in result["news"]:
		add_world_news(line)
	pending_invasion = result["invader"]
	if not pending_invasion.is_empty():
		return "%s의 침공! 대응을 고르세요." % get_world_sect(pending_invasion).sect_name
	if not result["news"].is_empty():
		return "강호 소식 %d건" % result["news"].size()
	return ""


## 연간 보고서 비교용 기록
func _take_year_snapshot() -> Dictionary:
	return {
		"year": current_year,
		"gold": player_sect.gold,
		"food": player_sect.food,
		"reputation": player_sect.reputation,
		"disciples": player_sect.disciple_count,
		"level": player_character.level,
		"arts": player_character.martial_arts.size(),
		"subjugated": world_sects.filter(func(s: SectData) -> bool: return s.subjugated).size(),
		"news": world_news.size(),
	}


## 지난 1년을 요약한다. 해가 바뀌는 계절 진행 끝에 만든다.
func build_year_report() -> Dictionary:
	var now: Dictionary = _take_year_snapshot()
	var before: Dictionary = year_start if not year_start.is_empty() else now
	var rows: Array = [
		["금화", "gold"], ["식량", "food"], ["명성", "reputation"], ["제자", "disciples"],
		["경지", "level"], ["무공", "arts"], ["굴복시킨 세력", "subjugated"],
	]
	var lines: PackedStringArray = []
	for row in rows:
		var a: int = int(before.get(row[1], now[row[1]]))
		var b: int = int(now[row[1]])
		lines.append("%s: %d → %d (%+d)" % [row[0], a, b, b - a])
	var war_news: Array = world_news.filter(func(line: String) -> bool: return line.contains("침공") or line.contains("쳐서") or line.contains("쳤다가"))
	lines.append("강호의 싸움 소식: %d건 (강호 정세에서 확인)" % war_news.size())
	if not current_ending_id.is_empty():
		lines.append("이른 결말: %s" % EndingManager.get_ending(current_ending_id).get("title", ""))
	if ScenarioRules.has_time_limit():
		lines.append("남은 연수: %d년" % ScenarioRules.years_left(current_year))
	return {"title": "%s %d년 결산" % [ScenarioManager.get_era_name(), current_year - 1], "lines": lines}


func add_world_news(line: String) -> void:
	world_news.append("%s: %s" % [get_date_text(), line])
	while world_news.size() > _Balance.WORLD_NEWS_LIMIT:
		world_news.remove_at(0)


## 침공 대응. choice: "fight"(방어전), "bribe"(금화로 물리기), "yield"(산문을 내주기)
func resolve_invasion(choice: String) -> Dictionary:
	var invader: SectData = get_world_sect(pending_invasion)
	if invader == null:
		pending_invasion = ""
		return {"success": false, "message": "침공해 온 세력이 없습니다."}
	var message: String
	match choice:
		"fight":
			pending_invasion = ""
			start_combat(CombatManager.create_invasion(invader, player_character, player_sect))
			return {"success": true, "message": "%s의 침공에 맞섭니다!" % invader.sect_name}
		"bribe":
			if not player_sect.spend_resources(_Balance.INVASION_BRIBE_GOLD):
				return {"success": false, "message": "금화가 부족합니다. (%d 필요)" % _Balance.INVASION_BRIBE_GOLD}
			invader.attitude = mini(100, invader.attitude + _Balance.AI_DIPLOMACY_ATTITUDE)
			message = "금화 %d를 내주고 %s을(를) 물렸습니다." % [_Balance.INVASION_BRIBE_GOLD, invader.sect_name]
		_:
			var lost: int = mini(_Balance.INVASION_YIELD_DISCIPLES, maxi(0, player_sect.disciple_count - 1))
			player_sect.disciple_count -= lost
			player_sect.reputation = maxi(0, player_sect.reputation - _Balance.INVASION_YIELD_REPUTATION)
			invader.disciple_count = mini(invader.max_disciples, invader.disciple_count + 1)
			invader.reputation += _Balance.INVASION_YIELD_REPUTATION
			message = "%s에게 산문을 내주었습니다. 제자 -%d, 명성 -%d" % [invader.sect_name, lost, _Balance.INVASION_YIELD_REPUTATION]
	pending_invasion = ""
	add_world_news(message)
	EventBus.resources_changed.emit(player_sect)
	_check_end_states()
	return {"success": true, "message": message}


func _process_seasonal_income() -> String:
	var income: Dictionary = SectManager.compute_seasonal_income(player_sect, player_character, get_current_season())
	income["gold"] += RoleActions.get_income_gold_bonus(role_state, player_character.role, income["gold"])
	player_sect.gold += income["gold"]
	player_sect.food += income["food"]
	player_sect.research_points += income["research"]
	return "수입: 금화 +%d, 식량 +%d, 연구점 +%d" % [income["gold"], income["food"], income["research"]]


## 다음 계절 예상 수지 (경영 화면 표시용). 계절 보정은 다음 계절 기준
func estimate_next_season() -> Dictionary:
	var next_season: String = SEASONS[(current_season_index + 1) % SEASONS.size()]
	var income: Dictionary = SectManager.compute_seasonal_income(player_sect, player_character, next_season)
	income["gold"] += RoleActions.get_income_gold_bonus(role_state, player_character.role, income["gold"])
	# 공물 (끊길 세력은 빼고)
	for sect in world_sects:
		if sect.tribute and sect.subjugated and sect.attitude > _Balance.TRIBUTE_REVOLT_ATTITUDE:
			income["gold"] += _Balance.TRIBUTE_GOLD
	return {
		"gold": income["gold"] - player_sect.get_gold_upkeep(),
		"food": income["food"] - player_sect.get_food_upkeep(),
	}


## 약방·연공실의 계절 효과
func _apply_facility_effects() -> String:
	var parts: PackedStringArray = []
	if player_sect.apothecary_level > 0:
		var regen: int = int(
			player_character.internal_energy_max * _Balance.APOTHECARY_INTERNAL_REGEN * player_sect.apothecary_level
		)
		var before: int = player_character.internal_energy_current
		player_character.internal_energy_current = mini(player_character.internal_energy_max, before + regen)
		if player_character.internal_energy_current > before:
			parts.append("약방 내공 +%d" % (player_character.internal_energy_current - before))
	if player_sect.meditation_hall_level > 0:
		var exp_gain: int = _Balance.MEDITATION_EXP_PER_LEVEL * player_sect.meditation_hall_level
		player_character.gain_experience(exp_gain)
		parts.append("연공실 수련 경험치 +%d" % exp_gain)
	return ", ".join(parts)


## 해가 바뀔 때: 나이·수련, 강호 세력 성장, 문파 명성, 재고 손실. 연간 정산 문구를 돌려준다.
func _process_yearly_events() -> String:
	player_character.age += 1
	player_character.restore_internal_energy()
	player_character.gain_experience(_Balance.YEARLY_TRAINING_EXP)
	SectWarManager.grow_world_sects(world_sects)
	var parts: PackedStringArray = []
	var reputation_gain: int = SectManager.apply_yearly_reputation(player_sect)
	if reputation_gain > 0:
		parts.append("문하생의 이름이 알려져 명성 +%d" % reputation_gain)
	var losses: Dictionary = SectManager.apply_yearly_losses(player_sect)
	if not losses["message"].is_empty():
		parts.append(losses["message"])
	EventBus.character_updated.emit(player_character)
	return "새해 정산: " + ", ".join(parts) if not parts.is_empty() else ""


func refresh_role_transitions() -> void:
	pending_role_transitions = RoleManager.get_available_transitions(
		player_character,
		player_sect,
		player_relationships,
		story_flags,
		role_state,
		world_sects
	)
	if not pending_role_transitions.is_empty():
		EventBus.role_transitions_available.emit(pending_role_transitions)


func _try_trigger_event() -> void:
	if not pending_event.is_empty():
		return
	# 우선 기연(인연 단계 변화 등)은 확률과 관계없이 일어난다.
	var candidates: Array[EventData] = EventManager.get_candidates(
		player_character, player_sect, player_relationships, get_current_season(), triggered_event_ids, story_flags
	)
	var urgent: bool = candidates.any(func(e: EventData) -> bool: return e.priority)
	if not urgent and randf() >= ScenarioRules.event_rate():
		return

	var event: Dictionary = EventManager.check_turn_events(
		player_character,
		player_sect,
		player_relationships,
		get_current_season(),
		triggered_event_ids,
		story_flags
	)
	if event.is_empty():
		return

	pending_event = event
	EventBus.event_triggered.emit(event)


func is_game_over() -> bool:
	return not game_over_id.is_empty()


## 게임오버를 먼저 확인하고, 아니면 엔딩을 확인한다.
func _check_end_states() -> void:
	if is_game_over():
		return
	var over_id: String = EndingManager.check_game_over(player_sect)
	if not over_id.is_empty():
		game_over_id = over_id
		is_game_active = false
		pending_event.clear()
		EventBus.game_over.emit(over_id)
		return
	_check_ending()


func _check_ending() -> void:
	if not current_ending_id.is_empty():
		return
	var ending: String = EndingManager.check_endings(
		player_character, player_sect, story_flags, player_relationships, get_current_season()
	)
	if ending.is_empty():
		return
	_reach_ending(ending)


func _reach_ending(ending: String) -> void:
	current_ending_id = ending
	EventManager.set_flag(story_flags, "ending_reached", ending)
	EventBus.ending_reached.emit(ending)
	if ScenarioRules.end_on_victory() and ScenarioManager.is_victory_ending(ending):
		_force_end("scenario_complete")
	elif EndingManager.is_final(ending):
		# 생을 마치는 엔딩: 전승할 수 있으면 후계자를 기다리고, 없으면 이야기가 끝난다.
		if can_continue_lineage():
			EventManager.set_flag(story_flags, "life_ended")
		else:
			_force_end("story_end")


## 시나리오 규칙상 다음 세대로 이어 갈 수 있는지 (나이·레벨 조건은 따로 본다)
func can_continue_lineage() -> bool:
	if not ScenarioRules.legacy_enabled():
		return false
	var max_generations: int = ScenarioRules.max_generations()
	return max_generations <= 0 or generation < max_generations


## 엔딩 화면에 보여 줄 이번 판의 요약
func get_run_summary() -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("시나리오: 「%s」 %s 1년 ~ %s" % [
		ScenarioManager.current.get("title", ""), ScenarioManager.get_era_name(), get_date_text(),
	])
	var role_names: PackedStringArray = []
	for role_key in role_history:
		role_names.append(CharacterData.get_role_display_name(CharacterData.Role.get(role_key)))
	lines.append("역할 변천: %s" % " → ".join(role_names))
	var subjugated: PackedStringArray = []
	for world_sect in world_sects:
		if world_sect.subjugated:
			subjugated.append(world_sect.sect_name)
	lines.append("굴복시킨 세력: %s" % (", ".join(subjugated) if not subjugated.is_empty() else "없음"))
	lines.append("무공: %s" % player_character.get_martial_arts_text())
	var bonds: Array[RelationshipData] = player_relationships.duplicate()
	bonds.sort_custom(func(a: RelationshipData, b: RelationshipData) -> bool:
		return a.bond_strength > b.bond_strength
	)
	var bond_texts: PackedStringArray = []
	for rel in bonds.slice(0, 3):
		bond_texts.append("%s(%s %d)" % [rel.target_name, rel.get_bond_name(), rel.bond_strength])
	lines.append("주요 인연: %s" % (", ".join(bond_texts) if not bond_texts.is_empty() else "없음"))
	return lines


## 그 판의 평가 (엔딩 화면용)
func get_evaluation() -> Dictionary:
	return EndingManager.evaluate(
		player_character,
		player_sect,
		world_sects,
		generation,
		current_ending_id,
		ScenarioManager.is_victory_ending(current_ending_id)
	)


## 기연의 end_game 효과: 엔딩이면 엔딩에 도달하고, 게임오버면 이야기를 끝낸다.
func _force_end(end_id: String) -> void:
	if EndingManager.GAME_OVERS.has(end_id):
		if not is_game_over():
			game_over_id = end_id
			is_game_active = false
			pending_event.clear()
			EventBus.game_over.emit(end_id)
	elif EndingManager.has_ending(end_id) and current_ending_id.is_empty():
		_reach_ending(end_id)


func resolve_pending_event(choice_index: int) -> void:
	if pending_event.is_empty():
		return

	var result: Dictionary = EventManager.resolve_choice(
		pending_event["id"],
		choice_index,
		player_character,
		player_sect,
		player_relationships,
		story_flags
	)
	pending_event.clear()
	_apply_event_result(result)


## 역할을 전환한다. option은 RoleManager가 준 선택지로, sect_id가 있으면 그 세력으로 옮겨 간다(이적·배신).
func apply_role_transition(role: CharacterData.Role, option: Dictionary = {}) -> Dictionary:
	var prefix: String = ""
	if option.has("sect_id"):
		prefix = _switch_player_sect(option["sect_id"], option.get("kind", "defect"))
	var result: Dictionary = _change_role(role)
	if not prefix.is_empty():
		result["message"] = prefix + " " + result["message"]
	EventBus.action_message.emit(result["message"])
	refresh_role_transitions()
	_check_end_states()
	return result


func _change_role(role: CharacterData.Role) -> Dictionary:
	var result: Dictionary = RoleManager.apply_transition(player_character, player_sect, role)
	RoleActions.on_role_changed(role_state, player_character.role)
	_record_role(player_character.role)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.role_changed.emit(player_character.role)
	return result


## 역할 자원이 한계에 이르렀을 때 축출·강등을 적용하고 알림 문구를 돌려준다.
func _apply_role_consequences() -> String:
	var consequence: Dictionary = RoleActions.check_consequences(self)
	if consequence.is_empty():
		return ""
	EventManager.set_flag(story_flags, consequence["flag"])
	if player_character.role == CharacterData.Role.LEADER:
		# 쫓겨난 문주 대신 원래 문주(또는 원로회)가 문파를 맡는다.
		player_sect.leader_name = (
			NpcRoster.get_display_name(player_sect.leader_id) if not player_sect.leader_id.is_empty() else "원로회"
		)
	_change_role(consequence["role"])
	return consequence["message"]


## 플레이어가 다른 세력으로 옮겨 간다. 옛 문파는 강호 세력이 된다. 알림 문구를 돌려준다.
func _switch_player_sect(sect_id: String, kind: String) -> String:
	var new_sect: SectData = get_world_sect(sect_id)
	if new_sect == null:
		return ""
	var old_sect: SectData = player_sect
	var betrayal: bool = kind == "betray"
	world_sects.erase(new_sect)
	# 플레이어 문파가 되면 외교 상태는 의미가 없다. 떠나온 문파와도 새로 시작한다.
	for sect in [new_sect, old_sect]:
		sect.allied = false
		sect.tribute = false
	if challenge_target == new_sect.id:
		challenge_target = ""
	old_sect.attitude = _Balance.BETRAY_OLD_SECT_ATTITUDE if betrayal else _Balance.DEFECT_OLD_SECT_ATTITUDE
	old_sect.subjugated = false
	old_sect.observed_commands.clear()
	if old_sect.leader_name == player_character.display_name:
		old_sect.leader_name = (
			NpcRoster.get_display_name(old_sect.leader_id) if not old_sect.leader_id.is_empty() else "원로회"
		)
	# 옛 문파는 강호 세력이 되어 제자 수만 남고, 새 문파는 명단을 만든다.
	old_sect.use_roster = false
	old_sect.disciples.clear()
	world_sects.append(old_sect)
	DiscipleRoster.enable(new_sect)
	new_sect.attitude = 0
	new_sect.subjugated = false
	new_sect.observed_commands.clear()
	player_sect = new_sect
	pending_war_plan = {}
	role_state["spy_target"] = ""
	EventManager.set_flag(story_flags, "joined_%s" % new_sect.id)
	if betrayal:
		EventManager.set_flag(story_flags, "betrayed_%s" % old_sect.id)
		player_character.morality -= _Balance.BETRAY_MORALITY_LOSS
		# 떠나온 문파의 스승·사형제는 배신자를 원수로 여긴다. 깊던 정만큼 원한도 깊다.
		for rel in player_relationships:
			if NpcRoster.get_npc(rel.target_id).get("sect_id") == old_sect.id:
				rel.bond_type = RelationshipData.BondType.HATRED
				rel.increase_bond(maxi(0, _Balance.BETRAY_HATRED_MIN - rel.bond_strength))
		return "%s을(를) 배신하고 %s(으)로 넘어갔습니다. (도덕 -%d)" % [
			old_sect.sect_name, new_sect.sect_name, _Balance.BETRAY_MORALITY_LOSS,
		]
	EventManager.set_flag(story_flags, "defected")
	return "%s에 객경으로 들어갔습니다." % new_sect.sect_name


## 외교 행동 (강호 정세 화면)
func do_diplomacy(sect_id: String, action_id: String) -> Dictionary:
	var result: Dictionary = DiplomacyManager.perform(self, sect_id, action_id)
	EventBus.resources_changed.emit(player_sect)
	_check_end_states()
	return result


## 인연 상호작용 (대화·선물·비무). 비무면 전투를 시작한다.
func interact_with(target_id: String, kind: String) -> Dictionary:
	var result: Dictionary = RelationshipManager.interact(
		player_relationships, target_id, kind, player_character, player_sect, story_flags, _get_turn_index()
	)
	EventBus.relationships_changed.emit(player_relationships)
	EventBus.resources_changed.emit(player_sect)
	if result.has("combat"):
		start_combat(result["combat"])
	return result


## 역할 고유 행동 (경영 화면의 역할 버튼). 전투·기연으로 이어지면 바로 시작한다.
func do_role_action(action_id: String, target: String = "") -> Dictionary:
	if is_game_over():
		return {"success": false, "message": "이야기가 끝났습니다."}
	var result: Dictionary = RoleActions.perform(self, action_id, target)
	var consequence: String = _apply_role_consequences()
	if not consequence.is_empty():
		result["message"] += " " + consequence
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)
	refresh_role_transitions()
	_check_end_states()
	if is_game_over():
		return result
	if result.has("event") and pending_event.is_empty():
		pending_event = result["event"]
		EventBus.event_triggered.emit(pending_event)
	elif result.has("combat"):
		start_combat(result["combat"])
	return result


func start_legacy_succession() -> Dictionary:
	if is_game_over():
		return {"success": false, "message": "이야기가 끝나 전승할 수 없습니다."}
	if not ScenarioRules.legacy_enabled():
		return {"success": false, "message": "이 시나리오에서는 세대 전승을 할 수 없습니다."}
	var max_generations: int = ScenarioRules.max_generations()
	if max_generations > 0 and generation >= max_generations:
		return {"success": false, "message": "이 시나리오의 마지막 세대입니다. (최대 %d세대)" % max_generations}
	# 생을 마치는 엔딩에 도달했다면 나이·레벨과 관계없이 전승한다.
	if not story_flags.get("life_ended", false) and not LegacyManager.can_retire(player_character):
		return {
			"success": false,
			"message": "아직 전승할 수 없습니다. (55세 이상 또는 레벨 10)",
		}

	var legacy: LegacyData = LegacyManager.create_legacy_record(
		player_character,
		player_sect,
		generation,
		current_ending_id
	)
	legacy_records.append(legacy)
	generation += 1

	_set_player_character(LegacyManager.create_successor(legacy, player_sect))
	# 문파 비전은 후계자에게 이어진다.
	if player_sect.secret_art:
		player_character.learn_martial_art(player_sect.secret_art.duplicate(true))
	LegacyManager.apply_legacy_bonuses(player_sect, legacy)
	player_relationships = RelationshipManager.create_default_relationships()
	triggered_event_ids.clear()
	current_ending_id = ""
	story_flags.clear()
	flag_turns.clear()
	role_history.clear()
	_record_role(player_character.role)
	role_state = RoleActions.create_state()
	_sync_event_context()

	EventBus.legacy_succession.emit(legacy)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)

	return {
		"success": true,
		"message": "%s이(가) %s(으)로 이어갑니다. (제%d세대)%s" % [
			legacy.predecessor_name,
			player_character.display_name,
			generation,
			" 문파 비전 [%s]을(를) 물려받았습니다." % player_sect.secret_art.display_name if player_sect.secret_art else "",
		],
	}


func get_world_sect(sect_id: String) -> SectData:
	for sect in world_sects:
		if sect.id == sect_id:
			return sect
	return null


## 강호 세력을 약한 순서로 정렬해 돌려준다.
func get_world_sects_by_power() -> Array[SectData]:
	var result: Array[SectData] = world_sects.duplicate()
	result.sort_custom(func(a: SectData, b: SectData) -> bool:
		return SectWarManager.get_sect_power(a) < SectWarManager.get_sect_power(b)
	)
	return result


## 문파전을 걸 수 있는 세력 (굴복하지 않았고 동맹이 아닌 세력, 약한 순서)
func get_war_targets() -> Array[SectData]:
	var result: Array[SectData] = []
	for sect in get_world_sects_by_power():
		if not sect.subjugated and not sect.allied:
			result.append(sect)
	return result


func can_wage_war() -> bool:
	return story_flags.get("last_war_turn", -1) != _get_turn_index()


## 대상 세력의 작전 계획을 준비한다. 같은 계절에 같은 상대면 기존 계획을 그대로 쓴다.
func prepare_war(target_id: String) -> Dictionary:
	var enemy: SectData = get_world_sect(target_id)
	if enemy == null:
		return {}
	if pending_war_plan.get("target") != target_id:
		pending_war_plan = SectWarManager.plan_battle(enemy)
	return pending_war_plan


## 정찰: 금화를 내고 적 계획을 한 라운드 공개한다.
func scout_war(target_id: String) -> Dictionary:
	var plan: Dictionary = prepare_war(target_id)
	if plan.is_empty():
		return {"success": false, "message": "정찰할 대상이 없습니다."}
	if not plan["revealed"].has(false):
		return {"success": false, "message": "이미 적의 작전을 모두 알고 있습니다."}
	var cost: int = roundi(
		SectWarManager.get_scout_cost(plan, player_character) * RoleActions.get_scout_scale(role_state, player_character.role)
	)
	if not player_sect.spend_resources(cost):
		return {"success": false, "message": "금화가 부족합니다. (%d 필요)" % cost}
	var round_index: int = SectWarManager.reveal_next(plan)
	var command: SectWarManager.Command = plan["enemy_commands"][round_index]
	EventBus.resources_changed.emit(player_sect)
	return {
		"success": true,
		"round": round_index,
		"message": "정찰 성공 (금화 -%d): 적은 %d라운드에 [%s]을(를) 준비하고 있습니다." % [
			cost, round_index + 1, SectWarManager.COMMAND_NAMES[command],
		],
	}


## 문파전에 장수로 데려갈 수 있는 인물: 유대가 깊은 사제·혈맹 인물. 상대 세력 소속은 제외.
func get_war_generals(target_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rel in player_relationships:
		if not rel.bond_type in [RelationshipData.BondType.MASTER_DISCIPLE, RelationshipData.BondType.BLOOD_OATH]:
			continue
		if rel.bond_strength < _Balance.WAR_GENERAL_MIN_BOND or not NpcRoster.has_npc(rel.target_id):
			continue
		if NpcRoster.get_npc(rel.target_id).get("sect_id") == target_id:
			continue
		result.append(SectWarManager.describe_general(rel.target_id))
	return result


## 문파전. 계절마다 한 번, 굴복하지 않은 세력을 상대로만 할 수 있다.
func resolve_sect_war(
	target_id: String,
	commands: Array,
	formation: SectWarManager.Formation = SectWarManager.Formation.NONE,
	general_id: String = ""
) -> Dictionary:
	if not can_wage_war():
		return {"success": false, "victory": false, "message": "이번 계절에는 이미 문파전을 치렀습니다."}
	var enemy: SectData = get_world_sect(target_id)
	if enemy == null or enemy.subjugated:
		return {"success": false, "victory": false, "message": "공격할 수 없는 상대입니다."}
	if enemy.allied:
		return {"success": false, "victory": false, "message": "동맹 세력은 공격할 수 없습니다. 먼저 동맹을 깨야 합니다."}
	var typed_commands: Array[SectWarManager.Command] = []
	for cmd in commands:
		typed_commands.append(cmd as SectWarManager.Command)
	var general: Dictionary = {}
	for candidate in get_war_generals(target_id):
		if candidate["id"] == general_id:
			general = candidate
	var plan: Dictionary = prepare_war(target_id)
	EventManager.set_flag(story_flags, "last_war_turn", _get_turn_index())
	var result: Dictionary = SectWarManager.resolve_battle(
		player_sect, player_character, enemy, typed_commands, plan, formation, general,
		DiplomacyManager.get_ally_support(world_sects)
	)
	pending_war_plan = {}
	# 도전장을 보낸 상대와의 결판에는 명성이 더 걸린다.
	if challenge_target == enemy.id:
		challenge_target = ""
		if result.get("victory", false):
			player_sect.reputation += _Balance.CHALLENGE_WIN_REPUTATION
			result["message"] += "\n도전장의 결판을 냈습니다! 명성 +%d" % _Balance.CHALLENGE_WIN_REPUTATION
		else:
			player_sect.reputation = maxi(0, player_sect.reputation - _Balance.CHALLENGE_LOSS_REPUTATION)
			result["message"] += "\n도전장을 보내 놓고 졌습니다. 명성 -%d" % _Balance.CHALLENGE_LOSS_REPUTATION
	if result.get("victory", false):
		EventManager.set_flag(story_flags, "won_sect_war")
		EventManager.set_flag(story_flags, "defeated_%s" % enemy.id)
	if result.get("subjugated", false):
		EventManager.set_flag(story_flags, "subjugated_%s" % enemy.id)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	_check_end_states()
	return result


## 전투를 시작한다. 전투 씬으로 이동하고, 결과는 finish_combat으로 받는다.
func start_combat(setup: CombatSetup) -> void:
	# 문파를 지키는 싸움에는 깊은 인연의 인물이 달려온다.
	if setup.allies_are_disciples:
		CombatManager.add_bond_allies(setup, player_relationships, player_character)
	pending_combat = setup
	SceneRouter.goto(get_tree(), SceneRouter.COMBAT)


## 전투 씬이 사용할 구성을 돌려준다. 예약된 전투가 없으면(개발자 메뉴 등) 비무를 만든다.
func get_or_create_combat_setup() -> CombatSetup:
	if pending_combat == null:
		pending_combat = CombatManager.create_sparring(player_character)
	return pending_combat


## 계절마다 한 번 할 수 있는 행동인지 (플래그에 마지막으로 한 계절을 기록)
func can_do_seasonal(action_flag: String) -> bool:
	return story_flags.get(action_flag, -1) != _get_turn_index()


func _mark_seasonal(action_flag: String) -> void:
	EventManager.set_flag(story_flags, action_flag, _get_turn_index())


## 영약 구매: 최대 내공이 오른다. 계절마다 한 번.
func buy_elixir() -> Dictionary:
	if not can_do_seasonal("last_elixir_turn"):
		return {"success": false, "message": "이번 계절에는 이미 영약을 구했습니다."}
	if not player_sect.spend_resources(_Balance.ELIXIR_GOLD):
		return {"success": false, "message": "금화가 부족합니다. (%d 필요)" % _Balance.ELIXIR_GOLD}
	_mark_seasonal("last_elixir_turn")
	player_character.internal_energy_max += _Balance.ELIXIR_INTERNAL_GAIN
	player_character.internal_energy_current += _Balance.ELIXIR_INTERNAL_GAIN
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	return {"success": true, "message": "영약을 복용해 최대 내공 +%d (금화 -%d)" % [
		_Balance.ELIXIR_INTERNAL_GAIN, _Balance.ELIXIR_GOLD,
	]}


## 문파 연회: 강호 인사를 초대해 명성을 높인다. 계절마다 한 번.
func hold_feast() -> Dictionary:
	if not can_do_seasonal("last_feast_turn"):
		return {"success": false, "message": "이번 계절에는 이미 연회를 열었습니다."}
	if not player_sect.spend_resources(_Balance.FEAST_GOLD, _Balance.FEAST_FOOD):
		return {"success": false, "message": "자원이 부족합니다. (금화 %d, 식량 %d 필요)" % [
			_Balance.FEAST_GOLD, _Balance.FEAST_FOOD,
		]}
	_mark_seasonal("last_feast_turn")
	player_sect.reputation += _Balance.FEAST_REPUTATION
	var message: String = "문파 연회를 열었습니다. 명성 +%d (금화 -%d, 식량 -%d)" % [
		_Balance.FEAST_REPUTATION, _Balance.FEAST_GOLD, _Balance.FEAST_FOOD,
	]
	# 문주가 여는 연회는 문파 안의 불만도 달랜다.
	if player_character.role == CharacterData.Role.LEADER:
		role_state["discontent"] = maxi(0, role_state["discontent"] - _Balance.FEAST_DISCONTENT_RELIEF)
		message += ", 불만도 -%d" % _Balance.FEAST_DISCONTENT_RELIEF
	EventBus.resources_changed.emit(player_sect)
	_check_end_states()
	return {"success": true, "message": message}


## 시설 확장. 막내 제자는 시설을 확장할 권한이 없다.
func upgrade_facility(facility: String) -> Dictionary:
	if player_character.role == CharacterData.Role.YOUNG_DISCIPLE:
		return {"success": false, "message": "막내 제자는 시설을 확장할 수 없습니다."}
	return SectManager.upgrade_facility(player_sect, facility)


func can_spar() -> bool:
	return story_flags.get("last_spar_turn", -1) != _get_turn_index()


## 경영 화면의 비무. 계절마다 한 번만 할 수 있다.
func start_sparring() -> Dictionary:
	if not can_spar():
		return {"success": false, "message": "이번 계절에는 이미 비무를 했습니다."}
	EventManager.set_flag(story_flags, "last_spar_turn", _get_turn_index())
	start_combat(CombatManager.create_sparring(player_character))
	return {"success": true, "message": "남궁휘에게 비무를 청합니다."}


## 전투 결과를 반영하고 결과(message, outcome 포함)를 돌려준다.
func finish_combat(outcome: CombatManager.Outcome, fallen_allies: int = 0, fallen_ids: Array = []) -> Dictionary:
	if pending_combat == null:
		return {"success": false, "message": "진행 중인 전투가 없습니다."}
	_record_observed_arts(pending_combat)
	# 침공 방어전: 막아 내면 침략 세력이 제자를 잃는다.
	if not pending_combat.invader_id.is_empty():
		var invader: SectData = get_world_sect(pending_combat.invader_id)
		if invader:
			if outcome == CombatManager.Outcome.VICTORY:
				invader.disciple_count = maxi(_Balance.AI_MIN_DISCIPLES, invader.disciple_count - _Balance.INVASION_REPEL_LOSS)
				add_world_news("%s의 침공을 막아 냈습니다. (%s 제자 -%d)" % [invader.sect_name, invader.sect_name, _Balance.INVASION_REPEL_LOSS])
			else:
				add_world_news("%s의 침공을 막지 못했습니다." % invader.sect_name)
	var result: Dictionary = CombatManager.apply_outcome(
		pending_combat,
		outcome,
		player_character,
		player_sect,
		player_relationships,
		story_flags,
		fallen_allies,
		fallen_ids
	)
	pending_combat = null
	EventBus.combat_finished.emit(result)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)
	refresh_role_transitions()
	_check_end_states()
	if result["success"]:
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	return result


## 전투에서 상대가 지닌 무공을 기록한다.
func _record_observed_arts(setup: CombatSetup) -> void:
	for enemy in setup.enemies:
		for art in enemy.martial_arts:
			if not observed_arts.has(art.id):
				observed_arts[art.id] = {
					"id": art.id, "name": art.display_name, "element": int(art.element), "owner": enemy.display_name,
				}


func _get_turn_index() -> int:
	return current_year * SEASONS.size() + current_season_index


func _load_mod_data() -> void:
	mod_martial_arts = _ModLoader.load_martial_arts_from_json()


## 수동 저장. 철인 모드에서는 할 수 없다.
func save_game(slot: int = 1) -> Dictionary:
	if ironman and slot != _SaveManager.AUTO_SLOT:
		return {"success": false, "message": "철인 모드에서는 계절이 바뀔 때 자동으로만 저장됩니다."}
	return _SaveManager.save_game(_build_save_state(), slot)


## 계절이 바뀔 때마다 자동 저장 슬롯에 저장한다.
func autosave() -> Dictionary:
	return _SaveManager.save_game(_build_save_state(), _SaveManager.AUTO_SLOT)


func _build_save_state() -> Dictionary:
	var state: Dictionary = {
		"summary": {
			"name": player_character.display_name,
			"role": player_character.get_role_name(),
			"date": get_date_text(),
			"scenario": ScenarioManager.current.get("title", ""),
			"generation": generation,
			"ironman": ironman,
			"ending": EndingManager.get_ending(current_ending_id).get("title", "") if not current_ending_id.is_empty() else "",
		},
		"ironman": ironman,
		"version": _SaveManager.SAVE_VERSION,
		"scenario_id": ScenarioManager.current_id,
		"scenario_overrides": ScenarioManager.user_overrides,
		"current_year": current_year,
		"current_season_index": current_season_index,
		"generation": generation,
		"story_flags": story_flags,
		"flag_turns": flag_turns,
		"role_history": role_history,
		"role_state": role_state,
		"observed_arts": observed_arts,
		"challenge_target": challenge_target,
		"pending_invasion": pending_invasion,
		"year_start": year_start,
		"world_news": world_news,
		"analyzed_elements": analyzed_elements,
		"triggered_event_ids": triggered_event_ids,
		"current_ending_id": current_ending_id,
		"game_over_id": game_over_id,
		"character": _SaveManager.serialize_character(player_character),
		"sect": _SaveManager.serialize_sect(player_sect),
		"world_sects": _SaveManager.serialize_sects(world_sects),
		"relationships": _SaveManager.serialize_relationships(player_relationships),
		"legacy_records": _SaveManager.serialize_legacy(legacy_records),
	}
	return state


func load_game(slot: int = 1) -> Dictionary:
	var result: Dictionary = _SaveManager.load_game(slot)
	if not result["success"]:
		return result
	_apply_save_data(result["data"])
	is_game_active = not is_game_over()
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)
	return result


func _apply_save_data(data: Dictionary) -> void:
	# 시나리오를 먼저 켜야 전용 인물·문파·기연이 준비된다. 구버전 세이브는 기본 시나리오.
	ScenarioManager.activate(
		data.get("scenario_id", ScenarioManager.DEFAULT_ID),
		data.get("scenario_overrides", {})
	)
	current_year = data.get("current_year", 1)
	current_season_index = data.get("current_season_index", 0)
	generation = data.get("generation", 1)
	story_flags = data.get("story_flags", {})
	flag_turns.clear()
	for flag in data.get("flag_turns", {}):
		flag_turns[flag] = int(data["flag_turns"][flag])
	role_history.clear()
	for role_name in data.get("role_history", []):
		role_history.append(str(role_name))
	# 역할 자원이 없는 구버전 세이브는 기본값으로 시작한다.
	role_state = RoleActions.restore_state(data.get("role_state", {}))
	ironman = data.get("ironman", false) == true
	challenge_target = str(data.get("challenge_target", ""))
	pending_invasion = str(data.get("pending_invasion", ""))
	year_start = data.get("year_start", {})
	pending_year_report = {}
	world_news.clear()
	for line in data.get("world_news", []):
		world_news.append(str(line))
	observed_arts = {}
	var saved_arts: Dictionary = data.get("observed_arts", {})
	for art_id in saved_arts:
		var entry: Dictionary = saved_arts[art_id]
		observed_arts[art_id] = {
			"id": str(entry.get("id", art_id)), "name": str(entry.get("name", "?")),
			"element": int(entry.get("element", 0)), "owner": str(entry.get("owner", "")),
		}
	analyzed_elements = []
	for element in data.get("analyzed_elements", []):
		analyzed_elements.append(int(element))
	triggered_event_ids.clear()
	for event_id in data.get("triggered_event_ids", []):
		triggered_event_ids.append(event_id)
	current_ending_id = data.get("current_ending_id", "")
	game_over_id = data.get("game_over_id", "")
	pending_event.clear()
	pending_war_plan = {}
	_set_player_character(_SaveManager.deserialize_character(data.get("character", {})))
	player_sect = _SaveManager.deserialize_sect(data.get("sect", {}))
	# 명단이 없는 구버전 세이브는 제자 수만큼 무작위 제자로 채운다.
	if not player_sect.use_roster:
		DiscipleRoster.enable(player_sect)
	# 강호 세력이 없는 구버전 세이브는 데이터 초기값으로 채운다.
	if data.has("world_sects"):
		world_sects = _SaveManager.deserialize_sects(data["world_sects"])
	else:
		world_sects = SectRegistry.create_rival_sects()
	# 역할 기록이 없는 구버전 세이브는 현재 역할만 기록한다.
	_record_role(player_character.role)
	_sync_event_context()
	player_relationships = _SaveManager.deserialize_relationships(data.get("relationships", []))
	legacy_records = _SaveManager.deserialize_legacy(data.get("legacy_records", []))
	refresh_role_transitions()


func has_save_file(slot: int = -1) -> bool:
	return _SaveManager.has_save(slot)


func _apply_event_result(result: Dictionary) -> void:
	if result.has("end_game"):
		_force_end(result["end_game"])
	EventBus.event_resolved.emit(result)
	EventBus.action_message.emit(result.get("message", ""))
	EventBus.resources_changed.emit(player_sect)
	EventBus.character_updated.emit(player_character)
	EventBus.relationships_changed.emit(player_relationships)
	refresh_role_transitions()
	_check_end_states()
	if result.get("success", false):
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	# 전투로 이어지는 선택지는 결과를 반영한 뒤 전투 씬으로 넘어간다.
	if result.has("combat"):
		start_combat(result["combat"])