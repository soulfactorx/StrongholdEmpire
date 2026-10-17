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


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	_build_settings()
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


func _on_settings_toggle_pressed() -> void:
	settings_grid.visible = not settings_grid.visible
	settings_toggle.text = "세부 설정 ▲" if settings_grid.visible else "세부 설정 ▼"


func _on_name_submitted(_text: String) -> void:
	_on_start_pressed()


func _on_start_pressed() -> void:
	AudioManager.play_click()
	GameManager.start_new_game(
		name_edit.text, _selected_role_id, _selected_scenario.get("id", ScenarioManager.DEFAULT_ID), get_overrides(),
		ironman_check.button_pressed, tutorial_check.button_pressed and tutorial_check.visible
	)
	SceneRouter.goto(get_tree(), SceneRouter.HUB)


func _on_back_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.MAIN_MENU)
