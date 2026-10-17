extends Control

## 옵션: 배경음악·효과음 음량, 전체 화면, 글자 크기. 바꾸면 바로 적용하고 저장한다. 화면 구성은 코드로 만든다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

var volume_slider: HSlider
var volume_label: Label
var music_slider: HSlider
var music_label: Label
var fullscreen_check: CheckButton
var text_option: OptionButton
var speed_option: OptionButton
var preview_check: CheckButton
var action_preview_check: CheckButton
var faction_report_check: CheckButton


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
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "설정"
	_UiTheme.style_label_title(title, 24)
	box.add_child(title)

	volume_label = Label.new()
	box.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.custom_minimum_size = Vector2(0, 48)
	volume_slider.value_changed.connect(_on_volume_changed)
	box.add_child(volume_slider)
	music_label = Label.new()
	box.add_child(music_label)
	music_slider = HSlider.new()
	music_slider.min_value = 0
	music_slider.max_value = 100
	music_slider.step = 5
	music_slider.custom_minimum_size = Vector2(0, 48)
	music_slider.value_changed.connect(func(value: float) -> void:
		GameSettings.set_and_save("music_volume", value / 100.0, get_tree())
		_update_volume_label()
	)
	box.add_child(music_slider)

	fullscreen_check = CheckButton.new()
	fullscreen_check.text = "전체 화면"
	fullscreen_check.custom_minimum_size = Vector2(0, 48)
	fullscreen_check.toggled.connect(func(on: bool) -> void: GameSettings.set_and_save("fullscreen", on, get_tree()))
	box.add_child(fullscreen_check)

	var text_row := HBoxContainer.new()
	text_row.add_theme_constant_override("separation", 12)
	var text_label := Label.new()
	text_label.text = "글자 크기"
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_row.add_child(text_label)
	text_option = OptionButton.new()
	text_option.custom_minimum_size = Vector2(200, 48)
	for entry in GameSettings.TEXT_SCALES:
		text_option.add_item(entry[0])
	text_option.item_selected.connect(_on_text_scale_selected)
	text_row.add_child(text_option)
	box.add_child(text_row)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 12)
	var speed_label := Label.new()
	speed_label.text = "전투 속도 (적 차례)"
	speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(speed_label)
	speed_option = OptionButton.new()
	speed_option.custom_minimum_size = Vector2(200, 48)
	for entry in GameSettings.COMBAT_DELAYS:
		speed_option.add_item(entry[0])
	speed_option.item_selected.connect(func(index: int) -> void:
		GameSettings.set_and_save("combat_delay", GameSettings.COMBAT_DELAYS[index][1], get_tree())
	)
	speed_row.add_child(speed_option)
	box.add_child(speed_row)
	preview_check = CheckButton.new()
	preview_check.text = "공격 전 미리보기 (예상 피해 확인 후 실행)"
	preview_check.custom_minimum_size = Vector2(0, 48)
	preview_check.toggled.connect(func(on: bool) -> void: GameSettings.set_and_save("combat_preview", on, get_tree()))
	box.add_child(preview_check)
	action_preview_check = CheckButton.new()
	action_preview_check.text = "행동 전 미리보기 (수치 변화 확인 후 실행)"
	action_preview_check.custom_minimum_size = Vector2(0, 48)
	action_preview_check.toggled.connect(func(on: bool) -> void: GameSettings.set_and_save("action_preview", on, get_tree()))
	box.add_child(action_preview_check)
	faction_report_check = CheckButton.new()
	faction_report_check.text = "계절마다 강호 세력 동향 보기"
	faction_report_check.custom_minimum_size = Vector2(0, 48)
	faction_report_check.toggled.connect(func(on: bool) -> void: GameSettings.set_and_save("faction_report", on, get_tree()))
	box.add_child(faction_report_check)
	var note := Label.new()
	note.text = "글자 크기는 다음에 여는 화면부터 적용됩니다."
	_UiTheme.set_font_size(note, 14)
	box.add_child(note)

	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void: visible = false)
	box.add_child(close)
	_UiTheme.apply_to_control(panel)


func open() -> void:
	volume_slider.set_value_no_signal(roundi(GameSettings.sfx_volume * 100))
	music_slider.set_value_no_signal(roundi(GameSettings.music_volume * 100))
	_update_volume_label()
	fullscreen_check.set_pressed_no_signal(GameSettings.fullscreen)
	preview_check.set_pressed_no_signal(GameSettings.combat_preview)
	action_preview_check.set_pressed_no_signal(GameSettings.action_preview)
	faction_report_check.set_pressed_no_signal(GameSettings.faction_report)
	for i in GameSettings.TEXT_SCALES.size():
		if is_equal_approx(GameSettings.TEXT_SCALES[i][1], GameSettings.text_scale):
			text_option.select(i)
	for i in GameSettings.COMBAT_DELAYS.size():
		if is_equal_approx(GameSettings.COMBAT_DELAYS[i][1], GameSettings.combat_delay):
			speed_option.select(i)
	visible = true


func _update_volume_label() -> void:
	volume_label.text = "효과음 음량: %d%%" % roundi(GameSettings.sfx_volume * 100)
	music_label.text = "배경음악 음량: %d%%" % roundi(GameSettings.music_volume * 100)


func _on_volume_changed(value: float) -> void:
	GameSettings.set_and_save("sfx_volume", value / 100.0, get_tree())
	_update_volume_label()
	AudioManager.play_click()


func _on_text_scale_selected(index: int) -> void:
	GameSettings.set_and_save("text_scale", GameSettings.TEXT_SCALES[index][1], get_tree())
