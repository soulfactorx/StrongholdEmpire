extends Control

## 강호 지도 화면: 지역마다 주인 세력을 색으로 보이고, 고른 지역의 정보와 할 수 있는 일(평정·공략)을 보인다.
## 오른쪽에는 세력마다 전략·땅 수와 지난 계절 동향이 있다. 화면 구성은 코드로 만든다.
## 지역 버튼은 64×48 이상이라 터치로 고를 수 있다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _ConfirmPopup = preload("res://scripts/UI/confirm_popup.gd")
## 지역 버튼 크기
const REGION_SIZE := Vector2(76, 48)
## 세력 색 (없으면 성향 색)
const SECT_COLORS: Dictionary = {
	"qingyun": Color("#2f6b5e"), "namgung": Color("#3e5488"), "heukpung": Color("#5a4a3a"),
	"cheonma": Color("#8c2824"), "wudang": Color("#5e6e88"), "tang": Color("#3e6448"), "haomun": Color("#6e5678"),
}
const ALIGNMENT_COLORS: Dictionary = {
	SectData.Alignment.RIGHTEOUS: Color("#3e5488"),
	SectData.Alignment.UNORTHODOX: Color("#5a4a3a"),
	SectData.Alignment.DEMONIC: Color("#8c2824"),
}
const NEUTRAL_COLOR := Color("#e2d6b8")

var canvas: Control
var info_label: Label
var action_button: Button
var summary_label: Label
var faction_box: VBoxContainer
var log_label: Label
var report_popup: Control
var _region_buttons: Dictionary = {}
var _selected: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.name = "Background"
	background.color = _UiTheme.COLORS["bg_panel"]
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 2.2
	root.add_child(map_panel)
	canvas = Control.new()
	canvas.name = "MapCanvas"
	canvas.clip_contents = true
	canvas.draw.connect(_draw_roads)
	canvas.resized.connect(_layout_regions)
	map_panel.add_child(canvas)

	var side_panel := PanelContainer.new()
	side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(side_panel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side_panel.add_child(side)
	var title := Label.new()
	title.text = "강호 지도"
	_UiTheme.style_label_title(title, 24)
	side.add_child(title)
	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(summary_label, 14)
	side.add_child(summary_label)
	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(info_label)
	action_button = Button.new()
	action_button.name = "RegionActionButton"
	action_button.custom_minimum_size = Vector2(0, 48)
	action_button.pressed.connect(_on_action_pressed)
	side.add_child(action_button)
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(log_label, 14)
	side.add_child(log_label)

	var faction_title := Label.new()
	faction_title.text = "강호 세력"
	_UiTheme.style_label_title(faction_title, 22)
	side.add_child(faction_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	faction_box = VBoxContainer.new()
	faction_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faction_box.add_theme_constant_override("separation", 4)
	scroll.add_child(faction_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	side.add_child(buttons)
	var report_button := Button.new()
	report_button.name = "FactionReportButton"
	report_button.text = "세력 동향"
	report_button.custom_minimum_size = Vector2(0, 48)
	report_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_button.set_meta("help", "지난 계절 강호 세력마다 어떤 전략으로 무엇을 했는지 봅니다.")
	report_button.pressed.connect(open_report)
	buttons.add_child(report_button)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "문파로 돌아가기"
	back.custom_minimum_size = Vector2(0, 48)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_on_back_pressed)
	buttons.add_child(back)

	report_popup = _ConfirmPopup.new()
	add_child(report_popup)

	for region in WorldMap.get_regions():
		var button := Button.new()
		button.name = "Region_" + region["id"]
		button.text = region["name"]
		button.custom_minimum_size = REGION_SIZE
		button.size = REGION_SIZE
		button.pressed.connect(select_region.bind(region["id"]))
		canvas.add_child(button)
		_region_buttons[region["id"]] = button
	_UiTheme.apply_to_control(self)
	refresh()
	var home: String = WorldMap.get_home(GameManager.map_state, GameManager.player_sect.id)
	select_region(home if not home.is_empty() else WorldMap.get_regions()[0]["id"])
	_layout_regions.call_deferred()


## 세력 색. 주인이 없으면 한지 색
static func sect_color(sect_id: String) -> Color:
	if sect_id.is_empty():
		return NEUTRAL_COLOR
	if SECT_COLORS.has(sect_id):
		return SECT_COLORS[sect_id]
	var info: Dictionary = SectRegistry.get_sect_info(sect_id)
	return ALIGNMENT_COLORS.get(SectData.Alignment.get(info.get("alignment", ""), 0), Color("#6b655b"))


func _sect_name(sect_id: String) -> String:
	if sect_id.is_empty():
		return "주인 없음"
	if sect_id == GameManager.player_sect.id:
		return GameManager.player_sect.sect_name
	var sect: SectData = GameManager.get_world_sect(sect_id)
	return sect.sect_name if sect else sect_id


## 지도 좌표(지도 데이터 크기)를 캔버스 크기에 맞춘다.
func _to_canvas(pos: Vector2) -> Vector2:
	var map_size: Vector2 = WorldMap.get_size()
	var area: Vector2 = canvas.size - REGION_SIZE - Vector2(16, 16)
	var scale_factor: float = minf(area.x / map_size.x, area.y / map_size.y)
	var offset: Vector2 = (canvas.size - map_size * scale_factor) / 2.0
	return offset + pos * scale_factor


func _layout_regions() -> void:
	for region in WorldMap.get_regions():
		var button: Button = _region_buttons[region["id"]]
		button.position = _to_canvas(region["pos"]) - REGION_SIZE / 2.0
	canvas.queue_redraw()


func _draw_roads() -> void:
	var drawn: Dictionary = {}
	for region in WorldMap.get_regions():
		for other in region["neighbors"]:
			var key: String = "%s|%s" % ([region["id"], other] if region["id"] < other else [other, region["id"]])
			if drawn.has(key):
				continue
			drawn[key] = true
			canvas.draw_line(
				_to_canvas(region["pos"]), _to_canvas(WorldMap.get_region(other)["pos"]),
				Color(0.12, 0.1, 0.08, 0.35), 3.0, true
			)


func refresh() -> void:
	var state: Dictionary = GameManager.map_state
	var player_id: String = GameManager.player_sect.id
	for region in WorldMap.get_regions():
		_style_region(region["id"])
	var income: Dictionary = WorldMap.income(state, player_id)
	summary_label.text = "%s의 땅 %d / %d · 땅에서 나는 계절 수입 금화 +%d, 식량 +%d\n지역을 눌러 정보를 보고, 문주라면 맞닿은 빈 땅을 평정하거나 남의 땅을 공략합니다." % [
		GameManager.player_sect.sect_name, WorldMap.count(state, player_id), WorldMap.get_regions().size(), income["gold"], income["food"],
	]
	for child in faction_box.get_children():
		faction_box.remove_child(child)
		child.queue_free()
	var reports: Dictionary = {}
	for report in GameManager.last_faction_report:
		reports[report.get("sect_id", "")] = report
	faction_box.add_child(_faction_row(player_id, "우리 문파", ""))
	for sect in GameManager.world_sects:
		var report: Dictionary = reports.get(sect.id, {})
		var last: String = "지난 계절: %s" % report["action"] if not report.is_empty() else ""
		faction_box.add_child(_faction_row(sect.id, "%s 전략%s" % [
			FactionStrategy.get_title(FactionStrategy.of(sect)), " · 굴복" if sect.subjugated else (" · 동맹" if sect.allied else ""),
		], last))


func _faction_row(sect_id: String, note: String, last: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var swatch := ColorRect.new()
	swatch.color = sect_color(sect_id)
	swatch.custom_minimum_size = Vector2(20, 20)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s — 땅 %d · %s%s" % [
		_sect_name(sect_id), WorldMap.count(GameManager.map_state, sect_id), note, "\n" + last if not last.is_empty() else "",
	]
	_UiTheme.set_font_size(label, 14)
	row.add_child(label)
	return row


func _style_region(region_id: String) -> void:
	var button: Button = _region_buttons[region_id]
	var owner: String = WorldMap.get_owner(GameManager.map_state, region_id)
	var color: Color = sect_color(owner)
	var home: bool = not owner.is_empty() and WorldMap.get_home(GameManager.map_state, owner) == region_id
	var mine: bool = owner == GameManager.player_sect.id
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.12) if state == "hover" else color
		style.set_corner_radius_all(24)
		var selected: bool = region_id == _selected
		style.set_border_width_all(4 if selected else (3 if home else 1))
		style.border_color = _UiTheme.COLORS["accent_gold"] if selected else (Color("#f2ead8") if home else Color(0, 0, 0, 0.5))
		if state == "focus":
			style.draw_center = false
		button.add_theme_stylebox_override(state, style)
	var text_color: Color = _UiTheme.COLORS["text_primary"] if owner.is_empty() else Color("#f8f2e4")
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, text_color)
	button.text = ("★" if home else "") + WorldMap.get_region(region_id)["name"]
	button.set_meta("help", "%s — %s%s" % [
		WorldMap.get_region(region_id)["name"], _sect_name(owner), " (우리 땅)" if mine else "",
	])


func select_region(region_id: String) -> void:
	var previous: String = _selected
	_selected = region_id
	if not previous.is_empty():
		_style_region(previous)
	_style_region(region_id)
	var region: Dictionary = WorldMap.get_region(region_id)
	var owner: String = WorldMap.get_owner(GameManager.map_state, region_id)
	var home: bool = not owner.is_empty() and WorldMap.get_home(GameManager.map_state, owner) == region_id
	var neighbors: PackedStringArray = []
	for other in region["neighbors"]:
		neighbors.append(WorldMap.get_region(other)["name"])
	info_label.text = "%s%s\n주인: %s · 주둔 병력 %d\n땅의 수입: 계절마다 금화 +%d, 식량 +%d%s\n%s\n이웃: %s" % [
		region["name"], " (본거지)" if home else "", _sect_name(owner), region["defense"],
		region["gold"], region["food"], " (본거지는 수입 없음)" if home else "",
		region["description"], ", ".join(neighbors),
	]
	var action: Dictionary = GameManager.get_region_action(region_id)
	match action["kind"]:
		"pacify":
			action_button.visible = true
			action_button.text = "평정 (금화 %d · 식량 %d)" % [action["cost"]["gold"], action["cost"]["food"]]
			action_button.disabled = not action["reason"].is_empty()
		"attack":
			action_button.visible = true
			action_button.text = "공략 — %s와(과) 문파전" % _sect_name(action["owner"])
			action_button.disabled = not action["reason"].is_empty()
		_:
			action_button.visible = false
	log_label.text = action.get("reason", "")


func get_selected() -> String:
	return _selected


func _on_action_pressed() -> void:
	var action: Dictionary = GameManager.get_region_action(_selected)
	match action["kind"]:
		"pacify":
			ActionPreview.confirm(self, "평정: %s" % WorldMap.get_region(_selected)["name"],
				GameManager.pacify_region.bind(_selected), _pacify.bind(_selected))
		"attack":
			var result: Dictionary = GameManager.prepare_region_attack(_selected)
			log_label.text = result["message"]
			if result["success"]:
				AudioManager.play_click()
				SceneRouter.goto(get_tree(), SceneRouter.SECT_WAR)


func _pacify(region_id: String) -> void:
	var result: Dictionary = GameManager.pacify_region(region_id)
	if result["success"]:
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	refresh()
	select_region(region_id)
	log_label.text = result["message"]


func open_report() -> void:
	AudioManager.play_click()
	report_popup.open("강호 세력 동향", SectAI.format_reports(GameManager.last_faction_report), Callable(), "확인", "")


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		if report_popup.visible:
			report_popup.visible = false
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)
