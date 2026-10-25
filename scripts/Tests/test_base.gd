extends RefCounted

## 스모크 테스트 스위트의 공통 부분. 각 영역 파일(test_*.gd)이 이 스크립트를 상속한다.
## SceneTree(진입 스크립트 smoke_test.gd)의 root·current_scene·process_frame을 그대로 쓰고,
## 검사 결과(_check)와 완료 표시(_completed)는 진입 스크립트에 모은다.

const _SaveManager = preload("res://scripts/Systems/save_manager.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")
const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

const MAIN_SCENES: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/Combat/combat_scene.tscn",
	"res://scenes/UI/management_screen.tscn",
	"res://scenes/UI/martial_art_screen.tscn",
	"res://scenes/UI/sect_war_screen.tscn",
	"res://scenes/UI/ending_screen.tscn",
	"res://scenes/UI/help_screen.tscn",
	"res://scenes/UI/new_game_screen.tscn",
]

const TEST_SAVE_DIR := "user://_test_saves/"

## 진입 스크립트 (smoke_test.gd, SceneTree)
var tree: SceneTree
## 끝까지 실행된 검사 함수 이름 (진입 스크립트와 같은 딕셔너리)
var _completed: Dictionary

var root: Window:
	get:
		return tree.root
var current_scene: Node:
	get:
		return tree.current_scene
var process_frame: Signal:
	get:
		return tree.process_frame


func _init(runner: SceneTree) -> void:
	tree = runner
	_completed = runner._completed


func create_timer(time_sec: float) -> SceneTreeTimer:
	return tree.create_timer(time_sec)


func _check(condition: bool, label: String) -> void:
	tree._check(condition, label)


func _event_with(extra: Dictionary) -> Dictionary:
	var data: Dictionary = {
		"id": "t", "title": "t", "description": "t",
		"choices": [{"label": "a", "effects": []}],
	}
	data.merge(extra, true)
	return data


func _condition_holds(condition: Dictionary, st: Dictionary) -> bool:
	var event := EventData.new()
	event.conditions.append(condition)
	return EventManager._conditions_met(event, st["character"], st["sect"], st["relationships"], "봄", st["flags"])


func _count_json(dir_path: String) -> int:
	var count: int = 0
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".json"):
			count += 1
	return count


func _clear_test_saves() -> void:
	for slot in range(SaveManager.AUTO_SLOT, SaveManager.SLOT_COUNT + 1):
		SaveManager.delete_save(slot)


func _make_combat_state() -> Dictionary:
	var character := CharacterData.new()
	character.internal_energy_max = 100
	character.restore_internal_energy()
	var sect := SectData.new()
	var relationships: Array[RelationshipData] = RelationshipManager.create_default_relationships()
	return {"character": character, "sect": sect, "relationships": relationships, "flags": {}}


func _apply(setup: CombatSetup, outcome: CombatManager.Outcome, st: Dictionary) -> Dictionary:
	return CombatManager.apply_outcome(
		setup, outcome, st["character"], st["sect"], st["relationships"], st["flags"]
	)


## 새 게임을 이벤트 없이 시작한다.
func _new_quiet_game(gm: Node, role_id: String) -> void:
	gm.start_new_game("신분", role_id, ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})


func _rel(gm: Node, target_id: String) -> RelationshipData:
	return RelationshipManager.get_bond_with(gm.player_relationships, target_id)


func _roster_matches(sect: SectData) -> bool:
	return sect.use_roster and sect.disciples.size() == sect.disciple_count


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func _mouse(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event
