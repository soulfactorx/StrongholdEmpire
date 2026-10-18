class_name CombatManager
extends RefCounted

## 전투 구성 생성과 전투 결과 반영을 담당한다.

const _Balance = preload("res://scripts/Systems/game_balance.gd")

enum Outcome { VICTORY, DEFEAT, RETREAT }

const RIVAL_ID := "npc_rival"


## 기연 데이터 등에서 id로 전투를 만들 때 쓴다.
const COMBAT_IDS: PackedStringArray = [
	"sparring", "rival_duel", "night_bandits", "bandit_hunt", "assassination", "bounty_hunters",
]


## 코드로 만드는 전투와 data/combats/의 데이터 전투를 모두 찾는다.
static func has_combat(combat_id: String) -> bool:
	return combat_id in COMBAT_IDS or CombatLibrary.has_combat(combat_id)


## sect를 주면 문파 방어 전투에 제자가 아군으로 합류한다.
static func create_by_id(combat_id: String, player: CharacterData, sect: SectData = null) -> CombatSetup:
	match combat_id:
		"rival_duel":
			return create_rival_duel(player)
		"night_bandits":
			return create_night_bandits(player, sect)
		"bandit_hunt":
			return create_bandit_hunt(player)
		"assassination":
			return create_assassination(player)
		"bounty_hunters":
			return create_bounty_hunters(player)
		"sparring":
			return create_sparring(player)
	if CombatLibrary.has_combat(combat_id):
		return CombatLibrary.create(combat_id, player, sect)
	return create_sparring(player)


## 경영 화면에서 할 수 있는 라이벌과의 비무. 계절당 한 번.
static func create_sparring(player: CharacterData) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "sparring"
	setup.title = "비무 — %s" % NpcRoster.get_display_name(RIVAL_ID)
	setup.relationship_target_id = RIVAL_ID
	setup.blocked_tiles = _central_wall()
	_add_arena_terrain(setup)
	setup.add_enemy(_create_rival(player), Vector2i(13, 5))
	setup.enemy_hp_scale = 0.8
	setup.enemy_damage_scale = 0.65
	setup.rewards = {"experience": _Balance.SPAR_EXP, "bond": 5}
	setup.defeat_penalty = {"injury_ratio": 0.5, "bond": 2}
	return setup


## 인연 상호작용의 비무: 명부의 인물과 겨룬다. 이기면 유대가 크게, 져도 조금 오른다.
static func create_sparring_with(npc_id: String, player: CharacterData) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "sparring_bond"
	setup.title = "비무 — %s" % NpcRoster.get_display_name(npc_id)
	setup.relationship_target_id = npc_id
	setup.blocked_tiles = _central_wall()
	_add_arena_terrain(setup)
	setup.add_enemy(NpcRoster.create_character(npc_id, player), Vector2i(13, 5))
	# 비무를 좋아하는 인물은 겨루기만 해도 더 가까워진다.
	var bond_win: int = RelationshipManager._like_bonus(npc_id, "spar", _Balance.SPAR_BOND_WIN)
	var bond_lose: int = RelationshipManager._like_bonus(npc_id, "spar", _Balance.SPAR_BOND_LOSE)
	setup.rewards = {"experience": _Balance.SPAR_EXP, "bond": bond_win}
	setup.defeat_penalty = {"injury_ratio": 0.5, "bond": bond_lose}
	return setup


## 기연 「라이벌의 도전」에서 시작되는 진검 승부.
static func create_rival_duel(player: CharacterData) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "rival_duel"
	setup.title = "결투 — %s의 도전" % NpcRoster.get_display_name(RIVAL_ID)
	setup.relationship_target_id = RIVAL_ID
	setup.blocked_tiles = _central_wall()
	_add_arena_terrain(setup)
	var rival: CharacterData = _create_rival(player)
	rival.strength += 2
	rival.internal_energy_max += 20
	rival.restore_internal_energy()
	setup.add_enemy(rival, Vector2i(13, 5))
	setup.enemy_hp_scale = 0.85
	setup.enemy_damage_scale = 0.7
	setup.rewards = {"experience": 40, "reputation": 5, "strength": 1, "bond": 10}
	setup.defeat_penalty = {"reputation": 5, "injury_ratio": 0.3, "bond": -5}
	setup.victory_flag = "won_rival_duel"
	return setup


## 기연 「야습 도적」에서 시작되는 문파 방어전. sect가 있으면 제자들이 함께 싸운다.
static func create_night_bandits(player: CharacterData, sect: SectData = null) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "night_bandits"
	setup.title = "야습 — 도적 무리"
	setup.player_position = Vector2i(3, 5)
	setup.blocked_tiles = [
		Vector2i(6, 2), Vector2i(6, 3), Vector2i(9, 6), Vector2i(9, 7), Vector2i(10, 7),
	]
	# 개울(물)이 가로지르는 야산. 가운데 돌다리로 건너고, 도적은 수풀에 숨어 있다.
	var stream: Array[Vector2i] = []
	for y in [0, 1, 2, 3, 4, 7, 8, 9]:
		stream.append(Vector2i(8, y))
	setup.set_terrain(stream, CombatRules.Terrain.WATER)
	setup.set_terrain([
		Vector2i(11, 2), Vector2i(12, 2), Vector2i(13, 2), Vector2i(11, 3), Vector2i(12, 3),
		Vector2i(11, 7), Vector2i(12, 7), Vector2i(12, 8),
	], CombatRules.Terrain.FOREST)
	setup.set_terrain([Vector2i(4, 8), Vector2i(5, 8), Vector2i(4, 9)], CombatRules.Terrain.HIGH)
	var positions: Array[Vector2i] = [Vector2i(12, 3), Vector2i(13, 5), Vector2i(12, 7)]
	if sect:
		add_disciple_allies(setup, sect, player, [Vector2i(2, 4), Vector2i(2, 6)])
	# 제자가 함께 싸우면 그만큼 도적도 늘어난다.
	var extra_positions: Array[Vector2i] = [Vector2i(14, 3), Vector2i(14, 7)]
	for i in setup.allies.size():
		positions.append(extra_positions[i])
	for i in positions.size():
		setup.add_enemy(_create_bandit(player, i), positions[i])
	setup.enemy_hp_scale = 0.5
	setup.enemy_damage_scale = 0.6
	setup.rewards = {"experience": 30, "gold": 30, "reputation": 3, "strength": 1}
	setup.defeat_penalty = {"gold": 40, "reputation": 3, "injury_ratio": 0.3}
	return setup


## 낭인 의뢰 게시판의 토벌 의뢰: 관도의 도적 두 명. gold_reward는 지역에 따라 달라진다.
static func create_bandit_hunt(player: CharacterData, gold_reward: int = _Balance.JOB_HUNT_GOLD) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "bandit_hunt"
	setup.title = "토벌 의뢰 — 관도의 도적"
	setup.blocked_tiles = [Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 7), Vector2i(7, 8)]
	setup.set_terrain([Vector2i(11, 4), Vector2i(12, 4), Vector2i(11, 6)], CombatRules.Terrain.FOREST)
	setup.add_enemy(_create_bandit(player, 0), Vector2i(12, 3))
	setup.add_enemy(_create_bandit(player, 1), Vector2i(12, 7))
	setup.enemy_hp_scale = 0.55
	setup.enemy_damage_scale = 0.6
	setup.rewards = {"experience": 30, "gold": gold_reward}
	setup.defeat_penalty = {"injury_ratio": 0.4}
	return setup


## 암살자의 표적 의뢰: 호위 둘을 거느린 표적. 플레이어는 수풀 속에서 잠입을 시작한다.
static func create_assassination(player: CharacterData) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "assassination"
	setup.title = "표적 의뢰 — 야밤의 잠입"
	setup.player_position = Vector2i(2, 2)
	setup.set_terrain([
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(5, 4), Vector2i(6, 4), Vector2i(6, 5),
	], CombatRules.Terrain.FOREST)
	setup.blocked_tiles = [Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 6), Vector2i(9, 7)]
	var target: CharacterData = _create_bandit(player, 0)
	target.id = "assassination_target"
	target.display_name = "표적 — 탐관오리"
	target.internal_energy_max += 30
	target.restore_internal_energy()
	setup.add_enemy(target, Vector2i(13, 5))
	for i in 2:
		var guard: CharacterData = _create_bandit(player, i + 1)
		guard.display_name = "호위 무사 %s" % ["갑", "을"][i]
		setup.add_enemy(guard, [Vector2i(11, 4), Vector2i(11, 6)][i])
	setup.enemy_hp_scale = 0.55
	setup.enemy_damage_scale = 0.65
	setup.rewards = {"experience": _Balance.ASSASSINATION_EXP, "gold": _Balance.ASSASSINATION_GOLD}
	setup.defeat_penalty = {"injury_ratio": 0.3}
	setup.victory_flag = "assassination_success"
	return setup


## 현상금이 높은 암살자를 쫓는 추격대.
static func create_bounty_hunters(player: CharacterData) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.id = "bounty_hunters"
	setup.title = "추격전 — 현상금 사냥꾼"
	setup.player_position = Vector2i(4, 5)
	setup.set_terrain([Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 6)], CombatRules.Terrain.FOREST)
	setup.set_terrain([Vector2i(8, 1), Vector2i(8, 2)], CombatRules.Terrain.HIGH)
	var positions: Array[Vector2i] = [Vector2i(12, 2), Vector2i(13, 5), Vector2i(12, 8)]
	for i in positions.size():
		var hunter: CharacterData = _create_bandit(player, i)
		hunter.display_name = "사냥꾼 %s" % ["갑", "을", "병"][i]
		setup.add_enemy(hunter, positions[i])
	setup.enemy_hp_scale = 0.55
	setup.enemy_damage_scale = 0.65
	setup.rewards = {"experience": 35, "reputation": 2}
	setup.defeat_penalty = {"gold": 40, "injury_ratio": 0.3}
	return setup


## 전투 결과를 캐릭터·문파·관계에 반영하고 결과 메시지를 돌려준다.
## fallen_allies: 전투에서 쓰러진 아군 수. 아군이 문파 제자면 그만큼 제자가 줄어든다.
static func apply_outcome(
	setup: CombatSetup,
	outcome: Outcome,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary,
	fallen_allies: int = 0,
	fallen_ids: Array = []
) -> Dictionary:
	var parts: PackedStringArray = []
	var lost: int = 0
	var lost_names: PackedStringArray = []
	if setup.allies_are_disciples and sect.use_roster and (fallen_allies == 0 or not fallen_ids.is_empty()):
		# 명단 제자: 쓰러진 제자는 빠지고, 살아남은 참전 제자는 경험을 얻는다.
		var ally_ids: Array = setup.allies.map(func(a: CharacterData) -> String: return a.id)
		lost_names = DiscipleRoster.apply_battle(sect, ally_ids, fallen_ids)
		lost = lost_names.size()
	elif setup.allies_are_disciples and fallen_allies > 0:
		lost = mini(fallen_allies, sect.disciple_count)
		sect.disciple_count -= lost
	var lost_text: String = "제자 %d명 전사" % lost
	if not lost_names.is_empty():
		lost_text += " (%s)" % ", ".join(lost_names)
	var bond: RelationshipData = null
	if not setup.relationship_target_id.is_empty():
		bond = RelationshipManager.get_bond_with(relationships, setup.relationship_target_id)

	if outcome == Outcome.VICTORY:
		var r: Dictionary = setup.rewards
		var exp_gain: int = r.get("experience", 0)
		if exp_gain > 0:
			character.gain_experience(exp_gain)
			parts.append("경험치 +%d" % exp_gain)
		if r.get("gold", 0) > 0:
			sect.gold += r["gold"]
			parts.append("금화 +%d" % r["gold"])
		if r.get("reputation", 0) > 0:
			sect.reputation += r["reputation"]
			parts.append("명성 +%d" % r["reputation"])
		if r.get("strength", 0) > 0:
			character.strength += r["strength"]
			parts.append("무력 +%d" % r["strength"])
		_change_bond(bond, r.get("bond", 0), parts)
		if not setup.victory_flag.is_empty():
			EventManager.set_flag(story_flags, setup.victory_flag)
		if lost > 0:
			parts.append(lost_text)
		return {
			"success": true,
			"outcome": outcome,
			"message": "승리! " + ", ".join(parts) if not parts.is_empty() else "승리!",
		}

	if not setup.defeat_flag.is_empty():
		EventManager.set_flag(story_flags, setup.defeat_flag)
	# 후퇴는 패배 손실의 절반만 받는다.
	var scale: float = 0.5 if outcome == Outcome.RETREAT else 1.0
	var p: Dictionary = setup.defeat_penalty
	var gold_loss: int = mini(sect.gold, int(p.get("gold", 0) * scale))
	if gold_loss > 0:
		sect.gold -= gold_loss
		parts.append("금화 -%d" % gold_loss)
	var rep_loss: int = mini(sect.reputation, int(p.get("reputation", 0) * scale))
	if rep_loss > 0:
		sect.reputation -= rep_loss
		parts.append("명성 -%d" % rep_loss)
	var injury_ratio: float = p.get("injury_ratio", 1.0)
	if outcome == Outcome.RETREAT:
		injury_ratio = (1.0 + injury_ratio) / 2.0
	var max_left: int = int(character.internal_energy_max * injury_ratio)
	if character.internal_energy_current > max_left:
		character.internal_energy_current = max_left
		parts.append("부상으로 내공 %d까지 감소" % max_left)
	if outcome == Outcome.DEFEAT:
		_change_bond(bond, p.get("bond", 0), parts)
	if lost > 0:
		parts.append(lost_text)

	var head: String = "후퇴했습니다." if outcome == Outcome.RETREAT else "패배했습니다."
	return {
		"success": false,
		"outcome": outcome,
		"message": head + (" " + ", ".join(parts) if not parts.is_empty() else ""),
	}


static func _change_bond(bond: RelationshipData, amount: int, parts: PackedStringArray) -> void:
	if bond == null or amount == 0:
		return
	if amount > 0:
		bond.increase_bond(amount)
	else:
		bond.decrease_bond(-amount)
	parts.append("%s 유대 %+d" % [bond.target_name, amount])


## 비무장: 한쪽에 수풀, 반대쪽에 고지가 있다.
static func _add_arena_terrain(setup: CombatSetup) -> void:
	setup.set_terrain([Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 3)], CombatRules.Terrain.FOREST)
	setup.set_terrain([Vector2i(10, 7), Vector2i(11, 7), Vector2i(10, 8)], CombatRules.Terrain.FOREST)
	setup.set_terrain([Vector2i(10, 2), Vector2i(11, 2), Vector2i(10, 3)], CombatRules.Terrain.HIGH)
	setup.set_terrain([Vector2i(4, 5), Vector2i(4, 6)], CombatRules.Terrain.HIGH)


static func _central_wall() -> Array[Vector2i]:
	return [
		Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6),
		Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7),
	]


## 문파 제자를 아군으로 붙인다. 무술장이 좋을수록 강하다.
static func add_disciple_allies(
	setup: CombatSetup,
	sect: SectData,
	player: CharacterData,
	positions: Array[Vector2i]
) -> void:
	var count: int = mini(mini(_Balance.DEFENSE_ALLY_COUNT, positions.size()), sect.disciple_count)
	var bonus: int = (sect.training_ground_level - 1) * _Balance.ALLY_TRAINING_STAT_BONUS
	# 명단이 있으면 출전 지정한 제자와 강한 제자가 나선다.
	if sect.use_roster:
		var chosen: Array[DiscipleData] = DiscipleRoster.choose_combat_disciples(sect, count)
		for i in chosen.size():
			setup.add_ally(DiscipleRoster.to_character(chosen[i], bonus), positions[i])
		setup.allies_are_disciples = not chosen.is_empty()
		return
	for i in count:
		var disciple: CharacterData = NpcRoster.create_character("npc_disciple", player)
		disciple.id = "ally_disciple_%d" % i
		disciple.display_name = "%s %s" % [disciple.display_name, ["갑", "을", "병"][i % 3]]
		disciple.strength += bonus
		disciple.agility += bonus
		setup.add_ally(disciple, positions[i])
	setup.allies_are_disciples = count > 0


## 세력 AI의 침공을 막는 방어전. 침략 세력의 졸개(soldier_npc)와 우두머리(champion_npc)가 쳐들어온다.
## 졸개 수는 침략 세력의 제자 10명당 1명(2~4명). 문파 제자가 함께 싸운다.
static func create_invasion(invader: SectData, player: CharacterData, sect: SectData = null) -> CombatSetup:
	var info: Dictionary = SectRegistry.get_sect_info(invader.id)
	var setup := CombatSetup.new()
	setup.id = "sect_invasion"
	setup.invader_id = invader.id
	setup.title = "방어전 — %s의 침공" % invader.sect_name
	setup.player_position = Vector2i(3, 5)
	setup.blocked_tiles = [Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 8), Vector2i(6, 9)]
	setup.set_terrain([Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 8), Vector2i(4, 8)], CombatRules.Terrain.HIGH)
	setup.set_terrain([Vector2i(10, 4), Vector2i(10, 5), Vector2i(11, 6)], CombatRules.Terrain.FOREST)
	var soldier_id: String = info.get("soldier_npc", "npc_bandit")
	var soldier_count: int = clampi(invader.disciple_count / 10, 2, 4)
	var positions: Array[Vector2i] = [Vector2i(12, 2), Vector2i(12, 8), Vector2i(13, 4), Vector2i(13, 6)]
	for i in soldier_count:
		var soldier: CharacterData = NpcRoster.create_character(soldier_id, player)
		soldier.id = "%s_%d" % [soldier_id, i]
		soldier.display_name = "%s %s" % [soldier.display_name, ["갑", "을", "병", "정"][i]]
		setup.add_enemy(soldier, positions[i])
	var champion_id: String = info.get("champion_npc", "")
	if NpcRoster.has_npc(champion_id):
		setup.add_enemy(NpcRoster.create_character(champion_id, player), Vector2i(14, 5))
	if sect:
		add_disciple_allies(setup, sect, player, [Vector2i(2, 4), Vector2i(2, 6)])
	setup.enemy_hp_scale = 0.7
	setup.enemy_damage_scale = 0.8
	setup.rewards = {"experience": 40, "gold": 50, "reputation": 5}
	setup.defeat_penalty = {"gold": 80, "reputation": _Balance.INVASION_YIELD_REPUTATION, "injury_ratio": 0.3}
	setup.victory_flag = "repelled_invasion"
	return setup


## 방어전에 깊은 인연(사제·혈맹·연인)의 인물이 아군으로 합류한다. 합류한 인물 이름을 돌려준다.
static func add_bond_allies(setup: CombatSetup, relationships: Array[RelationshipData], player: CharacterData) -> PackedStringArray:
	var joined: PackedStringArray = []
	var taken: Array = setup.allies.map(func(c: CharacterData) -> String: return c.id)
	taken.append_array(setup.enemies.map(func(c: CharacterData) -> String: return c.id))
	for rel in RelationshipManager.get_bond_allies(relationships):
		if joined.size() >= _Balance.BOND_ALLY_COUNT:
			break
		if rel.target_id in taken:
			continue
		var tile: Vector2i = find_free_tile(setup, setup.player_position)
		if tile.x < 0:
			break
		setup.add_ally(NpcRoster.create_character(rel.target_id, player), tile)
		joined.append(rel.target_name)
	return joined


## 기준 칸 근처의 빈 칸 (없으면 (-1, -1))
static func find_free_tile(setup: CombatSetup, near: Vector2i) -> Vector2i:
	var used: Array[Vector2i] = [setup.player_position]
	used.append_array(setup.enemy_positions)
	used.append_array(setup.ally_positions)
	used.append_array(setup.blocked_tiles)
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile: Vector2i = near + Vector2i(dx, dy)
				if tile.x < 0 or tile.x >= CombatLibrary.GRID_WIDTH or tile.y < 0 or tile.y >= CombatLibrary.GRID_HEIGHT:
					continue
				if tile in used or setup.get_terrain(tile) == CombatRules.Terrain.WATER:
					continue
				return tile
	return Vector2i(-1, -1)


## 남궁휘는 플레이어 레벨에 맞춰 함께 성장하는 라이벌이다. (명부의 scaling)
static func _create_rival(player: CharacterData) -> CharacterData:
	return NpcRoster.create_character(RIVAL_ID, player)


static func _create_bandit(player: CharacterData, index: int) -> CharacterData:
	var bandit: CharacterData = NpcRoster.create_character("npc_bandit", player)
	bandit.id = "npc_bandit_%d" % index
	bandit.display_name = "%s %s" % [bandit.display_name, ["갑", "을", "병", "정", "무"][index % 5]]
	return bandit
