extends SceneTree

## 밸런스 시뮬레이터: 전투 자동 플레이, 세력 AI, 장기 경제를 한 번에 돌려 수치를 출력한다.
## 실행: godot --headless --path . -s res://scripts/Tools/balance_sim.gd [-- combat|world|economy]
## 영역을 주지 않으면 모두 돌린다. 수치를 바꾸면 결과를 구현 계획(M9-5)에 함께 기록한다.

const _EconomySim = preload("res://scripts/Tools/economy_sim.gd")
## 전투 씬은 오토로드가 준비된 뒤에 불러야 하므로 preload하지 않는다.
const COMBAT_SCENE_PATH := "res://scenes/Combat/combat_scene.tscn"

## 전투 자동 플레이: 시험할 전투와 주인공 레벨, 판 수
const COMBATS: Array[String] = [
	"sparring", "rival_duel", "night_bandits", "bandit_hunt", "assassination", "bounty_hunters", "invasion",
]
const LEVELS: Array[int] = [1, 3, 6]
const COMBAT_RUNS := 30
## 한 판에서 넘기지 않을 라운드 수 (넘으면 무승부로 센다)
const MAX_ROUNDS := 40
const WORLD_RUNS := 100


func _initialize() -> void:
	# 시뮬레이션의 저장·설정이 실제 파일을 건드리지 않게 한다.
	SaveManager.save_dir = "user://_sim_saves/"
	GameSettings.settings_path = "user://_sim_saves/settings.cfg"
	GameSettings.combat_delay = 0.0
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var all: bool = args.is_empty()
	if all or args.has("combat"):
		await _run_combat()
	if all or args.has("world"):
		_run_world()
	if all or args.has("economy"):
		_run_economy()
	quit()


# ── 전투 ──

func _run_combat() -> void:
	var gm: Node = root.get_node("GameManager")
	print("[전투 자동 플레이] 양쪽 모두 같은 AI(가까운 상대에게 다가가 공격·무공). %d판씩" % COMBAT_RUNS)
	print("전투 / 주인공 레벨: 승률 · 이긴 판의 남은 체력 평균 · 평균 라운드")
	for combat_id in COMBATS:
		var line: String = "%-16s" % combat_id
		for level in LEVELS:
			var wins: int = 0
			var hp_sum: float = 0.0
			var rounds_sum: int = 0
			seed(combat_id.hash() + level)
			for run in COMBAT_RUNS:
				var result: Dictionary = await _play_combat(gm, combat_id, level)
				rounds_sum += result["rounds"]
				if result["victory"]:
					wins += 1
					hp_sum += result["hp_ratio"]
			line += " | Lv.%d 승 %3d%% 체력 %3d%% %4.1f라운드" % [
				level, roundi(100.0 * wins / COMBAT_RUNS), roundi(100.0 * hp_sum / maxi(1, wins)),
				float(rounds_sum) / COMBAT_RUNS,
			]
		print(line)


## 전투 한 판을 자동으로 치른다. {victory, hp_ratio, rounds}
func _play_combat(gm: Node, combat_id: String, level: int) -> Dictionary:
	gm.start_new_game("시뮬", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	gm.player_character.gain_experience(CharacterData.get_experience_for_level(level))
	gm.player_character.restore_internal_energy()
	# 레벨에 맞는 무공 하나를 익힌다 (Lv.3부터)
	if level >= 3:
		gm.player_character.learn_martial_art(MartialArtLibrary.create_art("preset_soul_chase_sword"))
	var setup: CombatSetup
	if combat_id == "invasion":
		setup = CombatManager.create_invasion(gm.get_world_sect("heukpung"), gm.player_character, gm.player_sect)
	else:
		setup = CombatManager.create_by_id(combat_id, gm.player_character, gm.player_sect)
	gm.pending_combat = setup
	var controller: Node = (load(COMBAT_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(controller)
	var player: CombatUnit = controller._get_player()
	var guard: int = 0
	while not controller._combat_over and controller._turn_manager.round_number <= MAX_ROUNDS and guard < 2000:
		guard += 1
		var current: CombatUnit = controller._get_controlled()
		if current:
			controller._run_enemy_ai(current)
			if controller._combat_over:
				break
			controller._on_end_turn_pressed()
		else:
			break
	var victory: bool = controller._combat_over and player.is_alive() and controller._get_alive_enemies().is_empty()
	var result: Dictionary = {
		"victory": victory,
		"hp_ratio": float(player.hp) / player.max_hp,
		"rounds": controller._turn_manager.round_number,
	}
	root.remove_child(controller)
	controller.free()
	gm.pending_combat = null
	await process_frame
	return result


# ── 세력 AI ──

func _run_world() -> void:
	print("[세력 AI] 시나리오마다 %d판 × 5년. 5년 뒤 세력별 제자 평균(최소~최대), 한 세력이 나머지를 모두 무너뜨린 판 수" % WORLD_RUNS)
	for scenario_id in ["cheonha", "heukpung_winter", "gangho_100"]:
		ScenarioManager.activate(scenario_id)
		seed(scenario_id.hash())
		var stats: Dictionary = {}
		var dominated: int = 0
		for run in WORLD_RUNS:
			var world: Array[SectData] = ScenarioManager.create_rival_sects()
			for season in 20:
				SectAI.run_season(world, 4 + season, 1 + (season + 1) / 4, 0.0)
				if (season + 1) % 4 == 0:
					SectWarManager.grow_world_sects(world)
			var fallen: int = 0
			for sect in world:
				var entry: Array = stats.get(sect.sect_name, [0, 999, 0])
				stats[sect.sect_name] = [entry[0] + sect.disciple_count, mini(entry[1], sect.disciple_count), maxi(entry[2], sect.disciple_count)]
				if sect.disciple_count <= SectWarManager._Balance.SUBJUGATE_DISCIPLE_THRESHOLD:
					fallen += 1
			if world.size() > 1 and fallen >= world.size() - 1:
				dominated += 1
		var parts: PackedStringArray = []
		for name in stats:
			parts.append("%s %.1f (%d~%d)" % [name, stats[name][0] / float(WORLD_RUNS), stats[name][1], stats[name][2]])
		print("%-16s %s | 휩쓴 판 %d" % [scenario_id, ", ".join(parts), dominated])
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)


# ── 경제 ──

func _run_economy() -> void:
	var gm: Node = root.get_node("GameManager")
	print("[경제] 전략별 10년 뒤 금화 / 식량 / 제자 / 명성 (시작: 금화 500, 식량 300)")
	for strategy in _EconomySim.STRATEGIES:
		for role in ["young_disciple", "leader"]:
			seed(1)
			gm.start_new_game("시뮬", role, ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
			var ended: String = ""
			for season in _EconomySim.YEARS * 4:
				_EconomySim.run_strategy(gm, strategy)
				gm.advance_turn()
				gm.pending_event.clear()
				gm.pending_combat = null
				if gm.is_game_over():
					ended = " → %s (%d년)" % [gm.game_over_id, gm.current_year]
					break
			var sect: SectData = gm.player_sect
			print("%-12s %-14s 금%d 식%d 제자%d 명%d%s" % [strategy, role, sect.gold, sect.food, sect.disciple_count, sect.reputation, ended])
