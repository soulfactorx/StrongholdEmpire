class_name DuelStage
extends Control

## 합 무대: 겨루는 사람들을 장기말처럼 양쪽에 세우고, 한 합의 칸마다 누가 무엇을 펼쳐 어떻게 맞았는지 움직임으로 보여 준다.
##   칸이 열리면 저마다 펼친 초식 이름이 머리 위에 뜨고, 공격하는 쪽이 상대에게 달려들었다 돌아온다.
##   맞으면 붉게 번쩍이며 흔들리고 피해 숫자가 솟아오른다. 흘려 내면 옆으로 비켜서고, 막기는 반격하고,
##   절초는 무대가 흔들리며 초식 이름이 크게 뜬다. 운기는 금빛으로 빛나고, 쓰러지면 말이 잿빛으로 눕는다.
## 판정은 이미 끝난 뒤의 기록(DuelEngine.slot_events)을 다시 보여 주는 것이라 결과는 바뀌지 않는다.
## 전투 화면(duel_controller)이 만든다. speed는 1이 보통, 클수록 느리다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const TOKEN_SIZE := Vector2(96, 162)
const PORTRAIT_SIZE := Vector2(72, 84)

## 연출이 끝나면 (다음 칸·다음 합으로)
signal finished

## 유닛 → {root, portrait, name, bar, card, home}
var _tokens: Dictionary = {}
var _friends: Array = []
var _foes: Array = []
var _portrait_of: Callable
var _banner: Label
## 말과 떠오르는 글자를 담는 판 (무대를 흔들 때 이 판만 움직인다. 무대 자체는 컨테이너가 자리를 정한다)
var _world: Control
var _shake_tween: Tween
var playing: bool = false
## 켜면 남은 연출을 기다리지 않고 바로 끝낸다 ([결과만 보기]·화면 나가기)
var hurry: bool = false


func _init() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(0, 215)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var ground := ColorRect.new()
	ground.color = Color(0.12, 0.1, 0.08, 0.12)
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)
	var line := ColorRect.new()
	line.color = Color(0.12, 0.1, 0.08, 0.35)
	line.anchor_left = 0.04
	line.anchor_right = 0.96
	line.anchor_top = 0.93
	line.anchor_bottom = 0.93
	line.offset_bottom = 2
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 6
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_UiTheme.style_label_title(_banner, 22)
	add_child(_banner)
	_world = Control.new()
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)
	resized.connect(_place_tokens)


## 무대에 설 사람들을 정한다. 사람이 바뀌었을 때만 말을 새로 만든다.
func set_units(friends: Array, foes: Array, portrait_of: Callable) -> void:
	_portrait_of = portrait_of
	if friends == _friends and foes == _foes and not _tokens.is_empty():
		refresh()
		return
	for unit in _tokens:
		_tokens[unit]["root"].queue_free()
	_tokens.clear()
	_friends = friends.duplicate()
	_foes = foes.duplicate()
	for unit in _friends + _foes:
		_tokens[unit] = _make_token(unit, unit in _foes)
	_place_tokens()
	refresh()


func has_token(unit: CombatUnit) -> bool:
	return _tokens.has(unit)


func token_of(unit: CombatUnit) -> Control:
	return _tokens[unit]["root"] if _tokens.has(unit) else null


## 체력 막대와 쓰러짐을 지금 값으로 맞춘다 (연출 없이)
func refresh() -> void:
	for unit in _tokens:
		var token: Dictionary = _tokens[unit]
		token["bar"].max_value = unit.max_hp
		token["bar"].value = unit.hp
		token["name"].text = "%s\n%d/%d" % [unit.display_name, unit.hp, unit.max_hp]
		_set_fallen(unit, not unit.is_alive())
		token["card"].visible = false


func _make_token(unit: CombatUnit, foe: bool) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = TOKEN_SIZE
	root.size = TOKEN_SIZE
	root.pivot_offset = TOKEN_SIZE / 2
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(root)
	var frame := Panel.new()
	frame.position = Vector2((TOKEN_SIZE.x - PORTRAIT_SIZE.x) / 2 - 3, 21)
	frame.size = PORTRAIT_SIZE + Vector2(6, 6)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.92, 0.85)
	style.border_color = _UiTheme.COLORS["accent_red"] if foe else _UiTheme.COLORS["accent_jade"]
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	var portrait := TextureRect.new()
	portrait.position = frame.position + Vector2(3, 3)
	portrait.size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture = _portrait_of.call(unit) if _portrait_of.is_valid() else null
	portrait.flip_h = foe
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(portrait)
	var bar := ProgressBar.new()
	bar.position = Vector2(4, 21 + PORTRAIT_SIZE.y + 8)
	bar.size = Vector2(TOKEN_SIZE.x - 8, 8)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = _UiTheme.COLORS["accent_red"] if foe else _UiTheme.COLORS["accent_jade"]
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.18)
	bar.add_theme_stylebox_override("background", bg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var name := Label.new()
	name.position = Vector2(-20, 21 + PORTRAIT_SIZE.y + 16)
	name.size = Vector2(TOKEN_SIZE.x + 40, 34)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_UiTheme.set_font_size(name, 14)
	name.add_theme_color_override("font_color", _UiTheme.COLORS["text_primary"])
	root.add_child(name)
	# 머리 위에 뜨는 초식 이름
	var card := Label.new()
	card.position = Vector2(-40, -2)
	card.size = Vector2(TOKEN_SIZE.x + 80, 22)
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.pivot_offset = card.size / 2
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	_UiTheme.set_font_size(card, 15)
	card.add_theme_color_override("font_outline_color", Color(0.98, 0.95, 0.88))
	card.add_theme_constant_override("outline_size", 6)
	root.add_child(card)
	return {"root": root, "portrait": portrait, "name": name, "bar": bar, "card": card, "home": Vector2.ZERO}


## 우리 편은 왼쪽, 상대는 오른쪽에 세운다. 여럿이면 앞뒤로 비껴 세운다
func _place_tokens() -> void:
	var height: float = maxf(size.y, custom_minimum_size.y)
	var width: float = maxf(size.x, 320.0)
	# 한쪽 편이 쓰는 폭: 가운데를 비워 달려드는 길을 남긴다
	var region: float = width * 0.42
	var most: int = maxi(1, maxi(_friends.size(), _foes.size()))
	var scale_down: float = clampf(region / (TOKEN_SIZE.x * most * 1.04), 0.6, 1.0)
	scale_down = minf(scale_down, (height - 8.0) / TOKEN_SIZE.y)
	for side in 2:
		var units: Array = _friends if side == 0 else _foes
		var step: float = TOKEN_SIZE.x * scale_down * 1.04
		if units.size() > 1:
			step = minf(step, (region - TOKEN_SIZE.x * scale_down) / (units.size() - 1))
		for i in units.size():
			var token: Dictionary = _tokens[units[i]]
			var root: Control = token["root"]
			root.scale = Vector2.ONE * scale_down
			# 앞사람(번호가 작은 사람)이 가운데 쪽에 선다
			var x: float = width * 0.04 + region - TOKEN_SIZE.x * scale_down - i * step if side == 0 else width * 0.54 + i * step
			var y: float = height - TOKEN_SIZE.y * scale_down - 4.0 - (i % 2) * 6.0
			root.pivot_offset = Vector2.ZERO
			root.position = Vector2(x, y)
			token["home"] = root.position
			# 앞사람(번호가 작은 사람)이 위에 그려지게
			_world.move_child(root, _world.get_child_count() - 1 - i)


## 한 합의 칸들을 차례로 보여 준다. 다 보여 주면 finished를 알린다.
func play(events: Array, speed: float = 1.0) -> void:
	playing = true
	hurry = false
	# 판정은 이미 끝났으므로 첫 칸이 열리기 전의 체력으로 되돌려 놓고 시작한다
	if not events.is_empty():
		for unit in events[0]["hp_before"]:
			if _tokens.has(unit):
				var before: int = int(events[0]["hp_before"][unit])
				_tokens[unit]["bar"].value = before
				_tokens[unit]["name"].text = "%s\n%d/%d" % [unit.display_name, before, unit.max_hp]
				_set_fallen(unit, before <= 0)
	for event in events:
		if not is_inside_tree():
			break
		await _play_slot(event, speed)
	playing = false
	_banner.text = ""
	refresh()
	finished.emit()


func _play_slot(event: Dictionary, speed: float) -> void:
	_banner.text = "%d칸" % (int(event["slot"]) + 1)
	_banner.modulate.a = 1.0
	# 펼친 초식 이름을 머리 위에
	for unit in event["cards"]:
		if not _tokens.has(unit):
			continue
		var card: DuelCard = event["cards"][unit]
		var label: Label = _tokens[unit]["card"]
		label.visible = true
		if card == null:
			label.text = "빈틈!"
			label.add_theme_color_override("font_color", Color("#9b2c1f"))
		else:
			label.text = card.display_name if card.art_id.is_empty() else "「%s」" % card.display_name
			label.add_theme_color_override("font_color", _type_color(card))
		label.scale = Vector2(0.4, 0.4)
		create_tween().tween_property(label, "scale", Vector2.ONE, 0.16 * speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _wait(0.28 * speed)
	for hit in event["hits"]:
		if not is_inside_tree():
			return
		await _play_hit(hit, event, speed)
	for unit in event["focus"]:
		_play_focus(unit, speed)
	if not event["focus"].is_empty():
		await _wait(0.3 * speed)
	# 칸이 끝난 체력 (이 칸의 독·회복까지)
	for unit in event["hp_after"]:
		if _tokens.has(unit):
			_tween_hp(unit, int(event["hp_after"][unit]), speed)
	await _wait(0.22 * speed)
	for unit in event["cards"]:
		if _tokens.has(unit):
			_tokens[unit]["card"].visible = false


func _play_hit(hit: Dictionary, event: Dictionary, speed: float) -> void:
	var source: CombatUnit = hit["from"]
	var target: CombatUnit = hit["to"]
	if not _tokens.has(source) or not _tokens.has(target):
		return
	var attacker: Control = _tokens[source]["root"]
	var defender: Control = _tokens[target]["root"]
	var card: DuelCard = hit["card"]
	var art: bool = card and not card.art_id.is_empty() and not hit["counter"]
	var home: Vector2 = _tokens[source]["home"]
	var toward: Vector2 = (_tokens[target]["home"] - home)
	var lunge: Vector2 = home + toward * (0.42 if not hit["counter"] else 0.25)
	if art:
		_float(Vector2(size.x / 2.0, 34), "「%s」" % card.display_name, _UiTheme.COLORS["accent_gold"], 30, speed)
		await _wait(0.25 * speed)
	# 달려든다
	var rush := create_tween()
	rush.tween_property(attacker, "position", lunge, 0.14 * speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await rush.finished
	if hit.get("evaded", false):
		_sound("evade")
		var dodge := create_tween()
		var side: float = -1.0 if target in _foes else 1.0
		dodge.tween_property(defender, "position", _tokens[target]["home"] + Vector2(28.0 * side, -18), 0.1 * speed)
		dodge.tween_property(defender, "position", _tokens[target]["home"], 0.16 * speed)
		_float(_center_of(defender) + Vector2(0, -40), "흘려 냄", _UiTheme.COLORS["text_muted"], 18, speed)
	elif hit.get("captured", false):
		_sound("block")
		_float(_center_of(defender) + Vector2(0, -40), "사로잡음!", _UiTheme.COLORS["accent_gold"], 22, speed)
	else:
		var dealt: int = int(hit.get("dealt", hit.get("damage", 0)))
		var blocked: bool = hit["defense"] != null and hit["defense"].type == DuelCard.Type.GUARD and not hit["counter"]
		if hit["counter"]:
			_sound("block")
			_float(_center_of(defender) + Vector2(0, -62), "반격!", _UiTheme.COLORS["accent_jade"], 20, speed)
		elif blocked:
			_sound("block")
		elif art:
			_sound("art")
		else:
			_sound("hit")
		_flash(defender, speed)
		_shake_token(defender, _tokens[target]["home"], 7.0 if art or dealt >= 15 else 4.0, speed)
		if art or dealt >= 20:
			_shake_stage(speed)
		_float(_center_of(defender) + Vector2(0, -34), "-%d" % dealt, Color("#b23a2b"), 30 if art else 24, speed)
		var note: String = str(hit.get("note", ""))
		if not note.is_empty() and not hit["counter"]:
			_float(_center_of(defender) + Vector2(0, -2), note, Color("#7a2a1f"), 14, speed)
		if hit.has("coverer") and _tokens.has(hit["coverer"]):
			_float(_center_of(_tokens[hit["coverer"]]["root"]) + Vector2(0, -30), "막아섬", _UiTheme.COLORS["accent_jade"], 18, speed)
		var bar: ProgressBar = _tokens[target]["bar"]
		_tween_hp(target, maxi(0, int(bar.value) - dealt), speed)
		if hit.get("fell", false):
			_sound("fall")
			_float(_center_of(defender) + Vector2(0, -70), "쓰러짐!", Color("#5a1a12"), 24, speed)
	# 돌아온다
	var back := create_tween()
	back.tween_property(attacker, "position", home, 0.2 * speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _wait(0.24 * speed)
	if hit.get("fell", false):
		_set_fallen(target, true, speed)


func _play_focus(unit: CombatUnit, speed: float) -> void:
	if not _tokens.has(unit):
		return
	var root: Control = _tokens[unit]["root"]
	_sound("focus")
	var glow := create_tween()
	glow.tween_property(root, "modulate", Color(1.35, 1.2, 0.7), 0.15 * speed)
	glow.tween_property(root, "modulate", Color.WHITE, 0.3 * speed)
	_float(_center_of(root) + Vector2(0, -40), "운기", Color("#7a5a8c"), 18, speed)


func _tween_hp(unit: CombatUnit, value: int, speed: float) -> void:
	var token: Dictionary = _tokens[unit]
	var bar: ProgressBar = token["bar"]
	create_tween().tween_property(bar, "value", float(value), 0.25 * speed)
	token["name"].text = "%s\n%d/%d" % [unit.display_name, value, unit.max_hp]


func _set_fallen(unit: CombatUnit, fallen: bool, speed: float = 0.0) -> void:
	var root: Control = _tokens[unit]["root"]
	var target_color: Color = Color(0.55, 0.55, 0.55, 0.55) if fallen else Color.WHITE
	if speed <= 0.0:
		root.modulate = target_color
		root.rotation = 0.12 if fallen else 0.0
		return
	var tween := create_tween().set_parallel()
	tween.tween_property(root, "modulate", target_color, 0.3 * speed)
	tween.tween_property(root, "rotation", 0.12, 0.3 * speed)


func _flash(control: Control, speed: float) -> void:
	var tween := create_tween()
	control.modulate = Color(1.8, 0.55, 0.5)
	tween.tween_property(control, "modulate", Color.WHITE, 0.25 * speed)


func _shake_token(control: Control, home: Vector2, strength: float, speed: float) -> void:
	var tween := create_tween()
	for i in 4:
		var offset := Vector2(strength * (1 if i % 2 == 0 else -1), 0)
		tween.tween_property(control, "position", home + offset, 0.035 * speed)
	tween.tween_property(control, "position", home, 0.04 * speed)


func _shake_stage(speed: float) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	for i in 4:
		_shake_tween.tween_property(_world, "position:y", 5.0 if i % 2 == 0 else -5.0, 0.04 * speed)
	_shake_tween.tween_property(_world, "position:y", 0.0, 0.05 * speed)


## 솟아오르며 사라지는 글자 (피해 숫자·흘려 냄·초식 이름)
func _float(at: Vector2, text: String, color: Color, font_size: int, speed: float) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_UiTheme.set_font_size(label, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.98, 0.95, 0.88))
	label.add_theme_constant_override("outline_size", 8)
	_world.add_child(label)
	label.size = Vector2(220, 60)
	label.position = Vector2(clampf(at.x - 110.0, 0.0, maxf(0.0, size.x - 220.0)), at.y)
	label.pivot_offset = Vector2(110, 10)
	label.scale = Vector2(0.6, 0.6)
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2(1.1, 1.1), 0.1 * speed)
	tween.tween_property(label, "scale", Vector2.ONE, 0.08 * speed)
	tween.parallel().tween_property(label, "position:y", label.position.y - 36, 0.7 * speed)
	tween.tween_property(label, "modulate:a", 0.0, 0.25 * speed)
	tween.tween_callback(label.queue_free)


func _center_of(control: Control) -> Vector2:
	return control.position + control.size * control.scale / 2.0


func _type_color(card: DuelCard) -> Color:
	match card.type:
		DuelCard.Type.STRIKE:
			return Color("#b23a2b")
		DuelCard.Type.QUICK:
			return Color("#94701a")
		DuelCard.Type.GUARD:
			return Color("#2f6b5e")
		DuelCard.Type.EVADE:
			return Color("#4a6f8a")
		DuelCard.Type.FOCUS:
			return Color("#7a5a8c")
	return Color("#5a5a5a")


func _sound(sfx_name: String) -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_sfx(sfx_name)


func _wait(seconds: float) -> void:
	if not is_inside_tree() or hurry:
		return
	await get_tree().create_timer(maxf(0.01, seconds)).timeout
