extends Node2D

const GRID_SIZE := 48
const GRID_WIDTH := 16
const GRID_HEIGHT := 10
const MOVE_COST := 1

@export var max_action_points: int = 4

var _grid_pos: Vector2i = Vector2i(2, 5)
var _action_points: int = 4
var _blocked_tiles: Array[Vector2i] = []

@onready var player_sprite: Sprite2D = $Player
@onready var grid_overlay: Node2D = $GridOverlay
@onready var ap_label: Label = %APLabel
@onready var pos_label: Label = %PosLabel
@onready var log_label: Label = %LogLabel


func _ready() -> void:
	_setup_blocked_tiles()
	_draw_grid()
	_update_player_visual()
	_update_hud()
	EventBus.action_message.emit("그리드 이동 데모: 타일을 클릭해 이동하세요.")


func _setup_blocked_tiles() -> void:
	_blocked_tiles = [
		Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5),
		Vector2i(8, 2), Vector2i(9, 2), Vector2i(10, 2),
		Vector2i(12, 6), Vector2i(12, 7),
	]


func _draw_grid() -> void:
	for child in grid_overlay.get_children():
		child.queue_free()

	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var tile := ColorRect.new()
			tile.size = Vector2(GRID_SIZE - 2, GRID_SIZE - 2)
			tile.position = Vector2(x * GRID_SIZE + 1, y * GRID_SIZE + 1)
			var grid_coord := Vector2i(x, y)
			if _blocked_tiles.has(grid_coord):
				tile.color = Color(0.35, 0.2, 0.2, 0.8)
			elif grid_coord == _grid_pos:
				tile.color = Color(0.2, 0.45, 0.7, 0.6)
			else:
				tile.color = Color(0.15, 0.2, 0.15, 0.5)
			grid_overlay.add_child(tile)


func _update_player_visual() -> void:
	player_sprite.position = Vector2(
		_grid_pos.x * GRID_SIZE + GRID_SIZE / 2.0,
		_grid_pos.y * GRID_SIZE + GRID_SIZE / 2.0
	)


func _update_hud() -> void:
	ap_label.text = "행동력: %d / %d" % [_action_points, max_action_points]
	pos_label.text = "위치: (%d, %d)" % [_grid_pos.x, _grid_pos.y]
	EventBus.grid_position_changed.emit(_grid_pos)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos := get_global_mouse_position() - global_position
		var target := Vector2i(
			int(local_pos.x / GRID_SIZE),
			int(local_pos.y / GRID_SIZE)
		)
		_try_move_to(target)


func _try_move_to(target: Vector2i) -> void:
	if not _is_valid_tile(target):
		log_label.text = "이동할 수 없는 위치입니다."
		return
	if target == _grid_pos:
		return

	var distance := absi(target.x - _grid_pos.x) + absi(target.y - _grid_pos.y)
	if distance != 1:
		log_label.text = "인접한 타일만 이동할 수 있습니다."
		return
	if _action_points < MOVE_COST:
		log_label.text = "행동력이 부족합니다. 턴 종료를 누르세요."
		return

	_grid_pos = target
	_action_points -= MOVE_COST
	_update_player_visual()
	_draw_grid()
	_update_hud()
	log_label.text = "이동 완료. 남은 행동력: %d" % _action_points


func _is_valid_tile(pos: Vector2i) -> bool:
	return (
		pos.x >= 0 and pos.x < GRID_WIDTH
		and pos.y >= 0 and pos.y < GRID_HEIGHT
		and not _blocked_tiles.has(pos)
	)


func _on_end_turn_pressed() -> void:
	_action_points = max_action_points
	_draw_grid()
	_update_hud()
	log_label.text = "턴 종료. 행동력이 회복되었습니다."


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")