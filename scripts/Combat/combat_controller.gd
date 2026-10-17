extends Node2D

const _Balance = preload("res://scripts/Systems/game_balance.gd")
const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

const GRID_SIZE := 48
const GRID_WIDTH := 16
const GRID_HEIGHT := 10

const TERRAIN_COLORS: Dictionary = {
	CombatRules.Terrain.PLAIN: Color(0.12, 0.15, 0.12),
	CombatRules.Terrain.FOREST: Color(0.1, 0.3, 0.12),
	CombatRules.Terrain.WATER: Color(0.12, 0.22, 0.4),
	CombatRules.Terrain.HIGH: Color(0.35, 0.3, 0.18),
}

enum ActionMode { MOVE, ATTACK, MARTIAL_ART }

var _setup: CombatSetup
var _units: Array[CombatUnit] = []
var _turn_manager := TurnManager.new()
var _action_mode: ActionMode = ActionMode.MOVE
var _selected_art: MartialArtData = null
var _combat_over: bool = false
## 무공 버튼을 만든 대상 (조종 중인 유닛이 바뀌면 다시 만든다)
var _art_buttons_owner: CombatUnit = null

@onready var grid_overlay: Node2D = $GridOverlay
@onready var units_layer: Node2D = $UnitsLayer
@onready var title_label: Label = %TitleLabel
@onready var terrain_label: Label = %TerrainLabel
@onready var round_label: Label = %RoundLabel
@onready var turn_label: Label = %TurnLabel
@onready var player_hp_label: Label = %PlayerHPLabel
@onready var enemy_hp_label: Label = %EnemyHPLabel
@onready var ap_label: Label = %APLabel
@onready var martial_label: Label = %MartialLabel
@onready var art_list: VBoxContainer = %ArtList
@onready var log_label: Label = %LogLabel
@onready var back_button: Button = %BackButton


func _ready() -> void:
	_UiTheme.apply_to_control($HUD/Panel)
	_setup = GameManager.get_or_create_combat_setup()
	_setup_combat()
	title_label.text = _setup.title
	terrain_label.text = (
		"지형 — 수풀: 이동 %d, 받는 피해 %d%% | 물: 이동 %d, 주는 피해 %d%% | 고지: 이동 %d, 주는 피해 %d%%, 원거리 사거리 +%d"
		% [
			_Balance.FOREST_MOVE_COST, int(_Balance.FOREST_DEFENSE * 100),
			_Balance.WATER_MOVE_COST, int(_Balance.WATER_ATTACK * 100),
			_Balance.HIGH_MOVE_COST, int(_Balance.HIGH_ATTACK * 100), _Balance.HIGH_RANGE_BONUS,
		]
	)
	back_button.text = "후퇴"
	_log("전투 시작! %s" % _setup.title)
	if not _setup.allies.is_empty():
		var names: PackedStringArray = []
		for ally in _setup.allies:
			names.append(ally.display_name)
		_log("전투 시작! %s — %s이(가) 함께 싸웁니다. 아군은 차례가 오면 직접 조종합니다." % [
			_setup.title, ", ".join(names),
		])
	_advance_turns()


func _setup_combat() -> void:
	var player_unit := CombatUnit.new(GameManager.player_character, true)
	player_unit.grid_pos = _setup.player_position
	_units.append(player_unit)

	for i in _setup.allies.size():
		var ally_unit := CombatUnit.new(_setup.allies[i], false, true)
		ally_unit.grid_pos = _setup.ally_positions[i]
		_units.append(ally_unit)

	for i in _setup.enemies.size():
		var enemy_unit := CombatUnit.new(_setup.enemies[i], false)
		enemy_unit.grid_pos = _setup.enemy_positions[i]
		var strength: float = ScenarioRules.enemy_strength_scale()
		enemy_unit.scale_stats(_setup.enemy_hp_scale * strength, _setup.enemy_damage_scale * strength)
		_units.append(enemy_unit)

	_turn_manager.setup(_units)


# ─── 조회 ───────────────────────────────────────────

func _get_player() -> CombatUnit:
	for unit in _units:
		if unit.is_player:
			return unit
	return null


func _get_alive_enemies() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in _units:
		if not unit.is_friendly() and unit.is_alive():
			result.append(unit)
	return result


func _get_alive_friendlies() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in _units:
		if unit.is_friendly() and unit.is_alive():
			result.append(unit)
	return result


func _get_friendly_at(coord: Vector2i) -> CombatUnit:
	for unit in _get_alive_friendlies():
		if unit.grid_pos == coord:
			return unit
	return null


## 지금 조종 중인 아군 유닛 (적 차례이거나 전투가 끝났으면 null)
func _get_controlled() -> CombatUnit:
	if _combat_over:
		return null
	var current := _turn_manager.get_current_unit()
	return current if current and current.is_friendly() else null


func _count_fallen_allies() -> int:
	var fallen: int = 0
	for unit in _units:
		if unit.is_ally and not unit.is_alive():
			fallen += 1
	return fallen


func _get_enemy_at(coord: Vector2i) -> CombatUnit:
	for unit in _get_alive_enemies():
		if unit.grid_pos == coord:
			return unit
	return null


func _terrain_at(pos: Vector2i) -> CombatRules.Terrain:
	return _setup.get_terrain(pos)


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_WIDTH and pos.y >= 0 and pos.y < GRID_HEIGHT


## 벽·격자 밖·살아 있는 유닛이 없는 칸
func _is_valid_tile(pos: Vector2i) -> bool:
	if not _in_bounds(pos) or _setup.blocked_tiles.has(pos):
		return false
	for unit in _units:
		if unit.is_alive() and unit.grid_pos == pos:
			return false
	return true


func _get_reachable(unit: CombatUnit) -> Dictionary:
	return CombatRules.reachable_tiles(unit.grid_pos, unit.action_points, _is_valid_tile, _terrain_at)


# ─── 화면 ───────────────────────────────────────────

func _refresh_all() -> void:
	_draw_grid()
	_refresh_units_visual()
	_update_hud()


func _draw_grid() -> void:
	for child in grid_overlay.get_children():
		child.queue_free()

	var controlled := _get_controlled()
	var reachable: Dictionary = {}
	var art_range: int = -1
	if controlled:
		if _action_mode == ActionMode.MOVE:
			reachable = _get_reachable(controlled)
		elif _action_mode == ActionMode.MARTIAL_ART and _selected_art:
			art_range = CombatRules.get_art_range(_selected_art, _terrain_at(controlled.grid_pos))

	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var coord := Vector2i(x, y)
			var tile := ColorRect.new()
			tile.size = Vector2(GRID_SIZE - 2, GRID_SIZE - 2)
			tile.position = Vector2(x * GRID_SIZE + 1, y * GRID_SIZE + 1)
			if _setup.blocked_tiles.has(coord):
				tile.color = Color(0.35, 0.2, 0.2)
			else:
				tile.color = TERRAIN_COLORS[_terrain_at(coord)]
				if reachable.has(coord):
					tile.color = tile.color.lerp(Color(0.4, 0.8, 0.4), 0.35)
				elif art_range >= 0 and CombatRules.distance(coord, controlled.grid_pos) <= art_range:
					tile.color = tile.color.lerp(Color(0.75, 0.3, 0.85), 0.45)
			grid_overlay.add_child(tile)


func _refresh_units_visual() -> void:
	for child in units_layer.get_children():
		child.queue_free()

	for unit in _units:
		if not unit.is_alive():
			continue
		var marker := ColorRect.new()
		marker.size = Vector2(28, 28)
		marker.position = Vector2(unit.grid_pos.x * GRID_SIZE + 10, unit.grid_pos.y * GRID_SIZE + 10)
		if unit.is_player:
			marker.color = Color(0.3, 0.7, 1)
		elif unit.is_ally:
			marker.color = Color(0.35, 0.85, 0.65)
		else:
			marker.color = Color(0.9, 0.3, 0.2)
		if unit == _get_controlled():
			var outline := ColorRect.new()
			outline.size = Vector2(36, 36)
			outline.position = marker.position - Vector2(4, 4)
			outline.color = _UiTheme.COLORS["accent_gold"]
			units_layer.add_child(outline)
		if unit.has_status("stunned"):
			marker.color = marker.color.darkened(0.5)
		units_layer.add_child(marker)

		var name_label := Label.new()
		name_label.text = unit.display_name
		name_label.position = marker.position + Vector2(-4, -18)
		name_label.add_theme_font_size_override("font_size", 11)
		units_layer.add_child(name_label)


func _update_hud() -> void:
	var current := _turn_manager.get_current_unit()
	var controlled := _get_controlled()

	round_label.text = "라운드 %d" % _turn_manager.round_number
	if current:
		turn_label.text = "현재 턴: %s%s" % [current.display_name, " (조종)" if controlled else ""]

	var friend_lines: PackedStringArray = []
	for unit in _units:
		if unit.is_friendly():
			friend_lines.append(_unit_line(unit))
	player_hp_label.text = "\n".join(friend_lines)

	var enemy_lines: PackedStringArray = []
	for unit in _units:
		if not unit.is_friendly():
			enemy_lines.append(_unit_line(unit))
	enemy_hp_label.text = "\n".join(enemy_lines)

	var shown: CombatUnit = controlled if controlled else _get_player()
	ap_label.text = "%s — 행동력: %d / %d | 내공: %d / %d | 지형: %s" % [
		shown.display_name,
		shown.action_points,
		shown.max_action_points,
		shown.character.internal_energy_current,
		shown.character.internal_energy_max,
		CombatRules.TERRAIN_NAMES[_terrain_at(shown.grid_pos)],
	]
	if _selected_art:
		var amount: int = _selected_art.damage if _selected_art.heal_amount <= 0 else _selected_art.heal_amount
		martial_label.text = "선택 무공: %s (%s %d, 사거리 %d, 내공 %d, 행동력 %d)\n효과: %s" % [
			_selected_art.display_name,
			"피해" if _selected_art.heal_amount <= 0 else "회복",
			amount,
			_selected_art.range,
			_selected_art.internal_cost,
			_selected_art.action_cost,
			_selected_art.get_effects_text(),
		]
	else:
		martial_label.text = "무공: %s" % ("없음" if shown.get_martial_arts().is_empty() else "선택 안 함")

	if controlled != _art_buttons_owner:
		_build_art_buttons(controlled)


func _unit_line(unit: CombatUnit) -> String:
	if not unit.is_alive():
		return "%s — 쓰러짐" % unit.display_name
	var status: String = unit.get_status_text()
	return "%s HP: %d / %d%s" % [
		unit.display_name, unit.hp, unit.max_hp, " [%s]" % status if not status.is_empty() else "",
	]


## 조종 중인 유닛의 무공으로 버튼을 만든다. 유닛이 바뀌면 선택 무공도 초기화한다.
func _build_art_buttons(unit: CombatUnit) -> void:
	_art_buttons_owner = unit
	_selected_art = null
	if _action_mode == ActionMode.MARTIAL_ART:
		_action_mode = ActionMode.MOVE
	for child in art_list.get_children():
		art_list.remove_child(child)
		child.queue_free()
	if unit == null:
		return
	for art in unit.get_martial_arts():
		var button := Button.new()
		button.text = "%s (내공 %d · 행동력 %d)" % [art.display_name, art.internal_cost, art.action_cost]
		_UiTheme.style_button(button)
		button.pressed.connect(_on_art_pressed.bind(art))
		art_list.add_child(button)


func _log(message: String) -> void:
	log_label.text = message
	EventBus.action_message.emit(message)


# ─── 플레이어 입력 ───────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _combat_over:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var current := _get_controlled()
	if current == null:
		return

	var local_pos := get_global_mouse_position() - global_position
	var target := Vector2i(int(local_pos.x / GRID_SIZE), int(local_pos.y / GRID_SIZE))
	if not _in_bounds(target):
		return

	match _action_mode:
		ActionMode.MOVE:
			_try_move(current, target)
		ActionMode.ATTACK:
			_try_attack(current, target)
		ActionMode.MARTIAL_ART:
			_try_martial_art(current, target)


func _try_move(unit: CombatUnit, target: Vector2i) -> void:
	var reachable: Dictionary = _get_reachable(unit)
	if not reachable.has(target):
		_log("이동할 수 없는 위치입니다.")
		return
	unit.grid_pos = target
	unit.action_points -= reachable[target]
	_refresh_all()
	_log("이동 완료. (%s, 행동력 -%d)" % [CombatRules.TERRAIN_NAMES[_terrain_at(target)], reachable[target]])


func _try_attack(unit: CombatUnit, target: Vector2i) -> void:
	var enemy := _get_enemy_at(target)
	if enemy == null or CombatRules.distance(target, unit.grid_pos) > 1:
		_log("인접한 적에게만 공격할 수 있습니다.")
		return
	if unit.action_points < 1:
		_log("행동력이 부족합니다.")
		return
	_perform_attack(unit, enemy)


func _try_martial_art(unit: CombatUnit, target: Vector2i) -> void:
	var art := _selected_art
	if art == null:
		_log("사용할 무공을 먼저 고르세요.")
		return
	var art_range: int = CombatRules.get_art_range(art, _terrain_at(unit.grid_pos))
	if art.heal_amount > 0:
		var friend := _get_friendly_at(target)
		if friend == null or CombatRules.distance(target, unit.grid_pos) > art_range:
			_log("사거리 안의 아군(자신 포함)을 선택하세요. (사거리 %d)" % art_range)
			return
		_perform_art(unit, friend, art)
		return
	var enemy := _get_enemy_at(target)
	if enemy == null or CombatRules.distance(target, unit.grid_pos) > art_range:
		_log("사거리 안의 적을 선택하세요. (사거리 %d)" % art_range)
		return
	_perform_art(unit, enemy, art)


# ─── 공통 행동 (플레이어·적) ──────────────────────────

func _relationship_bonus(attacker: CombatUnit, defender: CombatUnit) -> float:
	if not attacker.is_player:
		return 1.0
	return RelationshipManager.get_combat_damage_bonus(
		GameManager.player_relationships, defender.character.id
	)


func _perform_attack(attacker: CombatUnit, defender: CombatUnit) -> void:
	var result: Dictionary = CombatRules.calculate_damage(
		attacker, defender, null,
		_terrain_at(attacker.grid_pos), _terrain_at(defender.grid_pos),
		_relationship_bonus(attacker, defender)
	)
	defender.take_damage(result["damage"])
	attacker.action_points -= 1
	_log("%s의 공격! %s에게 %d 피해%s" % [
		attacker.display_name, defender.display_name, result["damage"], _notes_text(result["notes"]),
	])
	_after_hit(defender)


## 무공 시전. 회복 무공이면 defender는 회복 대상(null이면 자신). 시전하면 true.
func _perform_art(attacker: CombatUnit, defender: CombatUnit, art: MartialArtData) -> bool:
	if attacker.action_points < art.action_cost:
		_log("행동력이 부족합니다.")
		return false
	if not attacker.character.spend_internal_energy(art.internal_cost):
		_log("내공이 부족합니다.")
		return false
	attacker.action_points -= art.action_cost
	attacker.active_martial_art = art
	var effects: Array[MartialArtData.SpecialEffect] = art.special_effects
	var messages: PackedStringArray = []

	if art.heal_amount > 0:
		var patient: CombatUnit = defender if defender else attacker
		defender = null
		var multiplier: float = 1.0
		if attacker.is_player:
			multiplier = RelationshipManager.get_ally_buff_multiplier(GameManager.player_relationships)
		var heal := int(art.heal_amount * multiplier)
		patient.heal(heal)
		messages.append("[%s] %s, HP %d 회복" % [art.display_name, patient.display_name, heal])
	else:
		var result: Dictionary = CombatRules.calculate_damage(
			attacker, defender, art,
			_terrain_at(attacker.grid_pos), _terrain_at(defender.grid_pos),
			_relationship_bonus(attacker, defender)
		)
		var damage: int = result["damage"]
		messages.append("[%s] %s → %s %d 피해%s" % [
			art.display_name, attacker.display_name, defender.display_name, damage,
			_notes_text(result["notes"]),
		])

		# 파괴력: 대상을 한 칸 밀어낸다. 벽이나 유닛에 막히면 추가 피해.
		if effects.has(MartialArtData.SpecialEffect.DESTRUCTION):
			var push: Vector2i = _step_toward(attacker.grid_pos, defender.grid_pos)
			var landing: Vector2i = defender.grid_pos + push
			if _is_valid_tile(landing):
				defender.grid_pos = landing
				messages.append("밀려남")
			else:
				var extra := int(damage * _Balance.KNOCKBACK_WALL_BONUS)
				damage += extra
				messages.append("부딪혀 %d 추가 피해" % extra)
		defender.take_damage(damage)

		# 제어: 대상을 기절시킨다. 막 풀려난 대상은 저항한다.
		if effects.has(MartialArtData.SpecialEffect.CONTROL) and defender.is_alive():
			if defender.has_status("stun_immune"):
				messages.append("%s 기절 저항" % defender.display_name)
			else:
				defender.add_status("stunned", _Balance.STUN_TURNS)
				defender.add_status("stun_immune", _Balance.STUN_IMMUNE_TURNS)
				messages.append("%s 기절!" % defender.display_name)

		# 이동: 적 쪽으로 한 칸 파고든다.
		if effects.has(MartialArtData.SpecialEffect.MOVE) and defender.is_alive():
			var dash: Vector2i = attacker.grid_pos + _step_toward(attacker.grid_pos, defender.grid_pos)
			if _is_valid_tile(dash):
				attacker.grid_pos = dash

	if effects.has(MartialArtData.SpecialEffect.BUFF):
		attacker.add_status("empowered", _Balance.EMPOWER_TURNS)
		messages.append("기세 상승")

	var backlash: int = CombatRules.roll_overload(attacker.character, art)
	if backlash > 0:
		attacker.take_damage(backlash)
		messages.append("내공 폭주! %s 반동 %d 피해" % [attacker.display_name, backlash])

	_log(", ".join(messages))
	if defender:
		_after_hit(defender)
	if not _combat_over and not attacker.is_alive():
		_after_hit(attacker)
	_refresh_all()
	return true


## 주 축 기준으로 from에서 to 쪽 한 칸 방향
static func _step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var diff: Vector2i = to - from
	if absi(diff.x) >= absi(diff.y):
		return Vector2i(signi(diff.x), 0)
	return Vector2i(0, signi(diff.y))


static func _notes_text(notes: PackedStringArray) -> String:
	return " (%s)" % ", ".join(notes) if not notes.is_empty() else ""


## 피해를 받은 유닛의 생사에 따라 승패를 정한다. 아군이 쓰러져도 주인공이 살아 있으면 계속한다.
func _after_hit(unit: CombatUnit) -> void:
	_refresh_all()
	if unit.is_player and not unit.is_alive():
		_end_combat(CombatManager.Outcome.DEFEAT)
	elif unit.is_ally and not unit.is_alive():
		_log("%s이(가) 쓰러졌습니다!" % unit.display_name)
	else:
		_check_victory()


func _check_victory() -> void:
	if not _combat_over and _get_alive_enemies().is_empty():
		_end_combat(CombatManager.Outcome.VICTORY)


func _end_combat(outcome: CombatManager.Outcome) -> void:
	if _combat_over:
		return
	_combat_over = true
	var result: Dictionary = GameManager.finish_combat(outcome, _count_fallen_allies())
	back_button.text = "문파로 돌아가기"
	_refresh_all()
	_log(result["message"])


# ─── 적 AI ─────────────────────────────────────────

## 적이 노릴 대상: 가장 가까운 아군, 거리가 같으면 체력이 낮은 쪽
func _pick_enemy_target(enemy: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	for unit in _get_alive_friendlies():
		if best == null:
			best = unit
			continue
		var d: int = CombatRules.distance(enemy.grid_pos, unit.grid_pos)
		var best_d: int = CombatRules.distance(enemy.grid_pos, best.grid_pos)
		if d < best_d or (d == best_d and unit.hp < best.hp):
			best = unit
	return best


## 적 한 명의 차례: 공격할 수 있으면 공격하고, 아니면 다가간 뒤 공격을 시도한다.
## 공격은 차례당 한 번이다.
func _run_enemy_ai(enemy: CombatUnit) -> void:
	var target := _pick_enemy_target(enemy)
	if target == null or not enemy.is_alive():
		return
	if _enemy_try_attack(enemy, target):
		return

	var art: MartialArtData = _enemy_usable_art(enemy)
	var desired_range: int = art.range if art else 1
	var is_goal := func(pos: Vector2i) -> bool:
		return CombatRules.distance(pos, target.grid_pos) <= desired_range
	var path: Array[Vector2i] = CombatRules.find_path(enemy.grid_pos, is_goal, _is_valid_tile, _terrain_at)
	if not path.is_empty():
		# 공격할 행동력 1은 남겨 둔다.
		var walk: Dictionary = CombatRules.walk_path(path, enemy.action_points - 1, _terrain_at)
		if walk["index"] >= 0:
			enemy.grid_pos = path[walk["index"]]
			enemy.action_points -= walk["cost"]
	_enemy_try_attack(enemy, target)


func _enemy_usable_art(enemy: CombatUnit) -> MartialArtData:
	for art in enemy.get_martial_arts():
		if art.heal_amount > 0:
			continue
		if enemy.action_points >= art.action_cost and enemy.character.internal_energy_current >= art.internal_cost:
			return art
	return null


func _enemy_try_attack(enemy: CombatUnit, target: CombatUnit) -> bool:
	var art: MartialArtData = _enemy_usable_art(enemy)
	var dist: int = CombatRules.distance(enemy.grid_pos, target.grid_pos)
	if art and dist <= CombatRules.get_art_range(art, _terrain_at(enemy.grid_pos)):
		return _perform_art(enemy, target, art)
	if dist == 1 and enemy.action_points >= 1:
		_perform_attack(enemy, target)
		return true
	return false


# ─── 턴 진행 ────────────────────────────────────────

## 아군 차례가 올 때까지 적 턴과 기절한 유닛의 턴을 처리한다.
func _advance_turns() -> void:
	var guard: int = _units.size() * 4
	while not _combat_over and guard > 0:
		guard -= 1
		var current := _turn_manager.get_current_unit()
		if current == null:
			break
		if not current.is_alive():
			_turn_manager.end_turn()
			continue
		if current.has_status("stunned"):
			_log("%s은(는) 기절해 차례를 넘깁니다." % current.display_name)
			current.tick_statuses()
			_turn_manager.end_turn()
			continue
		if current.is_friendly():
			break
		_run_enemy_ai(current)
		current.tick_statuses()
		_turn_manager.end_turn()
	_refresh_all()


func _on_end_turn_pressed() -> void:
	if _combat_over:
		return
	var current := _get_controlled()
	if current:
		current.tick_statuses()
		_turn_manager.end_turn()
		_advance_turns()
		var next := _get_controlled()
		if next:
			_log("%s의 차례입니다." % next.display_name)


func _on_mode_move_pressed() -> void:
	_action_mode = ActionMode.MOVE
	_refresh_all()
	_log("행동: 이동 (초록 칸)")


func _on_mode_attack_pressed() -> void:
	_action_mode = ActionMode.ATTACK
	_refresh_all()
	_log("행동: 기본 공격")


func _on_art_pressed(art: MartialArtData) -> void:
	var current := _get_controlled()
	if current == null:
		return
	_selected_art = art
	_action_mode = ActionMode.MARTIAL_ART
	if art.heal_amount > 0:
		# 함께 싸우는 아군이 없으면 대상을 고를 필요 없이 자신에게 바로 쓴다.
		if _get_alive_friendlies().size() == 1:
			_perform_art(current, current, art)
			return
		_refresh_all()
		_log("행동: [%s] — 회복할 아군(자신 포함)을 누르세요 (보라 칸)" % art.display_name)
		return
	_refresh_all()
	_log("행동: [%s] — 사거리 안의 적을 누르세요 (보라 칸)" % art.display_name)


func _on_back_pressed() -> void:
	# 전투 중에 나가면 후퇴로 처리한다.
	if not _combat_over:
		_end_combat(CombatManager.Outcome.RETREAT)
	SceneRouter.goto(get_tree(), SceneRouter.HUB)
