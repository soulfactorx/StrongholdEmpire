extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

@onready var scenario_list: ItemList = %ScenarioList
@onready var scenario_length_label: Label = %ScenarioLengthLabel
@onready var scenario_desc_label: Label = %ScenarioDescLabel
@onready var name_edit: LineEdit = %NameEdit
@onready var role_list: ItemList = %RoleList
@onready var role_desc_label: Label = %RoleDescLabel
@onready var settings_toggle: Button = %SettingsToggle
@onready var settings_grid: GridContainer = %SettingsGrid
@onready var ironman_check: CheckButton = %IronmanCheck
@onready var tutorial_check: CheckButton = %TutorialCheck

var _scenarios: Array[Dictionary] = []
var _role_ids: Array = []
var _selected_scenario: Dictionary = {}
var _selected_role_id: String = StartingRoles.DEFAULT_ID
## 파라미터 이름 → OptionButton (첫 항목은 "시나리오 기본")
var _setting_options: Dictionary = {}
## 강호 세력 설정: 펼침 버튼, 세력 줄을 담는 상자, 세력 id → {check: CheckButton, option: OptionButton}
## 소속 문파 고르기 (낭인은 무소속)
var sect_option: OptionButton
var sect_note: Label
var _sect_ids: Array = []
var faction_toggle: Button
var faction_box: VBoxContainer
var _faction_rows: Dictionary = {}


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	# 세로(휴대폰): 시나리오 칸 위, 인물 칸 아래
	LayoutMode.stack($Margin/VBox/Columns, [0.8, 1.6])
	_build_settings()
	_build_sect_choice()
	_build_faction_section()
	_scenarios = ScenarioManager.list_scenarios()
	scenario_list.clear()
	for scenario in _scenarios:
		scenario_list.add_item(scenario["title"])
	if not _scenarios.is_empty():
		scenario_list.select(0)
		_on_scenario_selected(0)
	name_edit.grab_focus()


func _build_settings() -> void:
	for entry in ScenarioRules.UI_OPTIONS:
		var label := Label.new()
		label.text = entry["label"]
		settings_grid.add_child(label)
		var option := OptionButton.new()
		option.custom_minimum_size = Vector2(200, 48)
		option.add_item("시나리오 기본")
		for choice in entry["options"]:
			option.add_item(choice[0])
		option.item_selected.connect(func(_index: int) -> void: _update_length_text())
		_UiTheme.style_button(option)
		settings_grid.add_child(option)
		_setting_options[entry["param"]] = option


## 소속 문파: 역할 소개 아래에 고르는 칸을 둔다.
func _build_sect_choice() -> void:
	var parent: Node = role_desc_label.get_parent()
	var index: int = role_desc_label.get_index() + 1
	var label := Label.new()
	label.text = "소속 문파"
	parent.add_child(label)
	parent.move_child(label, index)
	sect_option = OptionButton.new()
	sect_option.name = "SectOption"
	sect_option.custom_minimum_size = Vector2(0, 48)
	sect_option.item_selected.connect(func(_i: int) -> void:
		_update_sect_note()
		_fill_factions()
	)
	parent.add_child(sect_option)
	parent.move_child(sect_option, index + 1)
	_UiTheme.style_button(sect_option)
	sect_note = Label.new()
	sect_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(sect_note, 14)
	parent.add_child(sect_note)
	parent.move_child(sect_note, index + 2)


## 시나리오의 기본 문파 id (scenario.json player_sect, 없으면 is_player_sect인 문파)
func _default_sect_id() -> String:
	var sect_id: String = str(_selected_scenario.get("player_sect", ""))
	return sect_id if not sect_id.is_empty() else SectRegistry.get_player_sect_id()


## 시나리오·역할에 맞게 소속 문파 목록을 채운다. 입문 수련처럼 문파가 정해진 시나리오와 낭인은 고를 수 없다.
func _fill_sects() -> void:
	sect_option.clear()
	_sect_ids.clear()
	if StartingRoles.is_unaffiliated(_selected_role_id):
		sect_option.add_item("무소속 (낭인은 문파에 속하지 않습니다)")
		_sect_ids.append("")
		sect_option.disabled = true
		_update_sect_note()
		return
	var default_id: String = _default_sect_id()
	_sect_ids.append(default_id)
	var fixed: bool = _selected_scenario.get("guided", false) == true or _selected_scenario.has("player_sect")
	if not fixed:
		var others: Array = _selected_scenario.get("sects", [])
		if others.is_empty():
			others = SectRegistry.get_default_rival_ids()
		for sect_id in others + SectRegistry.get_optional_ids():
			if not sect_id in _sect_ids and SectRegistry.has_sect(sect_id):
				_sect_ids.append(sect_id)
	for sect_id in _sect_ids:
		var info: Dictionary = SectRegistry.get_sect_info(sect_id)
		sect_option.add_item("%s (%s)%s" % [info.get("sect_name", sect_id), _alignment_name(info.get("alignment", "")), " — 기본" if sect_id == default_id else ""])
	sect_option.disabled = fixed
	sect_option.select(0)
	_update_sect_note()


func _update_sect_note() -> void:
	var sect_id: String = get_player_sect_choice()
	if sect_id.is_empty():
		sect_note.text = "제자·시설 없이 금화·식량을 개인 재산으로 씁니다. 신용을 쌓은 세력에 객경으로 들어갈 수 있습니다."
		return
	var info: Dictionary = SectRegistry.get_sect_info(sect_id)
	sect_note.text = "%s\n제자 %d명 · 명성 %d%s" % [
		info.get("description", ""), int(info.get("disciple_count", 12)), int(info.get("reputation", 50)),
		" (이 시나리오는 문파가 정해져 있습니다)" if sect_option.disabled else "",
	]


## 고른 소속 문파 id ("": 무소속)
func get_player_sect_choice() -> String:
	if _sect_ids.is_empty() or sect_option.selected < 0:
		return ""
	return str(_sect_ids[sect_option.selected])


## 소속 문파를 고른다 (테스트용)
func set_player_sect(sect_id: String) -> void:
	var index: int = _sect_ids.find(sect_id)
	if index >= 0:
		sect_option.select(index)
		_update_sect_note()
		_fill_factions()


## 강호 세력 설정 칸: 세부 설정 아래에 펼침 버튼과 세력 목록을 둔다.
func _build_faction_section() -> void:
	var parent: Node = settings_grid.get_parent()
	faction_toggle = Button.new()
	faction_toggle.name = "FactionToggle"
	faction_toggle.text = "강호 세력 설정 ▼"
	faction_toggle.custom_minimum_size = Vector2(0, 48)
	faction_toggle.set_meta("help", "강호에 나올 세력과 세력마다의 전략(영토 확장·무력 강병·내실 부강·합종연횡·기회주의)을 정합니다.")
	faction_toggle.pressed.connect(func() -> void:
		faction_box.visible = not faction_box.visible
		faction_toggle.text = "강호 세력 설정 ▲" if faction_box.visible else "강호 세력 설정 ▼"
	)
	parent.add_child(faction_toggle)
	_UiTheme.style_button(faction_toggle)
	faction_box = VBoxContainer.new()
	faction_box.name = "FactionBox"
	faction_box.visible = false
	faction_box.add_theme_constant_override("separation", 6)
	parent.add_child(faction_box)


## 시나리오에 나오는 세력(끌 수 없음)과 골라 넣을 수 있는 세력(켜고 끔)을 줄마다 보인다.
func _fill_factions() -> void:
	for child in faction_box.get_children():
		faction_box.remove_child(child)
		child.queue_free()
	_faction_rows.clear()
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "세력마다 전략을 정합니다. 계절이 지나면 [강호 세력 동향]과 [강호 지도]에서 누가 무엇을 했는지 봅니다."
	_UiTheme.set_font_size(note, 14)
	faction_box.add_child(note)
	var scenario_ids: Array = _selected_scenario.get("sects", [])
	if scenario_ids.is_empty():
		scenario_ids = SectRegistry.get_default_rival_ids()
	# 다른 문파에 속하거나 무소속이면 기본 문파도 강호 세력이 되고, 고른 문파는 빠진다.
	var mine: String = get_player_sect_choice()
	var fixed_ids: Array = scenario_ids.duplicate()
	if mine != _default_sect_id():
		fixed_ids.push_front(_default_sect_id())
	for sect_id in fixed_ids:
		if sect_id != mine:
			_add_faction_row(sect_id, true)
	for sect_id in SectRegistry.get_optional_ids():
		if not sect_id in fixed_ids and sect_id != mine:
			_add_faction_row(sect_id, false)


func _add_faction_row(sect_id: String, fixed: bool) -> void:
	if not SectRegistry.has_sect(sect_id):
		return
	var info: Dictionary = SectRegistry.get_sect_info(sect_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var check := CheckButton.new()
	check.text = "%s (%s)" % [info.get("sect_name", sect_id), _alignment_name(info.get("alignment", ""))]
	check.custom_minimum_size = Vector2(0, 48)
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.button_pressed = fixed
	check.disabled = fixed
	check.set_meta("help", "%s\n%s" % [
		info.get("description", ""), "이 시나리오에 늘 나오는 세력입니다." if fixed else "켜면 이 세력이 강호에 더해집니다.",
	])
	row.add_child(check)
	ButtonHelp.attach(check)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(170, 48)
	var default_id: String = str(info.get("strategy", ""))
	if not FactionStrategy.is_valid(default_id):
		default_id = FactionStrategy.default_for(SectData.Alignment.get(info.get("alignment", ""), 0))
	option.add_item("기본: %s" % FactionStrategy.get_title(default_id))
	option.set_item_metadata(0, "")
	option.add_item("무작위")
	option.set_item_metadata(1, FactionStrategy.RANDOM)
	for strategy_id in FactionStrategy.get_ids():
		option.add_item(FactionStrategy.get_title(strategy_id))
		option.set_item_metadata(option.item_count - 1, strategy_id)
	row.add_child(option)
	_UiTheme.style_button(option)
	faction_box.add_child(row)
	_faction_rows[sect_id] = {"check": check, "option": option, "fixed": fixed}


func _alignment_name(alignment: String) -> String:
	var sect := SectData.new()
	sect.alignment = SectData.Alignment.get(alignment, 0)
	return sect.get_alignment_name()


## 세력 설정: {extra: [켠 골라 넣는 세력], strategies: {세력 id: 전략}} (기본은 넣지 않는다)
func get_faction_setup() -> Dictionary:
	var extra: Array = []
	var strategies: Dictionary = {}
	for sect_id in _faction_rows:
		var row: Dictionary = _faction_rows[sect_id]
		if not row["fixed"] and row["check"].button_pressed:
			extra.append(sect_id)
		var strategy: String = str(row["option"].get_item_metadata(row["option"].selected))
		if not strategy.is_empty():
			strategies[sect_id] = strategy
	return {"extra": extra, "strategies": strategies, "player_sect": get_player_sect_choice()}


## 세력 줄을 고른다 (테스트용): enabled는 골라 넣는 세력만, strategy는 전략 id·"random"·""(기본)
func set_faction(sect_id: String, enabled: bool, strategy: String = "") -> void:
	var row: Dictionary = _faction_rows[sect_id]
	if not row["fixed"]:
		row["check"].button_pressed = enabled
	var option: OptionButton = row["option"]
	for i in option.item_count:
		if str(option.get_item_metadata(i)) == strategy:
			option.select(i)


## "세부 설정"에서 고른 값만 모은다. "시나리오 기본"은 넣지 않는다.
func get_overrides() -> Dictionary:
	var overrides: Dictionary = {}
	for entry in ScenarioRules.UI_OPTIONS:
		var option: OptionButton = _setting_options[entry["param"]]
		if option.selected > 0:
			overrides[entry["param"]] = entry["options"][option.selected - 1][1]
	return overrides


func _on_scenario_selected(index: int) -> void:
	_selected_scenario = _scenarios[index]
	scenario_desc_label.text = _selected_scenario.get("description", "")
	# 입문 수련처럼 자체 길잡이가 있는 시나리오에서는 일반 길잡이를 고를 필요가 없다.
	tutorial_check.visible = _selected_scenario.get("guided", false) != true
	_update_length_text()

	# 시나리오마다 고를 수 있는 시작 역할이 다르다.
	var previous_role: String = _selected_role_id
	_role_ids = ScenarioManager.get_start_role_ids(_selected_scenario)
	role_list.clear()
	for role_id in _role_ids:
		role_list.add_item(StartingRoles.get_by_id(role_id)["title"])
	var role_index: int = maxi(0, _role_ids.find(previous_role))
	role_list.select(role_index)
	_on_role_selected(role_index)


func _update_length_text() -> void:
	scenario_length_label.text = "길이: %s" % ScenarioManager.describe_length(_selected_scenario, get_overrides())


func _on_role_selected(index: int) -> void:
	var entry: Dictionary = StartingRoles.get_by_id(_role_ids[index])
	# 이름을 직접 입력하지 않았다면 역할별 기본 이름을 보여준다.
	var previous: Dictionary = StartingRoles.get_by_id(_selected_role_id)
	if name_edit.text.is_empty() or name_edit.text == previous["default_name"]:
		name_edit.text = entry["default_name"]
	_selected_role_id = entry["id"]
	role_desc_label.text = "%s\n\n%s" % [entry["description"], RoleDashboard.describe_role(entry["role"])]
	_fill_sects()
	_fill_factions()


func _on_settings_toggle_pressed() -> void:
	settings_grid.visible = not settings_grid.visible
	settings_toggle.text = "세부 설정 ▲" if settings_grid.visible else "세부 설정 ▼"


func _on_name_submitted(_text: String) -> void:
	_on_start_pressed()


func _on_start_pressed() -> void:
	AudioManager.play_click()
	GameManager.start_new_game(
		name_edit.text, _selected_role_id, _selected_scenario.get("id", ScenarioManager.DEFAULT_ID), get_overrides(),
		ironman_check.button_pressed, tutorial_check.button_pressed and tutorial_check.visible, get_faction_setup()
	)
	SceneRouter.goto(get_tree(), SceneRouter.HUB)


func _on_back_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.MAIN_MENU)
