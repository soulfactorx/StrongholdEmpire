extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")
const _ChoicePopup = preload("res://scripts/UI/choice_popup.gd")

## 참오할 수 있는 비급 목록 (GameManager.get_research_manuals: 문파 서고 + 가진 비급)
var _preset_arts: Array[MartialArtData] = []
## 강화·비전·분석의 대상을 고르는 창과, 지금 고르는 행동
var choice_popup: Control
var _pending_action: String = ""
## 특수 효과 "없음"의 항목 id. (OptionButton은 id -1을 "자동 번호"로 보므로 효과 번호와 겹치지 않는 값을 쓴다)
const NO_EFFECT := 1000

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
	# 세로(휴대폰): 창안 칸 위, 참오·보유 무공 칸 아래로 쌓고 끌어서 본다.
	LayoutMode.stack_scroll($Margin/RootHBox)
	choice_popup = _ChoicePopup.new()
	add_child(choice_popup)
	choice_popup.chosen.connect(_on_choice_made)
	_setup_options()
	_restore_draft()
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
	for option in _option_buttons():
		option.item_selected.connect(func(_i): _on_blueprint_changed())
	name_input.text_changed.connect(func(_text): _save_draft())


func _option_buttons() -> Array[OptionButton]:
	return [category_option, element_option, yin_yang_option, effect1_option, effect2_option, effect3_option]


## 고른 설정이 바뀌면 성공률을 다시 보고, 다음에 와도 이어지게 기억해 둔다.
func _on_blueprint_changed() -> void:
	_update_success_preview()
	_save_draft()


func _save_draft() -> void:
	GameManager.art_draft = _build_blueprint()


## 지난번에 고르던 설정을 되살린다.
func _restore_draft() -> void:
	if not GameManager.art_draft.is_empty():
		apply_blueprint(GameManager.art_draft)


## 설정을 화면에 적용한다 (저장한 설정 불러오기에도 쓴다)
func apply_blueprint(blueprint: Dictionary) -> void:
	name_input.text = str(blueprint.get("name", ""))
	_select_id(category_option, int(blueprint.get("category", 0)))
	_select_id(element_option, int(blueprint.get("element", 0)))
	_select_id(yin_yang_option, int(blueprint.get("yin_yang", 0)))
	var effects: Array = blueprint.get("effects", [])
	var effect_options: Array[OptionButton] = [effect1_option, effect2_option, effect3_option]
	for i in effect_options.size():
		_select_id(effect_options[i], int(effects[i]) if i < effects.size() else NO_EFFECT)
	_on_blueprint_changed()


func _select_id(option: OptionButton, id: int) -> void:
	var index: int = option.get_item_index(id)
	if index >= 0:
		option.select(index)


## 고른 설정을 짧게: "검법 · 화 · 양 · 파괴력, 속도"
func describe_blueprint(blueprint: Dictionary) -> String:
	var parts: PackedStringArray = []
	for pair in [[category_option, "category"], [element_option, "element"], [yin_yang_option, "yin_yang"]]:
		var option: OptionButton = pair[0]
		var index: int = option.get_item_index(int(blueprint.get(pair[1], 0)))
		parts.append(option.get_item_text(index) if index >= 0 else "?")
	var effects: PackedStringArray = []
	for effect in blueprint.get("effects", []):
		var index: int = effect1_option.get_item_index(int(effect))
		if index >= 0:
			effects.append(effect1_option.get_item_text(index))
	parts.append(", ".join(effects) if not effects.is_empty() else "효과 없음")
	return " · ".join(parts)


func _on_save_blueprint_pressed() -> void:
	AudioManager.play_click()
	var result: Dictionary = GameManager.save_art_blueprint(_build_blueprint())
	log_label.text = result["message"]
	Toast.notify_result(self, result)


func _blueprint_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for i in GameManager.art_blueprints.size():
		var blueprint: Dictionary = GameManager.art_blueprints[i]
		options.append({"id": str(i), "title": blueprint["title"], "description": describe_blueprint(blueprint)})
	return options


func _on_load_blueprint_pressed() -> void:
	_open_choice("load_blueprint", "저장한 설정 불러오기", "고른 설정으로 범주·속성·음양·특수 효과를 채웁니다.", _blueprint_options(), "저장한 설정이 없습니다.")


func _on_delete_blueprint_pressed() -> void:
	_open_choice("delete_blueprint", "저장한 설정 지우기", "고른 설정을 목록에서 지웁니다.", _blueprint_options(), "저장한 설정이 없습니다.")


func _fill_enum_options(button: OptionButton, enum_type: Variant, include_none: bool = false) -> void:
	button.clear()
	if include_none:
		button.add_item("없음", NO_EFFECT)
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


## 참오할 수 있는 비급: 소속 문파 서고의 비급과 가진 비급 (강호의 모든 비급이 아니다)
func _load_presets() -> void:
	preset_list.clear()
	_preset_arts.clear()
	for entry in GameManager.get_research_manuals():
		var art: MartialArtData = entry["art"]
		_preset_arts.append(art)
		preset_list.add_item("%s — %s · 깨달음 %d (%s)%s" % [
			art.display_name, art.get_category_name(), art.research_cost, entry["source"],
			" · 익힘" if GameManager.player_character.knows_martial_art(art.id) else "",
		])
	if _preset_arts.is_empty():
		preset_list.add_item("가진 비급이 없습니다. 문파에 몸담거나 기연·사부에게서 얻습니다.")
		preset_list.set_item_disabled(0, true)
		preset_list.set_item_selectable(0, false)


func _refresh_display() -> void:
	var character: CharacterData = GameManager.player_character
	known_arts_label.text = "%d개 · 문파 비전은 ★\n%s" % [character.martial_arts.size(), _mark_secret(character.get_martial_arts_detail())]
	var secret: MartialArtData = GameManager.player_sect.secret_art
	var analyzed: PackedStringArray = []
	for element in GameManager.analyzed_elements:
		analyzed.append(_element_name(element))
	secret_label.text = "문파 비전: %s\n분석한 상대 속성: %s (상극 속성 무공 창안 성공률 +%d%%)" % [
		"[%s] 강화 %d단계 — 후계자가 물려받습니다" % [secret.display_name, secret.enhance_level] if secret else "없음",
		", ".join(analyzed) if not analyzed.is_empty() else "없음",
		_Balance.COUNTER_SUCCESS_BONUS,
	]
	_update_success_preview()


## 문파 비전인 무공 이름에 ★
func _mark_secret(text: String) -> String:
	var secret: MartialArtData = GameManager.player_sect.secret_art
	if secret == null:
		return text
	return text.replace("[%s]" % secret.display_name, "★[%s]" % secret.display_name)


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
	success_rate_label.text = "예상 성공률: %d%%%s | 참오비: %d점 | 복잡도: %d" % [
		rate, " (상극 +%d)" % counter if counter > 0 else "", cost, complexity,
	]


func _collect_effects() -> Array:
	var effects: Array = []
	for option in [effect1_option, effect2_option, effect3_option]:
		var id: int = option.get_selected_id()
		if id != NO_EFFECT:
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
	Toast.notify_result(self, result)
	if result["success"]:
		EventBus.martial_art_learned.emit(result["martial_art"])
		EventBus.resources_changed.emit(GameManager.player_sect)
		EventBus.character_updated.emit(GameManager.player_character)
		# 같은 이름은 다시 못 쓰므로 이름만 비우고 나머지 설정은 남긴다.
		name_input.text = ""
		_save_draft()


func _on_research_preset_pressed() -> void:
	var selected: PackedInt32Array = preset_list.get_selected_items()
	if selected.is_empty():
		log_label.text = "참오할 비급을 선택하세요."
		return

	# 원본(비급 목록)을 지키기 위해 복제본을 익힌다. 강화는 복제본에만 적용된다.
	if selected[0] >= _preset_arts.size():
		return
	var art: MartialArtData = _preset_arts[selected[0]].duplicate(true)
	var result: Dictionary = MartialArtManager.research_existing(
		art,
		GameManager.player_sect,
		GameManager.player_character
	)
	log_label.text = result["message"]
	Toast.notify_result(self, result)
	if result["success"]:
		EventBus.martial_art_learned.emit(result["martial_art"])
		EventBus.resources_changed.emit(GameManager.player_sect)
		EventBus.character_updated.emit(GameManager.player_character)
		_load_presets()


func _on_enhance_pressed() -> void:
	var options: Array[Dictionary] = []
	for art in GameManager.player_character.martial_arts:
		var maxed: bool = art.enhance_level >= _Balance.ENHANCE_MAX_LEVEL
		options.append({
			"id": art.id,
			"title": "%s (강화 %d/%d)" % [art.display_name, art.enhance_level, _Balance.ENHANCE_MAX_LEVEL],
			"description": "최고 단계" if maxed else "깨달음 %d · %s +%d, 내공 소모 -%d" % [
				MartialArtManager.get_enhance_cost(art),
				"회복" if art.heal_amount > 0 else "피해",
				_Balance.ENHANCE_HEAL if art.heal_amount > 0 else _Balance.ENHANCE_DAMAGE,
				_Balance.ENHANCE_INTERNAL_COST_REDUCTION,
			],
		})
	_open_choice("enhance", "무공 강화", "문파의 깨달음을 들여 습득한 무공을 갈고닦습니다. 반드시 성공합니다.", options)


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
			"description": "분석 완료" if done else "깨달음 %d · %s 속성 무공 창안 성공률 +%d%%" % [
				_Balance.ANALYZE_RESEARCH,
				_element_name(MartialArtManager.get_counter_element(element)),
				_Balance.COUNTER_SUCCESS_BONUS,
			],
		})
	_open_choice("analyze", "상대 무공 분석", "전투에서 본 상대의 무공을 참오해 그 속성을 이기는 무공을 만들기 쉽게 합니다.", options)


func _open_choice(action: String, title: String, description: String, options: Array[Dictionary], empty_text: String = "") -> void:
	AudioManager.play_click()
	if options.is_empty():
		log_label.text = empty_text if not empty_text.is_empty() else "%s: 고를 수 있는 무공이 없습니다." % title
		Toast.notify(self, log_label.text, true)
		return
	_pending_action = action
	choice_popup.open(title, description, options)


func _on_choice_made(option_id: String) -> void:
	var sect: SectData = GameManager.player_sect
	var result: Dictionary
	match _pending_action:
		"load_blueprint", "delete_blueprint":
			_on_blueprint_chosen(_pending_action, int(option_id))
			_pending_action = ""
			return
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
	Toast.notify_result(self, result)
	if result["success"]:
		AudioManager.play_success()
		EventBus.resources_changed.emit(sect)
		EventBus.character_updated.emit(GameManager.player_character)
	else:
		AudioManager.play_failure()
	_refresh_display()


func _on_blueprint_chosen(action: String, index: int) -> void:
	if index < 0 or index >= GameManager.art_blueprints.size():
		return
	var blueprint: Dictionary = GameManager.art_blueprints[index]
	if action == "load_blueprint":
		apply_blueprint(blueprint)
		log_label.text = "설정 「%s」을(를) 불러왔습니다." % blueprint["title"]
	else:
		GameManager.art_blueprints.remove_at(index)
		log_label.text = "설정 「%s」을(를) 지웠습니다." % blueprint["title"]


func _find_known_art(art_id: String) -> MartialArtData:
	for art in GameManager.player_character.martial_arts:
		if art.id == art_id:
			return art
	return null


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)