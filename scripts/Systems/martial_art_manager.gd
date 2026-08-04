class_name MartialArtManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")
const MAX_EFFECTS := 3


static func create_from_blueprint(
	blueprint: Dictionary,
	sect: SectData,
	character: CharacterData
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
			"message": "연구점이 부족합니다. (%d 필요)" % research_cost,
		}

	var success_rate := calculate_success_rate(sect, character, complexity)
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
				"연구 실패! 내공 반동으로 %d 피해. (성공률 %d%%, 주사위 %d)"
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
		"message": "무공 창조 성공! [%s] 완성 (성공률 %d%%)" % [name, success_rate],
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
			"message": "연구점이 부족합니다. (%d 필요)" % art.research_cost,
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
			"message": "비급 연구 실패! 내공 반동 %d. (%d%% / %d)" % [backlash, success_rate, roll],
		}

	character.learn_martial_art(art)
	return {
		"success": true,
		"message": "[%s] 연구 완료!" % art.display_name,
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