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
## 고르기를 기다리는 행동 대화 장면 (ActionScenes.build의 결과). 저장하지 않는다
var pending_action_scene: Dictionary = {}
## 행동마다 최근에 본 장면 id (같은 장면이 이어지지 않게)
var _recent_action_scenes: Dictionary = {}
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
## 개인 재산: 문파에 몸담아 살림을 맡지 않는 역할(낭인·의뢰인·간자·자객)의 금화·식량. 문파 금고와 따로다.
## 금화·식량만 쓴다. 문주·총관·막내 제자는 문파 금고(player_sect)를 쓴다 → get_wallet()
var purse: SectData = create_purse()
## 등장인물 선택 플레이: 주인공이 된 명부 인물 id (시나리오 playables). 일반 시작이면 ""
var player_npc_id: String = ""
## 기능 단계 개방 (FeatureGate): 단계 개방 중인지, 열린 기능, 아직 소개하지 않은 새 기능
var progressive_features: bool = false
var unlocked_features: Array[String] = []
var pending_intros: Array[String] = []
## 강호 일지: 지금의 목표와 들려오는 소문 (최근 것이 뒤). 기연 효과 goal·rumor로 바뀐다
var journal_goal: String = ""
## 초식 배치 대결: 상대의 버릇 기록 {인물 id: {bouts, first: {유형: 횟수}}}, 초식 숙련 {무공 id: 쓴 횟수}
var duel_memory: Dictionary = {}
var art_mastery: Dictionary = {}
var journal_rumors: Array[String] = []
const JOURNAL_RUMOR_LIMIT := 6
## 지금 있는 지역 (강호 지도의 지역 id). 문파 일을 하는 역할은 본거지에 있고, 개인 재산을 쓰는 역할은 지도에서 옮겨 다닌다.
var player_region: String = ""
## 가진 비급 (무공 id). 소속 문파 서고의 비급과 함께 무공 연구소에서 연구할 수 있다. 기연·사부에게서 얻는다.
var owned_manuals: Array[String] = []
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
## 마지막 전투의 기록 (전투 화면의 전투 기록). 연대기에서도 본다
var last_combat_history: PackedStringArray = []
## 연대기: 이야기에서 일어난 일(기연 선택, 오간 대사, 전투, 역할 변화, 엔딩 등)을 순서대로 남긴다.
## 항목: {date, turn, generation, kind, text, lines}. 오래된 것부터 지운다.
var chronicle: Array[Dictionary] = []
const CHRONICLE_LIMIT := 1000
## 무공 창조 화면에서 고르던 설정 (다시 열면 이어서): {name, category, element, yin_yang, effects}
var art_draft: Dictionary = {}
## 저장해 둔 무공 창조 설정: [{title, name, category, element, yin_yang, effects}]
var art_blueprints: Array[Dictionary] = []
const ART_BLUEPRINT_LIMIT := 10
## 강호 지도 상태 {owners: {지역: 세력 id}, homes: {세력 id: 본거지}} (WorldMap)
var map_state: Dictionary = {}
## 지난 계절 세력마다 한 일: [{sect_id, sect_name, strategy, action, detail}] (SectAI.run_season의 reports)
var last_faction_report: Array[Dictionary] = []
## 지난 계절 우리 문파 직책 인물이 한 일: [{npc_id, name, post, action, detail}] (NpcAgent.run_season)
var last_npc_report: Array[Dictionary] = []


func _ready() -> void:
	GameSettings.load_settings()
	GameSettings.apply(get_tree())
	_load_mod_data()
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	_initialize_new_game()
	if SelfCheck.requested():
		_run_self_check.call_deferred()
	# 웹(설치형 앱)은 서비스 워커가 옛 파일을 보관하므로, 새 버전이 배포되면 알리고 바로 바꿀 수 있게 한다.
	if OS.has_feature("web"):
		JavaScriptBridge.pwa_update_available.connect(_on_web_update_available)
		if JavaScriptBridge.pwa_needs_update():
			_on_web_update_available.call_deferred()


func _on_web_update_available() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	ActionPreview.get_popup(scene).open(
		"새 버전이 있습니다",
		"게임이 새로 배포되었습니다. 지금 바꾸면 화면을 다시 불러옵니다.%s" % (
			"\n진행 중인 이야기는 먼저 자동 저장합니다. 다시 열고 [이어하기]를 누르세요." if is_game_active else ""
		),
		apply_web_update, "지금 업데이트", "나중에"
	)


## 웹: 진행 중이면 자동 저장한 뒤 새 버전으로 바꾸고 다시 불러온다.
func apply_web_update() -> void:
	if is_game_active and not is_game_over():
		autosave()
	JavaScriptBridge.pwa_update()


## 내보낸 빌드 자체 점검 (--self-check): 결과를 출력하고 종료 코드로 알린다.
func _run_self_check() -> void:
	# 첫 화면의 배경음악이 시작된 뒤에 멈추도록 한 프레임 기다린다.
	await get_tree().process_frame
	var result: Dictionary = SelfCheck.run()
	for line in result["lines"]:
		print(line)
	print("자체 점검: %s" % ("통과" if result["ok"] else "실패"))
	AudioManager.stop_all()
	# 정적 캐시가 쥔 그림·글꼴을 놓아 종료 시 "사용 중인 자원" 경고가 나지 않게 한다.
	ArtAssets.clear_cache()
	# 오디오 스레드가 재생 객체를 놓을 때까지 잠시 기다린다 (종료 시 누수 경고 방지)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if result["ok"] else 1)


## 새 게임을 시작한다. role_id는 StartingRoles.ROLES의 id.
## overrides는 새 게임 "세부 설정"에서 바꾼 시나리오 파라미터다.
## ironman: 철인 모드. 자동 저장 하나만 쓰고 수동 저장을 할 수 없어 선택을 되돌릴 수 없다.
func start_new_game(
	display_name: String,
	role_id: String,
	scenario_id: String = ScenarioManager.DEFAULT_ID,
	overrides: Dictionary = {},
	ironman_mode: bool = false,
	tutorial: bool = false,
	factions: Dictionary = {}
) -> void:
	ScenarioManager.activate(scenario_id, overrides)
	_initialize_new_game(role_id, display_name, factions)
	ironman = ironman_mode
	is_game_active = true
	add_chronicle("시작", "%s(%s), 「%s」의 강호에 첫발을 내딛다." % [
		player_character.display_name, player_character.get_role_name(), ScenarioManager.current.get("title", "강호"),
	], PackedStringArray([str(ScenarioManager.current.get("description", ""))]))
	# 길잡이: 첫 단계는 바로 보여 주고, 나머지는 계절마다 우선 기연으로 이어진다.
	# 안내형 시나리오("guided", 입문 수련)는 자체 길잡이가 있으므로 일반 길잡이 플래그를 켜지 않는다.
	var guided: bool = ScenarioManager.current.get("guided", false) == true
	if tutorial and not guided:
		EventManager.set_flag(story_flags, "tutorial")
	if tutorial or guided:
		pending_event = EventManager.check_turn_events(
			player_character, player_sect, player_relationships, get_current_season(), triggered_event_ids, story_flags
		)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.relationships_changed.emit(player_relationships)


## 연대기에 한 줄 남긴다. lines는 오간 대사·세부 결과.
func add_chronicle(kind: String, text: String, lines: PackedStringArray = PackedStringArray()) -> void:
	if text.is_empty():
		return
	chronicle.append({
		"date": get_date_text(), "turn": _get_turn_index(), "generation": generation,
		"kind": kind, "text": text, "lines": Array(lines),
	})
	if chronicle.size() > CHRONICLE_LIMIT:
		chronicle = chronicle.slice(chronicle.size() - CHRONICLE_LIMIT)


## 무공 창조 설정을 저장 형식으로 정리한다 (JSON을 거치면 숫자가 실수가 되므로 정수로)
static func _clean_blueprint(data: Dictionary) -> Dictionary:
	var effects: Array = []
	for effect in data.get("effects", []):
		effects.append(int(effect))
	return {
		"title": str(data.get("title", "")), "name": str(data.get("name", "")),
		"category": int(data.get("category", 0)), "element": int(data.get("element", 0)),
		"yin_yang": int(data.get("yin_yang", 0)), "effects": effects,
	}


## 무공 창조 설정을 저장한다. 같은 이름이면 덮어쓰고, 가득 차면 가장 오래된 것을 지운다.
func save_art_blueprint(blueprint: Dictionary) -> Dictionary:
	var clean: Dictionary = _clean_blueprint(blueprint)
	if clean["title"].is_empty():
		clean["title"] = clean["name"] if not clean["name"].is_empty() else "설정 %d" % (art_blueprints.size() + 1)
	for i in art_blueprints.size():
		if art_blueprints[i]["title"] == clean["title"]:
			art_blueprints[i] = clean
			return {"success": true, "message": "설정 「%s」을(를) 덮어썼습니다." % clean["title"]}
	art_blueprints.append(clean)
	var message: String = "설정 「%s」을(를) 저장했습니다." % clean["title"]
	if art_blueprints.size() > ART_BLUEPRINT_LIMIT:
		message += " (가장 오래된 「%s」은(는) 지웠습니다)" % art_blueprints[0]["title"]
		art_blueprints.remove_at(0)
	return {"success": true, "message": message}


## factions: 새 게임 화면의 세력 설정
##   {player_sect: 소속 문파 id(비면 시나리오 기본), extra: [더할 세력 id], strategies: {세력 id: 전략 id 또는 "random"}}
## 낭인은 소속 문파가 없다 (무소속: player_sect.id == NO_SECT, 제자·시설 없이 금화·식량만 개인 재산으로 쓴다).
func _initialize_new_game(
	role_id: String = StartingRoles.DEFAULT_ID,
	display_name: String = "",
	factions: Dictionary = {}
) -> void:
	# 등장인물로 시작: 역할·소속·인연·플래그를 시나리오의 등장인물 항목이 정한다.
	var playable: Dictionary = ScenarioManager.get_playable(str(factions.get("playable", "")))
	player_npc_id = str(playable.get("npc", ""))
	EventManager.player_npc_id = player_npc_id
	if playable.is_empty():
		_set_player_character(StartingRoles.create_character(role_id, display_name))
	else:
		role_id = str(playable["start_role"])
		factions = factions.duplicate()
		factions["player_sect"] = str(playable.get("sect", ""))
		factions["bonds"] = playable.get("bonds", {})
		_set_player_character(create_playable_character(playable))
	var default_sect: SectData = ScenarioManager.create_player_sect()
	var chosen: String = str(factions.get("player_sect", ""))
	if StartingRoles.is_unaffiliated(role_id) or chosen == NO_SECT:
		player_sect = create_unaffiliated_sect()
	elif not chosen.is_empty() and chosen != default_sect.id and SectRegistry.has_sect(chosen):
		player_sect = SectRegistry.create_sect(chosen, ScenarioManager.current.get("sect_overrides", {}).get(chosen, {}))
	else:
		player_sect = default_sect
	world_sects = ScenarioManager.create_rival_sects()
	# 다른 문파에 속하거나 무소속이면, 원래 플레이어 문파(청운검파 등)는 강호 세력이 된다.
	world_sects.assign(world_sects.filter(func(sect: SectData) -> bool: return sect.id != player_sect.id))
	if player_sect.id != default_sect.id and get_world_sect(default_sect.id) == null:
		world_sects.push_front(default_sect)
	_apply_faction_setup(factions)
	map_state = WorldMap.create_state(_all_sect_ids())
	player_region = _default_region()
	if WorldMap.has_region(str(playable.get("region", ""))):
		player_region = str(playable["region"])
	last_faction_report.clear()
	last_npc_report.clear()
	StartingRoles.apply_sect_setup(role_id, player_sect, player_character)
	purse = create_purse()
	if uses_purse():
		purse.gold = _Balance.PURSE_START_GOLD
		purse.food = _Balance.PURSE_START_FOOD
	DiscipleRoster.enable(player_sect)
	# 시작 인연: 직접 정했으면 그대로, 아니면 소속 문파 기준 (무소속 낭인은 없음)
	if factions.has("bonds"):
		player_relationships = RelationshipManager.create_from_setup(factions["bonds"])
	else:
		player_relationships = RelationshipManager.create_default_relationships(player_sect.id)
	triggered_event_ids.clear()
	pending_event.clear()
	story_flags.clear()
	flag_turns.clear()
	# 시작 역할이 이미 걸어온 길 (간자 포섭, 자객의 길 등)
	for flag in StartingRoles.get_by_id(role_id).get("flags", []):
		EventManager.set_flag(story_flags, flag)
	if not playable.is_empty():
		EventManager.set_flag(story_flags, "playing_" + player_npc_id)
		for flag in playable.get("flags", []):
			EventManager.set_flag(story_flags, str(flag))
	# 기능 단계 개방: 단계 개방 시나리오의 등장인물은 정한 기능만 열고 시작한다 (나머지는 모두 열림)
	progressive_features = ScenarioManager.current.get("progressive", false) == true and playable.has("features")
	unlocked_features.clear()
	pending_intros.clear()
	if progressive_features:
		for feature_id in playable["features"]:
			unlocked_features.append(str(feature_id))
		for feature_id in FeatureGate.ROLE_FEATURES.get(CharacterData.Role.keys()[player_character.role], []):
			if not unlocked_features.has(feature_id):
				unlocked_features.append(feature_id)
	journal_goal = str(playable.get("goal", ""))
	# 등장인물이 없는 시나리오는 시나리오의 역할별 첫 목표 (goals: {역할 id 또는 "default": 목표})
	var scenario_goals: Variant = ScenarioManager.current.get("goals", {})
	if journal_goal.is_empty() and scenario_goals is Dictionary:
		journal_goal = str(scenario_goals.get(role_id, scenario_goals.get("default", "")))
	journal_rumors.clear()
	role_history.clear()
	_record_role(player_character.role)
	role_state = RoleActions.create_state()
	_sync_location()
	legacy_records.clear()
	year_start = _take_year_snapshot()
	observed_arts = {}
	duel_memory = {}
	art_mastery = {}
	pending_action_scene = {}
	_recent_action_scenes = {}
	owned_manuals.clear()
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
	chronicle.clear()
	art_draft = {}
	art_blueprints.clear()
	_sync_event_context()


## 시나리오 등장인물로 주인공을 만든다: 인물의 능력치·무공·나이·도덕·초상화에 시작 역할을 입힌다.
static func create_playable_character(playable: Dictionary) -> CharacterData:
	var npc_id: String = str(playable["npc"])
	var character: CharacterData = NpcRoster.create_character(npc_id)
	character.id = "player_001"
	character.portrait_id = npc_id
	character.role = StartingRoles.get_by_id(str(playable["start_role"]))["role"]
	if playable.has("level"):
		character.level = int(playable["level"])
	for key in ["morality", "age"]:
		if playable.has(key):
			character.set(key, int(playable[key]))
	# 인물 데이터의 무공은 레벨 조건을 따르므로, 정한 레벨에 맞게 다시 익힌다.
	for entry in NpcRoster.get_npc(npc_id).get("martial_arts", []):
		if character.level >= int(entry.get("min_level", 1)):
			var art: MartialArtData = MartialArtLibrary.create_art(str(entry["id"]))
			if art:
				character.learn_martial_art(art)
	for art_id in playable.get("arts", []):
		var extra: MartialArtData = MartialArtLibrary.create_art(str(art_id))
		if extra:
			character.learn_martial_art(extra)
	character.restore_internal_energy()
	return character


## 새 게임 세력 설정: 고른 세력을 더하고 세력마다 전략을 정한다.
func _apply_faction_setup(factions: Dictionary) -> void:
	for sect_id in factions.get("extra", []):
		if SectRegistry.has_sect(sect_id) and get_world_sect(sect_id) == null and sect_id != player_sect.id:
			world_sects.append(SectRegistry.create_sect(sect_id))
	var strategies: Dictionary = factions.get("strategies", {})
	for sect in world_sects:
		var chosen: String = FactionStrategy.resolve(str(strategies.get(sect.id, "")))
		if FactionStrategy.is_valid(chosen):
			sect.strategy = chosen


## 무소속 (낭인): 제자·시설·땅이 없고 금화·식량은 개인 재산
const NO_SECT := "none"


func has_sect() -> bool:
	return player_sect != null and player_sect.id != NO_SECT


static func create_unaffiliated_sect() -> SectData:
	var sect := SectData.new()
	sect.id = NO_SECT
	sect.sect_name = "무소속"
	sect.leader_name = ""
	sect.disciple_count = 0
	sect.max_disciples = 0
	sect.reputation = 30
	sect.gold = 0
	sect.food = 0
	for facility in _Balance.FACILITIES:
		sect.set(facility + "_level", 0)
	return sect


## 개인 재산 주머니 (금화·식량만 쓴다)
static func create_purse() -> SectData:
	var purse_data: SectData = create_unaffiliated_sect()
	purse_data.id = "purse"
	purse_data.sect_name = "개인 재산"
	return purse_data


## 지금 역할이 개인 재산을 쓰는지 (RoleDashboard 구성에서 문파 일에 몸담지 않는 역할)
func uses_purse() -> bool:
	return not RoleDashboard.get_layout(player_character.role)["sect"]


## 금화·식량을 내고 받는 곳: 개인 재산을 쓰는 역할이면 주머니, 아니면 문파 금고
func get_wallet() -> SectData:
	return purse if uses_purse() else player_sect


func _all_sect_ids() -> Array:
	var ids: Array = [] if not has_sect() else [player_sect.id]
	for sect in world_sects:
		ids.append(sect.id)
	return ids


## 기연 판정에 쓰는 진행 상황을 EventManager에 넘긴다. (딕셔너리·배열은 같은 객체를 공유)
func _sync_event_context() -> void:
	EventManager.world_sects = world_sects
	EventManager.wallet = get_wallet() if player_character else null
	EventManager.owned_manuals = owned_manuals
	EventManager.player_name = player_character.display_name if player_character else ""
	EventManager.player_npc_id = player_npc_id
	FeatureGate.sync(progressive_features, unlocked_features)
	CombatManager.region_id = player_region
	CombatManager.season = get_current_season()
	EventManager.current_year = current_year
	EventManager.current_turn = _get_turn_index()
	EventManager.current_generation = generation
	EventManager.role_history = role_history
	EventManager.flag_turns = flag_turns
	EventManager.role_state = role_state
	EventManager.map_state = map_state
	EventManager.player_sect_id = player_sect.id if player_sect else ""


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
	# 우리 문파 직책 인물(문주·교두·의원)이 계절의 일을 한다. 플레이어가 문주가 아니면 문주가 살림을 맡는다.
	last_npc_report.assign(NpcAgent.run_season(self))
	if not last_npc_report.is_empty():
		add_chronicle("인물", "%s의 인물들이 움직였습니다." % player_sect.sect_name, _report_lines(last_npc_report, true))
	var income: String = _process_seasonal_income()
	var living: String = _pay_living_costs()
	var upkeep: Dictionary = SectManager.pay_upkeep(player_sect)
	var facility_report: String = _apply_facility_effects()
	var role_report: String = RoleActions.on_season(self)
	var disciple_report: String = DiscipleRoster.on_season(player_sect)
	var tribute_report: String = DiplomacyManager.on_season(player_sect, world_sects)
	var consequence: String = _apply_role_consequences()
	var world_report: String = _run_sect_ai()
	var report_parts: PackedStringArray = [income] if has_sect() else []
	if has_sect():
		report_parts.append(upkeep["message"])
	for part in [living, ignored_invasion, facility_report, disciple_report, tribute_report, role_report, consequence, yearly_report, world_report]:
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


## 동향 보고를 연대기 줄로
func _report_lines(reports: Array, npc: bool) -> PackedStringArray:
	var lines: PackedStringArray = []
	for report in reports:
		if npc:
			lines.append("%s(%s) %s: %s" % [report["name"], report["post"], report["action"], report["detail"]])
		else:
			lines.append("%s [%s 전략] %s: %s" % [report["sect_name"], report["strategy"], report["action"], report["detail"]])
	return lines


## 세력 AI의 한 계절. 강호 소식을 쌓고, 침공이 있으면 대응을 기다린다. 계절 보고 문구를 돌려준다.
func _run_sect_ai() -> String:
	if not SectAI.active:
		return ""
	# 침공 빈도는 기연 빈도를 따른다 (기연 빈도 0인 시험·시뮬레이션에서는 침공이 없다).
	# 무소속(낭인)은 쳐들어올 산문이 없다.
	var result: Dictionary = SectAI.run_season(
		world_sects, _get_turn_index(), current_year, ScenarioRules.event_rate() if has_sect() else 0.0, map_state
	)
	last_faction_report.assign(result["reports"])
	if not last_faction_report.is_empty():
		add_chronicle("세력", "강호 세력이 움직였습니다.", _report_lines(last_faction_report, false))
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
			message += _lose_region_to(invader)
	pending_invasion = ""
	add_world_news(message)
	EventBus.resources_changed.emit(player_sect)
	_check_end_states()
	return {"success": true, "message": message}


## 개인 재산의 생활비: 식량을 먹고(모자라면 금화로 사 먹는다) 금화를 쓴다. 둘 다 바닥나면 굶주려 내공이 준다.
func _pay_living_costs() -> String:
	if not uses_purse():
		return ""
	var parts: PackedStringArray = []
	var food_need: int = _Balance.LIVING_FOOD
	var eaten: int = mini(purse.food, food_need)
	purse.food -= eaten
	food_need -= eaten
	var gold_need: int = _Balance.LIVING_GOLD + food_need * _Balance.LIVING_FOOD_PRICE
	var paid: int = mini(purse.gold, gold_need)
	purse.gold -= paid
	parts.append("생활비: 식량 -%d, 금화 -%d%s" % [eaten, paid, " (모자란 식량을 사 먹음)" if food_need > 0 else ""])
	if paid < gold_need:
		var loss: int = mini(player_character.internal_energy_current, _Balance.STARVE_INTERNAL_LOSS)
		player_character.internal_energy_current -= loss
		parts.append("노자가 떨어져 굶주렸습니다. 내공 -%d (의뢰로 돈을 버세요)" % loss)
	EventBus.resources_changed.emit(player_sect)
	return ", ".join(parts)


func _process_seasonal_income() -> String:
	# 무소속은 문파 수입이 없다. 홀로 수련하며 깨닫는 연구점만 남는다.
	if not has_sect():
		var research: int = roundi(int(player_character.wisdom * _Balance.WISDOM_RESEARCH_RATIO) * ScenarioRules.income_scale())
		player_sect.research_points += research
		return "홀로 수련: 연구점 +%d" % research
	var income: Dictionary = SectManager.compute_seasonal_income(player_sect, player_character, get_current_season())
	income["gold"] += RoleActions.get_income_gold_bonus(role_state, player_character.role, income["gold"])
	var lands: Dictionary = WorldMap.income(map_state, player_sect.id)
	income["gold"] += lands["gold"]
	income["food"] += lands["food"]
	player_sect.gold += income["gold"]
	player_sect.food += income["food"]
	player_sect.research_points += income["research"]
	return "수입: 금화 +%d, 식량 +%d, 연구점 +%d" % [income["gold"], income["food"], income["research"]]


## 다음 계절 예상 수지 (경영 화면 표시용). 계절 보정은 다음 계절 기준.
## 개인 재산을 쓰는 역할이면 내 주머니의 생활비 (문파 금고 수지는 estimate_sect_season)
func estimate_next_season() -> Dictionary:
	if uses_purse():
		var food_short: int = maxi(0, _Balance.LIVING_FOOD - purse.food)
		return {
			"gold": -(_Balance.LIVING_GOLD + food_short * _Balance.LIVING_FOOD_PRICE),
			"food": -(_Balance.LIVING_FOOD - food_short),
		}
	return estimate_sect_season()


## 문파 금고의 다음 계절 예상 수지
func estimate_sect_season() -> Dictionary:
	if not has_sect():
		return {"gold": 0, "food": 0}
	var next_season: String = SEASONS[(current_season_index + 1) % SEASONS.size()]
	var income: Dictionary = SectManager.compute_seasonal_income(player_sect, player_character, next_season)
	income["gold"] += RoleActions.get_income_gold_bonus(role_state, player_character.role, income["gold"])
	var lands: Dictionary = WorldMap.income(map_state, player_sect.id)
	income["gold"] += lands["gold"]
	income["food"] += lands["food"]
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


## announce: 새 전환이 있으면 알린다 (역할 전환 창을 열 때는 조용히 다시 계산만)
func refresh_role_transitions(announce: bool = true) -> void:
	# 역할 전환이 아직 열리지 않았으면 (기능 단계 개방) 알리지 않는다
	if not FeatureGate.is_open("role_change"):
		pending_role_transitions = []
		return
	pending_role_transitions = RoleManager.get_available_transitions(
		player_character,
		player_sect,
		player_relationships,
		story_flags,
		role_state,
		world_sects
	)
	if announce and not pending_role_transitions.is_empty():
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
	add_chronicle("엔딩", "엔딩 「%s」에 이르렀습니다." % EndingManager.get_ending(ending).get("title", ending))
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
	# 기능 소개 장면은 읽고 닫으면 끝이다. 다음 소개가 있으면 이어서 띄운다.
	if pending_event.get("intro", false):
		pending_event.clear()
		_show_next_intro()
		return

	# 보이는 선택지 순번 → 원래 선택지 번호 (선택지 조건으로 일부만 보일 때)
	var choice_map: Array = pending_event.get("choice_map", [])
	var original_index: int = int(choice_map[choice_index]) if choice_index >= 0 and choice_index < choice_map.size() else choice_index
	var result: Dictionary = EventManager.resolve_choice(
		pending_event["id"],
		original_index,
		player_character,
		player_sect,
		player_relationships,
		story_flags,
		str(pending_event.get("subject", ""))
	)
	_chronicle_event(pending_event, choice_index, result)
	pending_event.clear()
	_apply_event_result(result)


## 기연 기록: 제목, 상황, 고른 선택지, 결과
func _chronicle_event(event: Dictionary, choice_index: int, result: Dictionary) -> void:
	var lines: PackedStringArray = []
	var description: String = str(event.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	var choices: Array = Array(event.get("choices", []))
	if choice_index >= 0 and choice_index < choices.size():
		lines.append("▶ 선택: %s" % choices[choice_index])
	if not str(result.get("message", "")).is_empty():
		lines.append("결과: %s" % result["message"])
	add_chronicle("기연", "「%s」" % event.get("title", "기연"), lines)


## 역할을 전환한다. option은 RoleManager가 준 선택지로, sect_id가 있으면 그 세력으로 옮겨 간다(이적·배신).
func apply_role_transition(role: CharacterData.Role, option: Dictionary = {}) -> Dictionary:
	var prefix: String = ""
	if option.get("kind", "") == "leave":
		prefix = _leave_player_sect("blessed" if option.get("blessed", false) else "desert")
	elif option.has("sect_id"):
		prefix = _switch_player_sect(option["sect_id"], option.get("kind", "defect"))
	var result: Dictionary = _change_role(role)
	if not prefix.is_empty():
		result["message"] = prefix + " " + result["message"]
	EventBus.action_message.emit(result["message"])
	refresh_role_transitions()
	_check_end_states()
	return result


func _change_role(role: CharacterData.Role) -> Dictionary:
	var had_purse: bool = uses_purse()
	var result: Dictionary = RoleManager.apply_transition(player_character, player_sect, role)
	RoleActions.on_role_changed(role_state, player_character.role)
	var transfer: String = _transfer_purse(had_purse)
	if not transfer.is_empty():
		result["message"] = str(result.get("message", "")) + " " + transfer
	_sync_event_context()
	add_chronicle("역할", str(result.get("message", "")))
	_record_role(player_character.role)
	# 새 역할의 기능이 열린다 (기능 단계 개방)
	for feature_id in FeatureGate.ROLE_FEATURES.get(CharacterData.Role.keys()[player_character.role], []):
		unlock_feature(feature_id)
	EventBus.character_updated.emit(player_character)
	EventBus.resources_changed.emit(player_sect)
	EventBus.role_changed.emit(player_character.role)
	return result


## 기능을 연다. 단계 개방 중이 아니거나 이미 열렸으면 false. 연 기능은 소개 장면을 기다린다.
func unlock_feature(feature_id: String) -> bool:
	if not progressive_features or unlocked_features.has(feature_id) or not FeatureGate.has_feature(feature_id):
		return false
	unlocked_features.append(feature_id)
	pending_intros.append(feature_id)
	add_chronicle("새 길", "「%s」이(가) 열렸습니다." % FeatureGate.get_title(feature_id))
	return true


## 기연 결과 중 이야기 진행에 관한 것: 기능 개방·역할 변화·강호 일지, 그리고 이어지는 장면(next)이나 기능 소개를 띄운다.
func _apply_story_result(result: Dictionary) -> void:
	for feature_id in result.get("unlock", []):
		unlock_feature(feature_id)
	if result.has("set_role"):
		var role: CharacterData.Role = CharacterData.Role.get(result["set_role"])
		if player_character.role != role:
			_change_role(role)
	if result.has("goal"):
		journal_goal = str(result["goal"])
	for rumor in result.get("rumors", []):
		add_rumor(str(rumor))
	if not str(result.get("next", "")).is_empty():
		var next_event: EventData = EventManager.get_event(result["next"])
		if next_event:
			pending_event = EventManager.make_popup(
				next_event, player_character, player_sect, player_relationships, get_current_season(), story_flags,
				str(result.get("subject", ""))
			)
			EventBus.event_triggered.emit(pending_event)
			return
	_show_next_intro()


## 기다리는 기능 소개가 있으면 띄운다 (다른 기연이 떠 있지 않을 때)
func _show_next_intro() -> void:
	if not pending_event.is_empty() or pending_intros.is_empty() or is_game_over():
		return
	pending_event = FeatureGate.intro_popup(pending_intros.duplicate())
	pending_intros.clear()
	EventBus.event_triggered.emit(pending_event)


## 강호 연표 (EventManager.get_timeline). 항목에 남은 계절(seasons_left)과 예상 날짜(date)를 붙인다.
func get_timeline() -> Array[Dictionary]:
	var now: int = _get_turn_index()
	var entries: Array[Dictionary] = EventManager.get_timeline(
		player_character, player_sect, player_relationships, get_current_season(), story_flags, triggered_event_ids, now
	)
	for entry in entries:
		var turn: int = entry["turn"]
		entry["seasons_left"] = turn - now if turn >= 0 else -1
		entry["date"] = "%s %d년 %s" % [ScenarioManager.get_era_name(), turn / SEASONS.size(), SEASONS[turn % SEASONS.size()]] if turn >= 0 else ""
	return entries


## 저장된 버릇 기록: JSON을 거치며 유형 키가 문자열이 되므로 숫자로 되돌린다
static func _load_duel_memory(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for npc_id in data:
		var record: Dictionary = data[npc_id]
		var first: Dictionary = {}
		for type in record.get("first", {}):
			first[int(type)] = int(record["first"][type])
		result[str(npc_id)] = {"bouts": int(record.get("bouts", 0)), "first": first}
	return result


## 다음 큰 사건 (없으면 {})
func get_next_timeline_event() -> Dictionary:
	for entry in get_timeline():
		if not entry["done"]:
			return entry
	return {}


func add_rumor(text: String) -> void:
	if text.is_empty():
		return
	journal_rumors.append(text)
	if journal_rumors.size() > JOURNAL_RUMOR_LIMIT:
		journal_rumors = journal_rumors.slice(journal_rumors.size() - JOURNAL_RUMOR_LIMIT)
	add_chronicle("소문", text)


## 개인 재산을 쓰는 역할과 문파 금고를 쓰는 역할 사이를 오갈 때 재산을 옮긴다.
## 문파 일을 맡게 되면 모은 재산을 문파에 보태고, 문파를 떠나 떠돌게 되면 노자를 챙긴다.
func _transfer_purse(had_purse: bool) -> String:
	var has_purse: bool = uses_purse()
	if had_purse == has_purse:
		return ""
	if had_purse:
		if not has_sect():
			return ""
		var gold: int = purse.gold
		var food: int = purse.food
		player_sect.gold += gold
		player_sect.food += food
		purse.gold = 0
		purse.food = 0
		return "모아 둔 재산(금화 %d, 식량 %d)을 %s에 보탰습니다." % [gold, food, player_sect.sect_name] if gold + food > 0 else ""
	# 무소속이 되며 떠난 경우 노자는 _leave_player_sect가 이미 챙겼다.
	if not has_sect():
		return ""
	var take_gold: int = mini(player_sect.gold, _Balance.PURSE_ALLOWANCE_GOLD)
	var take_food: int = mini(player_sect.food, _Balance.PURSE_ALLOWANCE_FOOD)
	player_sect.gold -= take_gold
	player_sect.food -= take_food
	purse.gold += take_gold
	purse.food += take_food
	return "노자로 금화 %d, 식량 %d를 챙겼습니다. 이제 금화·식량은 내 몫입니다." % [take_gold, take_food]


## 역할 자원이 한계에 이르렀을 때 축출·강등을 적용하고 알림 문구를 돌려준다.
func _apply_role_consequences() -> String:
	var consequence: Dictionary = RoleActions.check_consequences(self)
	if consequence.is_empty():
		return ""
	EventManager.set_flag(story_flags, consequence["flag"])
	var left: String = ""
	if player_character.role == CharacterData.Role.LEADER:
		# 쫓겨난 문주 대신 원래 문주(또는 원로회)가 문파를 맡고, 쫓겨난 문주는 산문을 나선다.
		player_sect.leader_name = (
			NpcRoster.get_display_name(player_sect.leader_id) if not player_sect.leader_id.is_empty() else "원로회"
		)
		if consequence["role"] == CharacterData.Role.WANDERER:
			left = " " + _leave_player_sect("ousted")
	_change_role(consequence["role"])
	return consequence["message"] + left


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
	if old_sect.id == NO_SECT:
		# 무소속이던 낭인은 지니던 재물을 들고 들어간다.
		new_sect.gold += old_sect.gold
		new_sect.food += old_sect.food
	else:
		world_sects.append(old_sect)
	DiscipleRoster.enable(new_sect)
	new_sect.attitude = 0
	new_sect.subjugated = false
	new_sect.observed_commands.clear()
	player_sect = new_sect
	pending_war_plan = {}
	pending_region_target = ""
	EventManager.player_sect_id = player_sect.id
	role_state["spy_target"] = ""
	# 새 문파의 본거지로 옮겨 간다
	player_region = _default_region()
	_sync_location()
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
	if kind == "join":
		EventManager.set_flag(story_flags, "joined_sect")
		# 문주가 사부가 된다 (이미 인연이 있으면 그대로)
		var master_note: String = ""
		if NpcRoster.has_npc(new_sect.leader_id) and new_sect.leader_id != player_npc_id and RelationshipManager.get_bond_with(player_relationships, new_sect.leader_id) == null:
			player_relationships.append(RelationshipManager.make_relationship(new_sect.leader_id, "MASTER_DISCIPLE", _Balance.JOIN_MASTER_BOND))
			master_note = " %s이(가) 사부가 되었습니다." % NpcRoster.get_display_name(new_sect.leader_id)
		EventBus.relationships_changed.emit(player_relationships)
		return "%s에 입문했습니다.%s" % [new_sect.sect_name, master_note]
	EventManager.set_flag(story_flags, "defected")
	return "%s에 객경으로 들어갔습니다." % new_sect.sect_name


## 문파를 떠나 무소속이 된다. mode: "blessed"(허락받은 하산·문주 사임) · "desert"(탈문) · "ousted"(축출)
## 떠나온 문파는 강호 세력이 된다. 알림 문구를 돌려준다.
func _leave_player_sect(mode: String) -> String:
	if not has_sect():
		return ""
	var old_sect: SectData = player_sect
	var parts: PackedStringArray = []
	if old_sect.leader_name == player_character.display_name:
		old_sect.leader_name = (
			NpcRoster.get_display_name(old_sect.leader_id) if not old_sect.leader_id.is_empty() else "원로회"
		)
	old_sect.attitude = {
		"blessed": _Balance.LEAVE_BLESSED_ATTITUDE, "desert": _Balance.LEAVE_DESERT_ATTITUDE, "ousted": _Balance.LEAVE_OUSTED_ATTITUDE,
	}[mode]
	old_sect.allied = false
	old_sect.tribute = false
	old_sect.subjugated = false
	old_sect.observed_commands.clear()
	old_sect.use_roster = false
	old_sect.disciples.clear()
	world_sects.append(old_sect)
	if mode == "blessed":
		# 노자를 챙긴다 (개인 재산)
		var take_gold: int = mini(old_sect.gold, _Balance.PURSE_ALLOWANCE_GOLD)
		var take_food: int = mini(old_sect.food, _Balance.PURSE_ALLOWANCE_FOOD)
		old_sect.gold -= take_gold
		old_sect.food -= take_food
		purse.gold += take_gold
		purse.food += take_food
		parts.append("%s을(를) 떠났습니다. 노자로 금화 %d, 식량 %d를 챙겼습니다." % [old_sect.sect_name, take_gold, take_food])
	elif mode == "desert":
		for rel in player_relationships:
			if rel.bond_type in [RelationshipData.BondType.MASTER_DISCIPLE, RelationshipData.BondType.FELLOW] \
					and NpcRoster.get_npc(rel.target_id).get("sect_id", "") == old_sect.id:
				rel.decrease_bond(_Balance.LEAVE_DESERT_BOND)
		parts.append("허락 없이 %s을(를) 떠났습니다(탈문). %s 태도 %d, 사부·동문 유대 -%d" % [
			old_sect.sect_name, old_sect.sect_name, old_sect.attitude, _Balance.LEAVE_DESERT_BOND,
		])
	else:
		parts.append("%s에서 쫓겨났습니다. %s 태도 %d" % [old_sect.sect_name, old_sect.sect_name, old_sect.attitude])
	player_sect = create_unaffiliated_sect()
	pending_war_plan = {}
	pending_region_target = ""
	pending_invasion = ""
	challenge_target = ""
	EventManager.player_sect_id = player_sect.id
	role_state["spy_target"] = ""
	EventManager.set_flag(story_flags, "left_%s" % old_sect.id)
	EventManager.set_flag(story_flags, "left_sect")
	# 떠나온 문파의 땅에 머문다 (이제 남의 땅)
	_sync_location()
	_sync_event_context()
	EventBus.relationships_changed.emit(player_relationships)
	return " ".join(parts) + " 이제 무소속입니다."


## 외교 행동 (강호 정세 화면)
func do_diplomacy(sect_id: String, action_id: String) -> Dictionary:
	var result: Dictionary = DiplomacyManager.perform(self, sect_id, action_id)
	if result["success"]:
		result["dialogue"] = DialogueLines.for_diplomacy(get_world_sect(sect_id), action_id, true)
		add_chronicle("외교", result["message"], result["dialogue"])
	EventBus.resources_changed.emit(player_sect)
	_check_end_states()
	return result


## 인연 상호작용 (대화·선물·비무). 비무면 전투를 시작한다.
func interact_with(target_id: String, kind: String) -> Dictionary:
	var result: Dictionary = RelationshipManager.interact(
		player_relationships, target_id, kind, player_character, get_wallet(), story_flags, _get_turn_index()
	)
	if result.get("married", "") != "":
		player_sect.reputation += _Balance.WEDDING_REPUTATION
	var rel: RelationshipData = RelationshipManager.get_bond_with(player_relationships, target_id)
	if rel and result["success"]:
		result["dialogue"] = DialogueLines.for_interaction(rel, kind, player_character.display_name, true)
		add_chronicle("대화", result["message"], result["dialogue"])
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
	var acted: bool = result["success"] or result.get("consumed", false)
	if acted:
		result["dialogue"] = DialogueLines.for_role_action(
			action_id, player_character.display_name, result["success"], _role_counterpart(action_id)
		)
		add_chronicle("행동", "%s: %s" % [RoleActions.ACTIONS[action_id]["title"], result["message"]], result["dialogue"])
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


## 역할 행동의 상대 이름 (사부·문주는 실제 인물 이름으로)
func _role_counterpart(action_id: String) -> String:
	match action_id:
		"teaching":
			for rel in player_relationships:
				if rel.bond_type == RelationshipData.BondType.MASTER_DISCIPLE:
					return rel.target_name
		"proposal":
			return player_sect.leader_name
	return ""


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

	# 후계자는 등장인물이 아니다.
	player_npc_id = ""
	EventManager.player_npc_id = ""
	_set_player_character(LegacyManager.create_successor(legacy, player_sect))
	# 문파 비전은 후계자에게 이어진다.
	if player_sect.secret_art:
		player_character.learn_martial_art(player_sect.secret_art.duplicate(true))
	LegacyManager.apply_legacy_bonuses(player_sect, legacy)
	player_relationships = RelationshipManager.create_default_relationships(player_sect.id)
	player_region = _default_region()
	triggered_event_ids.clear()
	current_ending_id = ""
	story_flags.clear()
	flag_turns.clear()
	role_history.clear()
	_record_role(player_character.role)
	role_state = RoleActions.create_state()
	_sync_event_context()

	add_chronicle("세대", "%s이(가) 물러나고 %s이(가) 제%d세대를 잇습니다." % [
		legacy.predecessor_name, player_character.display_name, generation,
	])
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


# ── 강호 지도 ──

## 지도에서 [공략]으로 고른 땅. 그 땅의 주인과 문파전에서 이기면 이 땅을 먼저 차지한다.
var pending_region_target: String = ""


## 땅을 넓힐 수 있는 역할 (문주)
func can_command_conquest() -> bool:
	return player_character.role == CharacterData.Role.LEADER


func get_player_regions() -> Array[String]:
	return WorldMap.regions_of(map_state, player_sect.id)


## 지도 화면에서 고른 땅에 할 수 있는 일: {kind: "pacify"|"attack"|"none", reason, cost?, owner?}
func get_region_action(region_id: String) -> Dictionary:
	if not WorldMap.has_region(region_id):
		return {"kind": "none", "reason": "없는 땅입니다."}
	var owner: String = WorldMap.get_owner(map_state, region_id)
	if owner == player_sect.id:
		return {"kind": "none", "reason": "우리 문파의 본거지입니다." if WorldMap.get_home(map_state, owner) == region_id else "우리 문파의 땅입니다."}
	if not can_command_conquest():
		return {"kind": "none", "reason": "땅을 넓히는 일은 문주만 명할 수 있습니다."}
	if not WorldMap.borders(map_state, region_id, player_sect.id):
		return {"kind": "none", "reason": "우리 땅과 맞닿은 곳만 노릴 수 있습니다."}
	if owner.is_empty():
		var cost: Dictionary = WorldMap.pacify_cost(region_id)
		var defense: int = int(WorldMap.get_region(region_id)["defense"])
		var power: int = SectWarManager.get_military_power(player_sect, player_character)
		var reason: String = ""
		if not can_do_seasonal("last_pacify_turn"):
			reason = "이번 계절에는 이미 땅을 평정했습니다."
		elif power < defense:
			reason = "전력이 모자랍니다. (우리 %d / 주둔 %d)" % [power, defense]
		elif player_sect.gold < cost["gold"] or player_sect.food < cost["food"]:
			reason = "자원이 모자랍니다. (금화 %d, 식량 %d 필요)" % [cost["gold"], cost["food"]]
		return {"kind": "pacify", "reason": reason, "cost": cost, "power": power, "defense": defense}
	var sect: SectData = get_world_sect(owner)
	var reason: String = ""
	if sect == null:
		reason = "알 수 없는 세력의 땅입니다."
	elif not WorldMap.can_be_taken(map_state, region_id):
		reason = "%s의 본거지는 빼앗을 수 없습니다. 문파전으로 굴복시키세요." % sect.sect_name
	elif sect.allied:
		reason = "동맹 세력의 땅입니다. 먼저 동맹을 깨야 합니다."
	elif sect.subjugated:
		reason = "굴복한 세력입니다."
	elif not can_wage_war():
		reason = "이번 계절에는 이미 문파전을 치렀습니다."
	return {"kind": "attack", "reason": reason, "owner": owner}


## 주인 없는 땅 평정: 금화·식량을 들여 차지한다. 계절에 한 번, 전력이 주둔 병력 이상이어야 한다.
func pacify_region(region_id: String) -> Dictionary:
	var action: Dictionary = get_region_action(region_id)
	if action["kind"] != "pacify":
		return {"success": false, "message": action.get("reason", "평정할 수 없는 땅입니다.")}
	if not action["reason"].is_empty():
		return {"success": false, "message": action["reason"]}
	player_sect.spend_resources(action["cost"]["gold"], action["cost"]["food"])
	_mark_seasonal("last_pacify_turn")
	WorldMap.transfer(map_state, region_id, player_sect.id, [player_sect])
	var region: Dictionary = WorldMap.get_region(region_id)
	var message: String = "%s을(를) 평정했습니다. 계절마다 금화 +%d, 식량 +%d, 제자 정원 +%d (금화 -%d, 식량 -%d)" % [
		region["name"], region["gold"], region["food"], _Balance.REGION_MAX_DISCIPLES, action["cost"]["gold"], action["cost"]["food"],
	]
	add_chronicle("영토", message)
	add_world_news("%s이(가) %s을(를) 차지했습니다." % [player_sect.sect_name, region["name"]])
	EventBus.resources_changed.emit(player_sect)
	_check_end_states()
	return {"success": true, "message": message}


## 지도에서 [공략]: 문파전 대상을 그 땅의 주인으로 정한다. 문파전 화면은 호출한 쪽이 연다.
func prepare_region_attack(region_id: String) -> Dictionary:
	var action: Dictionary = get_region_action(region_id)
	if action["kind"] != "attack" or not action["reason"].is_empty():
		return {"success": false, "message": action.get("reason", "공략할 수 없는 땅입니다.")}
	pending_region_target = region_id
	return {"success": true, "message": "%s 공략: %s와(과) 문파전을 벌입니다." % [
		WorldMap.get_region(region_id)["name"], get_world_sect(action["owner"]).sect_name,
	], "owner": action["owner"]}


## 문파전에서 이긴 상대의 땅 하나를 차지한다 (공략으로 고른 땅이 먼저). 차지한 지역 id 또는 ""
func _capture_region_from(enemy: SectData) -> String:
	var choices: Array[String] = []
	if not pending_region_target.is_empty() and WorldMap.get_owner(map_state, pending_region_target) == enemy.id:
		choices.append(pending_region_target)
	for region_id in WorldMap.regions_of(map_state, enemy.id):
		if WorldMap.borders(map_state, region_id, player_sect.id):
			choices.append(region_id)
	for region_id in choices:
		if WorldMap.can_be_taken(map_state, region_id):
			WorldMap.transfer(map_state, region_id, player_sect.id, [player_sect, enemy])
			add_world_news("%s이(가) %s의 땅 %s을(를) 차지했습니다." % [
				player_sect.sect_name, enemy.sect_name, WorldMap.get_region(region_id)["name"],
			])
			return region_id
	return ""


## 침공을 막지 못하면 침략 세력이 우리 땅 하나를 가져간다 (본거지는 빼고, 맞닿은 땅부터). 알림 문구
func _lose_region_to(invader: SectData) -> String:
	var candidates: Array[String] = []
	for region_id in get_player_regions():
		if WorldMap.can_be_taken(map_state, region_id):
			if WorldMap.borders(map_state, region_id, invader.id):
				candidates.push_front(region_id)
			else:
				candidates.append(region_id)
	if candidates.is_empty():
		return ""
	WorldMap.transfer(map_state, candidates[0], invader.id, [player_sect, invader])
	var name: String = WorldMap.get_region(candidates[0])["name"]
	add_chronicle("영토", "%s에게 %s 땅을 빼앗겼습니다." % [invader.sect_name, name])
	return " %s 땅을 빼앗겼습니다." % name


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
		"message": "정찰 성공 (금화 -%d): 적은 %d합에 [%s]을(를) 준비하고 있습니다." % [
			cost, round_index + 1, SectWarManager.COMMAND_NAMES[command],
		],
	}


## 문파전에 장수로 데려갈 수 있는 인물: 유대가 깊은 사부·혈맹·배우자·제자. 상대 세력 소속은 제외.
func get_war_generals(target_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rel in player_relationships:
		if not rel.bond_type in [
			RelationshipData.BondType.MASTER_DISCIPLE, RelationshipData.BondType.BLOOD_OATH,
			RelationshipData.BondType.SPOUSE, RelationshipData.BondType.PUPIL,
		]:
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
	if result.get("victory", false):
		var captured: String = _capture_region_from(enemy)
		if not captured.is_empty():
			result["message"] += "\n%s 땅을 차지했습니다." % WorldMap.get_region(captured)["name"]
			result["region"] = captured
	pending_region_target = ""
	add_chronicle("문파전", "%s와(과)의 문파전 %s" % [enemy.sect_name, "승리" if result.get("victory", false) else "패배"],
		PackedStringArray(str(result.get("message", "")).split("\n", false)))
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
	last_combat_history = PackedStringArray()
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
	if not get_wallet().spend_resources(_Balance.ELIXIR_GOLD):
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


## 무공 연구소에서 연구할 수 있는 비급: 소속 문파 서고의 비급과 가진 비급. [{art: MartialArtData, source: "문파 서고"|"소장"}]
## 무소속(낭인)은 가진 비급뿐이다.
func get_research_manuals() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	var library: Array = SectRegistry.get_sect_info(player_sect.id).get("manuals", []) if has_sect() and SectRegistry.has_sect(player_sect.id) else []
	for entry in [[library, "%s 서고" % player_sect.sect_name], [owned_manuals, "소장"]]:
		for art_id in entry[0]:
			var art: MartialArtData = MartialArtLibrary.create_art(str(art_id))
			if art and not seen.has(art.id):
				seen[art.id] = true
				result.append({"art": art, "source": entry[1]})
	return result


## 비급을 얻는다. art_id가 "random"이면 아직 연구할 수 없고 익히지도 않은 비급 중 하나. 얻은 비급 이름(못 얻으면 "")
func gain_manual(art_id: String) -> String:
	var gained: String = EventManager.gain_manual(art_id, owned_manuals, player_character, _available_manual_ids())
	EventBus.character_updated.emit(player_character)
	return gained


func _available_manual_ids() -> Array:
	return get_research_manuals().map(func(entry: Dictionary) -> String: return entry["art"].id)


# ── 지역·이동 ──

## 시작·소속이 바뀔 때 있을 지역: 소속 문파의 본거지, 무소속이면 지도 한가운데
func _default_region() -> String:
	if has_sect():
		var home: String = WorldMap.get_home(map_state, player_sect.id)
		if not home.is_empty():
			return home
	if WorldMap.has_region(_Balance.START_REGION):
		return _Balance.START_REGION
	var regions: Array[Dictionary] = WorldMap.get_regions()
	return regions[0]["id"] if not regions.is_empty() else ""


## 지금 지역 이름
func get_region_name() -> String:
	return str(WorldMap.get_region(player_region).get("name", "정처 없는 길"))


## 지금 지역과 그 땅의 주인: "낙양 · 주인 없는 땅", "청운산 · 우리 본거지"
func get_location_text() -> String:
	if not WorldMap.has_region(player_region):
		return "정처 없는 길"
	var owner: String = WorldMap.get_owner(map_state, player_region)
	var note: String
	if owner.is_empty():
		note = "주인 없는 땅"
	elif owner == player_sect.id:
		note = "우리 본거지" if WorldMap.get_home(map_state, owner) == player_region else "우리 땅"
	else:
		var sect: SectData = get_world_sect(owner)
		note = "%s의 %s" % [sect.sect_name if sect else owner, "본거지" if WorldMap.get_home(map_state, owner) == player_region else "땅"]
	return "%s · %s" % [get_region_name(), note]


## 타지에 있으면 그 땅 주인 세력 id를 역할 자원 location에 둔다 (의뢰 보상·위험·신용이 그 세력 기준)
func _sync_location() -> void:
	var owner: String = WorldMap.get_owner(map_state, player_region)
	role_state["location"] = owner if not owner.is_empty() and owner != player_sect.id and get_world_sect(owner) != null else ""


## 지도에서 옮겨 갈 수 있는 역할인지 (문파 일을 하는 역할은 본거지에 머문다)
func can_travel() -> bool:
	return uses_purse()


func get_travel_cost(region_id: String) -> int:
	return maxi(1, WorldMap.distance(player_region, region_id)) * _Balance.TRAVEL_GOLD_PER_STEP


## 그 지역으로 옮길 수 없는 까닭 (옮길 수 있으면 "")
func get_travel_block(region_id: String) -> String:
	if not WorldMap.has_region(region_id):
		return "없는 지역입니다."
	if region_id == player_region:
		return "지금 머무는 곳입니다."
	if not can_travel():
		return "문파 일을 하는 동안에는 본거지를 떠날 수 없습니다. (낭인·의뢰인·간자·자객만 옮겨 다닙니다)"
	if not can_do_seasonal("last_travel_turn"):
		return "이번 계절에는 이미 길을 떠났습니다."
	if WorldMap.distance(player_region, region_id) < 0:
		return "그곳으로 가는 길이 없습니다."
	if get_wallet().gold < get_travel_cost(region_id):
		return "여비가 모자랍니다. (금화 %d 필요)" % get_travel_cost(region_id)
	return ""


## 지도에서 고른 지역으로 옮긴다. 계절에 한 번, 여비는 거리만큼.
func travel_to(region_id: String) -> Dictionary:
	var block: String = get_travel_block(region_id)
	if not block.is_empty():
		return {"success": false, "message": block}
	var cost: int = get_travel_cost(region_id)
	get_wallet().gold -= cost
	_mark_seasonal("last_travel_turn")
	player_region = region_id
	_sync_location()
	var message: String = "%s(으)로 옮겼습니다. (여비 금화 -%d) — %s" % [get_region_name(), cost, get_location_text()]
	if not str(role_state["location"]).is_empty():
		message += ". 타지라 의뢰 보상이 크고 위험도 큽니다."
	add_chronicle("행동", message)
	EventBus.resources_changed.emit(player_sect)
	EventBus.character_updated.emit(player_character)
	return {"success": true, "message": message}


## 경영 화면 비무 상대 순서: 라이벌 → 동문 → 벗·혈맹 → 사부 → 그 밖의 인연 (원한은 빼고)
const SPAR_PARTNER_ORDER: Array = [
	RelationshipData.BondType.RIVALRY, RelationshipData.BondType.FELLOW,
	RelationshipData.BondType.FRIEND, RelationshipData.BondType.BLOOD_OATH, RelationshipData.BondType.MASTER_DISCIPLE,
]


## 경영 화면 비무 상대: 인연이 있는 인물 중 순서가 앞서고 유대가 깊은 사람. 없으면 "" (낭인은 처음엔 상대가 없다)
func get_spar_partner() -> String:
	var best: RelationshipData = null
	var best_rank: int = 99
	for rel in player_relationships:
		if rel.bond_type == RelationshipData.BondType.HATRED or not NpcRoster.has_npc(rel.target_id):
			continue
		var rank: int = SPAR_PARTNER_ORDER.find(rel.bond_type)
		if rank < 0:
			rank = SPAR_PARTNER_ORDER.size()
		if best == null or rank < best_rank or (rank == best_rank and rel.bond_strength > best.bond_strength):
			best = rel
			best_rank = rank
	return best.target_id if best else ""


func can_spar() -> bool:
	return story_flags.get("last_spar_turn", -1) != _get_turn_index() and not get_spar_partner().is_empty()


## 경영 화면의 비무. 계절마다 한 번, 인연이 있는 인물과 겨룬다.
func start_sparring() -> Dictionary:
	var partner: String = get_spar_partner()
	if partner.is_empty():
		return {"success": false, "message": "겨룰 상대가 없습니다. 강호에서 인연을 맺으면 비무할 수 있습니다."}
	if not can_spar():
		return {"success": false, "message": "이번 계절에는 이미 비무를 했습니다."}
	EventManager.set_flag(story_flags, "last_spar_turn", _get_turn_index())
	var setup: CombatSetup = CombatManager.create_sparring(player_character) if partner == CombatManager.RIVAL_ID \
		else CombatManager.create_sparring_with(partner, player_character)
	start_combat(setup)
	return {"success": true, "message": "%s에게 비무를 청합니다." % NpcRoster.get_display_name(partner)}


## 전투 결과를 반영하고 결과(message, outcome 포함)를 돌려준다.
## summary: DuelEngine.summary() — 평가·도전·사건 선택 효과·받아 낸 상대 무공·비무대회 성적
func finish_combat(outcome: CombatManager.Outcome, fallen_allies: int = 0, fallen_ids: Array = [], summary: Dictionary = {}) -> Dictionary:
	if pending_combat == null:
		return {"success": false, "message": "진행 중인 전투가 없습니다."}
	_record_observed_arts(pending_combat)
	var extra: PackedStringArray = _apply_combat_summary(summary)
	# 침공 방어전: 막아 내면 침략 세력이 제자를 잃는다.
	if not pending_combat.invader_id.is_empty():
		var invader: SectData = get_world_sect(pending_combat.invader_id)
		if invader:
			if outcome == CombatManager.Outcome.VICTORY:
				invader.disciple_count = maxi(_Balance.AI_MIN_DISCIPLES, invader.disciple_count - _Balance.INVASION_REPEL_LOSS)
				add_world_news("%s의 침공을 막아 냈습니다. (%s 제자 -%d)" % [invader.sect_name, invader.sect_name, _Balance.INVASION_REPEL_LOSS])
			else:
				add_world_news("%s의 침공을 막지 못했습니다.%s" % [invader.sect_name, _lose_region_to(invader)])
	var result: Dictionary = CombatManager.apply_outcome(
		pending_combat,
		outcome,
		player_character,
		player_sect,
		player_relationships,
		story_flags,
		fallen_allies,
		fallen_ids,
		get_wallet()
	)
	if not extra.is_empty():
		result["message"] = "%s\n%s" % [result.get("message", ""), " · ".join(extra)]
	add_chronicle("전투", str(result.get("message", "")), last_combat_history.slice(maxi(0, last_combat_history.size() - 6)))
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


## 경영 행동 뒤의 대화 장면을 띄운다. 띄웠으면 true (그러면 결과 알림은 장면 안에 보인다).
## 설정에서 껐거나, 기연·장면이 이미 기다리거나, 행동이 전투·기연으로 이어지면 띄우지 않는다.
func show_action_scene(action_id: String, result: Dictionary, context: Dictionary = {}) -> bool:
	if not GameSettings.action_scenes or is_game_over() or not pending_event.is_empty() or not pending_action_scene.is_empty():
		return false
	if result.has("combat") or result.has("event") or pending_combat != null:
		return false
	var recent: Array = _recent_action_scenes.get(action_id, [])
	var scene: Dictionary = ActionScenes.build(self, action_id, result, context, recent)
	if scene.is_empty():
		return false
	recent.append(scene["scene_id"])
	_recent_action_scenes[action_id] = recent.slice(maxi(0, recent.size() - 3))
	pending_action_scene = scene
	EventBus.action_scene_triggered.emit(scene)
	return true


## 행동 대화 장면의 선택지를 고른다: 작은 여파(유대 등)를 반영하고 알림을 남긴다
func resolve_action_scene(index: int) -> void:
	if pending_action_scene.is_empty():
		return
	var options: Array = pending_action_scene["options"]
	var option: Dictionary = options[clampi(index, 0, options.size() - 1)]
	pending_action_scene = {}
	if not option["effects"].is_empty():
		EventManager.apply_effects(option["effects"], player_character, player_sect, player_relationships, story_flags)
	if not str(option["message"]).is_empty():
		EventBus.action_message.emit(option["message"])
	EventBus.resources_changed.emit(player_sect)
	EventBus.character_updated.emit(player_character)
	EventBus.relationships_changed.emit(player_relationships)


## 대결 요약을 반영하고 결과 문장 조각을 돌려준다: 평가, 도전 보상, 받아 낸 절초(연구점), 사건 선택 효과, 비무대회 성적 플래그
func _apply_combat_summary(summary: Dictionary) -> PackedStringArray:
	var parts: PackedStringArray = []
	if summary.is_empty():
		return parts
	parts.append("평가: %s" % summary.get("rating", ""))
	var challenge: String = str(summary.get("challenge", ""))
	if not challenge.is_empty():
		if summary.get("challenge_met", false):
			player_sect.reputation += _Balance.DUEL_CHALLENGE_REPUTATION
			player_sect.research_points += _Balance.DUEL_CHALLENGE_RESEARCH
			parts.append("도전 달성 「%s」 명성 +%d, 연구점 +%d" % [challenge, _Balance.DUEL_CHALLENGE_REPUTATION, _Balance.DUEL_CHALLENGE_RESEARCH])
		else:
			parts.append("도전 실패 「%s」" % challenge)
	var studied: Array = summary.get("studied_arts", [])
	if not studied.is_empty():
		player_sect.research_points += _Balance.STUDY_RESEARCH * studied.size()
		parts.append("상대 절초를 받아 내며 깨달음 (연구점 +%d)" % (_Balance.STUDY_RESEARCH * studied.size()))
	var effects: Array = summary.get("effects", [])
	if not effects.is_empty():
		EventManager.apply_effects(effects, player_character, player_sect, player_relationships, story_flags)
	var flag: String = str(summary.get("placement_flag", ""))
	if not flag.is_empty():
		EventManager.set_flag(story_flags, flag)
	return parts


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


## 앱이 백그라운드로 가거나(모바일 홈 버튼·전화), 창을 닫거나, 웹 탭을 떠날 때 자동 저장한다.
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		save_on_suspend()


## 진행 중인 게임이 있으면 자동 저장 슬롯에 저장한다. 저장했으면 true.
func save_on_suspend() -> bool:
	if not is_game_active:
		return false
	return autosave().get("success", false)


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
		"owned_manuals": owned_manuals,
		"player_region": player_region,
		"player_npc_id": player_npc_id,
		"progressive_features": progressive_features,
		"unlocked_features": unlocked_features.duplicate(),
		"pending_intros": pending_intros.duplicate(),
		"journal_goal": journal_goal,
		"duel_memory": duel_memory.duplicate(true),
		"art_mastery": art_mastery.duplicate(),
		"journal_rumors": journal_rumors.duplicate(),
		"purse": {"gold": purse.gold, "food": purse.food},
		"challenge_target": challenge_target,
		"pending_invasion": pending_invasion,
		"year_start": year_start,
		"world_news": world_news,
		"chronicle": chronicle,
		"art_draft": art_draft,
		"art_blueprints": art_blueprints,
		"map_state": map_state,
		"faction_report": last_faction_report,
		"npc_report": last_npc_report,
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
	pending_action_scene = {}
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
	art_draft = _clean_blueprint(data.get("art_draft", {})) if data.get("art_draft", {}) is Dictionary and not data.get("art_draft", {}).is_empty() else {}
	art_blueprints.clear()
	for blueprint in data.get("art_blueprints", []):
		if blueprint is Dictionary:
			art_blueprints.append(_clean_blueprint(blueprint))
	chronicle.clear()
	for entry in data.get("chronicle", []):
		if entry is Dictionary:
			chronicle.append({
				"date": str(entry.get("date", "")), "turn": int(entry.get("turn", 0)),
				"generation": int(entry.get("generation", 1)), "kind": str(entry.get("kind", "")),
				"text": str(entry.get("text", "")), "lines": Array(entry.get("lines", [])).map(func(line: Variant) -> String: return str(line)),
			})
	purse = create_purse()
	if data.has("purse"):
		purse.gold = int(data["purse"].get("gold", 0))
		purse.food = int(data["purse"].get("food", 0))
	elif uses_purse():
		# 개인 재산이 생기기 전 세이브: 무소속이면 그 재산을, 아니면 시작 노자를 준다.
		purse.gold = player_sect.gold if not has_sect() else _Balance.PURSE_START_GOLD
		purse.food = player_sect.food if not has_sect() else _Balance.PURSE_START_FOOD
	if not has_sect():
		player_sect.gold = 0
		player_sect.food = 0
	owned_manuals.clear()
	for art_id in data.get("owned_manuals", []):
		if MartialArtLibrary.has_art(str(art_id)):
			owned_manuals.append(str(art_id))
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
	# 지도가 없는 구버전 세이브는 지금 세력으로 새 지도를 만든다.
	if data.get("map_state", {}) is Dictionary and not data.get("map_state", {}).is_empty():
		map_state = WorldMap.restore_state(data["map_state"])
	else:
		map_state = WorldMap.create_state(_all_sect_ids())
	player_npc_id = str(data.get("player_npc_id", ""))
	progressive_features = data.get("progressive_features", false) == true
	unlocked_features.assign(Array(data.get("unlocked_features", [])).map(func(x: Variant) -> String: return str(x)))
	pending_intros.assign(Array(data.get("pending_intros", [])).map(func(x: Variant) -> String: return str(x)))
	journal_goal = str(data.get("journal_goal", ""))
	duel_memory = _load_duel_memory(data.get("duel_memory", {}))
	art_mastery = data.get("art_mastery", {}).duplicate()
	journal_rumors.assign(Array(data.get("journal_rumors", [])).map(func(x: Variant) -> String: return str(x)))
	player_region = str(data.get("player_region", ""))
	if not WorldMap.has_region(player_region):
		player_region = _default_region()
	last_faction_report.clear()
	for entry in data.get("faction_report", []):
		if entry is Dictionary:
			last_faction_report.append(entry)
	last_npc_report.clear()
	for entry in data.get("npc_report", []):
		if entry is Dictionary:
			last_npc_report.append(entry)
	pending_region_target = ""
	_sync_event_context()
	refresh_role_transitions()


func has_save_file(slot: int = -1) -> bool:
	return _SaveManager.has_save(slot)


func _apply_event_result(result: Dictionary) -> void:
	if result.has("end_game"):
		_force_end(result["end_game"])
	_apply_story_result(result)
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