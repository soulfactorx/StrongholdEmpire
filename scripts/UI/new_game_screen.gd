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
var faction_toggle: Button
var faction_box: VBoxContainer
var _faction_rows: Dictionary = {}


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	# 세로(휴대폰): 시나리오 칸 위, 인물 칸 아래
	LayoutMode.stack($Margin/VBox/Columns, [0.8, 1.6])
	_build_settings()
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
	for sect_id in scenario_ids:
		_add_faction_row(sect_id, true)
	for sect_id in SectRegistry.get_optional_ids():
		if not sect_id in scenario_ids:
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
	return {"extra": extra, "strategies": strategies}


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
	_fill_factions()


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
