class_name MartialArtManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")
const MAX_EFFECTS := 3


## analyzed_elements: 상대 무공 분석으로 파악한 속성. 그 속성을 이기는 속성이면 성공률이 오른다.
static func create_from_blueprint(
	blueprint: Dictionary,
	sect: SectData,
	character: CharacterData,
	analyzed_elements: Array = []
) -> Dictionary:
	var name: String = blueprint.get("name", "").strip_edges()
	if name.is_empty():
		return {"success": false, "message": "무공 이름을 입력하세요."}

	var category: MartialArtData.Category = blueprint.get("category", MartialArtData.Category.SWORD)
	var element: MartialArtData.FiveElement = blueprint.get("element", MartialArtData.FiveElement.NONE)
	var yin_yang: MartialArtData.YinYang = blueprint.get("yin_yang", MartialArtData.YinYang.BALANCED)
	var effects: Array = blueprint.get("effects", [])

	if effects.size() > MAX_EFFECTS:
		return {"success": false, "message": "특수 효과는 최대 %d개까지입니다." % MAX_EFFECTS}

	var complexity := calculate_complexity(element, yin_yang, effects)
	var research_cost: int = _Balance.BASE_RESEARCH_COST + complexity * _Balance.RESEARCH_COST_PER_COMPLEXITY

	if sect.research_points < research_cost:
		return {
			"success": false,
			"message": "깨달음이 부족합니다. (%d 필요)" % research_cost,
		}

	var success_rate: int = mini(
		_Balance.MAX_SUCCESS_RATE,
		calculate_success_rate(sect, character, complexity) + get_counter_bonus(element, analyzed_elements)
	)
	var roll := randi_range(1, 100)
	sect.research_points -= research_cost

	if roll > success_rate:
		var backlash := 10 + complexity * 5
		character.internal_energy_current = maxi(
			0,
			character.internal_energy_current - backlash
		)
		return {
			"success": false,
			"message": (
				"참오 실패! 내공 반동으로 %d 피해. (성공률 %d%%, 주사위 %d)"
				% [backlash, success_rate, roll]
			),
		}

	var art := MartialArtData.new()
	art.id = "custom_%s_%d" % [name, Time.get_unix_time_from_system()]
	art.display_name = name
	art.category = category
	art.element = element
	art.yin_yang = yin_yang
	art.complexity = complexity
	art.research_cost = research_cost
	for effect in effects:
		art.special_effects.append(effect)
	_apply_effect_stats(art)
	art.description = _build_description(art)

	character.learn_martial_art(art)
	return {
		"success": true,
		"message": "무공 창안 성공! [%s] 완성 (성공률 %d%%)" % [name, success_rate],
		"martial_art": art,
	}


static func research_existing(
	art: MartialArtData,
	sect: SectData,
	character: CharacterData
) -> Dictionary:
	if character.knows_martial_art(art.id):
		return {"success": false, "message": "이미 습득한 무공입니다."}

	if sect.research_points < art.research_cost:
		return {
			"success": false,
			"message": "깨달음이 부족합니다. (%d 필요)" % art.research_cost,
		}

	var success_rate := calculate_success_rate(sect, character, art.complexity)
	var roll := randi_range(1, 100)
	sect.research_points -= art.research_cost

	if roll > success_rate:
		var backlash := 8 + art.complexity * 4
		character.internal_energy_current = maxi(
			0,
			character.internal_energy_current - backlash
		)
		return {
			"success": false,
			"message": "비급 참오 실패! 내공 반동 %d. (%d%% / %d)" % [backlash, success_rate, roll],
		}

	character.learn_martial_art(art)
	return {
		"success": true,
		"message": "[%s] 참오 완료!" % art.display_name,
		"martial_art": art,
	}


static func calculate_success_rate(
	sect: SectData,
	character: CharacterData,
	complexity: int
) -> int:
	var rate: int = _Balance.BASE_SUCCESS_RATE
	rate += sect.library_level * _Balance.LIBRARY_SUCCESS_BONUS
	rate += character.wisdom * _Balance.WISDOM_SUCCESS_MULTIPLIER
	rate -= complexity * _Balance.COMPLEXITY_PENALTY
	return clampi(rate, _Balance.MIN_SUCCESS_RATE, _Balance.MAX_SUCCESS_RATE)


## 분석한 속성을 이기는(상극) 속성이면 성공률 가산
static func get_counter_bonus(element: MartialArtData.FiveElement, analyzed_elements: Array) -> int:
	var countered: Variant = CombatRules.ELEMENT_OVERCOMES.get(element)
	if countered != null and analyzed_elements.has(int(countered)):
		return _Balance.COUNTER_SUCCESS_BONUS
	return 0


## 이 속성을 이기는 속성 (상극). 없으면 NONE
static func get_counter_element(element: MartialArtData.FiveElement) -> MartialArtData.FiveElement:
	for attacker in CombatRules.ELEMENT_OVERCOMES:
		if CombatRules.ELEMENT_OVERCOMES[attacker] == element:
			return attacker
	return MartialArtData.FiveElement.NONE


static func get_enhance_cost(art: MartialArtData) -> int:
	return _Balance.ENHANCE_RESEARCH_BASE + art.enhance_level * _Balance.ENHANCE_RESEARCH_STEP


## 문파 공동 참오로 무공을 강화한다. 위력(또는 회복량)이 오르고 내공 소모가 준다. 반드시 성공한다.
static func enhance(art: MartialArtData, sect: SectData) -> Dictionary:
	if art.enhance_level >= _Balance.ENHANCE_MAX_LEVEL:
		return {"success": false, "message": "[%s]은(는) 이미 극에 달했습니다." % art.display_name}
	var cost: int = get_enhance_cost(art)
	if sect.research_points < cost:
		return {"success": false, "message": "깨달음이 부족합니다. (%d 필요)" % cost}
	sect.research_points -= cost
	art.enhance_level += 1
	if art.heal_amount > 0:
		art.heal_amount += _Balance.ENHANCE_HEAL
	else:
		art.damage += _Balance.ENHANCE_DAMAGE
	art.internal_cost = maxi(1, art.internal_cost - _Balance.ENHANCE_INTERNAL_COST_REDUCTION)
	# 비전으로 지정한 무공이면 비전도 함께 강해진다.
	if sect.secret_art and sect.secret_art.id == art.id:
		sect.secret_art = art.duplicate(true)
	return {"success": true, "message": "[%s] 강화 %d단계! (깨달음 -%d)" % [art.display_name, art.enhance_level, cost]}


## 강화한 무공을 문파 비전으로 지정한다. 세대 전승 때 후계자가 물려받고, 제자에게 싸게 전수한다.
static func designate_secret(art: MartialArtData, sect: SectData) -> Dictionary:
	if art.enhance_level < _Balance.SECRET_ART_MIN_ENHANCE:
		return {"success": false, "message": "비전은 %d단계 이상 강화한 무공만 지정할 수 있습니다." % _Balance.SECRET_ART_MIN_ENHANCE}
	if sect.secret_art and sect.secret_art.id == art.id:
		return {"success": false, "message": "[%s]은(는) 이미 문파 비전입니다." % art.display_name}
	sect.secret_art = art.duplicate(true)
	return {"success": true, "message": "[%s]을(를) %s의 비전으로 정했습니다. 후계자에게 이어집니다." % [art.display_name, sect.sect_name]}


## 전투에서 본 상대 무공을 분석한다. observed: {id, name, element}. 분석한 속성은 analyzed_elements에 더한다.
static func analyze(observed: Dictionary, sect: SectData, analyzed_elements: Array) -> Dictionary:
	var element: int = int(observed.get("element", MartialArtData.FiveElement.NONE))
	if element == MartialArtData.FiveElement.NONE:
		return {"success": false, "message": "[%s]에는 다룰 만한 오행의 기운이 없습니다." % observed.get("name", "?")}
	if analyzed_elements.has(element):
		return {"success": false, "message": "이미 분석한 속성입니다."}
	if sect.research_points < _Balance.ANALYZE_RESEARCH:
		return {"success": false, "message": "깨달음이 부족합니다. (%d 필요)" % _Balance.ANALYZE_RESEARCH}
	sect.research_points -= _Balance.ANALYZE_RESEARCH
	analyzed_elements.append(element)
	var counter := MartialArtData.new()
	counter.element = get_counter_element(element)
	var target := MartialArtData.new()
	target.element = element
	return {"success": true, "message": "[%s] 분석 완료: %s 속성의 약점을 알았습니다. %s 속성 무공 창안 성공률 +%d%% (깨달음 -%d)" % [
		observed.get("name", "?"), target.get_element_name(), counter.get_element_name(),
		_Balance.COUNTER_SUCCESS_BONUS, _Balance.ANALYZE_RESEARCH,
	]}


static func calculate_complexity(
	element: MartialArtData.FiveElement,
	yin_yang: MartialArtData.YinYang,
	effects: Array
) -> int:
	var complexity := 1
	if element != MartialArtData.FiveElement.NONE:
		complexity += 1
	if yin_yang != MartialArtData.YinYang.BALANCED:
		complexity += 1
	complexity += effects.size()
	return complexity


static func _apply_effect_stats(art: MartialArtData) -> void:
	art.damage = 8 + art.complexity * 2
	art.internal_cost = 10 + art.complexity * 3
	art.action_cost = 2

	for effect in art.special_effects:
		match effect:
			MartialArtData.SpecialEffect.DESTRUCTION:
				art.damage += 6
			MartialArtData.SpecialEffect.AMBUSH:
				art.damage += 4
				art.internal_cost += 2
			MartialArtData.SpecialEffect.HEAL:
				art.heal_amount = 12 + art.complexity * 3
				art.damage = 0
			MartialArtData.SpecialEffect.MOVE:
				art.move_bonus = 2
			MartialArtData.SpecialEffect.RANGE:
				art.range = 2
			MartialArtData.SpecialEffect.SPEED:
				art.action_cost = 1
			MartialArtData.SpecialEffect.BUFF:
				art.damage += 2


static func _build_description(art: MartialArtData) -> String:
	return "%s %s, %s 기운. 효과: %s" % [
		art.get_category_name(),
		art.get_element_name(),
		art.get_yin_yang_name(),
		art.get_effects_text(),
	]