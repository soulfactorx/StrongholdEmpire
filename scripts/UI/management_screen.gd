extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

@onready var year_label: Label = %YearLabel
@onready var season_label: Label = %SeasonLabel
@onready var generation_label: Label = %GenerationLabel
@onready var sect_name_label: Label = %SectNameLabel
@onready var gold_label: Label = %GoldLabel
@onready var food_label: Label = %FoodLabel
@onready var reputation_label: Label = %ReputationLabel
@onready var research_label: Label = %ResearchLabel
@onready var disciple_label: Label = %DiscipleLabel
@onready var library_label: Label = %LibraryLabel
@onready var training_label: Label = %TrainingLabel
@onready var treasury_label: Label = %TreasuryLabel
@onready var character_name_label: Label = %CharacterNameLabel
@onready var character_role_label: Label = %CharacterRoleLabel
@onready var character_stats_label: Label = %CharacterStatsLabel
@onready var martial_arts_label: Label = %MartialArtsLabel
@onready var relationship_label: Label = %RelationshipLabel
@onready var log_label: Label = %LogLabel
@onready var event_popup: Control = %EventPopup
@onready var role_popup: Control = %RolePopup


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	EventBus.turn_advanced.connect(_on_turn_advanced)
	EventBus.resources_changed.connect(_on_resources_changed)
	EventBus.character_updated.connect(_on_character_updated)
	EventBus.relationships_changed.connect(_on_relationships_changed)
	EventBus.action_message.connect(_on_action_message)
	EventBus.event_triggered.connect(_on_event_triggered)
	EventBus.role_transitions_available.connect(_on_role_transitions_available)
	EventBus.role_changed.connect(_on_role_changed)
	EventBus.ending_reached.connect(_on_ending_reached)
	_refresh_all()
	if not GameManager.pending_event.is_empty():
		event_popup.show_event(GameManager.pending_event)


func _refresh_all() -> void:
	_update_time_display()
	_update_sect_display(GameManager.player_sect)
	_update_character_display(GameManager.player_character)
	_update_relationships_display(GameManager.player_relationships)


func _update_time_display() -> void:
	year_label.text = "천하대란 %d년" % GameManager.current_year
	season_label.text = GameManager.get_current_season()
	generation_label.text = "제%d세대" % GameManager.generation


func _update_sect_display(sect: SectData) -> void:
	sect_name_label.text = sect.sect_name
	gold_label.text = "금화: %d" % sect.gold
	food_label.text = "식량: %d" % sect.food
	reputation_label.text = "명성: %d" % sect.reputation
	research_label.text = "연구점: %d" % sect.research_points
	disciple_label.text = "제자: %d / %d" % [sect.disciple_count, sect.max_disciples]
	library_label.text = "서고 Lv.%d" % sect.library_level
	training_label.text = "무술장 Lv.%d" % sect.training_ground_level
	treasury_label.text = "금고 Lv.%d" % sect.treasury_level


func _update_character_display(character: CharacterData) -> void:
	character_name_label.text = "%s (%d세)" % [character.display_name, character.age]
	character_role_label.text = character.get_role_name()
	character_stats_label.text = (
		"무력 %d | 신법 %d | 지혜 %d | 매력 %d\n내공 %d/%d | 전투력 %d | 도덕 %d | Lv.%d (경험 %d/%d)"
		% [
			character.strength,
			character.agility,
			character.wisdom,
			character.charisma,
			character.internal_energy_current,
			character.internal_energy_max,
			character.get_combat_power(),
			character.morality,
			character.level,
			character.experience,
			character.get_next_level_experience(),
		]
	)
	martial_arts_label.text = "무공: %s" % character.get_martial_arts_text()


func _update_relationships_display(relationships: Array[RelationshipData]) -> void:
	relationship_label.text = RelationshipManager.format_relationships(relationships)


func _on_turn_advanced(_year: int, _season: String) -> void:
	_update_time_display()
	if GameManager.pending_event.is_empty():
		_on_action_message("계절이 지나갔습니다. 자원이 갱신되었습니다.")


func _on_resources_changed(sect: SectData) -> void:
	_update_sect_display(sect)


func _on_character_updated(character: CharacterData) -> void:
	_update_character_display(character)


func _on_relationships_changed(relationships: Array[RelationshipData]) -> void:
	_update_relationships_display(relationships)


func _on_action_message(message: String) -> void:
	log_label.text = message


func _on_event_triggered(event_data: Dictionary) -> void:
	AudioManager.play_event()
	event_popup.show_event(event_data)


func _on_role_transitions_available(options: Array[Dictionary]) -> void:
	if not options.is_empty():
		_on_action_message("새로운 역할 전환 기회가 있습니다. [역할 전환] 버튼을 누르세요.")


func _on_role_changed(_new_role: CharacterData.Role) -> void:
	_update_character_display(GameManager.player_character)


func _on_ending_reached(ending_id: String) -> void:
	var ending: Dictionary = EndingManager.get_ending(ending_id)
	_on_action_message("엔딩 도달: %s — [엔딩/레거시] 메뉴에서 확인하세요." % ending["title"])


func _execute_action(result: Dictionary) -> void:
	EventBus.action_message.emit(result["message"])
	if result["success"]:
		EventBus.resources_changed.emit(GameManager.player_sect)
		EventBus.character_updated.emit(GameManager.player_character)


func _on_advance_turn_pressed() -> void:
	AudioManager.play_click()
	GameManager.advance_turn()


func _on_train_pressed() -> void:
	_execute_action(SectManager.train_disciples(GameManager.player_sect, GameManager.player_character))


func _on_upgrade_library_pressed() -> void:
	_execute_action(SectManager.upgrade_library(GameManager.player_sect))


func _on_upgrade_training_pressed() -> void:
	_execute_action(SectManager.upgrade_training_ground(GameManager.player_sect))


func _on_upgrade_treasury_pressed() -> void:
	_execute_action(SectManager.upgrade_treasury(GameManager.player_sect))


func _on_martial_art_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.MARTIAL_ART)


func _on_role_pressed() -> void:
	if GameManager.pending_role_transitions.is_empty():
		_on_action_message("현재 가능한 역할 전환이 없습니다.")
		return
	role_popup.show_options(GameManager.pending_role_transitions)


func _on_combat_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.COMBAT)


func _on_sect_war_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.SECT_WAR)


func _on_ending_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.ENDING)


func _on_save_pressed() -> void:
	AudioManager.play_click()
	var result: Dictionary = GameManager.save_game()
	_on_action_message(result["message"])
	if result["success"]:
		AudioManager.play_success()
	else:
		AudioManager.play_failure()


func _on_help_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.HELP)


func _on_main_menu_pressed() -> void:
	AudioManager.play_click()
	SceneRouter.goto(get_tree(), SceneRouter.MAIN_MENU)