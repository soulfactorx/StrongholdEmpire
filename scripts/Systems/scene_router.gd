class_name SceneRouter
extends RefCounted

## 씬 경로와 화면 전환을 한 곳에서 관리한다.

const MAIN_MENU := "res://scenes/main.tscn"
const NEW_GAME := "res://scenes/UI/new_game_screen.tscn"
const HUB := "res://scenes/UI/management_screen.tscn"
const MARTIAL_ART := "res://scenes/UI/martial_art_screen.tscn"
const COMBAT := "res://scenes/Combat/combat_scene.tscn"
const SECT_WAR := "res://scenes/UI/sect_war_screen.tscn"
const WORLD := "res://scenes/UI/world_screen.tscn"
const ENDING := "res://scenes/UI/ending_screen.tscn"
const HELP := "res://scenes/UI/help_screen.tscn"
const MAP := "res://scenes/UI/map_screen.tscn"

static var _return_path: String = ""


static func goto(tree: SceneTree, path: String) -> void:
	# 트리를 떠난 노드가 부르면 무시한다.
	if tree == null:
		return
	var current: Node = tree.current_scene
	_return_path = current.scene_file_path if current else ""
	tree.change_scene_to_file(path)


## 직전 화면으로 돌아간다. 기록이 없으면 fallback으로 간다.
static func back(tree: SceneTree, fallback: String) -> void:
	var target: String = _return_path if not _return_path.is_empty() else fallback
	_return_path = ""
	tree.change_scene_to_file(target)
