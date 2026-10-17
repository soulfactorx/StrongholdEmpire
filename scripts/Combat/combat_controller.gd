extends Node2D

const _Balance = preload("res://scripts/Systems/game_balance.gd")
const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

const GRID_SIZE := 48
const GRID_WIDTH := 16
const GRID_HEIGHT := 10

## 지형 그림이 없을 때 쓰는 색
const TERRAIN_COLORS: Dictionary = {
	CombatRules.Terrain.PLAIN: Color("#e6dcc4"),
	CombatRules.Terrain.FOREST: Color("#b9c7a8"),
	CombatRules.Terrain.WATER: Color("#a9b8c4"),
	CombatRules.Terrain.HIGH: Color("#d2b88c"),
}
## 이동할 수 있는 칸·무공 사거리 칸에 덧칠하는 색
const REACHABLE_TINT := Color(0.18, 0.42, 0.37, 0.35)
const ART_RANGE_TINT := Color(0.7, 0.23, 0.17, 0.32)
## 장기말 크기와 칸 안 여백
const TOKEN_SIZE := 44.0

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
@onready var undo_move_button: Button = %UndoMoveButton
@onready var end_turn_button: Button = %EndTurnButton
## 되돌릴 수 있는 마지막 이동 {unit, from, ap}. 공격·무공·턴 종료 뒤에는 되돌릴 수 없다
var _last_move: Dictionary = {}
## 적이 움직이는 중 (전투 속도 옵션의 간격을 두고). 이때는 입력을 받지 않는다
var _enemy_acting: bool = false
const _ConfirmPopup = preload("res://scripts/UI/confirm_popup.gd")
## 후퇴 확인 대화상자 (처음 쓸 때 만든다)
var confirm_popup: Control
## 격자 커서 (키보드 방향키·게임패드로 칸을 고른다). 터치·마우스를 쓰면 숨긴다.
var cursor: Vector2i = Vector2i.ZERO
var cursor_visible: bool = false
var _cursor_layer: Node2D
## 왼쪽 스틱을 한 번 기울일 때 한 칸만 움직이도록 직전 방향을 기억한다
var _stick_dir: Vector2i = Vector2i.ZERO


func _ready() -> void:
	ArtAssets.apply_background(self)
	# 바탕이 터치·클릭을 가로채면 격자로 입력이 오지 않는다.
	$Background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# HUD는 CanvasLayer 아래라 창 테마가 이어지지 않으므로 직접 준다.
	$HUD/Panel.theme = get_tree().root.theme
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
	LongPressTip.attach(ap_label, func() -> String:
		return "행동력: 차례마다 다시 찹니다.\n이동은 칸마다 1 (수풀 %d, 물 %d, 고지 %d), 기본 공격 1 (차례에 한 번), 무공은 버튼에 적힌 만큼 듭니다.\n이동한 뒤 공격·무공을 쓰기 전이면 [이동 취소]로 되돌릴 수 있습니다." % [
			_Balance.FOREST_MOVE_COST, _Balance.WATER_MOVE_COST, _Balance.HIGH_MOVE_COST,
		]
	)
	LongPressTip.attach(martial_label, func() -> String:
		if _selected_art:
			return "%s\n%s" % [_selected_art.display_name, _selected_art.description]
		return "무공 버튼(또는 숫자 키)을 누른 뒤 사거리 안(붉은 칸)의 대상을 고르세요.\n오행 상극(목→토→수→화→금→목)이면 피해 +%d%%." % int((_Balance.ELEMENT_ADVANTAGE - 1.0) * 100)
	)
	_log("전투 시작! %s" % _setup.title)
	AudioManager.play_battle_start()
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
	if _enemy_acting:
		return null
	var current := _turn_manager.get_current_unit()
	return current if current and current.is_friendly() else null


## 쓰러진 아군의 id (명단 제자를 전사 처리할 때 쓴다)
func _get_fallen_ally_ids() -> Array:
	var ids: Array = []
	for unit in _units:
		if unit.is_ally and not unit.is_alive():
			ids.append(unit.character.id)
	return ids


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
	_draw_cursor()
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
			var rect := Rect2(x * GRID_SIZE + 1, y * GRID_SIZE + 1, GRID_SIZE - 2, GRID_SIZE - 2)
			var blocked: bool = _setup.blocked_tiles.has(coord)
			var terrain: int = _terrain_at(coord)
			var tex: Texture2D = ArtAssets.tile("wall" if blocked else ArtAssets.TERRAIN_TILES.get(terrain, "plain"))
			if tex:
				var tile := TextureRect.new()
				tile.texture = tex
				tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tile.position = rect.position
				tile.size = rect.size
				tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid_overlay.add_child(tile)
			else:
				var plain := ColorRect.new()
				plain.position = rect.position
				plain.size = rect.size
				plain.color = Color("#3a332b") if blocked else TERRAIN_COLORS[terrain]
				plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid_overlay.add_child(plain)
			if blocked:
				continue
			var tint := Color.TRANSPARENT
			if reachable.has(coord):
				tint = REACHABLE_TINT
			elif art_range >= 0 and CombatRules.distance(coord, controlled.grid_pos) <= art_range:
				tint = ART_RANGE_TINT
			if tint.a > 0.0:
				var overlay := ColorRect.new()
				overlay.position = rect.position
				overlay.size = rect.size
				overlay.color = tint
				overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid_overlay.add_child(overlay)


func _refresh_units_visual() -> void:
	for child in units_layer.get_children():
		child.queue_free()

	for unit in _units:
		if not unit.is_alive():
			continue
		units_layer.add_child(_make_token(unit, unit == _get_controlled()))


## 장기말: 아군은 둥근 말(주인공 금테·동료 옥색 테), 적은 팔각 말(주홍 테).
## 가운데에 이름 첫 글자를 붓글씨로 쓰고, 말 아래에 이름을 단다.
func _make_token(unit: CombatUnit, controlled: bool) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset: float = (GRID_SIZE - TOKEN_SIZE) / 2.0
	holder.position = Vector2(unit.grid_pos.x * GRID_SIZE + inset, unit.grid_pos.y * GRID_SIZE + inset)
	holder.size = Vector2(TOKEN_SIZE, TOKEN_SIZE)
	var kind: String = "player" if unit.is_player else ("ally" if unit.is_ally else "enemy")
	# 장기말 그림은 가운데가 비어 있으므로 한지색 원을 깔아 글자가 지형 위에서도 보이게 한다.
	var face := Panel.new()
	var face_style := StyleBoxFlat.new()
	face_style.bg_color = Color(_UiTheme.COLORS["bg_panel"], 0.92)
	face_style.set_corner_radius_all(int(TOKEN_SIZE * 0.4))
	face.add_theme_stylebox_override("panel", face_style)
	face.position = holder.size * 0.1
	face.size = holder.size * 0.8
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(face)
	var body := TextureRect.new()
	body.texture = ArtAssets.token(kind)
	body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	body.size = holder.size
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unit.has_status("stunned"):
		body.modulate = Color(0.55, 0.55, 0.55)
	holder.add_child(body)
	if controlled:
		var ring := TextureRect.new()
		ring.texture = ArtAssets.token("highlight")
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.position = Vector2(-5, -5)
		ring.size = holder.size + Vector2(10, 10)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(ring)

	var glyph := Label.new()
	glyph.text = unit.display_name.left(1)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.size = holder.size
	glyph.add_theme_font_size_override("font_size", 26)
	glyph.add_theme_color_override("font_color", _UiTheme.COLORS["accent_red"] if kind == "enemy" else _UiTheme.COLORS["text_primary"])
	var brush: Font = ArtAssets.brush_font()
	if brush:
		glyph.add_theme_font_override("font", brush)
		glyph.add_theme_font_size_override("font_size", 34)
	holder.add_child(glyph)

	var name_label := Label.new()
	name_label.text = unit.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-18, TOKEN_SIZE - 8)
	name_label.size = Vector2(TOKEN_SIZE + 36, 14)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", _UiTheme.COLORS["text_on_ink"])
	name_label.add_theme_color_override("font_outline_color", _UiTheme.COLORS["text_primary"])
	name_label.add_theme_constant_override("outline_size", 4)
	holder.add_child(name_label)
	return holder


## 격자 커서: 금빛 테두리. 커서를 쓰는 동안에만 보인다.
func _draw_cursor() -> void:
	if _cursor_layer == null:
		_cursor_layer = Node2D.new()
		_cursor_layer.name = "CursorLayer"
		add_child(_cursor_layer)
		move_child(_cursor_layer, units_layer.get_index() + 1)
	for child in _cursor_layer.get_children():
		child.queue_free()
	if not cursor_visible:
		return
	var frame := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(_UiTheme.COLORS["accent_gold"], 0.2)
	style.border_color = _UiTheme.COLORS["accent_gold"]
	style.set_border_width_all(4)
	style.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", style)
	frame.position = Vector2(cursor.x * GRID_SIZE - 1, cursor.y * GRID_SIZE - 1)
	frame.size = Vector2(GRID_SIZE + 2, GRID_SIZE + 2)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_layer.add_child(frame)


func _update_hud() -> void:
	var current := _turn_manager.get_current_unit()
	var controlled := _get_controlled()

	round_label.text = "라운드 %d" % _turn_manager.round_number
	undo_move_button.disabled = _last_move.is_empty() or controlled == null or _last_move["unit"] != controlled
	end_turn_button.disabled = _combat_over or controlled == null
	# 기본 공격은 차례에 한 번
	$HUD/Panel/VBox/ModeRow/ModeAttackButton.disabled = _combat_over or controlled == null or not controlled.can_basic_attack()
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
	var arts: Array = unit.get_martial_arts()
	for i in arts.size():
		var art: MartialArtData = arts[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 48)
		# 숫자 키로 고를 수 있다 (1~9)
		button.text = "%s%s (내공 %d · 행동력 %d)" % [
			"%d. " % (i + 1) if i < 9 else "", art.display_name, art.internal_cost, art.action_cost,
		]
		_UiTheme.style_button(button)
		button.pressed.connect(_on_art_pressed.bind(art))
		art_list.add_child(button)


func _log(message: String) -> void:
	log_label.text = message
	EventBus.action_message.emit(message)


# ─── 플레이어 입력 ───────────────────────────────────

## 키보드 단축키: 방향키 커서, Enter 실행, M 이동, A 공격, 1~9 무공, Z 이동 취소, Space·E 턴 종료, Esc 후퇴(확인)
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if confirm_popup and confirm_popup.visible:
		if key.keycode == KEY_ESCAPE:
			confirm_popup._answer(false)
		return
	match key.keycode:
		KEY_LEFT:
			move_cursor(Vector2i.LEFT)
		KEY_RIGHT:
			move_cursor(Vector2i.RIGHT)
		KEY_UP:
			move_cursor(Vector2i.UP)
		KEY_DOWN:
			move_cursor(Vector2i.DOWN)
		KEY_ENTER, KEY_KP_ENTER:
			confirm_cursor()
		KEY_M:
			_on_mode_move_pressed()
		KEY_A:
			_on_mode_attack_pressed()
		KEY_Z:
			_on_undo_move_pressed()
		KEY_SPACE, KEY_E:
			_on_end_turn_pressed()
		KEY_ESCAPE:
			_on_back_pressed()
		_:
			var index: int = key.keycode - KEY_1
			var controlled := _get_controlled()
			if index >= 0 and index < 9 and controlled and index < controlled.get_martial_arts().size():
				_on_art_pressed(controlled.get_martial_arts()[index])
				return
			return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _combat_over:
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if _handle_gamepad(event):
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var current := _get_controlled()
	if current == null:
		return

	# 마우스 커서가 아니라 이벤트 위치로 칸을 구한다. (터치는 커서 위치가 갱신되지 않을 수 있다)
	var local_pos: Vector2 = (make_input_local(event) as InputEventMouseButton).position
	var target := Vector2i(floori(local_pos.x / GRID_SIZE), floori(local_pos.y / GRID_SIZE))
	if not _in_bounds(target):
		return
	# 터치·마우스로 고르면 커서는 숨기고 그 칸으로 옮겨 둔다.
	cursor = target
	cursor_visible = false
	_act_on_tile(current, target)


## 고른 칸에 지금 행동 방식(이동·공격·무공)을 실행한다. 터치·마우스·커서가 함께 쓴다.
func _act_on_tile(current: CombatUnit, target: Vector2i) -> void:
	match _action_mode:
		ActionMode.MOVE:
			_try_move(current, target)
		ActionMode.ATTACK:
			_try_attack(current, target)
		ActionMode.MARTIAL_ART:
			_try_martial_art(current, target)


## 게임패드: 십자키·왼쪽 스틱 커서, A 실행, B 이동 취소, X 공격, Y 이동, LB·RB 무공 고르기,
## Start 턴 종료, Back 후퇴. 처리했으면 true.
func _handle_gamepad(event: InputEvent) -> bool:
	if confirm_popup and confirm_popup.visible:
		return false
	var motion := event as InputEventJoypadMotion
	if motion:
		if motion.axis != JOY_AXIS_LEFT_X and motion.axis != JOY_AXIS_LEFT_Y:
			return false
		var dir := Vector2i.ZERO
		if absf(motion.axis_value) > 0.6:
			var step: int = signi(int(signf(motion.axis_value)))
			dir = Vector2i(step, 0) if motion.axis == JOY_AXIS_LEFT_X else Vector2i(0, step)
		# 기울인 순간에만 한 칸 움직이고, 중앙으로 돌아오면 다시 받는다.
		if dir != Vector2i.ZERO and dir != _stick_dir:
			move_cursor(dir)
		_stick_dir = dir
		return true
	var button := event as InputEventJoypadButton
	if button == null or not button.pressed:
		return false
	match button.button_index:
		JOY_BUTTON_DPAD_LEFT:
			move_cursor(Vector2i.LEFT)
		JOY_BUTTON_DPAD_RIGHT:
			move_cursor(Vector2i.RIGHT)
		JOY_BUTTON_DPAD_UP:
			move_cursor(Vector2i.UP)
		JOY_BUTTON_DPAD_DOWN:
			move_cursor(Vector2i.DOWN)
		JOY_BUTTON_A:
			confirm_cursor()
		JOY_BUTTON_B:
			_on_undo_move_pressed()
		JOY_BUTTON_X:
			_on_mode_attack_pressed()
		JOY_BUTTON_Y:
			_on_mode_move_pressed()
		JOY_BUTTON_LEFT_SHOULDER:
			cycle_art(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			cycle_art(1)
		JOY_BUTTON_START:
			_on_end_turn_pressed()
		JOY_BUTTON_BACK:
			_on_back_pressed()
		_:
			return false
	return true


## 커서를 한 칸 옮긴다. 처음 쓰면 조종 중인 유닛 자리에서 나타난다.
func move_cursor(dir: Vector2i) -> void:
	if _combat_over:
		return
	if not cursor_visible:
		cursor_visible = true
		var controlled := _get_controlled()
		if controlled:
			cursor = controlled.grid_pos
	else:
		var next: Vector2i = cursor + dir
		if _in_bounds(next):
			cursor = next
	# 버튼에 포커스가 있으면 방향 입력을 버튼이 가져가므로 놓는다.
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	_draw_cursor()
	_log(_describe_tile(cursor))


## 커서가 있는 칸에 지금 행동 방식을 실행한다.
func confirm_cursor() -> void:
	var current := _get_controlled()
	if current == null or not cursor_visible:
		return
	_act_on_tile(current, cursor)


## 조종 중인 유닛의 무공을 차례로 고른다 (dir: 1 다음, -1 이전). 마지막 다음은 기본 공격.
func cycle_art(dir: int) -> void:
	var current := _get_controlled()
	if current == null:
		return
	var arts: Array[MartialArtData] = current.get_martial_arts()
	if arts.is_empty():
		_on_mode_attack_pressed()
		return
	# -1은 기본 공격 자리
	var index: int = arts.find(_selected_art) if _action_mode == ActionMode.MARTIAL_ART else -1
	index += dir
	if index >= arts.size():
		index = -1
	elif index < -1:
		index = arts.size() - 1
	if index == -1:
		_on_mode_attack_pressed()
	else:
		_on_art_pressed(arts[index])


## 커서 칸 설명: 좌표·지형과 그 칸의 유닛
func _describe_tile(coord: Vector2i) -> String:
	var parts: PackedStringArray = ["커서 (%d, %d)" % [coord.x, coord.y]]
	if _setup.blocked_tiles.has(coord):
		parts.append("막힌 칸")
	else:
		parts.append(CombatRules.TERRAIN_NAMES[_terrain_at(coord)])
	for unit in _units:
		if unit.is_alive() and unit.grid_pos == coord:
			parts.append("%s %s 체력 %d/%d" % ["아군" if unit.is_friendly() else "적", unit.display_name, unit.hp, unit.max_hp])
	return " · ".join(parts)


func _try_move(unit: CombatUnit, target: Vector2i) -> void:
	var reachable: Dictionary = _get_reachable(unit)
	if not reachable.has(target):
		_log("이동할 수 없는 위치입니다.")
		return
	_last_move = {"unit": unit, "from": unit.grid_pos, "ap": unit.action_points}
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
	if unit.basic_attacks_left <= 0:
		_log("기본 공격은 차례에 한 번만 할 수 있습니다. 남은 행동력은 이동과 무공에 쓰세요.")
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


## 적에게 맞는 쪽의 인연 가호: 인연이 있는 아군 인물은 그 인연만큼, 주인공은 함께 싸우는 가장 깊은 인연만큼 피해가 준다.
func _relationship_defense(attacker: CombatUnit, defender: CombatUnit) -> float:
	if attacker.is_friendly() or not defender.is_friendly():
		return 1.0
	var relationships: Array[RelationshipData] = GameManager.player_relationships
	if defender.is_player:
		var ally_ids: Array = []
		for unit in _units:
			if unit.is_ally and unit.is_alive():
				ally_ids.append(unit.character.id)
		return RelationshipManager.get_defense_modifier(relationships, ally_ids)
	return RelationshipManager.get_defense_modifier(relationships, [defender.character.id])


## 이동 취소: 이번 차례의 마지막 이동을 되돌린다. 공격·무공을 쓴 뒤에는 할 수 없다.
func _on_undo_move_pressed() -> void:
	var current := _get_controlled()
	if _last_move.is_empty() or current == null or _last_move["unit"] != current:
		_log("되돌릴 이동이 없습니다.")
		return
	current.grid_pos = _last_move["from"]
	current.action_points = _last_move["ap"]
	_last_move = {}
	_refresh_all()
	_log("이동을 되돌렸습니다.")


func _perform_attack(attacker: CombatUnit, defender: CombatUnit) -> void:
	_last_move = {}
	var result: Dictionary = CombatRules.calculate_damage(
		attacker, defender, null,
		_terrain_at(attacker.grid_pos), _terrain_at(defender.grid_pos),
		_relationship_bonus(attacker, defender), _relationship_defense(attacker, defender)
	)
	defender.take_damage(result["damage"])
	attacker.action_points -= 1
	attacker.basic_attacks_left -= 1
	AudioManager.play_hit()
	_log("%s의 공격! %s에게 %d 피해%s" % [
		attacker.display_name, defender.display_name, result["damage"], _notes_text(result["notes"]),
	])
	_after_hit(defender)


## 무공 시전. 회복 무공이면 defender는 회복 대상(null이면 자신). 시전하면 true.
func _perform_art(attacker: CombatUnit, defender: CombatUnit, art: MartialArtData) -> bool:
	_last_move = {}
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
			_relationship_bonus(attacker, defender), _relationship_defense(attacker, defender)
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
	AudioManager.play_art()
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
	var level_before: int = GameManager.player_character.level
	var result: Dictionary = GameManager.finish_combat(outcome, _count_fallen_allies(), _get_fallen_ally_ids())
	if GameManager.player_character.level > level_before:
		AudioManager.play_level_up()
	elif outcome == CombatManager.Outcome.VICTORY:
		AudioManager.play_victory()
	elif outcome == CombatManager.Outcome.DEFEAT:
		AudioManager.play_defeat()
	back_button.text = "문파로 돌아가기"
	_refresh_all()
	_log(result["message"])


# ─── 적 AI ─────────────────────────────────────────

## 적이 노릴 대상: 가장 가까운 아군, 거리가 같으면 체력이 낮은 쪽
## 가장 가까운(같으면 체력이 낮은) 상대편 유닛. 적이면 아군 중에서, 아군이면 적 중에서 고른다.
func _pick_enemy_target(enemy: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var candidates: Array[CombatUnit] = _get_alive_enemies() if enemy.is_friendly() else _get_alive_friendlies()
	for unit in candidates:
		if best == null:
			best = unit
			continue
		var d: int = CombatRules.distance(enemy.grid_pos, unit.grid_pos)
		var best_d: int = CombatRules.distance(enemy.grid_pos, best.grid_pos)
		if d < best_d or (d == best_d and unit.hp < best.hp):
			best = unit
	return best


## 적 한 명의 차례: 닿지 않으면 다가간 뒤, 행동력이 남는 동안 무공과 기본 공격(차례에 한 번)을 쓴다.
## 플레이어와 같은 규칙이다. 밸런스 시뮬레이터는 같은 방식으로 아군도 자동으로 움직인다.
func _run_enemy_ai(enemy: CombatUnit) -> void:
	var target := _pick_enemy_target(enemy)
	if target == null or not enemy.is_alive():
		return
	if not _enemy_try_attack(enemy, target):
		_enemy_approach(enemy, target)
	var guard: int = 0
	while not _combat_over and enemy.is_alive() and guard < 8:
		guard += 1
		target = _pick_enemy_target(enemy)
		if target == null or not _enemy_try_attack(enemy, target):
			break


## 대상에게 무공 사거리(없으면 인접)까지 다가간다. 공격할 행동력 1은 남겨 둔다.
func _enemy_approach(enemy: CombatUnit, target: CombatUnit) -> void:

	var art: MartialArtData = _enemy_usable_art(enemy)
	var desired_range: int = art.range if art else 1
	var is_goal := func(pos: Vector2i) -> bool:
		return CombatRules.distance(pos, target.grid_pos) <= desired_range
	var path: Array[Vector2i] = CombatRules.find_path(enemy.grid_pos, is_goal, _is_valid_tile, _terrain_at)
	if not path.is_empty():
		var walk: Dictionary = CombatRules.walk_path(path, enemy.action_points - 1, _terrain_at)
		if walk["index"] >= 0:
			enemy.grid_pos = path[walk["index"]]
			enemy.action_points -= walk["cost"]


## 지금 쓸 수 있는 공격 무공. 시전 뒤 내공이 폭주 기준 아래로 떨어지는 무공은 쓰지 않는다.
func _enemy_usable_art(enemy: CombatUnit) -> MartialArtData:
	var character: CharacterData = enemy.character
	for art in enemy.get_martial_arts():
		if art.heal_amount > 0:
			continue
		var left: int = character.internal_energy_current - art.internal_cost
		if enemy.action_points >= art.action_cost and left >= character.internal_energy_max * _Balance.OVERLOAD_THRESHOLD:
			return art
	return null


func _enemy_try_attack(enemy: CombatUnit, target: CombatUnit) -> bool:
	var art: MartialArtData = _enemy_usable_art(enemy)
	var dist: int = CombatRules.distance(enemy.grid_pos, target.grid_pos)
	if art and dist <= CombatRules.get_art_range(art, _terrain_at(enemy.grid_pos)):
		return _perform_art(enemy, target, art)
	if dist == 1 and enemy.can_basic_attack():
		_perform_attack(enemy, target)
		return true
	return false


# ─── 턴 진행 ────────────────────────────────────────

## 아군 차례가 올 때까지 적 턴과 기절한 유닛의 턴을 처리한다.
## 적 차례를 진행한다. 전투 속도 옵션만큼 적 행동 사이에 간격을 둔다 (0이면 바로).
func _advance_turns() -> void:
	var guard: int = _units.size() * 4
	_last_move = {}
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
		if GameSettings.combat_delay > 0.0:
			_enemy_acting = true
			_refresh_all()
			await get_tree().create_timer(GameSettings.combat_delay).timeout
			if not is_inside_tree() or _combat_over:
				_enemy_acting = false
				return
		_run_enemy_ai(current)
		current.tick_statuses()
		_turn_manager.end_turn()
	_enemy_acting = false
	_refresh_all()


func _on_end_turn_pressed() -> void:
	if _combat_over:
		return
	var current := _get_controlled()
	if current:
		current.tick_statuses()
		_turn_manager.end_turn()
		await _advance_turns()
		var next := _get_controlled()
		if next:
			# 커서를 쓰는 중이면 다음 아군 자리로 옮긴다.
			if cursor_visible:
				cursor = next.grid_pos
				_draw_cursor()
			_log("%s의 차례입니다." % next.display_name)


func _on_mode_move_pressed() -> void:
	_action_mode = ActionMode.MOVE
	_refresh_all()
	_log("행동: 이동 (옥색 칸)")


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
		_log("행동: [%s] — 회복할 아군(자신 포함)을 누르세요 (붉은 칸)" % art.display_name)
		return
	_refresh_all()
	_log("행동: [%s] — 사거리 안의 적을 누르세요 (붉은 칸)" % art.display_name)


func _on_back_pressed() -> void:
	if _combat_over:
		leave_combat()
		return
	if confirm_popup == null:
		confirm_popup = _ConfirmPopup.new()
		add_child(confirm_popup)
	confirm_popup.open("후퇴", "전투에서 물러납니다. 패배 손실의 절반을 받습니다.\n정말 후퇴할까요?", leave_combat, "후퇴", "계속 싸운다")


## 전투를 떠난다. 전투 중이면 후퇴로 처리한다.
func leave_combat() -> void:
	if not _combat_over:
		_end_combat(CombatManager.Outcome.RETREAT)
	SceneRouter.goto(get_tree(), SceneRouter.HUB)
