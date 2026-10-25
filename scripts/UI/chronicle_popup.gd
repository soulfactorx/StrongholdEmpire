extends Control

## 강호 연대기: 이번 이야기에서 일어난 일(기연 선택, 오간 대사, 전투, 외교, 신분 변화, 결말)을 최근 것부터 보여 준다.
## 갈래 버튼으로 골라 볼 수 있다. 화면 구성은 코드로 만든다. 버튼은 모두 48px 이상, 목록은 끌어서 스크롤한다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
## 한 번에 보여 줄 최대 항목 수
const SHOW_LIMIT := 200
## 갈래 버튼: [이름, 포함할 kind 목록 (비면 전체)]
const FILTERS: Array = [
	["전체", []],
	["기연", ["기연", "시작", "결말", "세대"]],
	["대화·외교", ["대화", "외교", "행동"]],
	["전투", ["전투", "문파전"]],
	["신분", ["신분", "세대"]],
	["인물·세력", ["인물", "세력", "영토"]],
]

var _summary: Label
var _entries: VBoxContainer
var _scroll: ScrollContainer
var _filter_buttons: Array[Button] = []
var _filter: int = 0


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
	# 세로 화면(휴대폰)에서는 화면 폭에 맞춘다
	LayoutMode.fit_width(panel, 960)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "강호 연대기"
	_UiTheme.style_label_title(title, 24)
	box.add_child(title)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(_summary, 14)
	box.add_child(_summary)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	box.add_child(filters)
	var group := ButtonGroup.new()
	for i in FILTERS.size():
		var button := Button.new()
		button.name = "Filter%d" % i
		button.text = FILTERS[i][0]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == 0
		button.custom_minimum_size = Vector2(0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("help", "연대기에서 %s 항목만 봅니다." % FILTERS[i][0] if i > 0 else "모든 기록을 봅니다.")
		button.pressed.connect(set_filter.bind(i))
		filters.add_child(button)
		_filter_buttons.append(button)

	_scroll = ScrollContainer.new()
	_scroll.name = "ChronicleScroll"
	_scroll.custom_minimum_size = Vector2(0, 440)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_entries = VBoxContainer.new()
	_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries.add_theme_constant_override("separation", 10)
	_scroll.add_child(_entries)

	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void: visible = false)
	box.add_child(close)
	_UiTheme.apply_to_control(panel)


func open() -> void:
	refresh()
	visible = true


func set_filter(index: int) -> void:
	_filter = index
	_filter_buttons[index].set_pressed_no_signal(true)
	refresh()


## 지금 갈래에 보이는 항목 수 (테스트용)
func get_entry_count() -> int:
	return _entries.get_child_count()


func refresh() -> void:
	var scenario: Dictionary = ScenarioManager.current
	_summary.text = "시나리오 「%s」 · %s · 제%d세대 %s (%s)\n%s" % [
		scenario.get("title", "강호"), GameManager.get_date_text(), GameManager.generation,
		GameManager.player_character.display_name, GameManager.player_character.get_role_name(),
		str(scenario.get("description", "")),
	]
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	var kinds: Array = FILTERS[_filter][1]
	var shown: int = 0
	var chronicle: Array[Dictionary] = GameManager.chronicle
	for i in range(chronicle.size() - 1, -1, -1):
		var entry: Dictionary = chronicle[i]
		if not kinds.is_empty() and not entry.get("kind", "") in kinds:
			continue
		_entries.add_child(_make_entry(entry))
		shown += 1
		if shown >= SHOW_LIMIT:
			break
	if shown == 0:
		var empty := Label.new()
		empty.text = "아직 남은 기록이 없습니다."
		_entries.add_child(empty)
	_scroll.scroll_vertical = 0


func _make_entry(entry: Dictionary) -> VBoxContainer:
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 2)
	var head := Label.new()
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.text = "%s · 〈%s〉 %s" % [entry.get("date", ""), entry.get("kind", ""), entry.get("text", "")]
	head.add_theme_color_override("font_color", _UiTheme.COLORS["accent_gold"])
	_UiTheme.set_font_size(head, 16)
	item.add_child(head)
	for line in entry.get("lines", []):
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "    " + str(line)
		_UiTheme.set_font_size(label, 14)
		item.add_child(label)
	return item
