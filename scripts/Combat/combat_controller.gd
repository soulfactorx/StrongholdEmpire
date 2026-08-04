extends Node2D

const GRID_SIZE := 48
const GRID_WIDTH := 16
const GRID_HEIGHT := 10
const MOVE_COST := 1

enum ActionMode { MOVE, ATTACK, MARTIAL_ART }

var _units: Array[CombatUnit] = []
var _turn_manager := TurnManager.new()
var _blocked_tiles: Array[Vector2i] = []
var _action_mode: ActionMode = ActionMode.MOVE
var _combat_over: bool = false
var _winner: String = ""

@onready var grid_overlay: Node2D = $GridOverlay
@onready var units_layer: Node2D = $UnitsLayer
@onready var round_label: Label = %RoundLabel
@onready var turn_label: Label = %TurnLabel
@onready var player_hp_label: Label = %PlayerHPLabel
@onready var enemy_hp_label: Label = %EnemyHPLabel
@onready var ap_label: Label = %APLabel
@onready var martial_label: Label = %MartialLabel
@onready var log_label: Label = %LogLabel


func _ready() -> void:
	_setup_combat()
	_draw_grid()
	_refresh_units_visual()
	_update_hud()
	_log("전투 시작! 남궁휘와의 결투.")


func _setup_combat() -> void:
	_blocked_tiles = [
		Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6),
		Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7),
	]

	var player_unit := CombatUnit.new(GameManager.player_character, true)
	player_unit.grid_pos = Vector2i(2, 5)
	player_unit.target_id = "npc_rival"
	_units.append(player_unit)

	var enemy_char := _create_enemy_character()
	var enemy_unit := CombatUnit.new(enemy_char, false)
	enemy_unit.grid_pos = Vector2i(13, 5)
	enemy_unit.target_id = "player_001"
	_units.append(enemy_unit)

	_turn_manager.setup(_units)


func _create_enemy_character() -> CharacterData:
	var enemy := CharacterData.new()
	enemy.id = "npc_rival"
	enemy.display_name = "남궁휘"
	enemy.role = CharacterData.Role.YOUNG_DISCIPLE
	enemy.strength = 14
	enemy.agility = 13
	enemy.wisdom = 10
	enemy.charisma = 9
	enemy.internal_energy_max = 100
	enemy.internal_energy_current = 100
	enemy.level = 2
	return enemy


func _get_player() -> CombatUnit:
	for unit in _units:
		if unit.is_player:
			return unit
	return null


func _get_enemy() -> CombatUnit:
	for unit in _units:
		if not unit.is_player:
			return unit
	return null


func _draw_grid() -> void:
	for child in grid_overlay.get_children():
		child.queue_free()

	var player := _get_player()
	var enemy := _get_enemy()
	var current := _turn_manager.get_current_unit()

	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var tile := ColorRect.new()
			tile.size = Vector2(GRID_SIZE - 2, GRID_SIZE - 2)
			tile.position = Vector2(x * GRID_SIZE + 1, y * GRID_SIZE + 1)
			var coord := Vector2i(x, y)
			if _blocked_tiles.has(coord):
				tile.color = Color(0.35, 0.2, 0.2, 0.8)
			elif player and coord == player.grid_pos:
				tile.color = Color(0.2, 0.45, 0.7, 0.7)
			elif enemy and coord == enemy.grid_pos:
				tile.color = Color(0.7, 0.25, 0.2, 0.7)
			elif current and current.is_player and _is_reachable(player, coord):
				tile.color = Color(0.2, 0.35, 0.2, 0.6)
			else:
				tile.color = Color(0.12, 0.15, 0.12, 0.5)
			grid_overlay.add_child(tile)


func _is_reachable(unit: CombatUnit, target: Vector2i) -> bool:
	if unit == null:
		return false
	var distance := absi(target.x - unit.grid_pos.x) + absi(target.y - unit.grid_pos.y)
	return distance == 1 and _is_valid_tile(target) and target != unit.grid_pos


func _refresh_units_visual() -> void:
	for child in units_layer.get_children():
		child.queue_free()

	for unit in _units:
		if not unit.is_alive():
			continue
		var marker := ColorRect.new()
		marker.size = Vector2(28, 28)
		marker.position = Vector2(
			unit.grid_pos.x * GRID_SIZE + 10,
			unit.grid_pos.y * GRID_SIZE + 10
		)
		marker.color = Color(0.3, 0.7, 1) if unit.is_player else Color(0.9, 0.3, 0.2)
		units_layer.add_child(marker)

		var name_label := Label.new()
		name_label.text = unit.display_name
		name_label.position = marker.position + Vector2(-4, -18)
		name_label.add_theme_font_size_override("font_size", 11)
		units_layer.add_child(name_label)


func _update_hud() -> void:
	var player := _get_player()
	var enemy := _get_enemy()
	var current := _turn_manager.get_current_unit()

	round_label.text = "라운드 %d" % _turn_manager.round_number
	if current:
		turn_label.text = "현재 턴: %s" % current.display_name
	if player:
		player_hp_label.text = "이청풍 HP: %d / %d" % [player.hp, player.max_hp]
		ap_label.text = "행동력: %d / %d" % [player.action_points, player.max_action_points]
		if player.active_martial_art:
			martial_label.text = "무공: %s" % player.active_martial_art.display_name
		else:
			martial_label.text = "무공: 없음"
	if enemy:
		enemy_hp_label.text = "남궁휘 HP: %d / %d" % [enemy.hp, enemy.max_hp]


func _log(message: String) -> void:
	log_label.text = message
	EventBus.action_message.emit(message)


func _unhandled_input(event: InputEvent) -> void:
	if _combat_over:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var current := _turn_manager.get_current_unit()
	if current == null or not current.is_player:
		return

	var local_pos := get_global_mouse_position() - global_position
	var target := Vector2i(int(local_pos.x / GRID_SIZE), int(local_pos.y / GRID_SIZE))

	match _action_mode:
		ActionMode.MOVE:
			_try_move(current, target)
		ActionMode.ATTACK:
			_try_attack(current, target)
		ActionMode.MARTIAL_ART:
			_try_martial_art(current, target)


func _try_move(unit: CombatUnit, target: Vector2i) -> void:
	if not _is_reachable(unit, target):
		_log("이동할 수 없는 위치입니다.")
		return
	if unit.action_points < MOVE_COST:
		_log("행동력이 부족합니다.")
		return

	unit.grid_pos = target
	unit.action_points -= MOVE_COST
	_draw_grid()
	_refresh_units_visual()
	_update_hud()
	_log("이동 완료.")


func _try_attack(unit: CombatUnit, target: Vector2i) -> void:
	var enemy := _get_enemy()
	if enemy == null or not enemy.is_alive():
		return

	var distance := absi(target.x - unit.grid_pos.x) + absi(target.y - unit.grid_pos.y)
	if target != enemy.grid_pos or distance > 1:
		_log("인접한 적에게만 공격할 수 있습니다.")
		return
	if unit.action_points < 1:
		_log("행동력이 부족합니다.")
		return

	var damage := 8 + unit.character.strength
	var hatred_bonus := RelationshipManager.get_combat_damage_bonus(
		GameManager.player_relationships,
		"npc_rival"
	)
	damage = int(damage * hatred_bonus)
	enemy.take_damage(damage)
	unit.action_points -= 1
	_draw_grid()
	_refresh_units_visual()
	_update_hud()
	_log("기본 공격! %d 피해 (관계 보정 %.0f%%)" % [damage, hatred_bonus * 100])

	if not enemy.is_alive():
		_end_combat(true)


func _try_martial_art(unit: CombatUnit, target: Vector2i) -> void:
	var art := unit.active_martial_art
	if art == null:
		_log("사용 가능한 무공이 없습니다.")
		return
	if unit.action_points < art.action_cost:
		_log("행동력이 부족합니다.")
		return
	if not unit.character.spend_internal_energy(art.internal_cost):
		_log("내공이 부족합니다.")
		return

	var enemy := _get_enemy()
	if art.heal_amount > 0:
		var heal := int(art.heal_amount * RelationshipManager.get_ally_buff_multiplier(
			GameManager.player_relationships
		))
		unit.heal(heal)
		unit.action_points -= art.action_cost
		_log("[%s] 시전! HP %d 회복." % [art.display_name, heal])
	else:
		if enemy == null:
			return
		var distance := absi(target.x - unit.grid_pos.x) + absi(target.y - unit.grid_pos.y)
		if target != enemy.grid_pos or distance > art.range:
			_log("사거리 밖입니다. (사거리 %d)" % art.range)
			unit.character.internal_energy_current += art.internal_cost
			return

		var damage := art.damage + int(unit.character.strength * 0.3)
		var bonus := RelationshipManager.get_combat_damage_bonus(
			GameManager.player_relationships,
			"npc_rival"
		)
		damage = int(damage * bonus)

		if art.move_bonus > 0:
			var dir := target - unit.grid_pos
			var new_pos := unit.grid_pos + dir
			if _is_valid_tile(new_pos) and new_pos != enemy.grid_pos:
				unit.grid_pos = new_pos

		enemy.take_damage(damage)
		unit.action_points -= art.action_cost
		_log("[%s] 시전! %d 피해!" % [art.display_name, damage])

		if not enemy.is_alive():
			_end_combat(true)

	_draw_grid()
	_refresh_units_visual()
	_update_hud()


func _is_valid_tile(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= GRID_WIDTH or pos.y < 0 or pos.y >= GRID_HEIGHT:
		return false
	if _blocked_tiles.has(pos):
		return false
	for unit in _units:
		if unit.is_alive() and unit.grid_pos == pos:
			return false
	return true


func _end_combat(player_won: bool) -> void:
	_combat_over = true
	if player_won:
		_winner = "player"
		GameManager.player_character.experience += 30
		var rival := RelationshipManager.get_bond_with(GameManager.player_relationships, "npc_rival")
		if rival:
			rival.increase_bond(5)
		_log("승리! 경험치 +30")
	else:
		_winner = "enemy"
		_log("패배... 다시 도전하세요.")


func _run_enemy_ai() -> void:
	var enemy := _get_enemy()
	var player := _get_player()
	if enemy == null or player == null or not enemy.is_alive() or not player.is_alive():
		return

	var distance := absi(player.grid_pos.x - enemy.grid_pos.x) + absi(player.grid_pos.y - enemy.grid_pos.y)
	if distance == 1 and enemy.action_points >= 1:
		var damage := 10 + enemy.character.strength
		player.take_damage(damage)
		enemy.action_points -= 1
		_log("남궁휘의 반격! %d 피해" % damage)
		if not player.is_alive():
			_end_combat(false)
			return
	elif enemy.action_points >= 1:
		var dir := signi(player.grid_pos.x - enemy.grid_pos.x)
		if dir == 0:
			dir = signi(player.grid_pos.y - enemy.grid_pos.y)
		var next_pos := enemy.grid_pos
		if dir != 0:
			if absi(player.grid_pos.x - enemy.grid_pos.x) >= absi(player.grid_pos.y - enemy.grid_pos.y):
				next_pos.x += signi(player.grid_pos.x - enemy.grid_pos.x)
			else:
				next_pos.y += signi(player.grid_pos.y - enemy.grid_pos.y)
		if _is_valid_tile(next_pos):
			enemy.grid_pos = next_pos
			enemy.action_points -= 1
			_log("남궁휘가 접근합니다.")

	_draw_grid()
	_refresh_units_visual()
	_update_hud()


func _on_end_turn_pressed() -> void:
	if _combat_over:
		return

	var current := _turn_manager.get_current_unit()
	if current and current.is_player:
		var next := _turn_manager.end_turn()
		_update_hud()
		if next and not next.is_player:
			_run_enemy_ai()
			next = _turn_manager.end_turn()
		_draw_grid()
		_update_hud()
		if next:
			_log("%s의 턴입니다." % next.display_name)


func _on_mode_move_pressed() -> void:
	_action_mode = ActionMode.MOVE
	_log("행동: 이동")


func _on_mode_attack_pressed() -> void:
	_action_mode = ActionMode.ATTACK
	_log("행동: 기본 공격")


func _on_mode_martial_pressed() -> void:
	_action_mode = ActionMode.MARTIAL_ART
	_log("행동: 무공")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")