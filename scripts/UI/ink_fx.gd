class_name InkFx
extends RefCounted

## 수묵 연출 모음: 화면 전환(먹물 번짐), 붓 베기, 먹물 튐, 계절 입자(꽃잎·낙엽·눈), 버튼 눌림, 창 펼침.
## 그림 파일 없이 셰이더·입자·트윈으로 만든다. GL Compatibility(웹·모바일)에서 돈다.
## 설정의 "화면 연출"(GameSettings.screen_effects)을 끄면 모두 건너뛴다. 전투 합 연출은 따로 "전투 연출"이 정한다.

## 화면 전환 층 (모든 화면·창 위)
const TRANSITION_LAYER := 120
const TRANSITION_TIME := 0.65

## 먹물 번짐: 지난 화면(캡처)이 가운데부터 먹물에 먹히며 새 화면이 드러난다. 경계에 먹빛 테두리가 진다.
const _DISSOLVE_SHADER := """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 origin = vec2(0.5, 0.5);
uniform float aspect = 1.777;
uniform vec4 ink : source_color = vec4(0.09, 0.08, 0.07, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 d = (UV - origin) * vec2(aspect, 1.0);
	// 가운데서 멀수록 늦게 먹힌다. 번짐 결은 fbm.
	float field = length(d) / (0.5 * aspect + 0.5) * 0.75 + fbm(UV * vec2(aspect, 1.0) * 5.0) * 0.45;
	float edge = progress * 1.25;
	float gone = smoothstep(edge - 0.02, edge + 0.02, field);
	float rim = smoothstep(edge - 0.10, edge, field) * (1.0 - smoothstep(edge, edge + 0.035, field));
	vec4 old = texture(TEXTURE, UV);
	vec3 color = mix(old.rgb, ink.rgb, clamp(rim * 1.4, 0.0, 1.0));
	// 먹물 테두리 바깥(이미 먹힌 곳)은 투명 → 새 화면
	float alpha = max(gone, rim * 0.92);
	COLOR = vec4(color, alpha * old.a);
}
"""

static var _dissolve_material: ShaderMaterial
static var _dot_texture: Texture2D
static var _petal_texture: Texture2D
static var _snow_texture: Texture2D


static func enabled() -> bool:
	return GameSettings.screen_effects


## 그림을 실제로 그리는 환경인지 (헤드리스 테스트는 화면 캡처가 없다)
static func can_capture() -> bool:
	return DisplayServer.get_name() != "headless"


# ── 화면 전환 ───────────────────────────────────────────

## 화면을 바꾸기 직전에 부른다. 지금 화면을 찍어 맨 위에 덮고, 새 화면이 뜨면 먹물이 번지듯 걷어 낸다.
## 화면 전환 자체는 기다리지 않는다 (덮개는 창(root)에 붙어 씬이 바뀌어도 남는다).
static func transition(tree: SceneTree) -> void:
	if tree == null or tree.root == null or not enabled() or not can_capture():
		return
	var old: Node = tree.root.get_node_or_null("InkTransition")
	if old:
		old.free()
	var image: Image = tree.root.get_texture().get_image()
	if image == null or image.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.name = "InkTransition"
	layer.layer = TRANSITION_LAYER
	var cover := TextureRect.new()
	cover.texture = ImageTexture.create_from_image(image)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_SCALE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial = _dissolve().duplicate()
	var view: Vector2 = tree.root.get_visible_rect().size
	material.set_shader_parameter("aspect", view.x / maxf(1.0, view.y))
	material.set_shader_parameter("progress", 0.0)
	cover.material = material
	layer.add_child(cover)
	tree.root.add_child(layer)
	var tween: Tween = layer.create_tween()
	tween.tween_interval(0.05)
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("progress", value), 0.0, 1.0, TRANSITION_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(layer.queue_free)


static func _dissolve() -> ShaderMaterial:
	if _dissolve_material == null:
		var shader := Shader.new()
		shader.code = _DISSOLVE_SHADER
		_dissolve_material = ShaderMaterial.new()
		_dissolve_material.shader = shader
	return _dissolve_material


# ── 전투: 붓 베기·먹물 튐 ─────────────────────────────

## 붓으로 그은 듯한 획: 가운데가 굵고 양끝이 가는 선이 한 번에 그어졌다가 번지며 사라진다.
## at은 parent 좌표. angle은 라디안, length는 획 길이. speed는 1이 보통(클수록 느림).
static func brush_slash(parent: Control, at: Vector2, angle: float, length: float, color: Color, width: float = 14.0, speed: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var dir := Vector2.from_angle(angle)
	var start: Vector2 = at - dir * length / 2.0
	var finish: Vector2 = at + dir * length / 2.0
	for stroke in 2:
		var line := Line2D.new()
		line.width = width if stroke == 0 else width * 0.35
		line.default_color = color if stroke == 0 else Color(color, 0.55)
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.05))
		curve.add_point(Vector2(0.3, 1.0))
		curve.add_point(Vector2(0.75, 0.7))
		curve.add_point(Vector2(1.0, 0.0))
		line.width_curve = curve
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true
		var offset: Vector2 = dir.orthogonal() * (0.0 if stroke == 0 else width * 0.6)
		var a: Vector2 = start + offset
		var b: Vector2 = finish + offset
		line.points = PackedVector2Array([a, a])
		parent.add_child(line)
		var tween: Tween = line.create_tween()
		# 붓이 지나가는 동안 점을 여럿 찍어 살짝 휘게 한다
		tween.tween_method(func(t: float) -> void: _stroke_points(line, a, b, t), 0.0, 1.0, 0.09 * speed) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_interval(0.08 * speed)
		tween.tween_property(line, "modulate:a", 0.0, 0.35 * speed)
		tween.parallel().tween_property(line, "width", line.width * 1.4, 0.35 * speed)
		tween.tween_callback(line.queue_free)


static func _stroke_points(line: Line2D, a: Vector2, b: Vector2, t: float) -> void:
	var points := PackedVector2Array()
	var steps: int = 8
	var bend: Vector2 = (b - a).orthogonal().normalized() * (b - a).length() * 0.06
	for i in steps + 1:
		var u: float = float(i) / steps * t
		points.append(a.lerp(b, u) + bend * sin(u * PI))
	line.points = points


## 먹물이 사방으로 튄다 (맞은 자리). amount는 방울 수.
static func ink_splash(parent: Control, at: Vector2, color: Color, amount: int = 18, spread: float = 1.0, speed: float = 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var particles := CPUParticles2D.new()
	particles.position = at
	particles.texture = dot_texture()
	particles.amount = maxi(1, amount)
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.lifetime = 0.55 * speed
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2(0, 520)
	particles.initial_velocity_min = 90.0 * spread
	particles.initial_velocity_max = 260.0 * spread
	particles.damping_min = 40.0
	particles.damping_max = 120.0
	particles.scale_amount_min = 0.12
	particles.scale_amount_max = 0.5
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	particles.color_ramp = fade
	particles.local_coords = false
	parent.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


# ── 살아 있는 화면: 계절 입자 ─────────────────────────

## 화면 위를 천천히 떠다니는 계절 입자. season은 0 봄(꽃잎)·1 여름(반딧불)·2 가을(낙엽)·3 겨울(눈).
## 화면(screen)의 판들(above) 바로 위, 창(팝업)들 아래에 넣는다. 입자는 누름을 가로채지 않는다. 만든 노드를 돌려준다.
static func add_season_particles(screen: Control, above: Node, season: int) -> CPUParticles2D:
	if screen == null or not enabled():
		return null
	var old: Node = screen.get_node_or_null("SeasonParticles")
	if old:
		var refit: Callable = old.get_meta("refit", Callable())
		if refit.is_valid() and screen.resized.is_connected(refit):
			screen.resized.disconnect(refit)
		screen.remove_child(old)
		old.queue_free()
	var background: Control = screen
	var particles := CPUParticles2D.new()
	particles.name = "SeasonParticles"
	particles.local_coords = false
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.preprocess = 12.0
	var color := Color.WHITE
	match season:
		0:
			particles.texture = petal_texture()
			particles.amount = 26
			particles.lifetime = 14.0
			particles.gravity = Vector2(14, 22)
			particles.initial_velocity_min = 10.0
			particles.initial_velocity_max = 30.0
			particles.angular_velocity_min = -60.0
			particles.angular_velocity_max = 60.0
			particles.angle_max = 360.0
			particles.scale_amount_min = 0.35
			particles.scale_amount_max = 0.7
			color = Color(0.96, 0.72, 0.76, 0.85)
		1:
			particles.texture = dot_texture()
			particles.amount = 22
			particles.lifetime = 9.0
			particles.gravity = Vector2(0, -4)
			particles.initial_velocity_min = 4.0
			particles.initial_velocity_max = 14.0
			particles.scale_amount_min = 0.08
			particles.scale_amount_max = 0.16
			color = Color(0.95, 0.85, 0.45, 0.8)
		2:
			particles.texture = petal_texture()
			particles.amount = 20
			particles.lifetime = 12.0
			particles.gravity = Vector2(18, 34)
			particles.initial_velocity_min = 10.0
			particles.initial_velocity_max = 30.0
			particles.angular_velocity_min = -120.0
			particles.angular_velocity_max = 120.0
			particles.angle_max = 360.0
			particles.scale_amount_min = 0.45
			particles.scale_amount_max = 0.85
			color = Color(0.78, 0.42, 0.18, 0.8)
		_:
			particles.texture = snow_texture()
			particles.amount = 60
			particles.lifetime = 16.0
			particles.gravity = Vector2(6, 26)
			particles.initial_velocity_min = 6.0
			particles.initial_velocity_max = 18.0
			particles.scale_amount_min = 0.15
			particles.scale_amount_max = 0.4
			color = Color(0.72, 0.78, 0.88, 0.9)
	# 수명 끝에 흐려지게
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(color, 0.0), color, color, Color(color, 0.0)])
	particles.color_ramp = fade
	particles.direction = Vector2(0.3, 1.0)
	particles.spread = 25.0
	screen.add_child(particles)
	if above and above.get_parent() == screen:
		screen.move_child(particles, above.get_index() + 1)
	_fit_particles(particles, background)
	var refit: Callable = func() -> void: _fit_particles(particles, background)
	particles.set_meta("refit", refit)
	background.resized.connect(refit)
	return particles


## 입자가 화면 전체(위쪽 띠)에서 생기게 맞춘다. 여름 반딧불은 화면 아래 절반에서 생긴다.
static func _fit_particles(particles: CPUParticles2D, background: Control) -> void:
	if not is_instance_valid(particles):
		return
	var area: Vector2 = background.size
	if particles.gravity.y < 0.0:
		particles.position = Vector2(area.x / 2.0, area.y * 0.72)
		particles.emission_rect_extents = Vector2(area.x / 2.0, area.y * 0.25)
	else:
		particles.position = Vector2(area.x / 2.0, -20)
		particles.emission_rect_extents = Vector2(area.x * 0.6, 10)


# ── 버튼·창 ────────────────────────────────────────────

## 누르는 동안 살짝 눌려 들어가고 떼면 튕겨 돌아온다. UiTheme.style_button이 붙인다.
static func attach_press(button: BaseButton) -> void:
	if button == null or button.has_meta("ink_press"):
		return
	button.set_meta("ink_press", true)
	button.button_down.connect(func() -> void: _press_to(button, 0.95, 0.06))
	button.button_up.connect(func() -> void: _press_to(button, 1.0, 0.18))


static func _press_to(button: BaseButton, value: float, time: float) -> void:
	if not enabled() or not button.is_inside_tree():
		button.scale = Vector2.ONE
		return
	button.pivot_offset = button.size / 2.0
	var tween: Tween = button.create_tween()
	tween.tween_property(button, "scale", Vector2(value, value), time) \
		.set_trans(Tween.TRANS_BACK if value >= 1.0 else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 창(판)이 두루마리처럼 위아래로 펼쳐지며 나타난다.
static func unroll(panel: Control, time: float = 0.28) -> void:
	if panel == null or not enabled() or not panel.is_inside_tree():
		return
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(1.0, 0.08)
	panel.modulate.a = 0.0
	var tween: Tween = panel.create_tween().set_parallel()
	tween.tween_property(panel, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, time * 0.6)


## 글자가 위에서 아래로 붓질하듯 차례로 드러난다 (visible_ratio). 글 자체는 바로 다 들어 있다.
static func reveal_text(label: Label, chars_per_second: float = 90.0) -> void:
	if label == null or not enabled() or not label.is_inside_tree():
		return
	var count: int = label.text.length()
	if count == 0:
		return
	# 글자를 다 배치한 뒤에 가린다. (기본값은 보이는 글자만 배치해 줄 수·높이가 연출 중에 달라진다)
	label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	label.visible_ratio = 0.0
	var time: float = clampf(count / chars_per_second, 0.2, 1.2)
	label.create_tween().tween_property(label, "visible_ratio", 1.0, time)


# ── 그림 없이 만드는 입자 텍스처 ──────────────────────

## 부드러운 먹 방울 (가장자리가 번진 원)
static func dot_texture() -> Texture2D:
	if _dot_texture == null:
		_dot_texture = _radial(32, 1.0, 1.0, 1.6)
	return _dot_texture


## 눈송이 (작고 둥근 빛)
static func snow_texture() -> Texture2D:
	if _snow_texture == null:
		_snow_texture = _radial(24, 1.0, 1.0, 2.2)
	return _snow_texture


## 꽃잎·잎 (끝이 뾰족한 타원)
static func petal_texture() -> Texture2D:
	if _petal_texture == null:
		var w: int = 28
		var h: int = 18
		var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var u: float = (x + 0.5) / w * 2.0 - 1.0
				var v: float = (y + 0.5) / h * 2.0 - 1.0
				# 한쪽이 더 뾰족한 잎 모양
				var half: float = (1.0 - absf(u)) * (0.75 + 0.25 * u)
				var d: float = absf(v) / maxf(0.001, half)
				var a: float = clampf((1.0 - d) * 3.0, 0.0, 1.0) * clampf((1.0 - absf(u)) * 4.0, 0.0, 1.0)
				image.set_pixel(x, y, Color(1, 1, 1, a))
		_petal_texture = ImageTexture.create_from_image(image)
	return _petal_texture


static func _radial(size: int, scale_x: float, scale_y: float, falloff: float) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c: float = size / 2.0
	for y in size:
		for x in size:
			var dx: float = (x + 0.5 - c) / c / scale_x
			var dy: float = (y + 0.5 - c) / c / scale_y
			var a: float = pow(clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0), 1.0 / falloff)
			image.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(image)
