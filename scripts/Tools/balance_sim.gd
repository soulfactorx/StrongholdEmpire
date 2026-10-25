extends SceneTree

## 밸런스 시뮬레이터: 전투 자동 플레이, 세력 AI, 장기 경제를 한 번에 돌려 수치를 출력한다.
## 실행: godot --headless --path . -s res://scripts/Tools/balance_sim.gd [-- combat|world|economy] [runs=N] [only=전투,전투] [levels=1,3,6]
## 영역을 주지 않으면 모두 돌린다. 수치를 바꾸면 결과를 구현 계획(M9-5)에 함께 기록한다.

const _EconomySim = preload("res://scripts/Tools/economy_sim.gd")

## 전투 자동 플레이: 시험할 전투와 주인공 레벨, 판 수
const COMBATS: Array[String] = [
	"sparring", "rival_duel", "night_bandits", "bandit_hunt", "assassination", "bounty_hunters", "invasion",
	"arc_love_trial", "arc_love_pursuit", "arc_revenge_duel", "arc_revenge_duel_allied", "arc_revenge_chief",
	"arc_spy_rescue", "arc_spy_enforcer", "arc_succession_coup", "arc_succession_coup_traitor",
	"arc_cheonma_blood_shadow", "arc_cheonma_siege", "arc_cheonma_siege_allied", "arc_cheonma_final", "martial_tournament",
	# 메인 시나리오 전투: "시나리오:전투"
	"saga_1_blood_moon:s1_blood_night_gate", "saga_1_blood_moon:s1_guard_the_master", "saga_1_blood_moon:s1_heaven_duel",
	"saga_1_blood_moon:s1_black_wind_ambush", "saga_1_blood_moon:s1_duel_mugyeom",
	"saga_2_black_lotus:s2_civil_war", "saga_2_black_lotus:s2_lotus_raid", "saga_2_black_lotus:s2_luoyang_wall", "saga_2_black_lotus:s2_dokgo_duel",
	"saga_3_blue_sky:s3_rescue", "saga_3_blue_sky:s3_kaifeng_last", "saga_3_blue_sky:s3_hunt_hwarin", "saga_3_blue_sky:s3_father_duel",
]
## 인자 levels=1,3,6으로 바꿀 수 있다
var levels: Array[int] = [1, 3, 6]
## 판 수는 인자 runs=N으로 바꿀 수 있다.
var combat_runs: int = 30
## 인자 only=a,b로 시험할 전투를 고른다 (비우면 모두)
var only_combats: PackedStringArray = []
const WORLD_RUNS := 100


func _initialize() -> void:
	# 시뮬레이션의 저장·설정이 실제 파일을 건드리지 않게 한다.
	SaveManager.save_dir = "user://_sim_saves/"
	GameSettings.settings_path = "user://_sim_saves/settings.cfg"
	GameSettings.combat_delay = 0.0
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("runs="):
			combat_runs = maxi(1, arg.trim_prefix("runs=").to_int())
		elif arg.begins_with("levels="):
			levels.assign(Array(arg.trim_prefix("levels=").split(",")).map(func(x: String) -> int: return x.to_int()))
		elif arg.begins_with("only="):
			only_combats = arg.trim_prefix("only=").split(",")
	var all: bool = not (args.has("combat") or args.has("world") or args.has("economy"))
	if all or args.has("combat"):
		await _run_combat()
	if all or args.has("world"):
		_run_world()
	if all or args.has("economy"):
		_run_economy()
	# 재생 중인 효과음을 멈추고 오디오 스레드가 놓을 때까지 기다린다 (종료 시 누수 경고 방지)
	root.get_node("AudioManager").stop_all()
	await create_timer(0.3).timeout
	quit()


# ── 전투 ──

func _run_combat() -> void:
	var gm: Node = root.get_node("GameManager")
	print("[전투 자동 플레이] %d판씩. 초식 배치 대결을 양쪽 모두 자동 배치로 치른다" % combat_runs)
	print("  자동 배치: 상대가 지난 합에 낸 유형을 읽어 맞받고(주인공 60%, 적 45%), 기세가 차면 절초를 낸다. 사건 선택도 자동")
	print("  코드 전투는 판마다 형식·전장·목표가 바뀐다 (CombatManager.varied)")
	print("전투 / 주인공 레벨: 승률 · 이긴 판의 남은 체력 평균 · 평균 합 수 · 판당 전사한 동료")
	for combat_id in COMBATS:
		if not only_combats.is_empty() and not only_combats.has(combat_id):
			continue
		var line: String = "%-16s" % combat_id.get_slice(":", combat_id.count(":"))
		for level in levels:
			var wins: int = 0
			var hp_sum: float = 0.0
			var rounds_sum: int = 0
			var fallen_sum: int = 0
			seed(combat_id.hash() + level)
			for run in combat_runs:
				var result: Dictionary = _play_combat(gm, combat_id, level)
				rounds_sum += result["rounds"]
				fallen_sum += result["fallen"]
				if result["victory"]:
					wins += 1
					hp_sum += result["hp_ratio"]
			line += " | Lv.%d 승 %3d%% 체력 %3d%% %4.1f합 전사 %.1f" % [
				level, roundi(100.0 * wins / combat_runs), roundi(100.0 * hp_sum / maxi(1, wins)),
				float(rounds_sum) / combat_runs, float(fallen_sum) / combat_runs,
			]
		print(line)


## 전투 한 판을 자동으로 치른다. {victory, hp_ratio, rounds, fallen}
## 초식 배치 대결 엔진을 화면 없이 돌린다: 양쪽 모두 상대의 지난 합을 읽어 배치하는 AI.
func _play_combat(gm: Node, combat_id: String, level: int) -> Dictionary:
	gm.start_new_game("시뮬", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	gm.player_character.gain_experience(CharacterData.get_experience_for_level(level))
	gm.player_character.restore_internal_energy()
	# 레벨에 맞는 무공 하나를 익힌다 (Lv.3부터)
	if level >= 3:
		gm.player_character.learn_martial_art(MartialArtLibrary.create_art("preset_soul_chase_sword"))
	var setup: CombatSetup
	if ":" in combat_id:
		# 시나리오 전용 전투는 그 시나리오를 켜고 만든다
		ScenarioManager.activate(combat_id.get_slice(":", 0))
		setup = CombatLibrary.create(combat_id.get_slice(":", 1), gm.player_character, gm.player_sect)
		ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	elif combat_id == "invasion":
		setup = CombatManager.create_invasion(gm.get_world_sect("heukpung"), gm.player_character, gm.player_sect)
	else:
		setup = CombatManager.create_by_id(combat_id, gm.player_character, gm.player_sect)
	var engine := DuelEngine.new(setup, gm.player_character, {}, {}, gm.player_relationships)
	engine.rng.seed = randi()
	engine.play_to_end()
	var player: CombatUnit = engine.get_player()
	# 목표(우두머리·탈출·버티기 등)로 이긴 판도 승리로 센다
	return {
		"victory": engine.outcome == CombatManager.Outcome.VICTORY,
		"hp_ratio": float(player.hp) / player.max_hp,
		"rounds": engine.bout_total,
		"fallen": engine.fallen_ally_ids().size(),
	}


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
