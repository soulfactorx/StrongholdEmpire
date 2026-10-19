extends Control

## 강호 연표: 이 이야기의 큰 사건이 언제 일어나는지(남은 계절)와, 사건마다 갈림길이 어떤 조건으로 나뉘는지 보여 준다.
## 지금 조건을 채운 갈림길에는 ★를 붙인다. 지난 사건은 위에 짧게 남긴다. 화면 구성은 코드로 만든다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

var _body: Label
var _scroll: ScrollContainer


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	LayoutMode.fit_width(panel, 960)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "강호 연표"
	_UiTheme.style_label_title(title, 24)
	box.add_child(title)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "다가오는 큰 사건과 남은 계절입니다. 사건마다 갈림길의 조건을 보고 미리 준비하세요. ★는 지금 조건을 채운 갈림길입니다.\n(남은 계절은 어림입니다. 한 계절에는 사건이 하나씩 일어나므로 조금 늦어질 수 있습니다.)"
	_UiTheme.set_font_size(note, 14)
	box.add_child(note)
	_scroll = ScrollContainer.new()
	_scroll.name = "TimelineScroll"
	_scroll.custom_minimum_size = Vector2(0, 520)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_body = Label.new()
	_body.name = "TimelineText"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_UiTheme.set_font_size(_body, 16)
	_scroll.add_child(_body)
	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 52)
	close.pressed.connect(func() -> void: visible = false)
	box.add_child(close)
	_UiTheme.apply_to_control(panel)


func open() -> void:
	_body.text = describe(GameManager.get_timeline())
	_scroll.scroll_vertical = 0
	visible = true


## 연표 글 (테스트에서도 쓴다)
static func describe(entries: Array[Dictionary]) -> String:
	if entries.is_empty():
		return "이 이야기에는 연표에 오른 사건이 없습니다."
	var past: PackedStringArray = []
	var lines: PackedStringArray = []
	for entry in entries:
		if entry["done"]:
			past.append(entry["title"])
			continue
		var when: String = "시기를 알 수 없음"
		var left: int = entry["seasons_left"]
		if left == 0:
			when = "이번 계절"
		elif left > 0:
			when = "%d계절 뒤 (%s 무렵)" % [left, entry["date"]]
		lines.append("▶ %s — %s" % [entry["title"], when])
		if not str(entry["hint"]).is_empty():
			lines.append("   " + str(entry["hint"]))
		for branch in entry["branches"]:
			var mark: String = "★" if branch["met"] else "·"
			lines.append("   %s %s" % [mark, branch["text"]])
		lines.append("")
	var text: String = "\n".join(lines).strip_edges()
	if not past.is_empty():
		text = "지난 사건: %s\n\n%s" % [" → ".join(past), text]
	return text
