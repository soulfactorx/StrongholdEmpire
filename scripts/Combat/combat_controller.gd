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
## 적 공격 예고를 띄우고 [확인]을 기다리는 중인지
var _enemy_waiting: bool = false
## 적 공격 예고를 닫으면 적 차례가 이어진다.
signal enemy_preview_closed
const _ConfirmPopup = preload("res://scripts/UI/confirm_popup.gd")
## 후퇴 확인 대화상자 (처음 쓸 때 만든다)
var confirm_popup: Control
## 격자 커서 (키보드 방향키·게임패드로 칸을 고른다). 터치·마우스를 쓰면 숨긴다.
var cursor: Vector2i = Vector2i.ZERO
var cursor_visible: bool = false
var _cursor_layer: Node2D
## 왼쪽 스틱을 한 번 기울일 때 한 칸만 움직이도록 직전 방향을 기억한다
var _stick_dir: Vector2i = Vector2i.ZERO
## 아군 턴에 지금 조종하려고 고른 아군 (아군 칸을 누르거나 [다음 아군]으로 바꾼다)
var _selected: CombatUnit = null
## 전투 기록: 누가 무엇을 해서 얼마의 피해·회복이 났고 체력이 어떻게 바뀌었는지
var history: PackedStringArray = []
## 미리보기 중인 행동 {kind: "attack"|"art", unit, target, art}. 비어 있으면 미리보기 없음
var _pending_action: Dictionary = {}
var preview_panel: PanelContainer
var preview_label: Label
var history_popup: Control
var history_label: Label
var next_ally_button: Button
var history_button: Button


func _ready() -> void:
	ArtAssets.apply_background(self)
	# 바탕이 터치·클릭을 가로채면 격자로 입력이 오지 않는다.
	$Background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# HUD는 CanvasLayer 아래라 창 테마가 이어지지 않으므로 직접 준다.
	$HUD/Panel.theme = get_tree().root.theme
	_build_extra_hud()
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
		_log("전투 시작! %s — %s이(가) 함께 싸웁니다. 아군 턴에는 아군 칸을 눌러 누구든 골라 움직입니다." % [
			_setup.title, ", ".join(names),
		])
	_record("전투 시작: %s" % _setup.title)
	_start_player_phase(true)


## 전투 화면에 코드로 더하는 것: [다음 아군]·[전투 기록] 버튼, 공격 미리보기 창, 전투 기록 창
func _build_extra_hud() -> void:
	var unit_row := HBoxContainer.new()
	unit_row.name = "UnitRow"
	unit_row.add_theme_constant_override("separation", 6)
	next_ally_button = Button.new()
	next_ally_button.name = "NextAllyButton"
	next_ally_button.text = "다음 아군 (Tab)"
	next_ally_button.custom_minimum_size = Vector2(0, 48)
	next_ally_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_ally_button.pressed.connect(select_next_ally)
	unit_row.add_child(next_ally_button)
	history_button = Button.new()
	history_button.name = "HistoryButton"
	history_button.text = "전투 기록 (H)"
	history_button.custom_minimum_size = Vector2(0, 48)
	history_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_button.pressed.connect(open_history)
	unit_row.add_child(history_button)
	var turn_row: Node = $HUD/Panel/VBox/TurnRow
	turn_row.get_parent().add_child(unit_row)
	turn_row.get_parent().move_child(unit_row, turn_row.get_index() + 1)

	# 공격·무공 미리보기: 화면 가운데 위쪽에 뜨고, [실행]·[취소]를 고른다.
	preview_panel = PanelContainer.new()
	preview_panel.name = "PreviewPanel"
	preview_panel.visible = false
	preview_panel.theme = get_tree().root.theme
	preview_panel.custom_minimum_size = Vector2(520, 0)
	preview_panel.position = Vector2(120, 40)
	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 8)
	preview_panel.add_child(preview_box)
	preview_label = Label.new()
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.custom_minimum_size = Vector2(480, 0)
	preview_box.add_child(preview_label)
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 8)
	var confirm := Button.new()
	confirm.name = "PreviewConfirmButton"
	confirm.text = "실행 (Enter)"
	confirm.custom_minimum_size = Vector2(0, 48)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(confirm_preview)
	preview_row.add_child(confirm)
	var cancel := Button.new()
	cancel.name = "PreviewCancelButton"
	cancel.text = "취소 (Esc)"
	cancel.custom_minimum_size = Vector2(0, 48)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(cancel_preview)
	preview_row.add_child(cancel)
	preview_box.add_child(preview_row)
	$HUD.add_child(preview_panel)
	_UiTheme.apply_to_control(preview_panel)

	# 전투 기록 창: 화면 전체를 덮고 끌어서 스크롤한다.
	history_popup = Control.new()
	history_popup.name = "HistoryPopup"
	history_popup.visible = false
	history_popup.theme = get_tree().root.theme
	history_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	history_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	history_popup.add_child(dimmer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	history_popup.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "전투 기록"
	_UiTheme.style_label_title(title, 24)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "HistoryScroll"
	scroll.custom_minimum_size = Vector2(0, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	history_label = Label.new()
	history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_UiTheme.set_font_size(history_label, 15)
	scroll.add_child(history_label)
	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void: history_popup.visible = false)
	box.add_child(close)
	$HUD.add_child(history_popup)
	_UiTheme.apply_to_control(panel)


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
	if _enemy_acting or not _turn_manager.is_player_phase():
		return null
	if _selected and _selected.is_alive() and _selected.is_friendly() and not _selected.has_status("stunned"):
		return _selected
	return null


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
	elif unit.is_friendly() and _turn_manager.is_player_phase() and not _can_still_act(unit):
		# 이번 아군 턴에 할 일을 다 한 아군은 흐리게
		holder.modulate = Color(1, 1, 1, 0.55)
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
	var controlled := _get_controlled()

	round_label.text = "라운드 %d" % _turn_manager.round_number
	undo_move_button.disabled = _last_move.is_empty() or controlled == null or _last_move["unit"] != controlled
	end_turn_button.disabled = _combat_over or controlled == null
	# 기본 공격은 차례에 한 번
	$HUD/Panel/VBox/ModeRow/ModeAttackButton.disabled = _combat_over or controlled == null or not controlled.can_basic_attack()
	if _combat_over:
		turn_label.text = "전투 종료"
	elif not _turn_manager.is_player_phase() or _enemy_acting:
		turn_label.text = "적군 턴"
	else:
		turn_label.text = "아군 턴 — %s 조종 중 (아군 칸을 눌러 바꾸기)" % (controlled.display_name if controlled else "없음")
	if next_ally_button:
		next_ally_button.disabled = _combat_over or controlled == null or _selectable_friendlies().size() < 2

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

## 키보드 단축키: 방향키 커서, Enter 실행, M 이동, A 공격, 1~9 무공, Z 이동 취소, Tab 다음 아군, H 전투 기록,
## Space·E 턴 종료, Esc 후퇴(확인). 미리보기 중에는 Enter·Space 실행, Esc 취소
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if confirm_popup and confirm_popup.visible:
		if key.keycode == KEY_ESCAPE:
			confirm_popup._answer(false)
		return
	if history_popup and history_popup.visible:
		if key.keycode in [KEY_ESCAPE, KEY_H]:
			history_popup.visible = false
			get_viewport().set_input_as_handled()
		return
	if is_previewing():
		if key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			confirm_preview()
		elif key.keycode == KEY_ESCAPE:
			cancel_preview()
		get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_TAB:
			select_next_ally()
		KEY_H:
			open_history()
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
	if current == null or is_previewing() or history_popup.visible:
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
	if is_previewing():
		return
	var friend: CombatUnit = _get_friendly_at(target)
	var healing: bool = _action_mode == ActionMode.MARTIAL_ART and _selected_art != null and _selected_art.heal_amount > 0
	if friend and friend != current and not healing:
		select_unit(friend)
		return
	match _action_mode:
		ActionMode.MOVE:
			_try_move(current, target)
		ActionMode.ATTACK:
			_try_attack(current, target)
		ActionMode.MARTIAL_ART:
			_try_martial_art(current, target)


## 게임패드: 십자키·왼쪽 스틱 커서, A 실행, B 이동 취소, X 공격, Y 이동, LB·RB 무공 고르기,
## 왼쪽 스틱 누르기 다음 아군, Start 턴 종료, Back 후퇴. 미리보기 중에는 A 실행·B 취소. 처리했으면 true.
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
	if is_previewing():
		if button.button_index == JOY_BUTTON_A:
			confirm_preview()
		elif button.button_index == JOY_BUTTON_B:
			cancel_preview()
		return true
	match button.button_index:
		JOY_BUTTON_LEFT_STICK:
			select_next_ally()
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
	_record("%s 이동 (%d,%d) → (%d,%d) %s, 행동력 %d → %d" % [
		unit.display_name, unit.grid_pos.x, unit.grid_pos.y, target.x, target.y,
		CombatRules.TERRAIN_NAMES[_terrain_at(target)], unit.action_points, unit.action_points - reachable[target],
	])
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
	_request_action({"kind": "attack", "unit": unit, "target": enemy})


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
		_request_action({"kind": "art", "unit": unit, "target": friend, "art": art})
		return
	var enemy := _get_enemy_at(target)
	if enemy == null or CombatRules.distance(target, unit.grid_pos) > art_range:
		_log("사거리 안의 적을 선택하세요. (사거리 %d)" % art_range)
		return
	if unit.action_points < art.action_cost or unit.character.internal_energy_current < art.internal_cost:
		_log("행동력이나 내공이 부족합니다.")
		return
	_request_action({"kind": "art", "unit": unit, "target": enemy, "art": art})


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
	_record("%s 이동 취소" % current.display_name)
	_refresh_all()
	_log("이동을 되돌렸습니다.")


func _perform_attack(attacker: CombatUnit, defender: CombatUnit) -> void:
	_last_move = {}
	var result: Dictionary = CombatRules.calculate_damage(
		attacker, defender, null,
		_terrain_at(attacker.grid_pos), _terrain_at(defender.grid_pos),
		_relationship_bonus(attacker, defender), _relationship_defense(attacker, defender)
	)
	var hp_before: int = defender.hp
	defender.take_damage(result["damage"])
	attacker.action_points -= 1
	attacker.basic_attacks_left -= 1
	_record("%s → %s 기본 공격 %d 피해%s | %s" % [
		attacker.display_name, defender.display_name, result["damage"], _notes_text(result["notes"]),
		_hp_change(defender, hp_before),
	])
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
	var attacker_hp_before: int = attacker.hp
	var target_unit: CombatUnit = defender if defender else attacker
	var target_hp_before: int = target_unit.hp
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
	var changes: PackedStringArray = [_hp_change(target_unit, target_hp_before)]
	if attacker != target_unit and attacker.hp != attacker_hp_before:
		changes.append(_hp_change(attacker, attacker_hp_before))
	_record("%s | %s | 내공 %d 소모" % [", ".join(messages), " · ".join(changes), art.internal_cost])
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
		_record("%s 쓰러짐" % unit.display_name)
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
	# 연대기에 전투의 마지막 몇 수를 남기도록 결과 처리 전에 넘긴다.
	GameManager.last_combat_history = history
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
	_record("── 전투 끝: %s ──" % result["message"])
	GameManager.last_combat_history = history


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
## 적이 아군을 칠 때는 설정에 따라 예고(예상 피해)를 보여 주고 [확인]을 기다린다.
func _run_enemy_ai(enemy: CombatUnit) -> void:
	var target := _pick_enemy_target(enemy)
	if target == null or not enemy.is_alive():
		return
	var attacked: bool = await _enemy_try_attack(enemy, target)
	if not attacked:
		_enemy_approach(enemy, target)
	var guard: int = 0
	while not _combat_over and enemy.is_alive() and guard < 8:
		guard += 1
		target = _pick_enemy_target(enemy)
		if target == null:
			break
		attacked = await _enemy_try_attack(enemy, target)
		if not attacked:
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
			var from: Vector2i = enemy.grid_pos
			enemy.grid_pos = path[walk["index"]]
			enemy.action_points -= walk["cost"]
			if enemy.grid_pos != from:
				_record("%s 이동 (%d,%d) → (%d,%d)" % [enemy.display_name, from.x, from.y, enemy.grid_pos.x, enemy.grid_pos.y])


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
	var action: Dictionary = {}
	if art and dist <= CombatRules.get_art_range(art, _terrain_at(enemy.grid_pos)):
		action = {"kind": "art", "unit": enemy, "target": target, "art": art}
	elif dist == 1 and enemy.can_basic_attack():
		action = {"kind": "attack", "unit": enemy, "target": target}
	else:
		return false
	if not enemy.is_friendly() and GameSettings.enemy_preview and is_inside_tree():
		await _show_enemy_preview(action)
		if _combat_over or not is_inside_tree() or not enemy.is_alive() or not target.is_alive():
			return false
	if action["kind"] == "art":
		return _perform_art(enemy, target, art)
	_perform_attack(enemy, target)
	return true


## 적 공격 예고: 누가 누구를 무엇으로 치는지, 예상 피해와 체력 변화. [확인]을 누르면 공격이 이어진다.
func _show_enemy_preview(action: Dictionary) -> void:
	_pending_action = action
	_enemy_waiting = true
	_refresh_all()
	preview_label.text = enemy_preview_text(action)
	var confirm: Button = preview_panel.find_child("PreviewConfirmButton", true, false)
	confirm.text = "확인 (Enter)"
	preview_panel.find_child("PreviewCancelButton", true, false).visible = false
	preview_panel.reset_size()
	preview_panel.visible = true
	confirm.grab_focus()
	await enemy_preview_closed


func _close_enemy_preview() -> void:
	_enemy_waiting = false
	_pending_action = {}
	preview_panel.visible = false
	preview_panel.find_child("PreviewConfirmButton", true, false).text = "실행 (Enter)"
	preview_panel.find_child("PreviewCancelButton", true, false).visible = true
	enemy_preview_closed.emit()


func is_enemy_preview() -> bool:
	return _enemy_waiting


## 적 공격 예고 문구
func enemy_preview_text(action: Dictionary) -> String:
	var unit: CombatUnit = action["unit"]
	var target: CombatUnit = action["target"]
	var art: MartialArtData = action.get("art")
	var lines: PackedStringArray = ["[적 공격 예고]"]
	lines.append("%s → %s: %s" % [unit.display_name, target.display_name, "기본 공격" if art == null else "[%s]" % art.display_name])
	var p: Dictionary = CombatRules.preview_damage(
		unit, target, art, _terrain_at(unit.grid_pos), _terrain_at(target.grid_pos),
		_relationship_bonus(unit, target), _relationship_defense(unit, target)
	)
	var crit_text: String = " (회심 %d%%면 최대 %d)" % [roundi(p["crit_chance"] * 100), p["crit_max"]] if p["crit_chance"] > 0.0 else ""
	lines.append("예상 피해: %d ~ %d%s" % [p["min"], p["max"], crit_text])
	var danger: String = ""
	if p["min"] >= target.hp:
		danger = " — 반드시 쓰러짐"
	elif p["max"] >= target.hp:
		danger = " — 쓰러질 수 있음"
	elif p["crit_max"] >= target.hp:
		danger = " — 회심이면 쓰러짐"
	lines.append("%s 체력: %d → %d ~ %d / %d%s" % [
		target.display_name, target.hp, maxi(0, target.hp - p["max"]), maxi(0, target.hp - p["min"]), target.max_hp, danger,
	])
	if not p["notes"].is_empty():
		lines.append("요인: %s" % ", ".join(p["notes"]))
	if art:
		var effects: String = art.get_effects_text()
		if not effects.is_empty() and effects != "없음":
			lines.append("효과: %s" % effects)
	lines.append("%s 체력 %d / %d, 내공 %d" % [unit.display_name, unit.hp, unit.max_hp, unit.character.internal_energy_current])
	return "\n".join(lines)


# ─── 턴 진행 ────────────────────────────────────────

## 아군 턴 시작: 아군 행동력을 채우고(첫 턴 제외, setup에서 채움) 조종할 아군을 고른다.
## 고를 수 있는 아군이 없으면(모두 기절) 바로 적군 턴으로 넘어간다.
func _start_player_phase(first: bool = false) -> void:
	if _combat_over:
		return
	if not first:
		_turn_manager.begin_player_phase()
	_last_move = {}
	_record("── 라운드 %d · 아군 턴 ──" % _turn_manager.round_number)
	for unit in _turn_manager.get_friendlies():
		if unit.has_status("stunned"):
			_record("%s은(는) 기절해 이번 턴에 움직이지 못합니다." % unit.display_name)
	var choices: Array[CombatUnit] = _selectable_friendlies()
	if choices.is_empty():
		_refresh_all()
		await _end_player_phase()
		return
	var player: CombatUnit = _get_player()
	_selected = player if choices.has(player) else choices[0]
	_action_mode = ActionMode.MOVE
	_selected_art = null
	_refresh_all()
	_log("아군 턴입니다. %s 조종 중 — 다른 아군은 그 칸을 눌러 고르세요." % _selected.display_name)


## 이번 아군 턴에 고를 수 있는 아군 (살아 있고 기절하지 않음)
func _selectable_friendlies() -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for unit in _turn_manager.get_friendlies():
		if not unit.has_status("stunned"):
			result.append(unit)
	return result


## 아직 할 수 있는 일이 남았는지 (행동력이 있음)
func _can_still_act(unit: CombatUnit) -> bool:
	return unit.action_points > 0 and not unit.has_status("stunned")


## 아군을 골라 조종한다. 아군 턴에만, 살아 있고 기절하지 않은 아군만.
func select_unit(unit: CombatUnit) -> bool:
	if _combat_over or _enemy_acting or not _turn_manager.is_player_phase():
		return false
	if unit == null or not unit.is_friendly() or not unit.is_alive():
		return false
	if unit.has_status("stunned"):
		_log("%s은(는) 기절해 움직일 수 없습니다." % unit.display_name)
		return false
	if unit == _selected:
		return true
	_selected = unit
	_action_mode = ActionMode.MOVE
	_selected_art = null
	if cursor_visible:
		cursor = unit.grid_pos
	_refresh_all()
	_log("%s 조종 (행동력 %d)" % [unit.display_name, unit.action_points])
	return true


## 다음 아군으로 바꾼다. 행동력이 남은 아군을 먼저 고른다.
func select_next_ally() -> void:
	var choices: Array[CombatUnit] = _selectable_friendlies()
	if choices.size() < 2:
		return
	var start: int = maxi(0, choices.find(_selected))
	for step in range(1, choices.size() + 1):
		var candidate: CombatUnit = choices[(start + step) % choices.size()]
		if _can_still_act(candidate) or step == choices.size():
			select_unit(candidate)
			return


## 행동한 뒤 조종 중인 아군이 할 일이 없으면, 행동력이 남은 다른 아군으로 넘어간다.
func _auto_advance_selection() -> void:
	if _combat_over or not _turn_manager.is_player_phase() or _selected == null:
		return
	if _selected.is_alive() and _can_still_act(_selected):
		return
	for unit in _selectable_friendlies():
		if _can_still_act(unit):
			select_unit(unit)
			return


## [턴 종료]: 아군 턴을 마치고 적군 턴을 진행한 뒤, 다음 라운드의 아군 턴을 연다.
func _on_end_turn_pressed() -> void:
	if _combat_over or _enemy_acting or not _turn_manager.is_player_phase():
		return
	cancel_preview()
	await _end_player_phase()


func _end_player_phase() -> void:
	for unit in _turn_manager.get_friendlies():
		unit.tick_statuses()
	_last_move = {}
	await _run_enemy_phase()
	if not _combat_over and is_inside_tree():
		_start_player_phase()


## 적군 턴: 적이 빠른 순서로 하나씩 움직인다. 전투 속도 옵션만큼 적 행동 사이에 간격을 둔다 (0이면 바로).
func _run_enemy_phase() -> void:
	_turn_manager.begin_enemy_phase()
	_record("── 라운드 %d · 적군 턴 ──" % _turn_manager.round_number)
	_enemy_acting = true
	_refresh_all()
	for enemy in _turn_manager.get_enemy_order():
		if _combat_over:
			break
		if not enemy.is_alive():
			continue
		if enemy.has_status("stunned"):
			_record("%s은(는) 기절해 차례를 넘깁니다." % enemy.display_name)
			_log("%s은(는) 기절해 차례를 넘깁니다." % enemy.display_name)
			enemy.tick_statuses()
			continue
		if GameSettings.combat_delay > 0.0:
			_refresh_all()
			await get_tree().create_timer(GameSettings.combat_delay).timeout
			if not is_inside_tree() or _combat_over:
				_enemy_acting = false
				return
		await _run_enemy_ai(enemy)
		if not is_inside_tree():
			return
		enemy.tick_statuses()
	_enemy_acting = false
	_refresh_all()


## 전투 기록에 한 줄 남긴다.
func _record(text: String) -> void:
	history.append(text)
	if history_popup and history_popup.visible:
		_fill_history()


## 전투 기록 창을 연다 (가장 최근이 아래).
func open_history() -> void:
	cancel_preview()
	_fill_history()
	history_popup.visible = true
	var scroll: ScrollContainer = history_popup.find_child("HistoryScroll", true, false)
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _fill_history() -> void:
	history_label.text = "\n".join(history)


## 체력 변화 문구: "체력 54 → 33"
static func _hp_change(unit: CombatUnit, before: int) -> String:
	return "%s 체력 %d → %d%s" % [unit.display_name, before, unit.hp, " (쓰러짐)" if not unit.is_alive() else ""]


# ─── 공격 미리보기 ──────────────────────────────────

## 공격·무공을 실행하기 전에 예상 결과를 보여 준다. 설정에서 끄면 바로 실행한다.
func _request_action(action: Dictionary) -> void:
	if not GameSettings.combat_preview:
		_execute_action(action)
		return
	_pending_action = action
	preview_label.text = preview_text(action)
	preview_panel.reset_size()
	preview_panel.visible = true
	preview_panel.find_child("PreviewConfirmButton", true, false).grab_focus()


func confirm_preview() -> void:
	if _enemy_waiting:
		_close_enemy_preview()
		return
	if _pending_action.is_empty():
		return
	var action: Dictionary = _pending_action
	cancel_preview()
	_execute_action(action)


## 적 공격 예고는 취소할 수 없으므로 닫으면 공격이 이어진다.
func cancel_preview() -> void:
	if _enemy_waiting:
		_close_enemy_preview()
		return
	_pending_action = {}
	if preview_panel:
		preview_panel.visible = false


func is_previewing() -> bool:
	return not _pending_action.is_empty()


func _execute_action(action: Dictionary) -> void:
	if action["kind"] == "attack":
		_perform_attack(action["unit"], action["target"])
	else:
		_perform_art(action["unit"], action["target"], action["art"])
	_auto_advance_selection()


## 미리보기 문구: 예상 피해·회복, 대상 체력 변화, 내 소모와 위험, 대상이 살아남으면 다음 적 턴의 예상 반격
func preview_text(action: Dictionary) -> String:
	var unit: CombatUnit = action["unit"]
	var target: CombatUnit = action["target"]
	var art: MartialArtData = action.get("art")
	var lines: PackedStringArray = []
	var title: String = "기본 공격" if art == null else "[%s]" % art.display_name
	lines.append("%s: %s → %s" % [title, unit.display_name, target.display_name])
	if art and art.heal_amount > 0:
		var multiplier: float = RelationshipManager.get_ally_buff_multiplier(GameManager.player_relationships) if unit.is_player else 1.0
		var heal: int = int(art.heal_amount * multiplier)
		var after: int = mini(target.max_hp, target.hp + heal)
		lines.append("회복: +%d → %s 체력 %d → %d / %d" % [heal, target.display_name, target.hp, after, target.max_hp])
	else:
		var p: Dictionary = CombatRules.preview_damage(
			unit, target, art, _terrain_at(unit.grid_pos), _terrain_at(target.grid_pos),
			_relationship_bonus(unit, target), _relationship_defense(unit, target)
		)
		var crit_text: String = " (회심 %d%%면 최대 %d)" % [roundi(p["crit_chance"] * 100), p["crit_max"]] if p["crit_chance"] > 0.0 else ""
		lines.append("예상 피해: %d ~ %d%s" % [p["min"], p["max"], crit_text])
		var low_hp: int = maxi(0, target.hp - p["max"])
		var high_hp: int = maxi(0, target.hp - p["min"])
		var kill: String = ""
		if p["min"] >= target.hp:
			kill = " — 반드시 쓰러뜨림"
		elif p["max"] >= target.hp:
			kill = " — 쓰러뜨릴 수 있음"
		elif p["crit_max"] >= target.hp:
			kill = " — 회심이면 쓰러뜨림"
		lines.append("%s 체력: %d → %d ~ %d / %d%s" % [target.display_name, target.hp, low_hp, high_hp, target.max_hp, kill])
		if not p["notes"].is_empty():
			lines.append("요인: %s" % ", ".join(p["notes"]))
	# 내 소모
	if art == null:
		lines.append("내 소모: 행동력 1 (%d → %d), 이번 턴 기본 공격 1회 사용" % [unit.action_points, unit.action_points - 1])
	else:
		var energy: int = unit.character.internal_energy_current
		lines.append("내 소모: 행동력 %d (%d → %d), 내공 %d (%d → %d)" % [
			art.action_cost, unit.action_points, unit.action_points - art.action_cost,
			art.internal_cost, energy, energy - art.internal_cost,
		])
		if energy - art.internal_cost < unit.character.internal_energy_max * _Balance.OVERLOAD_THRESHOLD:
			lines.append("위험: 내공 폭주 %d%% — 반동으로 내가 %d 피해" % [
				_Balance.OVERLOAD_CHANCE, maxi(1, int(art.internal_cost * _Balance.OVERLOAD_DAMAGE_PER_COST)),
			])
		var effects: String = art.get_effects_text()
		if not effects.is_empty() and effects != "없음":
			lines.append("효과: %s" % effects)
	# 반격 예상: 대상이 살아남으면 다음 적 턴에 나에게 줄 수 있는 피해
	if not target.is_friendly():
		var counter: Dictionary = _counter_estimate(target, unit)
		if not counter.is_empty():
			lines.append("살아남으면 다음 적 턴에 %s이(가) %s(으)로 약 %d ~ %d 피해 (내 체력 %d)" % [
				target.display_name, counter["name"], counter["min"], counter["max"], unit.hp,
			])
	return "\n".join(lines)


## 적이 다음 턴에 이 아군에게 줄 수 있는 피해 범위 (쓸 수 있는 무공이 있으면 무공, 아니면 기본 공격)
func _counter_estimate(enemy: CombatUnit, victim: CombatUnit) -> Dictionary:
	var art: MartialArtData = null
	for candidate in enemy.get_martial_arts():
		if candidate.heal_amount <= 0 and enemy.character.internal_energy_current >= candidate.internal_cost:
			art = candidate
			break
	var p: Dictionary = CombatRules.preview_damage(
		enemy, victim, art, _terrain_at(enemy.grid_pos), _terrain_at(victim.grid_pos),
		1.0, _relationship_defense(enemy, victim)
	)
	return {"name": "기본 공격" if art == null else "[%s]" % art.display_name, "min": p["min"], "max": p["max"]}


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
			_request_action({"kind": "art", "unit": current, "target": current, "art": art})
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
