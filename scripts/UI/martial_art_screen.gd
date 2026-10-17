extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

const PRESET_PATHS: Array[String] = [
	"res://resources/MartialArts/soul_chase_sword.tres",
	"res://resources/MartialArts/earth_life_palm.tres",
]

var _preset_arts: Array[MartialArtData] = []

@onready var name_input: LineEdit = %NameInput
@onready var category_option: OptionButton = %CategoryOption
@onready var element_option: OptionButton = %ElementOption
@onready var yin_yang_option: OptionButton = %YinYangOption
@onready var effect1_option: OptionButton = %Effect1Option
@onready var effect2_option: OptionButton = %Effect2Option
@onready var effect3_option: OptionButton = %Effect3Option
@onready var success_rate_label: Label = %SuccessRateLabel
@onready var known_arts_label: Label = %KnownArtsLabel
@onready var preset_list: ItemList = %PresetList
@onready var log_label: Label = %LogLabel


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	_setup_options()
	_load_presets()
	_refresh_display()
	EventBus.martial_art_learned.connect(func(_art): _refresh_display())
	EventBus.character_updated.connect(func(_c): _refresh_display())


func _setup_options() -> void:
	_fill_enum_options(category_option, MartialArtData.Category)
	_fill_enum_options(element_option, MartialArtData.FiveElement)
	_fill_enum_options(yin_yang_option, MartialArtData.YinYang)
	_fill_enum_options(effect1_option, MartialArtData.SpecialEffect, true)
	_fill_enum_options(effect2_option, MartialArtData.SpecialEffect, true)
	_fill_enum_options(effect3_option, MartialArtData.SpecialEffect, true)
	category_option.item_selected.connect(func(_i): _update_success_preview())
	element_option.item_selected.connect(func(_i): _update_success_preview())
	yin_yang_option.item_selected.connect(func(_i): _update_success_preview())
	effect1_option.item_selected.connect(func(_i): _update_success_preview())
	effect2_option.item_selected.connect(func(_i): _update_success_preview())
	effect3_option.item_selected.connect(func(_i): _update_success_preview())


func _fill_enum_options(button: OptionButton, enum_type: Variant, include_none: bool = false) -> void:
	button.clear()
	if include_none:
		button.add_item("없음", -1)
	var keys: PackedStringArray = enum_type.keys()
	for i in keys.size():
		button.add_item(_enum_label(keys[i]), enum_type[keys[i]])


func _enum_label(key: String) -> String:
	match key:
		"SWORD":
			return "검법"
		"PALM":
			return "장법"
		"FIST":
			return "권법"
		"LEG":
			return "퇴법"
		"FINGER":
			return "지법"
		"HIDDEN":
			return "암기"
		"QINGGONG":
			return "경공"
		"INTERNAL":
			return "내공심법"
		"NONE":
			return "무"
		"WOOD":
			return "목"
		"FIRE":
			return "화"
		"EARTH":
			return "토"
		"METAL":
			return "금"
		"WATER":
			return "수"
		"YIN":
			return "음"
		"YANG":
			return "양"
		"BALANCED":
			return "균형"
		"SPEED":
			return "속도"
		"DESTRUCTION":
			return "파괴력"
		"AMBUSH":
			return "기습"
		"CONTROL":
			return "제어"
		"HEAL":
			return "회복"
		"MOVE":
			return "이동"
		"RANGE":
			return "범위"
		"BUFF":
			return "강화"
		_:
			return key


func _load_presets() -> void:
	preset_list.clear()
	_preset_arts.clear()
	for path in PRESET_PATHS:
		var art: MartialArtData = load(path) as MartialArtData
		if art:
			_preset_arts.append(art)
			preset_list.add_item("%s — %s" % [art.display_name, art.get_category_name()])
	for mod_art in GameManager.mod_martial_arts:
		_preset_arts.append(mod_art)
		preset_list.add_item("%s — %s [모드]" % [mod_art.display_name, mod_art.get_category_name()])


func _refresh_display() -> void:
	known_arts_label.text = "습득 무공: %s" % GameManager.player_character.get_martial_arts_text()
	_update_success_preview()


func _update_success_preview() -> void:
	var blueprint: Dictionary = _build_blueprint()
	var complexity: int = MartialArtManager.calculate_complexity(
		blueprint["element"] as MartialArtData.FiveElement,
		blueprint["yin_yang"] as MartialArtData.YinYang,
		blueprint["effects"] as Array
	)
	var rate: int = MartialArtManager.calculate_success_rate(
		GameManager.player_sect,
		GameManager.player_character,
		complexity
	)
	var cost: int = 20 + complexity * 8
	success_rate_label.text = "예상 성공률: %d%% | 연구비: %d점 | 복잡도: %d" % [rate, cost, complexity]


func _collect_effects() -> Array:
	var effects: Array = []
	for option in [effect1_option, effect2_option, effect3_option]:
		var id: int = option.get_selected_id()
		if id >= 0:
			effects.append(id)
	return effects


func _build_blueprint() -> Dictionary:
	return {
		"name": name_input.text,
		"category": category_option.get_selected_id(),
		"element": element_option.get_selected_id(),
		"yin_yang": yin_yang_option.get_selected_id(),
		"effects": _collect_effects(),
	}


func _on_create_pressed() -> void:
	var result: Dictionary = MartialArtManager.create_from_blueprint(
		_build_blueprint(),
		GameManager.player_sect,
		GameManager.player_character
	)
	log_label.text = result["message"]
	if result["success"]:
		EventBus.martial_art_learned.emit(result["martial_art"])
		EventBus.resources_changed.emit(GameManager.player_sect)
		EventBus.character_updated.emit(GameManager.player_character)
		name_input.text = ""


func _on_research_preset_pressed() -> void:
	var selected: PackedInt32Array = preset_list.get_selected_items()
	if selected.is_empty():
		log_label.text = "연구할 비급을 선택하세요."
		return

	var art: MartialArtData = _preset_arts[selected[0]]
	var result: Dictionary = MartialArtManager.research_existing(
		art,
		GameManager.player_sect,
		GameManager.player_character
	)
	log_label.text = result["message"]
	if result["success"]:
		EventBus.martial_art_learned.emit(result["martial_art"])
		EventBus.resources_changed.emit(GameManager.player_sect)
		EventBus.character_updated.emit(GameManager.player_character)


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)