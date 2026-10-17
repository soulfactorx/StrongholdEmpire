extends Control

## 시설 관리 팝업: 시설별 레벨·효과·확장 비용을 보여 주고 확장한다. 화면 구성은 코드로 만든다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

## 확장을 시도한 결과 (success, message)
signal upgraded(result: Dictionary)

var _rows: VBoxContainer


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
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "시설 관리"
	_UiTheme.style_label_title(title, 24)
	box.add_child(title)
	var note := Label.new()
	note.text = "확장할수록 비용이 오르고, 시작 수준을 넘는 단계마다 계절 유지비 금화 %d가 듭니다." % _Balance.FACILITY_UPKEEP_GOLD
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(note, 13)
	box.add_child(note)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)

	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void: visible = false)
	box.add_child(close)
	_UiTheme.apply_to_control(panel)


func open() -> void:
	_refresh()
	visible = true


func _refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var sect: SectData = GameManager.player_sect
	# 막내 제자는 시설을 볼 수만 있고 확장할 수 없다.
	var can_build: bool = GameManager.player_character.role != CharacterData.Role.YOUNG_DISCIPLE
	for facility in SectManager.get_facility_ids():
		var spec: Array = _Balance.FACILITIES[facility]
		var info: Dictionary = SectManager.FACILITY_INFO[facility]
		var level: int = SectManager.get_facility_level(sect, facility)
		var cost: int = SectManager.get_upgrade_cost(sect, facility)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s  Lv.%d / %d\n%s" % [info["name"], level, spec[1], info["effect"]]
		row.add_child(label)

		var button := Button.new()
		button.custom_minimum_size = Vector2(200, 48)
		if cost < 0:
			button.text = "최고 수준"
			button.disabled = true
		elif not can_build:
			button.text = "권한 없음 (막내 제자)"
			button.disabled = true
		else:
			button.text = ("짓기" if level == 0 else "확장") + " (금화 %d)" % cost
			button.disabled = sect.gold < cost
			button.pressed.connect(_on_upgrade_pressed.bind(facility))
		_UiTheme.style_button(button)
		row.add_child(button)
		_rows.add_child(row)


func _on_upgrade_pressed(facility: String) -> void:
	ActionPreview.confirm(
		self, "%s 확장" % SectManager.FACILITY_INFO[facility]["name"],
		GameManager.upgrade_facility.bind(facility), _upgrade.bind(facility)
	)


func _upgrade(facility: String) -> void:
	var result: Dictionary = GameManager.upgrade_facility(facility)
	upgraded.emit(result)
	_refresh()
