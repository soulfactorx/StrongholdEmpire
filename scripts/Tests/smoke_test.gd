extends SceneTree

## 헤드리스 스모크 테스트 진입 스크립트.
## 실행: godot --headless --path . -s res://scripts/Tests/smoke_test.gd
## 검사는 영역별 파일(scripts/Tests/test_*.gd)에 있고, 여기서는 순서대로 실행해 결과를 모은다.
## 새 검사 함수를 만들면 해당 영역 파일에 넣고 아래 순서 목록에 추가한다.

const TEST_SAVE_DIR := "user://_test_saves/"

## 영역 이름 → 스위트 스크립트
const SUITES: Dictionary = {
	"core": preload("res://scripts/Tests/test_core.gd"),
	"events": preload("res://scripts/Tests/test_events.gd"),
	"combat": preload("res://scripts/Tests/test_combat.gd"),
	"world": preload("res://scripts/Tests/test_world.gd"),
	"scenario": preload("res://scripts/Tests/test_scenario.gd"),
	"roles": preload("res://scripts/Tests/test_roles.gd"),
	"ui": preload("res://scripts/Tests/test_ui.gd"),
}

## 오토로드가 준비되기 전(첫 프레임 전)에 돌리는 검사: 데이터·규칙만 본다.
const INIT_SEQUENCE: Array = [
	["core", "_test_scenes_load"],
	["core", "_test_level_curve"],
	["core", "_test_gain_experience"],
	["core", "_test_martial_art_round_trip"],
	["core", "_test_old_save_without_martial_arts"],
	["core", "_test_starting_roles"],
	["combat", "_test_combat_outcomes"],
	["combat", "_test_combat_events"],
	["events", "_test_event_definitions"],
	["events", "_test_event_validation"],
	["events", "_test_event_conditions"],
	["events", "_test_event_branches"],
	["events", "_test_event_mod_folder"],
	["core", "_test_upkeep"],
	["core", "_test_game_over_conditions"],
	["world", "_test_npc_roster"],
	["world", "_test_sect_registry"],
	["world", "_test_world_sect_events"],
	["combat", "_test_combat_rules"],
	["combat", "_test_damage_randomness"],
	["combat", "_test_martial_art_library"],
	["combat", "_test_ally_setup"],
	["events", "_test_event_grammar_validation"],
	["events", "_test_event_grammar_conditions"],
	["events", "_test_event_grammar_effects"],
]

## 첫 프레임 뒤에 돌리는 검사: GameManager·화면을 쓴다. 순서가 결과에 영향을 줄 수 있으니 지킨다.
const RUNTIME_SEQUENCE: Array = [
	["core", "_test_turn_loop"],
	["core", "_test_start_new_game"],
	["core", "_test_scene_navigation"],
	["combat", "_test_combat_flow"],
	["events", "_test_event_popup_choices"],
	["core", "_test_game_over_flow"],
	["world", "_test_world_state_and_war"],
	["combat", "_test_combat_effects"],
	["combat", "_test_ally_combat"],
	["combat", "_test_basic_attack_limit"],
	["combat", "_test_grid_cursor"],
	["combat", "_test_combat_preview_and_history"],
	["events", "_test_event_progress_tracking"],
	["scenario", "_test_scenario_data"],
	["scenario", "_test_scenario_parameters"],
	["scenario", "_test_scenario_flow"],
	["scenario", "_test_new_game_screen_scenarios"],
	["scenario", "_test_ending_data"],
	["scenario", "_test_every_ending_reachable"],
	["scenario", "_test_final_ending_flow"],
	["scenario", "_test_tutorial_scenario"],
	["world", "_test_war_rules"],
	["world", "_test_war_balance"],
	["world", "_test_war_flow"],
	["core", "_test_economy_rules"],
	["core", "_test_economy_flow"],
	["roles", "_test_role_actions"],
	["roles", "_test_role_transitions_extended"],
	["roles", "_test_role_actions_hub"],
	["combat", "_test_combat_library"],
	["events", "_test_story_arcs"],
	["events", "_test_main_saga_system"],
	["events", "_test_main_saga_paths"],
	["roles", "_test_starting_sect"],
	["roles", "_test_disciple_roster"],
	["roles", "_test_disciple_roster_flow"],
	["combat", "_test_transmission_and_secret"],
	["combat", "_test_martial_art_screen_actions"],
	["roles", "_test_bond_evolution"],
	["roles", "_test_bond_flow"],
	["roles", "_test_bond_system"],
	["roles", "_test_manuals"],
	["roles", "_test_purse"],
	["roles", "_test_join_leave"],
	["roles", "_test_region_travel"],
	["roles", "_test_npc_agents"],
	["world", "_test_diplomacy"],
	["world", "_test_diplomacy_screen"],
	["world", "_test_sect_ai"],
	["world", "_test_world_map_and_factions"],
	["world", "_test_map_screens"],
	["ui", "_test_save_slots"],
	["world", "_test_invasion_flow"],
	["ui", "_test_save_screens"],
	["ui", "_test_settings_and_reports"],
	["ui", "_test_ui_flows"],
	["ui", "_test_input_and_tips"],
	["ui", "_test_action_preview"],
	["ui", "_test_chronicle_and_dialogue"],
	["ui", "_test_role_dashboard"],
	["ui", "_test_role_guide"],
	["ui", "_test_portrait_layout"],
	["ui", "_test_art_assets"],
	["ui", "_test_audio"],
	["core", "_test_self_check"],
	["ui", "_test_suspend_autosave"],
]

var _failures: int = 0
## 끝까지 실행된 검사 함수 이름
var _completed: Dictionary = {}
var _checks: int = 0
var _suites: Dictionary = {}


func _initialize() -> void:
	# 테스트의 저장(자동 저장 포함)은 실제 세이브와 다른 폴더에 한다.
	SaveManager.save_dir = TEST_SAVE_DIR
	GameSettings.settings_path = TEST_SAVE_DIR.path_join("settings.cfg")
	# 적 차례 간격 없이 바로 진행 (간격은 test_ui의 _test_input_and_tips에서 따로 시험)
	GameSettings.combat_delay = 0.0
	# 공격 미리보기는 끄고 바로 실행한다 (켠 상태는 test_combat의 _test_combat_preview_and_history에서 따로)
	GameSettings.combat_preview = false
	GameSettings.enemy_preview = false
	# 경영 행동 미리보기도 끈다 (켠 상태는 test_ui의 _test_action_preview에서 따로)
	GameSettings.action_preview = false
	GameSettings.faction_report = false
	# 세력 AI는 계절마다 강호 세력 수치를 바꾸므로, 그 영향을 시험하는 곳에서만 켠다.
	SectAI.active = false
	# 우리 문파 직책 인물(NpcAgent)도 문파 수치를 바꾸므로 시험하는 곳에서만 켠다.
	NpcAgent.active = false
	# 피해 흔들림·회심은 끄고 정확한 값으로 시험한다 (켠 상태는 test_combat의 _test_damage_randomness에서 따로)
	CombatRules.randomness = false
	for key in SUITES:
		_suites[key] = SUITES[key].new(self)
	_suites["core"]._clear_test_saves()
	for entry in INIT_SEQUENCE:
		_suites[entry[0]].call(entry[1])
		_check(_completed.has(entry[1]), "%s 끝까지 실행" % entry[1])
	# 오토로드의 _ready()는 첫 프레임에 실행되므로 런타임 검사는 그 뒤로 미룬다.
	process_frame.connect(_run_runtime_tests, CONNECT_ONE_SHOT)


func _run_runtime_tests() -> void:
	# GameManager가 준비되며 설정 파일을 읽으므로, 시험용 전투 설정을 다시 맞춘다.
	GameSettings.combat_delay = 0.0
	GameSettings.combat_preview = false
	GameSettings.enemy_preview = false
	GameSettings.action_preview = false
	GameSettings.faction_report = false
	# 각 검사가 끝까지 실행됐는지 확인한다. 스크립트 오류로 중단되면 완료 표시가 남지 않는다.
	# 환경 변수 SMOKE_ONLY="검사1,검사2"를 주면 그 런타임 검사만 돌린다 (개발 중 빠른 확인용).
	var only: PackedStringArray = OS.get_environment("SMOKE_ONLY").split(",", false)
	for entry in RUNTIME_SEQUENCE:
		if not only.is_empty() and not entry[1] in only:
			continue
		await _suites[entry[0]].call(entry[1])
		_check(_completed.has(entry[1]), "%s 끝까지 실행" % entry[1])

	print("스모크 테스트: %d개 검사, %d개 실패" % [_checks, _failures])
	# 재생 중인 효과음을 멈추고, 오디오 스레드가 재생 객체를 놓을 때까지 잠시 기다린다.
	root.get_node("AudioManager").stop_all()
	await create_timer(0.3).timeout
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)
