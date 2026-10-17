extends Node2D

const _Balance = preload("res://scripts/Systems/game_balance.gd")

const GRID_SIZE := 48
const GRID_WIDTH := 16
const GRID_HEIGHT := 10
const MOVE_COST := 1

enum ActionMode { MOVE, ATTACK, MARTIAL_ART }

var _setup: CombatSetup
var _units: Array[CombatUnit] = []
var _turn_manager := TurnManager.new()
var _action_mode: ActionMode = ActionMode.MOVE
var _combat_over: bool = false

@onready var grid_overlay: Node2D = $GridOverlay
@onready var units_layer: Node2D = $UnitsLayer
@onready var title_label: Label = %TitleLabel
@onready var round_label: Label = %RoundLabel
@onready var turn_label: Label = %TurnLabel
@onready var player_hp_label: Label = %PlayerHPLabel
@onready var enemy_hp_label: Label = %EnemyHPLabel
@onready var ap_label: Label = %APLabel
@onready var martial_label: Label = %MartialLabel
@onready var log_label: Label = %LogLabel
@onready var back_button: Button = %BackButton


func _ready() -> void:
	_setup = GameManager.get_or_create_combat_setup()
	_setup_combat()
	title_label.text = _setup.title
	back_button.text = "후퇴"
	_refresh_all()
	_log("전투 시작! %s" % _setup.title)
	# 적이 더 빠르면 적의 턴부터 진행한다.
	var current := _turn_manager.get_current_unit()
	if current and not current.is_player:
		_run_enemy_turns()


func _setup_combat() -> void:
	var player_unit := CombatUnit.new(GameManager.player_character, true)
	player_unit.grid_pos = _setup.player_position
	_units.append(player_unit)

	for i in _setup.enemies.size():
		var enemy_unit := CombatUnit.new(_setup.enemies[i], false)
		enemy_unit.grid_pos = _setup.enemy_positions[i]
		enemy_unit.scale_stats(_setup.enemy_hp_scale, _setup.enemy_damage_scale)
		_units.append(enemy_unit)

	_turn_manager.setup(_units)


func _get_player() -> CombatUnit:
	for unit in _units:
		if unit.is_player:
			return unit
	return null


func _get_alive_enemies() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in _units:
		if not unit.is_player and unit.is_alive():
			result.append(unit)
	return result


func _get_enemy_at(coord: Vector2i) -> CombatUnit:
	for unit in _get_alive_enemies():
		if unit.grid_pos == coord:
			return unit
	return null


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _refresh_all() -> void:
	_draw_grid()
	_refresh_units_visual()
	_update_hud()


func _draw_grid() -> void:
	for child in grid_overlay.get_children():
		child.queue_free()

	var player := _get_player()
	var current := _turn_manager.get_current_unit()
	var show_moves: bool = not _combat_over and current != null and current.is_player

	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var tile := ColorRect.new()
			tile.size = Vector2(GRID_SIZE - 2, GRID_SIZE - 2)
			tile.position = Vector2(x * GRID_SIZE + 1, y * GRID_SIZE + 1)
			var coord := Vector2i(x, y)
			if _setup.blocked_tiles.has(coord):
				tile.color = Color(0.35, 0.2, 0.2, 0.8)
			elif player and coord == player.grid_pos:
				tile.color = Color(0.2, 0.45, 0.7, 0.7)
			elif _get_enemy_at(coord):
				tile.color = Color(0.7, 0.25, 0.2, 0.7)
			elif show_moves and _is_reachable(player, coord):
				tile.color = Color(0.2, 0.35, 0.2, 0.6)
			else:
				tile.color = Color(0.12, 0.15, 0.12, 0.5)
			grid_overlay.add_child(tile)


func _is_reachable(unit: CombatUnit, target: Vector2i) -> bool:
	if unit == null:
		return false
	return _distance(target, unit.grid_pos) == 1 and _is_valid_tile(target)


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
	var current := _turn_manager.get_current_unit()

	round_label.text = "라운드 %d" % _turn_manager.round_number
	if current:
		turn_label.text = "현재 턴: %s" % current.display_name
	if player:
		player_hp_label.text = "%s HP: %d / %d" % [player.display_name, player.hp, player.max_hp]
		ap_label.text = "행동력: %d / %d | 내공: %d" % [
			player.action_points,
			player.max_action_points,
			player.character.internal_energy_current,
		]
		if player.active_martial_art:
			martial_label.text = "무공: %s" % player.active_martial_art.display_name
		else:
			martial_label.text = "무공: 없음"

	var lines: PackedStringArray = []
	for unit in _units:
		if unit.is_player:
			continue
		if unit.is_alive():
			lines.append("%s HP: %d / %d" % [unit.display_name, unit.hp, unit.max_hp])
		else:
			lines.append("%s — 쓰러짐" % unit.display_name)
	enemy_hp_label.text = "\n".join(lines)


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
	_refresh_all()
	_log("이동 완료.")


func _try_attack(unit: CombatUnit, target: Vector2i) -> void:
	var enemy := _get_enemy_at(target)
	if enemy == null or _distance(target, unit.grid_pos) > 1:
		_log("인접한 적에게만 공격할 수 있습니다.")
		return
	if unit.action_points < 1:
		_log("행동력이 부족합니다.")
		return

	var bonus := _relationship_bonus(enemy)
	var damage := int((_Balance.BASE_ATTACK_DAMAGE + unit.character.strength) * bonus)
	enemy.take_damage(damage)
	unit.action_points -= 1
	_refresh_all()
	_log("%s에게 기본 공격! %d 피해 (관계 보정 %.0f%%)" % [enemy.display_name, damage, bonus * 100])
	_check_victory()


func _try_martial_art(unit: CombatUnit, target: Vector2i) -> void:
	var art := unit.active_martial_art
	if art == null:
		_log("사용 가능한 무공이 없습니다.")
		return
	if unit.action_points < art.action_cost:
		_log("행동력이 부족합니다.")
		return

	if art.heal_amount > 0:
		if not unit.character.spend_internal_energy(art.internal_cost):
			_log("내공이 부족합니다.")
			return
		var heal := int(art.heal_amount * RelationshipManager.get_ally_buff_multiplier(
			GameManager.player_relationships
		))
		unit.heal(heal)
		unit.action_points -= art.action_cost
		_refresh_all()
		_log("[%s] 시전! HP %d 회복." % [art.display_name, heal])
		return

	var enemy := _get_enemy_at(target)
	if enemy == null or _distance(target, unit.grid_pos) > art.range:
		_log("사거리 안의 적을 선택하세요. (사거리 %d)" % art.range)
		return
	if not unit.character.spend_internal_energy(art.internal_cost):
		_log("내공이 부족합니다.")
		return

	var damage := int((art.damage + int(unit.character.strength * 0.3)) * _relationship_bonus(enemy))

	# 이동 효과가 있는 무공은 적 방향으로 한 칸 파고든다.
	if art.move_bonus > 0:
		var step := Vector2i(signi(target.x - unit.grid_pos.x), signi(target.y - unit.grid_pos.y))
		if step.x != 0 and step.y != 0:
			step.y = 0
		var new_pos := unit.grid_pos + step
		if _is_valid_tile(new_pos):
			unit.grid_pos = new_pos

	enemy.take_damage(damage)
	unit.action_points -= art.action_cost
	_refresh_all()
	_log("[%s] 시전! %s에게 %d 피해!" % [art.display_name, enemy.display_name, damage])
	_check_victory()


func _relationship_bonus(enemy: CombatUnit) -> float:
	return RelationshipManager.get_combat_damage_bonus(
		GameManager.player_relationships,
		enemy.character.id
	)


func _is_valid_tile(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= GRID_WIDTH or pos.y < 0 or pos.y >= GRID_HEIGHT:
		return false
	if _setup.blocked_tiles.has(pos):
		return false
	for unit in _units:
		if unit.is_alive() and unit.grid_pos == pos:
			return false
	return true


func _check_victory() -> void:
	if not _combat_over and _get_alive_enemies().is_empty():
		_end_combat(CombatManager.Outcome.VICTORY)


func _end_combat(outcome: CombatManager.Outcome) -> void:
	if _combat_over:
		return
	_combat_over = true
	var result: Dictionary = GameManager.finish_combat(outcome)
	back_button.text = "문파로 돌아가기"
	_refresh_all()
	_log(result["message"])


## 적 한 명의 행동: 인접하면 공격, 아니면 플레이어 쪽으로 한 칸 이동한다.
func _run_enemy_ai(enemy: CombatUnit) -> void:
	var player := _get_player()
	if player == null or not enemy.is_alive() or not player.is_alive():
		return
	if enemy.action_points < 1:
		return

	if _distance(player.grid_pos, enemy.grid_pos) == 1:
		var damage := enemy.get_attack_damage(_Balance.ENEMY_BASE_ATTACK_DAMAGE)
		player.take_damage(damage)
		enemy.action_points -= 1
		_log("%s의 공격! %d 피해" % [enemy.display_name, damage])
		if not player.is_alive():
			_end_combat(CombatManager.Outcome.DEFEAT)
		return

	var dx := player.grid_pos.x - enemy.grid_pos.x
	var dy := player.grid_pos.y - enemy.grid_pos.y
	var primary := Vector2i(signi(dx), 0) if absi(dx) >= absi(dy) else Vector2i(0, signi(dy))
	var secondary := Vector2i(0, signi(dy)) if absi(dx) >= absi(dy) else Vector2i(signi(dx), 0)
	for step in [primary, secondary]:
		if step == Vector2i.ZERO:
			continue
		var next_pos: Vector2i = enemy.grid_pos + step
		if _is_valid_tile(next_pos):
			enemy.grid_pos = next_pos
			enemy.action_points -= 1
			return


## 플레이어 차례가 돌아올 때까지 적 턴을 진행한다.
func _run_enemy_turns() -> void:
	var current := _turn_manager.get_current_unit()
	var guard: int = _units.size() + 1
	while current and not current.is_player and not _combat_over and guard > 0:
		_run_enemy_ai(current)
		current = _turn_manager.end_turn()
		guard -= 1
	_refresh_all()
	if current and not _combat_over:
		_log("%s의 턴입니다." % current.display_name)


func _on_end_turn_pressed() -> void:
	if _combat_over:
		return
	var current := _turn_manager.get_current_unit()
	if current and current.is_player:
		_turn_manager.end_turn()
		_run_enemy_turns()


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
	# 전투 중에 나가면 후퇴로 처리한다.
	if not _combat_over:
		_end_combat(CombatManager.Outcome.RETREAT)
	SceneRouter.goto(get_tree(), SceneRouter.HUB)
