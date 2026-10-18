class_name RoleManager
extends RefCounted

const _Balance = preload("res://scripts/Systems/game_balance.gd")

static func get_available_transitions(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary,
	role_state: Dictionary = {},
	world_sects: Array[SectData] = []
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if role_state.is_empty():
		role_state = RoleActions.create_state()

	if character.role == CharacterData.Role.YOUNG_DISCIPLE:
		# 스토리 아크 「승계와 배신」에서 후계자로 지명되면 승진 조건을 따지지 않는다.
		if _can_become_manager(character, sect, relationships) or story_flags.get("arc_succession_heir", false):
			options.append(_transition_option(
				CharacterData.Role.MANAGER,
				"중간관리자 승진",
				"문파 내 신뢰를 얻어 중간관리자가 됩니다."
			))
		if _can_become_spy(character, story_flags):
			options.append(_transition_option(
				CharacterData.Role.SPY,
				"스파이 임무 수락",
				"적 문파에 잠입해 정보를 수집합니다."
			))

	elif character.role == CharacterData.Role.MANAGER:
		var named_heir: bool = story_flags.get("arc_succession_heir", false) and character.level >= _Balance.MANAGER_LEVEL_REQ
		if (
			(_can_become_leader(character, sect, relationships) or named_heir)
			and role_state["trust"] >= _Balance.MANAGER_TRUST_FOR_LEADER
		):
			options.append(_transition_option(
				CharacterData.Role.LEADER,
				"문주 승계",
				"%s의 새 문주가 됩니다." % sect.sect_name
			))

	elif character.role == CharacterData.Role.SPY:
		if _can_become_assassin(character, story_flags):
			options.append(_transition_option(
				CharacterData.Role.ASSASSIN,
				"암살자로 전향",
				"은밀한 제거 임무를 전담합니다."
			))
		if story_flags.get("spy_mission_complete", false):
			options.append(_transition_option(
				CharacterData.Role.MANAGER,
				"임무 완료 후 복귀",
				"스파이 임무를 마치고 문파로 돌아옵니다."
			))
		# 배신: 잠입한 세력에 붙는다.
		var infiltrated: SectData = _find_sect(world_sects, str(role_state["spy_target"]))
		if infiltrated and not infiltrated.subjugated:
			options.append(_sect_option(
				infiltrated, "betray",
				"%s(으)로 전향" % infiltrated.sect_name,
				"잠입한 세력에 붙어 옛 문파를 배신합니다. 그곳의 중간관리자가 됩니다."
			))

	elif character.role == CharacterData.Role.WANDERER:
		if character.level >= _Balance.MERCENARY_LEVEL_REQ:
			options.append(_transition_option(
				CharacterData.Role.MERCENARY,
				"의뢰인이 된다",
				"세력들의 임무를 계약으로 맡는 청부업을 시작합니다."
			))

	elif character.role == CharacterData.Role.MERCENARY:
		options.append(_transition_option(
			CharacterData.Role.WANDERER,
			"청부를 접는다",
			"계약에서 손을 떼고 다시 떠돌이 낭인이 됩니다."
		))

	# 입문: 무소속 낭인·의뢰인은 신용을 조금 쌓았거나 연줄(그 세력 인물과의 유대)이 있는 세력에 제자로 들어간다.
	if sect.id == NpcRoster.NO_SECT and character.role in [CharacterData.Role.WANDERER, CharacterData.Role.MERCENARY]:
		for world_sect in world_sects:
			var reason: String = get_join_block(world_sect, character, relationships, role_state)
			if reason.is_empty():
				var option: Dictionary = _sect_option(
					world_sect, "join",
					"%s에 입문한다" % world_sect.sect_name,
					"%s의 막내 제자로 들어갑니다. 문주가 사부가 되고, 모은 재산은 문파에 보탭니다." % world_sect.sect_name
				)
				option["role"] = CharacterData.Role.YOUNG_DISCIPLE
				options.append(option)

	# 문파를 떠난다: 사부(문주)와 유대가 깊으면 허락받고 하산, 아니면 탈문
	if sect.id != NpcRoster.NO_SECT and (character.role != CharacterData.Role.YOUNG_DISCIPLE or character.level >= _Balance.LEAVE_LEVEL_REQ):
		options.append(get_leave_option(character, sect, relationships))

	# 이적: 신용을 쌓은 세력에 객경으로 들어간다.
	if character.role in [CharacterData.Role.WANDERER, CharacterData.Role.MERCENARY]:
		for world_sect in world_sects:
			if world_sect.subjugated:
				continue
			if RoleActions.get_credit(role_state, world_sect.id) >= _Balance.DEFECT_CREDIT_REQ:
				options.append(_sect_option(
					world_sect, "defect",
					"%s에 객경으로 들어간다" % world_sect.sect_name,
					"신용을 쌓은 세력에 몸을 의탁합니다. 그곳의 중간관리자가 됩니다."
				))

	# 배신: 도덕이 낮은 제자·관리자는 가장 적대적인 비정파 세력으로 넘어갈 수 있다.
	if character.role in [CharacterData.Role.YOUNG_DISCIPLE, CharacterData.Role.MANAGER]:
		if character.morality <= _Balance.BETRAY_MORALITY_REQ:
			var enemy: SectData = _most_hostile_unorthodox(world_sects)
			if enemy:
				options.append(_sect_option(
					enemy, "betray",
					"%s(으)로 투항" % enemy.sect_name,
					"문파를 배신하고 적에게 넘어갑니다. 그곳의 중간관리자가 됩니다."
				))

	return options


# ── 역할 전환 안내 ──

## 지금 역할에서 갈 수 있는 길과 조건 (역할 전환 창의 안내). gm은 GameManager 노드다.
## [{title, conditions: [{text, ok}], alt: {text, ok} (있으면 이것만 채워도 됨), available}]
static func get_transition_guide(gm: Node) -> Array[Dictionary]:
	var c: CharacterData = gm.player_character
	var sect: SectData = gm.player_sect
	var flags: Dictionary = gm.story_flags
	var state: Dictionary = gm.role_state
	var in_sect: bool = gm.has_sect()
	var master: int = get_master_bond(sect, gm.player_relationships) if in_sect else 0
	var paths: Array[Dictionary] = []
	match c.role:
		CharacterData.Role.YOUNG_DISCIPLE:
			paths.append(_path("총관(중간관리자) 승진", [
				_req("경지 %d" % _Balance.MANAGER_LEVEL_REQ, c.level, _Balance.MANAGER_LEVEL_REQ),
				_req("지혜 %d" % _Balance.MANAGER_WISDOM_REQ, c.wisdom, _Balance.MANAGER_WISDOM_REQ),
				_req("문파 명성 %d" % _Balance.MANAGER_REPUTATION_REQ, sect.reputation, _Balance.MANAGER_REPUTATION_REQ),
				_req("사부(문주) 유대 25", master, 25),
			], {"text": "또는 「승계와 배신」에서 후계자로 지명", "ok": flags.get("arc_succession_heir", false)}))
			paths.append(_path("간자(스파이) 임무", [
				_req("신법 15", c.agility, 15), _req("매력 13", c.charisma, 13),
			], {"text": "또는 포섭 기연을 겪음", "ok": flags.get("spy_recruitment", false)}))
		CharacterData.Role.MANAGER:
			var heir: bool = flags.get("arc_succession_heir", false)
			paths.append(_path("문주 승계", [
				_req("경지 %d" % _Balance.LEADER_LEVEL_REQ, c.level, _Balance.LEADER_LEVEL_REQ),
				_req("문파 명성 %d" % _Balance.LEADER_REPUTATION_REQ, sect.reputation, _Balance.LEADER_REPUTATION_REQ),
				_req("제자 %d명" % _Balance.LEADER_DISCIPLE_REQ, sect.disciple_count, _Balance.LEADER_DISCIPLE_REQ),
				_req("사부(문주) 유대 50", master, 50),
				_req("신임도 %d" % _Balance.MANAGER_TRUST_FOR_LEADER, int(state["trust"]), _Balance.MANAGER_TRUST_FOR_LEADER),
			], {"text": "또는 후계자로 지명 + 경지 %d + 신임도 %d" % [_Balance.MANAGER_LEVEL_REQ, _Balance.MANAGER_TRUST_FOR_LEADER],
				"ok": heir and c.level >= _Balance.MANAGER_LEVEL_REQ and int(state["trust"]) >= _Balance.MANAGER_TRUST_FOR_LEADER}))
		CharacterData.Role.SPY:
			paths.append(_path("자객으로 전향", [
				{"text": "도덕 45 이하 (지금 %d)" % c.morality, "ok": c.morality <= 45},
				_req("무력 13", c.strength, 13),
				{"text": "자객의 길 기연을 겪음", "ok": flags.get("assassin_path", false)},
			]))
			paths.append(_path("임무를 마치고 복귀 (총관)", [
				{"text": "정보 수집 %d회로 임무 완료 (지금 %d회)" % [_Balance.SPY_MISSION_INTEL, int(state.get("intel_count", 0))], "ok": flags.get("spy_mission_complete", false)},
			]))
			paths.append(_path("잠입한 세력으로 전향 (배신)", [
				{"text": "정보를 캐는 세력이 있음 (정보 수집으로 정함)", "ok": not str(state["spy_target"]).is_empty()},
			]))
		CharacterData.Role.WANDERER:
			paths.append(_path("의뢰인이 된다", [_req("경지 %d" % _Balance.MERCENARY_LEVEL_REQ, c.level, _Balance.MERCENARY_LEVEL_REQ)]))
		CharacterData.Role.MERCENARY:
			paths.append(_path("청부를 접고 낭인으로", [{"text": "언제든", "ok": true}]))
		CharacterData.Role.LEADER:
			paths.append(_path("(자동) 축출", [
				{"text": "불만도 %d이 되면 쫓겨나 무소속 낭인이 됨 (지금 %d)" % [_Balance.DISCONTENT_OUSTED, int(state["discontent"])], "ok": false},
			]))
	if c.role in [CharacterData.Role.WANDERER, CharacterData.Role.MERCENARY]:
		var best_credit: Array = _best_credit(gm)
		if not in_sect:
			var best_tie: Array = _best_tie(gm)
			# 실제로 받아 줄 세력 (역할 전환 선택지와 같은 판정)
			var joinable: PackedStringArray = []
			for world_sect in gm.world_sects:
				if get_join_block(world_sect, c, gm.player_relationships, state).is_empty():
					joinable.append(world_sect.sect_name)
			var join: Dictionary = _path("문파에 입문 (막내 제자)", [
				{"text": "신용 %d 이상인 세력 (지금 최고: %s)" % [_Balance.JOIN_CREDIT_REQ, best_credit[0]], "ok": best_credit[1] >= _Balance.JOIN_CREDIT_REQ},
				{"text": "정파는 도덕 %d 이상 (지금 %d), 그 세력 신용이 마이너스면 거절" % [_Balance.JOIN_RIGHTEOUS_MORALITY, c.morality], "ok": true},
				{"text": "받아 줄 세력: %s" % (", ".join(joinable) if not joinable.is_empty() else "아직 없음"), "ok": not joinable.is_empty()},
				_credit_hint(gm),
			], {"text": "또는 그 세력 인물과 유대 %d 이상 (지금 최고: %s)" % [_Balance.JOIN_BOND_REQ, best_tie[0]], "ok": best_tie[1] >= _Balance.JOIN_BOND_REQ})
			join["force"] = not joinable.is_empty()
			paths.append(join)
		paths.append(_path("세력의 객경(총관)으로 이적", [
			{"text": "그 세력 신용 %d 이상 (지금 최고: %s)" % [_Balance.DEFECT_CREDIT_REQ, best_credit[0]], "ok": best_credit[1] >= _Balance.DEFECT_CREDIT_REQ},
		]))
	if c.role in [CharacterData.Role.YOUNG_DISCIPLE, CharacterData.Role.MANAGER]:
		paths.append(_path("적대 세력으로 투항 (배신)", [
			{"text": "도덕 %d 이하 (지금 %d)" % [_Balance.BETRAY_MORALITY_REQ, c.morality], "ok": c.morality <= _Balance.BETRAY_MORALITY_REQ},
			{"text": "받아 줄 사파·마교 세력이 있음", "ok": _most_hostile_unorthodox(gm.world_sects) != null},
		]))
	if in_sect:
		var conditions: Array = []
		if c.role == CharacterData.Role.YOUNG_DISCIPLE:
			conditions.append(_req("경지 %d" % _Balance.LEAVE_LEVEL_REQ, c.level, _Balance.LEAVE_LEVEL_REQ))
		conditions.append({"text": "사부 유대 %d 이상이면 허락받은 하산(노자), 아니면 탈문 (지금 %d)" % [_Balance.LEAVE_BLESSING_BOND, master], "ok": true})
		paths.append(_path("문파를 떠나 무소속으로", conditions))
	for path in paths:
		path["available"] = path["conditions"].all(func(r: Dictionary) -> bool: return r["ok"]) or path.get("alt", {}).get("ok", false)
		# 판정이 따로 있는 길(입문)은 그 판정을 따른다
		if path.has("force"):
			path["available"] = path["force"]
		if path["title"].begins_with("(자동)"):
			path["available"] = false
	return paths


static func _path(title: String, conditions: Array, alt: Dictionary = {}) -> Dictionary:
	var path: Dictionary = {"title": title, "conditions": conditions}
	if not alt.is_empty():
		path["alt"] = alt
	return path


## 수치 조건 한 줄: "경지 3 (지금 2)"
static func _req(label: String, value: int, need: int) -> Dictionary:
	return {"text": "%s 이상 (지금 %d)" % [label, value], "ok": value >= need}


## 신용이 가장 높은 세력: ["남궁세가 12", 12]. 쌓은 신용이 없으면 ["아직 없음", 0]
static func _best_credit(gm: Node) -> Array:
	var best_name: String = "아직 없음"
	var best: int = 0
	for world_sect in gm.world_sects:
		var credit: int = RoleActions.get_credit(gm.role_state, world_sect.id)
		if credit > best:
			best = credit
			best_name = "%s %d" % [world_sect.sect_name, credit]
	return [best_name, best]


## 신용을 쌓는 곳 안내: 지금 지역이 어느 세력의 땅인지에 따라
static func _credit_hint(gm: Node) -> Dictionary:
	var location: String = str(gm.role_state.get("location", ""))
	var sect: SectData = gm.get_world_sect(location) if not location.is_empty() else null
	if sect:
		return {"text": "지금 %s — 여기서 의뢰를 마치면 %s 신용 +%d" % [gm.get_location_text(), sect.sect_name, _Balance.JOB_CREDIT_GAIN], "ok": true}
	return {"text": "지금 %s — 의뢰해도 신용이 오르지 않음. 세력의 땅으로 이동해 의뢰하세요" % gm.get_location_text(), "ok": false}


## 세력 인물과의 가장 깊은 유대 (원한 제외): ["위청(흑풍채) 20", 20]
static func _best_tie(gm: Node) -> Array:
	var best_name: String = "없음"
	var best: int = -1
	for rel in gm.player_relationships:
		var npc_sect: String = str(NpcRoster.get_npc(rel.target_id).get("sect_id", ""))
		if rel.bond_type == RelationshipData.BondType.HATRED or gm.get_world_sect(npc_sect) == null:
			continue
		if rel.bond_strength > best:
			best = rel.bond_strength
			best_name = "%s(%s) %d" % [rel.target_name, gm.get_world_sect(npc_sect).sect_name, rel.bond_strength]
	return [best_name, best]


## 입문할 수 없는 까닭 (할 수 있으면 "")
static func get_join_block(
	world_sect: SectData, character: CharacterData, relationships: Array[RelationshipData], role_state: Dictionary
) -> String:
	if world_sect.subjugated:
		return "굴복한 세력"
	# 세력의 태도는 플레이어 문파를 보는 눈이라 무소속에게는 쓰지 않는다. 그 세력에 진 신용이 마이너스(계약 위반·배신)면 받지 않는다.
	var credit: int = RoleActions.get_credit(role_state, world_sect.id)
	if credit < 0:
		return "신용이 바닥남 (%d) — 계약 위반·배신 등" % credit
	if world_sect.alignment == SectData.Alignment.RIGHTEOUS and character.morality < _Balance.JOIN_RIGHTEOUS_MORALITY:
		return "정파는 도덕 %d 이상만 받음" % _Balance.JOIN_RIGHTEOUS_MORALITY
	if RoleActions.get_credit(role_state, world_sect.id) >= _Balance.JOIN_CREDIT_REQ:
		return ""
	for rel in relationships:
		if rel.bond_type != RelationshipData.BondType.HATRED and rel.bond_strength >= _Balance.JOIN_BOND_REQ \
				and NpcRoster.get_npc(rel.target_id).get("sect_id", "") == world_sect.id:
			return ""
	return "신용 %d 이상이나 그 세력 인물과 유대 %d 이상(연줄)이 필요" % [_Balance.JOIN_CREDIT_REQ, _Balance.JOIN_BOND_REQ]


## 문파를 떠나는 선택지. 문주는 자리를 내려놓고, 의뢰인·자객은 그 일을 이어 가고, 나머지는 낭인이 된다.
static func get_leave_option(character: CharacterData, sect: SectData, relationships: Array[RelationshipData]) -> Dictionary:
	var blessed: bool = character.role == CharacterData.Role.LEADER or get_master_bond(sect, relationships) >= _Balance.LEAVE_BLESSING_BOND
	var role: CharacterData.Role = character.role if character.role in [
		CharacterData.Role.MERCENARY, CharacterData.Role.ASSASSIN, CharacterData.Role.WANDERER,
	] else CharacterData.Role.WANDERER
	var title: String
	var description: String
	if character.role == CharacterData.Role.LEADER:
		title = "문주 자리를 내려놓고 떠난다"
		description = "문파를 원래 문주(원로회)에게 맡기고 강호로 나섭니다. 노자를 챙기고, 문파와의 사이는 좋게 남습니다."
	elif blessed:
		title = "사부의 허락을 받아 하산한다"
		description = "사부와의 유대가 깊어 좋게 떠납니다. 노자(금화 %d·식량 %d)를 챙기고 %s의 태도 +%d." % [
			_Balance.PURSE_ALLOWANCE_GOLD, _Balance.PURSE_ALLOWANCE_FOOD, sect.sect_name, _Balance.LEAVE_BLESSED_ATTITUDE,
		]
	else:
		title = "몰래 문파를 떠난다 (탈문)"
		description = "허락 없이 떠납니다 (사부 유대 %d 미만). 노자 없이, %s의 태도 %d, 사부·동문 유대 -%d." % [
			_Balance.LEAVE_BLESSING_BOND, sect.sect_name, _Balance.LEAVE_DESERT_ATTITUDE, _Balance.LEAVE_DESERT_BOND,
		]
	var option: Dictionary = _transition_option(role, title, description + " 무소속이 됩니다.")
	option["kind"] = "leave"
	option["blessed"] = blessed
	return option


## 사부(소속 문파의 문주)와의 유대. 문주와 사부 인연이 없으면 같은 문파 인물 중 사부 관계의 유대
static func get_master_bond(sect: SectData, relationships: Array[RelationshipData]) -> int:
	var best: int = 0
	for rel in relationships:
		if rel.bond_type != RelationshipData.BondType.MASTER_DISCIPLE:
			continue
		if rel.target_id == sect.leader_id:
			return rel.bond_strength
		if NpcRoster.get_npc(rel.target_id).get("sect_id", "") == sect.id:
			best = maxi(best, rel.bond_strength)
	return best


static func _sect_option(sect: SectData, kind: String, title: String, description: String) -> Dictionary:
	var option: Dictionary = _transition_option(CharacterData.Role.MANAGER, title, description)
	option["sect_id"] = sect.id
	option["kind"] = kind
	return option


static func _find_sect(world_sects: Array[SectData], sect_id: String) -> SectData:
	for sect in world_sects:
		if sect.id == sect_id:
			return sect
	return null


static func _most_hostile_unorthodox(world_sects: Array[SectData]) -> SectData:
	var result: SectData = null
	for sect in world_sects:
		if sect.subjugated or sect.alignment == SectData.Alignment.RIGHTEOUS:
			continue
		if result == null or sect.attitude < result.attitude:
			result = sect
	return result


static func apply_transition(
	character: CharacterData,
	sect: SectData,
	new_role: CharacterData.Role
) -> Dictionary:
	var old_name: String = character.get_role_name()
	character.role = new_role
	_apply_role_bonuses(character, new_role)

	if new_role == CharacterData.Role.LEADER:
		sect.leader_name = character.display_name

	var new_name: String = character.get_role_name()
	return {
		"success": true,
		"message": "%s에서 %s(으)로 역할이 전환되었습니다." % [old_name, new_name],
		"new_role": new_role,
	}


static func get_role_combat_bonus(role: CharacterData.Role) -> float:
	match role:
		CharacterData.Role.LEADER:
			return 1.15
		CharacterData.Role.SPY, CharacterData.Role.ASSASSIN:
			return 1.1
		CharacterData.Role.MANAGER:
			return 1.05
		CharacterData.Role.WANDERER, CharacterData.Role.MERCENARY:
			return 1.08
		_:
			return 1.0


static func get_role_management_bonus(role: CharacterData.Role) -> float:
	match role:
		CharacterData.Role.LEADER:
			return 1.2
		CharacterData.Role.MANAGER:
			return 1.15
		_:
			return 1.0


static func _transition_option(
	role: CharacterData.Role,
	title: String,
	description: String
) -> Dictionary:
	return {"role": role, "title": title, "description": description}


static func _can_become_manager(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData]
) -> bool:
	var master_bond: int = get_master_bond(sect, relationships)
	return (
		character.level >= _Balance.MANAGER_LEVEL_REQ
		and character.wisdom >= _Balance.MANAGER_WISDOM_REQ
		and sect.reputation >= _Balance.MANAGER_REPUTATION_REQ
		and master_bond >= 25
	)


static func _can_become_spy(
	character: CharacterData,
	story_flags: Dictionary
) -> bool:
	return (
		character.agility >= 15
		and character.charisma >= 13
	) or story_flags.get("spy_recruitment", false)


static func _can_become_leader(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData]
) -> bool:
	var master_bond: int = get_master_bond(sect, relationships)
	return (
		character.level >= _Balance.LEADER_LEVEL_REQ
		and sect.reputation >= _Balance.LEADER_REPUTATION_REQ
		and sect.disciple_count >= _Balance.LEADER_DISCIPLE_REQ
		and master_bond >= 50
	)


static func _can_become_assassin(
	character: CharacterData,
	story_flags: Dictionary
) -> bool:
	return character.morality <= 45 and character.strength >= 13 and story_flags.get("assassin_path", false)


static func _apply_role_bonuses(character: CharacterData, role: CharacterData.Role) -> void:
	match role:
		CharacterData.Role.LEADER:
			character.charisma += 2
			character.internal_energy_max += 20
		CharacterData.Role.MANAGER:
			character.wisdom += 2
		CharacterData.Role.SPY:
			character.agility += 2
		CharacterData.Role.ASSASSIN:
			character.strength += 2
			character.morality -= 10
		CharacterData.Role.WANDERER:
			character.agility += 1
			character.charisma += 1
		CharacterData.Role.MERCENARY:
			character.strength += 1
			character.charisma += 1
	character.internal_energy_current = mini(
		character.internal_energy_current,
		character.internal_energy_max
	)