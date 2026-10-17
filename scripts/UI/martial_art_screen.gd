extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")
const _ChoicePopup = preload("res://scripts/UI/choice_popup.gd")

## 비급 목록 (MartialArtLibrary: 프리셋 + 모드 무공)
var _preset_arts: Array[MartialArtData] = []
## 강화·비전·분석의 대상을 고르는 팝업과, 지금 고르는 행동
var choice_popup: Control
var _pending_action: String = ""

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
@onready var secret_label: Label = %SecretLabel


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	choice_popup = _ChoicePopup.new()
	add_child(choice_popup)
	choice_popup.chosen.connect(_on_choice_made)
	_setup_options()
	_load_presets()
	_refresh_display()
	EventBus.martial_art_learned.connect(_on_martial_art_learned)
	EventBus.character_updated.connect(_on_character_updated)


## 전역 EventBus 연결은 화면이 트리를 떠날 때 끊는다.
func _exit_tree() -> void:
	if EventBus.martial_art_learned.is_connected(_on_martial_art_learned):
		EventBus.martial_art_learned.disconnect(_on_martial_art_learned)
	if EventBus.character_updated.is_connected(_on_character_updated):
		EventBus.character_updated.disconnect(_on_character_updated)


func _on_martial_art_learned(_art: MartialArtData) -> void:
	_refresh_display()


func _on_character_updated(_character: CharacterData) -> void:
	_refresh_display()


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
	_preset_arts = MartialArtLibrary.get_all()
	for art in _preset_arts:
		preset_list.add_item("%s — %s%s" % [
			art.display_name, art.get_category_name(), " [모드]" if MartialArtLibrary.is_mod(art) else "",
		])


func _refresh_display() -> void:
	known_arts_label.text = "습득 무공: %s" % GameManager.player_character.get_martial_arts_text()
	var secret: MartialArtData = GameManager.player_sect.secret_art
	var analyzed: PackedStringArray = []
	for element in GameManager.analyzed_elements:
		analyzed.append(_element_name(element))
	secret_label.text = "문파 비전: %s\n분석한 상대 속성: %s (상극 속성 무공 창조 성공률 +%d%%)" % [
		"[%s] 강화 %d단계 — 후계자가 물려받습니다" % [secret.display_name, secret.enhance_level] if secret else "없음",
		", ".join(analyzed) if not analyzed.is_empty() else "없음",
		_Balance.COUNTER_SUCCESS_BONUS,
	]
	_update_success_preview()


func _element_name(element: int) -> String:
	var art := MartialArtData.new()
	art.element = element
	return art.get_element_name()


func _update_success_preview() -> void:
	var blueprint: Dictionary = _build_blueprint()
	var complexity: int = MartialArtManager.calculate_complexity(
		blueprint["element"] as MartialArtData.FiveElement,
		blueprint["yin_yang"] as MartialArtData.YinYang,
		blueprint["effects"] as Array
	)
	var counter: int = MartialArtManager.get_counter_bonus(
		blueprint["element"] as MartialArtData.FiveElement, GameManager.analyzed_elements
	)
	var rate: int = mini(_Balance.MAX_SUCCESS_RATE, MartialArtManager.calculate_success_rate(
		GameManager.player_sect,
		GameManager.player_character,
		complexity
	) + counter)
	var cost: int = _Balance.BASE_RESEARCH_COST + complexity * _Balance.RESEARCH_COST_PER_COMPLEXITY
	success_rate_label.text = "예상 성공률: %d%%%s | 연구비: %d점 | 복잡도: %d" % [
		rate, " (상극 +%d)" % counter if counter > 0 else "", cost, complexity,
	]


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
		GameManager.player_character,
		GameManager.analyzed_elements
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

	# 원본(비급 목록)을 지키기 위해 복제본을 익힌다. 강화는 복제본에만 적용된다.
	var art: MartialArtData = _preset_arts[selected[0]].duplicate(true)
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


func _on_enhance_pressed() -> void:
	var options: Array[Dictionary] = []
	for art in GameManager.player_character.martial_arts:
		var maxed: bool = art.enhance_level >= _Balance.ENHANCE_MAX_LEVEL
		options.append({
			"id": art.id,
			"title": "%s (강화 %d/%d)" % [art.display_name, art.enhance_level, _Balance.ENHANCE_MAX_LEVEL],
			"description": "최고 단계" if maxed else "연구점 %d · %s +%d, 내공 소모 -%d" % [
				MartialArtManager.get_enhance_cost(art),
				"회복" if art.heal_amount > 0 else "피해",
				_Balance.ENHANCE_HEAL if art.heal_amount > 0 else _Balance.ENHANCE_DAMAGE,
				_Balance.ENHANCE_INTERNAL_COST_REDUCTION,
			],
		})
	_open_choice("enhance", "무공 강화", "문파의 연구점을 들여 습득한 무공을 갈고닦습니다. 반드시 성공합니다.", options)


func _on_secret_pressed() -> void:
	var options: Array[Dictionary] = []
	for art in GameManager.player_character.martial_arts:
		if art.enhance_level >= _Balance.SECRET_ART_MIN_ENHANCE:
			options.append({"id": art.id, "title": art.display_name, "description": "강화 %d단계 · %s" % [art.enhance_level, art.description]})
	_open_choice("secret", "비전 지정", "강화 %d단계 이상인 무공을 문파 비전으로 정합니다.\n비전은 세대 전승 때 후계자가 물려받고, 제자에게 반값에 전수합니다." % _Balance.SECRET_ART_MIN_ENHANCE, options)


func _on_analyze_pressed() -> void:
	var options: Array[Dictionary] = []
	for art_id in GameManager.observed_arts:
		var observed: Dictionary = GameManager.observed_arts[art_id]
		var element: int = observed["element"]
		var done: bool = GameManager.analyzed_elements.has(element)
		options.append({
			"id": art_id,
			"title": "%s (%s · %s 속성)" % [observed["name"], observed["owner"], _element_name(element)],
			"description": "분석 완료" if done else "연구점 %d · %s 속성 무공 창조 성공률 +%d%%" % [
				_Balance.ANALYZE_RESEARCH,
				_element_name(MartialArtManager.get_counter_element(element)),
				_Balance.COUNTER_SUCCESS_BONUS,
			],
		})
	_open_choice("analyze", "상대 무공 분석", "전투에서 본 상대의 무공을 연구해 그 속성을 이기는 무공을 만들기 쉽게 합니다.", options)


func _open_choice(action: String, title: String, description: String, options: Array[Dictionary]) -> void:
	AudioManager.play_click()
	if options.is_empty():
		log_label.text = "%s: 고를 수 있는 무공이 없습니다." % title
		return
	_pending_action = action
	choice_popup.open(title, description, options)


func _on_choice_made(option_id: String) -> void:
	var sect: SectData = GameManager.player_sect
	var result: Dictionary
	match _pending_action:
		"enhance":
			result = MartialArtManager.enhance(_find_known_art(option_id), sect)
		"secret":
			result = MartialArtManager.designate_secret(_find_known_art(option_id), sect)
		"analyze":
			result = MartialArtManager.analyze(GameManager.observed_arts[option_id], sect, GameManager.analyzed_elements)
		_:
			return
	_pending_action = ""
	log_label.text = result["message"]
	if result["success"]:
		AudioManager.play_success()
		EventBus.resources_changed.emit(sect)
		EventBus.character_updated.emit(GameManager.player_character)
	else:
		AudioManager.play_failure()
	_refresh_display()


func _find_known_art(art_id: String) -> MartialArtData:
	for art in GameManager.player_character.martial_arts:
		if art.id == art_id:
			return art
	return null


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)