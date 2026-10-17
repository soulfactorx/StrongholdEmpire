extends SceneTree

## 경제 밸런스 시뮬레이터. 전략별로 10년(40계절)을 자동 진행하고 자원 변화를 출력한다.
## 실행: godot --headless --path . -s res://scripts/Tools/economy_sim.gd
## 기연·전투는 끄고(event_rate 0) 순수 경제만 본다.

const YEARS := 10
const STRATEGIES: Array[String] = ["무행동", "제자 18명까지", "제자 최대 훈련", "시설 확장", "적극 투자"]


func _initialize() -> void:
	# 시뮬레이션의 자동 저장이 실제 세이브를 덮어쓰지 않게 한다.
	SaveManager.save_dir = "user://_sim_saves/"
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	print("전략 | 금화 / 식량 / 제자 / 명성 (5년 후, 10년 후). 시작: 금화 500, 식량 300")
	for strategy in STRATEGIES:
		for role in ["young_disciple", "leader"]:
			seed(1)
			gm.start_new_game("시뮬", role, ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
			var line: String = "%-10s %-14s" % [strategy, role]
			for season in YEARS * 4:
				run_strategy(gm, strategy)
				gm.advance_turn()
				gm.pending_event.clear()
				gm.pending_combat = null
				var sect: SectData = gm.player_sect
				if (season + 1) % 20 == 0 or gm.is_game_over():
					line += " | %d년 후 금%d 식%d 제자%d 명%d" % [
						(season + 1) / 4, sect.gold, sect.food, sect.disciple_count, sect.reputation,
					]
				if gm.is_game_over():
					line += " → %s" % gm.game_over_id
					break
			print(line)
	quit()


## 전략별 한 계절의 행동
static func run_strategy(gm: Node, strategy: String) -> void:
	var sect: SectData = gm.player_sect
	match strategy:
		"제자 18명까지":
			if sect.disciple_count < 18:
				SectManager.train_disciples(sect, gm.player_character)
		"제자 최대 훈련":
			SectManager.train_disciples(sect, gm.player_character)
		"시설 확장":
			for facility in SectManager.get_facility_ids():
				SectManager.upgrade_facility(sect, facility)
		"적극 투자":
			if sect.disciple_count < 18:
				SectManager.train_disciples(sect, gm.player_character)
			for facility in SectManager.get_facility_ids():
				SectManager.upgrade_facility(sect, facility)
			gm.buy_elixir()
			gm.hold_feast()
