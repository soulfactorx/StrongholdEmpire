class_name EventManager
extends RefCounted

static func check_turn_events(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	triggered_ids: Array[String],
	story_flags: Dictionary
) -> Dictionary:
	var events: Array[Dictionary] = _build_event_pool(
		character, sect, relationships, season, triggered_ids, story_flags
	)
	if events.is_empty():
		return {}

	var chosen: Dictionary = events[randi() % events.size()]
	if not chosen.get("can_repeat", false):
		triggered_ids.append(chosen["id"])
	return chosen


static func resolve_choice(
	event_id: String,
	choice_index: int,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary
) -> Dictionary:
	match event_id:
		"master_trial":
			return _resolve_master_trial(choice_index, character, sect, relationships)
		"night_bandits":
			return _resolve_night_bandits(choice_index, character, sect)
		"sect_fellowship":
			return _resolve_sect_fellowship(choice_index, character, sect, relationships)
		"ancient_manual":
			return _resolve_ancient_manual(choice_index, character, sect)
		"spy_recruitment":
			return _resolve_spy_recruitment(choice_index, story_flags)
		"spy_mission":
			return _resolve_spy_mission(choice_index, character, sect, story_flags)
		"assassin_contract":
			return _resolve_assassin_contract(choice_index, character, story_flags)
		"leader_council":
			return _resolve_leader_council(choice_index, character, sect)
		"rival_duel":
			return _resolve_rival_duel(choice_index, character, relationships)
		_:
			return {"success": false, "message": "알 수 없는 기연입니다."}


static func _build_event_pool(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	triggered_ids: Array[String],
	story_flags: Dictionary
) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []

	if not triggered_ids.has("master_trial") and character.martial_arts.is_empty():
		var trial_desc: String = (
			"청운검선이 당신을 불러 무공 연구를 격려합니다.\n"
			+ "「무에서 창조하는 것이 진정한 강호인의 길이니라.」"
		)
		pool.append({
			"id": "master_trial",
			"title": "스승의 시험",
			"description": trial_desc,
			"choices": ["연구에 전념한다", "나중에 하겠다"],
			"can_repeat": false,
		})

	if season == "가을" and not triggered_ids.has("night_bandits"):
		pool.append({
			"id": "night_bandits",
			"title": "야습 도적",
			"description": "문파 외곽에서 도적 무리가 습격해옵니다!",
			"choices": ["맞서 싸운다", "은밀히 피한다"],
			"can_repeat": false,
		})

	var master: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_master")
	if master and master.bond_strength >= 30 and not triggered_ids.has("sect_fellowship"):
		pool.append({
			"id": "sect_fellowship",
			"title": "사제의 밤",
			"description": "스승과 함께 달빛 아래 검을 맞대며 도담합니다.",
			"choices": ["진심을 털어놓는다", "무공 이론을 토론한다"],
			"can_repeat": false,
		})

	if sect.library_level >= 2 and not triggered_ids.has("ancient_manual"):
		pool.append({
			"id": "ancient_manual",
			"title": "고서 발견",
			"description": "서고 깊은 곳에서 낡은 무공 비급을 발견했습니다.",
			"choices": ["즉시 연구한다", "보관해 둔다"],
			"can_repeat": false,
		})

	if (
		character.role == CharacterData.Role.YOUNG_DISCIPLE
		and character.agility >= 14
		and not triggered_ids.has("spy_recruitment")
	):
		var spy_desc: String = (
			"문주가 몰래 당신을 불러 남궁세가 잠입을 제안합니다.\n"
			+ "위험하지만 문파에 큰 공을 세울 기회입니다."
		)
		pool.append({
			"id": "spy_recruitment",
			"title": "비밀 제의",
			"description": spy_desc,
			"choices": ["임무를 수락한다", "거절한다"],
			"can_repeat": false,
		})

	if character.role == CharacterData.Role.SPY and not triggered_ids.has("spy_mission"):
		pool.append({
			"id": "spy_mission",
			"title": "스파이 임무",
			"description": "적 문파 내부에서 기밀 문서를 빼내야 합니다.",
			"choices": ["위험을 감수한다", "신중히 접근한다"],
			"can_repeat": false,
		})

	if (
		character.role == CharacterData.Role.SPY
		and character.morality <= 50
		and not triggered_ids.has("assassin_contract")
	):
		pool.append({
			"id": "assassin_contract",
			"title": "암살 의뢰",
			"description": "정체불명의 의뢰인이 표적 제거를 요청합니다.",
			"choices": ["받아들인다", "거절한다"],
			"can_repeat": false,
		})

	if character.role == CharacterData.Role.LEADER and season == "여름":
		pool.append({
			"id": "leader_council",
			"title": "문파 회의",
			"description": "제자들과 강호 정세를 논의할 때입니다.",
			"choices": ["정파 연합 추진", "세력 확장 우선"],
			"can_repeat": true,
		})

	var rival: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_rival")
	if rival and rival.bond_strength >= 20 and season == "봄" and not triggered_ids.has("rival_duel"):
		pool.append({
			"id": "rival_duel",
			"title": "라이벌의 도전",
			"description": "남궁휘가 당신에게 결투를 신청합니다!",
			"choices": ["맞서 싸운다", "묘한 승부를 피한다"],
			"can_repeat": false,
		})

	return pool


static func _resolve_master_trial(
	choice_index: int,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData]
) -> Dictionary:
	if choice_index == 0:
		sect.research_points += 15
		character.wisdom += 1
		var master: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_master")
		if master:
			master.increase_bond(10)
		return {"success": true, "message": "스승의 가르침으로 연구점 +15, 지혜 +1, 사제 유대 상승."}
	return {"success": true, "message": "스승이 아쉬운 눈빛으로 고개를 끄덕입니다."}


static func _resolve_night_bandits(
	choice_index: int,
	character: CharacterData,
	sect: SectData
) -> Dictionary:
	if choice_index == 0:
		character.strength += 1
		character.experience += 20
		sect.reputation += 3
		character.internal_energy_current = maxi(0, character.internal_energy_current - 15)
		return {
			"success": true,
			"message": "도적을 물리쳤습니다! 무력 +1, 명성 +3 (내공 -15)",
		}
	character.agility += 1
	return {"success": true, "message": "은밀히 피해 신법 +1."}


static func _resolve_sect_fellowship(
	choice_index: int,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData]
) -> Dictionary:
	var master: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_master")
	if master == null:
		return {"success": true, "message": "평온한 밤이 지나갑니다."}

	if choice_index == 0:
		master.increase_bond(15)
		character.charisma += 1
		return {"success": true, "message": "스승과의 유대가 깊어졌습니다. 사제 +15, 매력 +1."}

	master.increase_bond(8)
	sect.research_points += 10
	return {"success": true, "message": "무공 이론 토론 완료. 사제 +8, 연구점 +10."}


static func _resolve_ancient_manual(
	choice_index: int,
	_character: CharacterData,
	sect: SectData
) -> Dictionary:
	if choice_index == 0:
		sect.research_points += 20
		return {"success": true, "message": "고서 연구로 연구점 +20."}
	sect.reputation += 2
	return {"success": true, "message": "비급을 보관했습니다. 문파 명성 +2."}


static func _resolve_spy_recruitment(choice_index: int, story_flags: Dictionary) -> Dictionary:
	if choice_index == 0:
		story_flags["spy_recruitment"] = true
		return {
			"success": true,
			"message": "스파이 임무를 수락했습니다. 역할 전환 메뉴에서 전향할 수 있습니다.",
		}
	return {"success": true, "message": "문주가 고개를 끄덕이며 다른 제자를 찾습니다."}


static func _resolve_spy_mission(
	choice_index: int,
	character: CharacterData,
	sect: SectData,
	story_flags: Dictionary
) -> Dictionary:
	if choice_index == 0:
		var exposed: bool = randi_range(1, 100) <= 25
		if exposed:
			story_flags["spy_exposed"] = true
			return {
				"success": true,
				"message": "정체가 드러났습니다! 비극의 길이 열렸습니다.",
			}
		story_flags["spy_mission_complete"] = true
		sect.reputation += 10
		character.experience += 30
		return {"success": true, "message": "임무 성공! 기밀 확보. 명성 +10"}
	character.agility += 1
	story_flags["spy_mission_complete"] = true
	return {"success": true, "message": "신중히 임무 완료. 신법 +1"}


static func _resolve_assassin_contract(
	choice_index: int,
	character: CharacterData,
	story_flags: Dictionary
) -> Dictionary:
	if choice_index == 0:
		story_flags["assassin_path"] = true
		character.morality -= 15
		character.strength += 1
		character.experience += 25
		return {"success": true, "message": "암살 의뢰 완료. 도덕 -15, 암살자의 길이 열렸습니다."}
	character.morality += 5
	return {"success": true, "message": "의뢰를 거절했습니다. 도덕 +5"}


static func _resolve_leader_council(
	choice_index: int,
	character: CharacterData,
	sect: SectData
) -> Dictionary:
	if choice_index == 0:
		character.morality += 5
		sect.reputation += 5
		return {"success": true, "message": "정파 연합 추진. 도덕 +5, 명성 +5"}
	sect.gold += 30
	sect.disciple_count += 2
	return {"success": true, "message": "세력 확장. 금화 +30, 제자 +2"}


static func _resolve_rival_duel(
	choice_index: int,
	character: CharacterData,
	relationships: Array[RelationshipData]
) -> Dictionary:
	var rival: RelationshipData = RelationshipManager.get_bond_with(relationships, "npc_rival")
	if choice_index == 0:
		character.strength += 1
		character.experience += 20
		if rival:
			rival.increase_bond(10)
		return {"success": true, "message": "결투에서 승리! 무력 +1, 라이벌 유대 +10"}
	if rival:
		rival.decrease_bond(5)
	return {"success": true, "message": "결투를 피했습니다. 라이벌 유대 -5"}