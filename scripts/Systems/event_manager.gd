class_name EventManager
extends RefCounted

## 기연(이벤트) 시스템. 기연 내용은 data/events/*.json에 데이터로 정의하고,
## 이 클래스는 불러오기·검증·조건 판정·효과 적용만 담당한다.
##
## ■ 파일 형식
##   { "id", "title", "description", "can_repeat": bool,
##     "conditions": [조건...], "choices": [선택지...] }
##   선택지: { "label", "message", "effects": [효과...],
##            "branches": [{ "chance": 1~100, "message", "effects" }] (선택),
##            "success": bool (선택, 기본 true) }
##   branches는 위에서부터 확률을 굴려 처음 걸린 것을 쓰고, 모두 빗나가면 기본 효과를 쓴다.
##
## ■ 조건 (type별 필드)
##   character  field, op, value   — CHARACTER_FIELDS (martial_arts_count는 습득 무공 수)
##   sect       field, op, value   — SECT_FIELDS
##   bond       target, op, value  — 관계 대상의 유대 수치. 관계가 없으면 거짓
##   role       in: [역할 이름]     — CharacterData.Role 이름 (예: "SPY")
##   season     in: [계절]          — "봄" "여름" "가을" "겨울"
##   flag       flag, value        — 스토리 플래그 값 비교 (없으면 false로 간주)
##   world_sect sect, field, op, value — 강호 세력 수치 비교 (WORLD_SECT_FIELDS)
##   year       op, value          — 현재 연차 비교
##   turns_since_flag flag, op, value — 플래그가 켜진 뒤 지난 계절 수 비교 (켜진 적 없으면 거짓)
##   relationship_type target, bond_type — 해당 인물과의 관계 유형이 일치
##   role_history role, value       — 그 역할을 거쳐 왔는지 (value 생략 시 true)
##   scenario   in: [시나리오 id]   — 현재 시나리오가 목록에 있음
##   years_left op, value          — 시나리오 제한까지 남은 연수 (제한 없으면 9999)
##   subjugated_count op, value    — 굴복시킨 강호 세력 수
##   regions_owned op, value       — 강호 지도에서 우리 문파가 가진 땅 수 (본거지 포함)
##   generation op, value          — 현재 세대 (1세대부터)
##   alignment  in: ["good","neutral","evil"] — 주인공의 성향 (도덕 65 이상 선, 35 이하 악, 그 사이 중립)
##   role_state field, op, value   — 역할 자원 비교 (RoleActions.NUMERIC_FIELDS: discontent, trust, exposure, bounty ...)
##   (world_sect의 field에는 subjugated(0/1)도 쓸 수 있다)
##   op: ">=" "<=" ">" "<" "==" "!="
##
## ■ 효과 (type별 필드)
##   character   field, add        — 능력치 증감. 내공은 0~최대치로 제한
##   sect        field, add        — 문파 자원 증감. 0 미만으로 내려가지 않음
##   experience  amount            — 경험치 (레벨업 포함)
##   bond        target, add       — 유대 증감
##   flag        flag, value       — 스토리 플래그 설정
##   combat      combat            — 전투 시작 (CombatManager.create_by_id, 방어전이면 제자 합류)
##   world_sect  sect, field, add  — 강호 세력 수치 증감 (태도는 -100~100)
##   set_bond_type target, bond_type — 기존 관계의 유형을 바꾼다
##   add_relationship target, bond_type, strength — 명부 인물과 새 관계를 맺는다 (이미 있으면 무시)
##   learn_art   art               — 무공 습득 (MartialArtLibrary id)
##   end_game    ending            — 지정한 엔딩 또는 게임오버로 이야기를 끝낸다
##   role_state  field, add        — 역할 자원 증감 (0~100으로 제한)
##
## ■ 관계 대상 기연 (subject)
##   최상위 "subject"가 있으면 기연이 일어날 때 조건에 맞는 인물 하나를 고른다.
##   조건·효과의 target "$subject"가 그 인물이고, 제목·설명·선택지·결과 글의 {name}·{title}이 그 인물의 이름·호칭으로 바뀐다.
##   subject { bond_types: [관계 유형] — 그 관계인 인물 중에서,
##             stranger: true — 아직 관계가 없는 이름 있는 인물 중에서 (문주 제외),
##             min, max — 유대 범위 (bond_types일 때), sect: "same"|"other"|"none"|"any" — 인물의 소속,
##             min_age, max_age — 인물의 나이 }
##   bond_count bond_type, op, value — 그 관계인 인물 수 비교 (조건)
##   marry target                    — 연인(또는 누구든)을 배우자로 맞는다. 배우자는 여럿 둘 수 있다 (효과)
##   end_relationship target         — 관계를 끝낸다 (이별·사별, 효과)
##
## ■ 비급
##   gain_manual art — 비급을 얻는다 (무공 연구소에서 연구할 수 있게 됨). art가 "random"이면 아직 연구할 수 없고
##                     익히지도 않은 비급 중 하나 (효과)
##
## ■ 선택지 조건과 장면 대사
##   선택지에 "conditions"(조건 목록)를 주면 조건을 채울 때만 그 선택지가 보인다 (성향·인물·관계별 선택지).
##   최상위 "scene": [{ "speaker": 인물 id 또는 "player"(주인공) 또는 ""(서술), "text": 대사, "only": [인물 id] (선택) }]
##   — 설명 아래에 인물들의 대사로 보인다. only가 있으면 그 등장인물로 플레이할 때만 보이고,
##   주인공이 연기하는 인물의 대사 줄은 빠진다. 글 속 {player}는 주인공 이름으로 바뀐다.
##
## ■ 이야기 진행 (메인 시나리오)
##   선택지 "next": 기연 id — 고르면 계절을 기다리지 않고 그 기연이 바로 이어진다 (여러 단계 대화).
##   최상위 "follow_up": true — 다른 기연의 next로만 일어나는 기연 (계절마다 뽑는 후보에 들지 않는다)
##   scene 줄의 "if": [조건] — 조건을 채울 때만 그 대사가 보인다 (지난 선택을 기억하는 대사)
##   효과 unlock feature — 기능을 연다 (FeatureGate, 기능 단계 개방)
##   효과 set_role role — 역할을 바꾼다 (CharacterData.Role 이름. 예: 아버지를 잃고 가주가 됨)
##   효과 goal text — 강호 일지의 목표를 바꾼다 / rumor text — 강호 일지에 소문을 더한다
##
## ■ 강호 연표 (메인 시나리오)
##   최상위 "timeline": { "title", "hint", "branches": [{ "text", "if": [조건] }] } — 강호 연표에 다가오는 큰 사건으로 보인다.
##   언제 일어날지는 조건의 year·turns_since_flag(앞 사건 id)로 계산하고, 갈림길은 지금 조건을 채웠는지 표시한다.
##
## ■ 가중치
##   최상위 "weight"(기본 1): 발생 후보 중에서 뽑힐 상대적 확률. 스토리 핵심 기연은 높게 준다.
##   최상위 "priority"(기본 false): true면 조건을 채운 계절에 기연 발생 확률과 관계없이 먼저 일어난다.
##
## ■ 초상화
##   최상위 "npc"(선택): 팝업에 초상화를 보일 인물 id. 없으면 조건·효과에서 처음 나오는 명부 인물(target)을 쓴다.

const EVENTS_DIR := "res://data/events/"

const CHARACTER_FIELDS: PackedStringArray = [
	"strength", "agility", "wisdom", "charisma", "morality",
	"internal_energy_current", "internal_energy_max", "level", "age",
]
const CHARACTER_COMPUTED_FIELDS: PackedStringArray = ["martial_arts_count"]
const SECT_FIELDS: PackedStringArray = [
	"gold", "food", "reputation", "research_points", "disciple_count", "max_disciples",
	"library_level", "training_ground_level", "treasury_level",
	"apothecary_level", "meditation_hall_level",
]
const WORLD_SECT_FIELDS: PackedStringArray = ["attitude", "reputation", "disciple_count"]
## 조건에서만 쓰는 세력 필드 (효과로는 바꿀 수 없음)
const WORLD_SECT_CONDITION_FIELDS: PackedStringArray = ["subjugated"]
const OPERATORS: PackedStringArray = [">=", "<=", ">", "<", "==", "!="]
const SEASON_NAMES: PackedStringArray = ["봄", "여름", "가을", "겨울"]

static var _definitions: Array[EventData] = []
static var _loaded: bool = false


## 기연 판정에 쓰는 진행 상황. GameManager가 새 게임·불러오기·계절 진행 때 갱신한다.
static var world_sects: Array[SectData] = []
static var current_year: int = 1
## 연차 × 4 + 계절 순번
static var current_turn: int = 0
static var current_generation: int = 1
## 거쳐 온 역할 이름 (CharacterData.Role 키)
static var role_history: Array[String] = []
## 플래그 이름 → 켜진 계절(current_turn)
static var flag_turns: Dictionary = {}
## 역할 자원 (GameManager.role_state와 같은 객체)
static var role_state: Dictionary = {}
## 강호 지도 상태 (GameManager.map_state)와 플레이어 문파 id — regions_owned 조건
static var map_state: Dictionary = {}
static var player_sect_id: String = ""
## 주인공 이름 ({player}) · 주인공이 된 명부 인물 (등장인물 선택 플레이. 새 인연 후보에서 뺀다)
static var player_name: String = ""
static var player_npc_id: String = ""
## 금화·식량을 내고 받는 곳 (GameManager.get_wallet). 개인 재산을 쓰는 역할이면 주머니다.
## sect 조건·효과의 gold·food는 여기를 본다. null이면 문파.
static var wallet: SectData = null
## 가진 비급 (GameManager.owned_manuals와 같은 배열) — gain_manual 효과
static var owned_manuals: Array[String] = []
## 관계 대상 기연에서 지금 판정·적용 중인 대상 인물 ("$subject")
static var _subject: String = ""
## get_candidates가 관계 대상 기연마다 고른 대상 (기연 id → 인물 id)
static var _picked_subjects: Dictionary = {}

const SUBJECT_KEYS: PackedStringArray = ["bond_types", "stranger", "min", "max", "sect", "min_age", "max_age"]
const SUBJECT_SECTS: PackedStringArray = ["same", "other", "none", "any"]


## 스토리 플래그를 설정하고 켜진 계절을 기록한다. 플래그는 항상 이 함수로 설정한다.
static func set_flag(story_flags: Dictionary, flag: String, value: Variant = true) -> void:
	story_flags[flag] = value
	flag_turns[flag] = current_turn


## 지금 발생할 수 있는 기연 후보 전체 (가중치 추첨 전)
static func get_candidates(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	triggered_ids: Array[String],
	story_flags: Dictionary
) -> Array[EventData]:
	var pool: Array[EventData] = []
	_picked_subjects.clear()
	for event in get_definitions():
		if event.follow_up or (not event.can_repeat and triggered_ids.has(event.id)):
			continue
		if event.subject.is_empty():
			if _conditions_met(event, character, sect, relationships, season, story_flags):
				pool.append(event)
			continue
		# 관계 대상 기연: 조건을 채우는 대상 중 하나를 고른다.
		var fits: Array[String] = []
		for subject_id in _subject_candidates(event.subject, relationships):
			_subject = subject_id
			if _conditions_met(event, character, sect, relationships, season, story_flags):
				fits.append(subject_id)
		_subject = ""
		if not fits.is_empty():
			_picked_subjects[event.id] = fits.pick_random()
			pool.append(event)
	return pool


## 관계 대상 기연의 대상 후보 인물 id
static func _subject_candidates(spec: Dictionary, relationships: Array[RelationshipData]) -> Array[String]:
	var result: Array[String] = []
	if spec.get("stranger", false) == true:
		for npc in NpcRoster.get_all():
			if not NpcRoster.is_listed(npc) or npc.get("role", "") == "LEADER" or npc["id"] == player_npc_id:
				continue
			if RelationshipManager.get_bond_with(relationships, npc["id"]) == null and _subject_fits(spec, npc):
				result.append(npc["id"])
		return result
	var types: Array = spec.get("bond_types", [])
	for rel in relationships:
		if not types.is_empty() and not RelationshipData.BondType.keys()[rel.bond_type] in types:
			continue
		if rel.bond_strength < int(spec.get("min", 0)) or rel.bond_strength > int(spec.get("max", 100)):
			continue
		if NpcRoster.has_npc(rel.target_id) and _subject_fits(spec, NpcRoster.get_npc(rel.target_id)):
			result.append(rel.target_id)
	return result


static func _subject_fits(spec: Dictionary, npc: Dictionary) -> bool:
	var npc_sect: String = str(npc.get("sect_id", ""))
	match str(spec.get("sect", "any")):
		"same":
			if npc_sect != player_sect_id or npc_sect == NpcRoster.NO_SECT:
				return false
		"other":
			if npc_sect == player_sect_id or npc_sect == NpcRoster.NO_SECT:
				return false
		"none":
			if npc_sect != NpcRoster.NO_SECT:
				return false
	var age: int = int(npc.get("stats", {}).get("age", 30))
	return age >= int(spec.get("min_age", 0)) and age <= int(spec.get("max_age", 999))


## 조건·효과의 target: "$subject"면 지금 대상 인물
static func _target(entry: Dictionary) -> String:
	var target: String = str(entry.get("target", ""))
	return _subject if target == "$subject" else target


static func check_turn_events(
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	triggered_ids: Array[String],
	story_flags: Dictionary
) -> Dictionary:
	var pool: Array[EventData] = get_candidates(character, sect, relationships, season, triggered_ids, story_flags)
	# 우선 기연이 있으면 그중에서만 고른다.
	var urgent: Array[EventData] = []
	for event in pool:
		if event.priority:
			urgent.append(event)
	if not urgent.is_empty():
		pool = urgent
		# 인물을 콕 집은 이야기 기연이 누구에게나 일어나는 관계 기연보다 먼저다.
		var named: Array[EventData] = urgent.filter(func(e: EventData) -> bool: return e.subject.is_empty())
		if not named.is_empty():
			pool = named
	if pool.is_empty():
		return {}

	var chosen: EventData = _pick_weighted(pool)
	if not chosen.can_repeat:
		triggered_ids.append(chosen.id)
	var subject_id: String = str(_picked_subjects.get(chosen.id, ""))
	return make_popup(chosen, character, sect, relationships, season, story_flags, subject_id)


## 팝업에 띄울 기연: 조건을 채운 선택지와 대사 줄만 보인다.
static func make_popup(
	event: EventData, character: CharacterData, sect: SectData, relationships: Array[RelationshipData],
	season: String, story_flags: Dictionary, subject_id: String = ""
) -> Dictionary:
	var lines: Array = []
	_subject = subject_id
	for i in event.scene.size():
		if conditions_met(event.scene[i].get("if", []), character, sect, relationships, season, story_flags):
			lines.append(i)
	_subject = ""
	return event.to_popup_dict(subject_id, visible_choices(event, character, sect, relationships, season, story_flags, subject_id), lines)


## 조건을 채운 선택지 번호 (선택지 conditions). 조건이 없으면 모두.
static func visible_choices(
	event: EventData, character: CharacterData, sect: SectData, relationships: Array[RelationshipData],
	season: String, story_flags: Dictionary, subject_id: String = ""
) -> Array:
	var result: Array = []
	_subject = subject_id
	for i in event.choices.size():
		if conditions_met(event.choices[i].get("conditions", []), character, sect, relationships, season, story_flags):
			result.append(i)
	_subject = ""
	return result


static func resolve_choice(
	event_id: String,
	choice_index: int,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary,
	subject_id: String = ""
) -> Dictionary:
	var event: EventData = get_event(event_id)
	if event == null or choice_index < 0 or choice_index >= event.choices.size():
		return {"success": false, "message": "알 수 없는 기연입니다."}

	var choice: Dictionary = event.choices[choice_index]
	var effects: Array = choice.get("effects", [])
	var message: String = choice.get("message", "")
	for branch in choice.get("branches", []):
		if randi_range(1, 100) <= int(branch.get("chance", 0)):
			effects = branch.get("effects", [])
			message = branch.get("message", message)
			break

	var result: Dictionary = {
		"success": choice.get("success", true),
		"message": EventData.fill_text(message, subject_id),
	}
	_subject = subject_id
	for effect in effects:
		_apply_effect(effect, character, sect, relationships, story_flags, result)
	_subject = ""
	if choice.has("next"):
		result["next"] = str(choice["next"])
		result["subject"] = subject_id
	return result


## 시간 조건(year·turns_since_flag·season)
const TIME_CONDITIONS: PackedStringArray = ["year", "turns_since_flag", "season"]


## 기연이 일어날 가장 이른 계절(턴 번호). 앞 사건이 아직이면 그 사건의 예상 시점으로 이어서 계산한다. 알 수 없으면 -1
static func estimate_turn(event: EventData, story_flags: Dictionary, triggered_ids: Array[String], now: int, memo: Dictionary = {}) -> int:
	if memo.has(event.id):
		return memo[event.id]
	memo[event.id] = -1
	var turn: int = now
	var seasons: Array = []
	for c in event.conditions:
		match str(c.get("type", "")):
			"year":
				# 턴 번호 = 연차 × 4 + 계절 (GameManager._get_turn_index)
				if str(c.get("op", ">=")) in [">=", "==", ">"]:
					turn = maxi(turn, (int(c["value"]) + (1 if c.get("op") == ">" else 0)) * 4)
			"turns_since_flag":
				var flag: String = str(c["flag"])
				var base: int = -1
				if story_flags.get(flag, false) and flag_turns.has(flag):
					base = int(flag_turns[flag])
				else:
					var before: EventData = get_event(flag)
					if before == null:
						return -1
					# 지금 떠 있는(일어났지만 아직 고르지 않은) 앞 사건은 이번 계절로 친다
					base = now if triggered_ids.has(flag) else estimate_turn(before, story_flags, triggered_ids, now, memo)
				if base < 0:
					return -1
				turn = maxi(turn, base + int(c.get("value", 0)))
			"season":
				seasons = c.get("in", [])
	if not seasons.is_empty():
		var guard: int = 0
		while not SEASON_NAMES[turn % 4] in seasons and guard < 4:
			turn += 1
			guard += 1
	memo[event.id] = turn
	return turn


## 강호 연표: 연표에 오른 큰 사건 가운데 지금 이야기에 해당하는 것.
## [{id, title, hint, turn(-1이면 알 수 없음), done, branches: [{text, met}]}] — 일어난 것 먼저, 그다음 이른 순
static func get_timeline(
	character: CharacterData, sect: SectData, relationships: Array[RelationshipData],
	season: String, story_flags: Dictionary, triggered_ids: Array[String], now: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var memo: Dictionary = {}
	for event in get_definitions():
		if event.timeline.is_empty():
			continue
		var done: bool = triggered_ids.has(event.id)
		# 시간 말고 다른 조건(등장인물·플래그 등)이 맞는 사건만
		var other: Array = event.conditions.filter(func(c: Dictionary) -> bool: return not str(c.get("type", "")) in TIME_CONDITIONS)
		if not done and not conditions_met(other, character, sect, relationships, season, story_flags):
			continue
		var branches: Array = []
		for branch in event.timeline.get("branches", []):
			var conds: Array = branch.get("if", [])
			# 다른 등장인물의 갈림길(playing_ 플래그)은 빼고, 그 조건은 ★ 판정에 넣지 않는다
			var who: Array = conds.filter(func(c: Dictionary) -> bool: return c.get("type") == "flag" and str(c.get("flag", "")).begins_with("playing_"))
			if not conditions_met(who, character, sect, relationships, season, story_flags):
				continue
			var rest: Array = conds.filter(func(c: Dictionary) -> bool: return not who.has(c))
			branches.append({
				"text": EventData.fill_text(str(branch["text"]), ""),
				"met": not rest.is_empty() and conditions_met(rest, character, sect, relationships, season, story_flags),
				"conditional": not rest.is_empty(),
			})
		result.append({
			"id": event.id, "title": str(event.timeline["title"]), "hint": EventData.fill_text(str(event.timeline.get("hint", "")), ""),
			"turn": -1 if done else estimate_turn(event, story_flags, triggered_ids, now, memo), "done": done, "branches": branches,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["done"] != b["done"]:
			return a["done"]
		var ta: int = a["turn"] if a["turn"] >= 0 else 9999
		var tb: int = b["turn"] if b["turn"] >= 0 else 9999
		return ta < tb
	)
	return result


static func _pick_weighted(pool: Array[EventData]) -> EventData:
	var total: float = 0.0
	for event in pool:
		total += event.weight
	var roll: float = randf() * total
	for event in pool:
		roll -= event.weight
		if roll < 0.0:
			return event
	return pool[-1]


static func get_definitions() -> Array[EventData]:
	if not _loaded:
		reload_definitions()
	return _definitions


static func get_event(event_id: String) -> EventData:
	for event in get_definitions():
		if event.id == event_id:
			return event
	return null


## 기연 폴더를 다시 읽는다. extra_dirs(시나리오 전용 기연 등)가 있으면 이어서 읽는다.
## only_folders가 있으면 첫 폴더(공용 기연)에서는 그 하위 폴더의 기연만 읽는다.
## 잘못된 파일과 중복 id는 경고를 남기고 건너뛴다.
static func reload_definitions(dir_path: String = EVENTS_DIR, extra_dirs: Array = [], only_folders: Array = []) -> void:
	_definitions.clear()
	_loaded = true
	var seen_ids: Dictionary = {}
	for i in extra_dirs.size() + 1:
		var current_dir: String = dir_path if i == 0 else str(extra_dirs[i - 1])
		if i > 0 and not DirAccess.dir_exists_absolute(current_dir):
			continue
		if not DirAccess.dir_exists_absolute(current_dir):
			push_warning("기연 폴더를 열 수 없습니다: %s" % current_dir)
			continue
		for path in collect_json_files(current_dir):
			if i == 0 and not only_folders.is_empty() and not _in_folders(path, current_dir, only_folders):
				continue
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not data is Dictionary:
				push_warning("기연 JSON 파싱 실패: %s" % path)
				continue
			var errors: PackedStringArray = validate_event_dict(data)
			if seen_ids.has(data.get("id")):
				errors.append("중복된 id: %s" % data.get("id"))
			if not errors.is_empty():
				push_warning("기연 정의 오류 (%s): %s" % [path, "; ".join(errors)])
				continue
			seen_ids[data["id"]] = true
			_definitions.append(_to_event_data(data))
	# 이어지는 기연(next)이 실제로 있는지는 모두 읽은 뒤에 확인한다
	for event in _definitions:
		for choice in event.choices:
			if choice.has("next") and not seen_ids.has(choice["next"]):
				push_warning("기연 정의 오류 (%s): 이어지는 기연이 없음: %s" % [event.id, choice["next"]])


## folders 항목: 하위 폴더 이름("bonds") 또는 파일 경로 앞부분("bonds/bond_g_")
static func _in_folders(path: String, base: String, folders: Array) -> bool:
	var relative: String = path.trim_prefix(base).trim_prefix("/")
	for folder in folders:
		var prefix: String = str(folder)
		if DirAccess.dir_exists_absolute(base.path_join(prefix)):
			prefix = prefix.trim_suffix("/") + "/"
		if relative.begins_with(prefix):
			return true
	return false


## 폴더와 하위 폴더(스토리 아크 등)의 JSON 파일 경로를 이름순으로 모은다.
static func collect_json_files(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var files: PackedStringArray = DirAccess.get_files_at(dir_path)
	files.sort()
	for file_name in files:
		if file_name.ends_with(".json"):
			result.append(dir_path.path_join(file_name))
	var dirs: PackedStringArray = DirAccess.get_directories_at(dir_path)
	dirs.sort()
	for sub_dir in dirs:
		result.append_array(collect_json_files(dir_path.path_join(sub_dir)))
	return result


## 기연 정의 하나를 검사해 오류 메시지 목록을 돌려준다. 비어 있으면 정상이다.
static func validate_event_dict(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in ["id", "title", "description"]:
		if not data.get(key) is String or String(data.get(key)).is_empty():
			errors.append("'%s'가 비어 있음" % key)
	if data.has("npc") and not NpcRoster.has_npc(str(data["npc"])):
		errors.append("명부에 없는 인물(npc): %s" % data["npc"])
	if data.has("priority") and not data["priority"] is bool:
		errors.append("priority는 true/false여야 함")
	if data.has("weight") and not ((data["weight"] is float or data["weight"] is int) and data["weight"] > 0):
		errors.append("weight는 0보다 큰 숫자여야 함")
	for line in data.get("scene", []):
		if not line is Dictionary or not line.get("text") is String:
			errors.append("scene 줄은 { speaker, text } 형식이어야 함")
		elif not str(line.get("speaker", "")) in ["", "player"] and not NpcRoster.has_npc(str(line.get("speaker", ""))):
			errors.append("scene에 명부에 없는 인물: %s" % line.get("speaker"))
		elif line.has("only") and not line["only"] is Array:
			errors.append("scene 줄의 only는 인물 id 목록이어야 함")
		elif line.has("if"):
			validate_conditions(line["if"], errors)
	if data.has("subject"):
		_validate_subject(data["subject"], errors)
	elif JSON.stringify(data).contains("$subject"):
		errors.append("$subject를 쓰려면 subject가 필요함")
	validate_conditions(data.get("conditions", []), errors)
	if data.has("timeline"):
		var timeline: Variant = data["timeline"]
		if not timeline is Dictionary or str(timeline.get("title", "")).is_empty():
			errors.append("timeline에 title 필요")
		else:
			for branch in timeline.get("branches", []):
				if not branch is Dictionary or str(branch.get("text", "")).is_empty():
					errors.append("timeline branch는 { text, if }")
				elif branch.has("if"):
					validate_conditions(branch["if"], errors)
	var choices: Variant = data.get("choices")
	if not choices is Array or (choices as Array).is_empty():
		errors.append("choices가 비어 있음")
	elif (choices as Array).all(func(c: Variant) -> bool: return c is Dictionary and not c.get("conditions", []).is_empty()):
		errors.append("조건 없는 선택지가 적어도 하나 있어야 함 (모든 선택지가 숨으면 고를 수 없음)")
		return errors
	for i in (choices as Array).size():
		var choice: Variant = choices[i]
		if not choice is Dictionary or not choice.get("label") is String:
			errors.append("선택지 %d: label 필요" % i)
			continue
		for effect in choice.get("effects", []):
			_validate_effect(effect, errors)
		if choice.has("conditions"):
			validate_conditions(choice["conditions"], errors)
		if choice.has("next") and (not choice["next"] is String or String(choice["next"]).is_empty()):
			errors.append("선택지 %d: next는 기연 id" % i)
		for branch in choice.get("branches", []):
			if not branch is Dictionary or not branch.has("chance"):
				errors.append("선택지 %d: branch에 chance 필요" % i)
				continue
			for effect in branch.get("effects", []):
				_validate_effect(effect, errors)
	return errors


static func _validate_subject(spec: Variant, errors: PackedStringArray) -> void:
	if not spec is Dictionary:
		errors.append("subject는 객체여야 함")
		return
	for key in spec:
		if not key in SUBJECT_KEYS:
			errors.append("알 수 없는 subject 필드: %s" % key)
	for type_key in spec.get("bond_types", []):
		if not RelationshipData.BondType.has(str(type_key)):
			errors.append("알 수 없는 관계 유형: %s" % type_key)
	if spec.has("sect") and not str(spec["sect"]) in SUBJECT_SECTS:
		errors.append("알 수 없는 subject sect: %s" % spec["sect"])
	if spec.get("stranger", false) != true and not spec.has("bond_types"):
		errors.append("subject에 bond_types나 stranger 필요")


static func _validate_condition(condition: Variant, errors: PackedStringArray) -> void:
	if not condition is Dictionary:
		errors.append("조건은 객체여야 함")
		return
	var c: Dictionary = condition
	match c.get("type", ""):
		"character":
			if not (c.get("field") in CHARACTER_FIELDS or c.get("field") in CHARACTER_COMPUTED_FIELDS):
				errors.append("알 수 없는 캐릭터 필드: %s" % c.get("field"))
			_validate_compare(c, errors)
		"sect":
			if not c.get("field") in SECT_FIELDS:
				errors.append("알 수 없는 문파 필드: %s" % c.get("field"))
			_validate_compare(c, errors)
		"bond":
			if not c.get("target") is String:
				errors.append("bond 조건에 target 필요")
			_validate_compare(c, errors)
		"role":
			for role_name in c.get("in", []):
				if not CharacterData.Role.has(role_name):
					errors.append("알 수 없는 역할: %s" % role_name)
		"season":
			for season in c.get("in", []):
				if not season in SEASON_NAMES:
					errors.append("알 수 없는 계절: %s" % season)
		"flag":
			if not c.get("flag") is String:
				errors.append("flag 조건에 flag 필요")
		"world_sect":
			_validate_world_sect(c, errors, true)
			_validate_compare(c, errors)
		"year":
			_validate_compare(c, errors)
		"turns_since_flag":
			if not c.get("flag") is String:
				errors.append("turns_since_flag 조건에 flag 필요")
			_validate_compare(c, errors)
		"relationship_type":
			if not c.get("target") is String:
				errors.append("relationship_type 조건에 target 필요")
			_validate_bond_type(c, errors)
		"bond_count":
			_validate_bond_type(c, errors)
			_validate_compare(c, errors)
		"role_history":
			if not CharacterData.Role.has(c.get("role", "")):
				errors.append("알 수 없는 역할: %s" % c.get("role"))
		"scenario":
			if not c.get("in") is Array or (c.get("in") as Array).is_empty():
				errors.append("scenario 조건에 in 목록 필요")
		"years_left", "subjugated_count", "generation", "regions_owned":
			_validate_compare(c, errors)
		"role_state":
			if not c.get("field") in RoleActions.NUMERIC_FIELDS:
				errors.append("알 수 없는 역할 자원: %s" % c.get("field"))
			_validate_compare(c, errors)
		"alignment":
			if not c.get("in") is Array or (c["in"] as Array).any(func(a: Variant) -> bool: return not str(a) in ["good", "neutral", "evil"]):
				errors.append("alignment 조건의 in은 good·neutral·evil 목록")
		_:
			errors.append("알 수 없는 조건 type: %s" % c.get("type"))


static func _validate_compare(c: Dictionary, errors: PackedStringArray) -> void:
	if not c.get("op") in OPERATORS:
		errors.append("알 수 없는 비교 연산자: %s" % c.get("op"))
	if not (c.get("value") is float or c.get("value") is int):
		errors.append("비교 값은 숫자여야 함")


static func _validate_effect(effect: Variant, errors: PackedStringArray) -> void:
	if not effect is Dictionary:
		errors.append("효과는 객체여야 함")
		return
	var e: Dictionary = effect
	match e.get("type", ""):
		"character":
			if not e.get("field") in CHARACTER_FIELDS:
				errors.append("알 수 없는 캐릭터 필드: %s" % e.get("field"))
		"sect":
			if not e.get("field") in SECT_FIELDS:
				errors.append("알 수 없는 문파 필드: %s" % e.get("field"))
		"experience":
			if not e.has("amount"):
				errors.append("experience 효과에 amount 필요")
		"bond":
			if not e.get("target") is String:
				errors.append("bond 효과에 target 필요")
		"flag":
			if not e.get("flag") is String:
				errors.append("flag 효과에 flag 필요")
		"combat":
			if not CombatManager.has_combat(e.get("combat", "")):
				errors.append("알 수 없는 전투: %s" % e.get("combat"))
		"world_sect":
			_validate_world_sect(e, errors)
		"set_bond_type":
			if not e.get("target") is String:
				errors.append("set_bond_type 효과에 target 필요")
			_validate_bond_type(e, errors)
		"add_relationship":
			if not NpcRoster.has_npc(str(e.get("target", ""))) and e.get("target") != "$subject":
				errors.append("명부에 없는 인물: %s" % e.get("target"))
			_validate_bond_type(e, errors)
		"gain_manual":
			var manual: String = str(e.get("art", ""))
			if manual != "random" and not MartialArtLibrary.has_art(manual):
				errors.append("알 수 없는 비급: %s" % manual)
		"marry", "end_relationship":
			if not e.get("target") is String:
				errors.append("%s 효과에 target 필요" % e.get("type"))
		"learn_art":
			if not MartialArtLibrary.has_art(str(e.get("art", ""))):
				errors.append("알 수 없는 무공: %s" % e.get("art"))
		"role_state":
			if not e.get("field") in RoleActions.NUMERIC_FIELDS:
				errors.append("알 수 없는 역할 자원: %s" % e.get("field"))
		"end_game":
			var ending: String = str(e.get("ending", ""))
			if not (EndingManager.has_ending(ending) or EndingManager.GAME_OVERS.has(ending)):
				errors.append("알 수 없는 엔딩: %s" % ending)
		"unlock":
			if not FeatureGate.has_feature(str(e.get("feature", ""))):
				errors.append("알 수 없는 기능: %s" % e.get("feature"))
		"set_role":
			if not CharacterData.Role.has(str(e.get("role", ""))):
				errors.append("알 수 없는 역할: %s" % e.get("role"))
		"goal", "rumor":
			if not e.get("text") is String or String(e.get("text")).is_empty():
				errors.append("%s 효과에 text 필요" % e.get("type"))
		_:
			errors.append("알 수 없는 효과 type: %s" % e.get("type"))


static func _validate_bond_type(entry: Dictionary, errors: PackedStringArray) -> void:
	if not RelationshipData.BondType.has(entry.get("bond_type", "")):
		errors.append("알 수 없는 관계 유형: %s" % entry.get("bond_type"))


static func _validate_world_sect(entry: Dictionary, errors: PackedStringArray, is_condition: bool = false) -> void:
	var sect_id: String = str(entry.get("sect", ""))
	if not SectRegistry.has_sect(sect_id) or SectRegistry.get_sect_info(sect_id).get("is_player_sect", false):
		errors.append("알 수 없는 강호 세력: %s" % sect_id)
	var allowed: bool = entry.get("field") in WORLD_SECT_FIELDS
	if is_condition:
		allowed = allowed or entry.get("field") in WORLD_SECT_CONDITION_FIELDS
	if not allowed:
		errors.append("알 수 없는 세력 필드: %s" % entry.get("field"))


static func _find_world_sect(sect_id: String) -> SectData:
	for sect in world_sects:
		if sect.id == sect_id:
			return sect
	return null


## 초상화를 보일 인물: 조건·효과에서 처음 나오는 명부의 인물 (target·npc 값). 없으면 ""
static func _infer_npc(data: Dictionary) -> String:
	var found: Array[String] = []
	_collect_npc_ids(data.get("conditions", []), found)
	_collect_npc_ids(data.get("choices", []), found)
	return found[0] if not found.is_empty() else ""


static func _collect_npc_ids(value: Variant, found: Array[String]) -> void:
	if not found.is_empty():
		return
	if value is Dictionary:
		for key in ["target", "npc"]:
			if value.get(key) is String and NpcRoster.has_npc(value[key]):
				found.append(value[key])
				return
		for key in value:
			_collect_npc_ids(value[key], found)
	elif value is Array:
		for item in value:
			_collect_npc_ids(item, found)


static func _to_event_data(data: Dictionary) -> EventData:
	var event := EventData.new()
	event.id = data["id"]
	event.title = data["title"]
	event.description = data["description"]
	event.can_repeat = data.get("can_repeat", false)
	event.weight = float(data.get("weight", 1.0))
	event.priority = data.get("priority", false) == true
	event.follow_up = data.get("follow_up", false) == true
	event.timeline = data.get("timeline", {})
	event.npc = str(data.get("npc", _infer_npc(data)))
	event.subject = data.get("subject", {})
	for line in data.get("scene", []):
		event.scene.append(line)
	for condition in data.get("conditions", []):
		event.conditions.append(condition)
	for choice in data["choices"]:
		event.choices.append(choice)
	return event


static func _conditions_met(
	event: EventData,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	story_flags: Dictionary
) -> bool:
	return conditions_met(event.conditions, character, sect, relationships, season, story_flags)


## 조건 목록을 모두 만족하는지. 기연 외에 엔딩 판정에서도 쓴다.
static func conditions_met(
	conditions: Array,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	story_flags: Dictionary
) -> bool:
	for c in conditions:
		if not _condition_met(c, character, sect, relationships, season, story_flags):
			return false
	return true


## 조건 목록을 검사해 오류를 errors에 더한다. 기연 외에 엔딩 정의 검증에서도 쓴다.
static func validate_conditions(conditions: Variant, errors: PackedStringArray) -> void:
	if not conditions is Array:
		errors.append("conditions는 배열이어야 함")
		return
	for condition in conditions:
		_validate_condition(condition, errors)


static func _condition_met(
	c: Dictionary,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	season: String,
	story_flags: Dictionary
) -> bool:
	match c["type"]:
		"character":
			var value: int
			if c["field"] == "martial_arts_count":
				value = character.martial_arts.size()
			else:
				value = character.get(c["field"])
			return _compare(value, c["op"], c["value"])
		"sect":
			return _compare(_money_target(sect, c["field"]).get(c["field"]), c["op"], c["value"])
		"bond":
			var bond: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(c))
			return bond != null and _compare(bond.bond_strength, c["op"], c["value"])
		"bond_count":
			return _compare(RelationshipManager.count_type(relationships, RelationshipData.BondType.get(c["bond_type"])), c["op"], c["value"])
		"role":
			return str(CharacterData.Role.find_key(character.role)) in c["in"]
		"season":
			return season in c["in"]
		"flag":
			return story_flags.get(c["flag"], false) == c.get("value", true)
		"world_sect":
			var world_sect: SectData = _find_world_sect(c["sect"])
			return world_sect != null and _compare(int(world_sect.get(c["field"])), c["op"], c["value"])
		"year":
			return _compare(current_year, c["op"], c["value"])
		"turns_since_flag":
			if not flag_turns.has(c["flag"]) or not story_flags.get(c["flag"], false):
				return false
			return _compare(current_turn - int(flag_turns[c["flag"]]), c["op"], c["value"])
		"relationship_type":
			var rel: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(c))
			return rel != null and rel.bond_type == RelationshipData.BondType.get(c["bond_type"])
		"role_history":
			return role_history.has(c["role"]) == c.get("value", true)
		"scenario":
			return ScenarioManager.current_id in c["in"]
		"years_left":
			return _compare(ScenarioRules.years_left(current_year), c["op"], c["value"])
		"regions_owned":
			return _compare(WorldMap.count(map_state, player_sect_id), c["op"], c["value"])
		"subjugated_count":
			var count: int = 0
			for world_sect in world_sects:
				if world_sect.subjugated:
					count += 1
			return _compare(count, c["op"], c["value"])
		"generation":
			return _compare(current_generation, c["op"], c["value"])
		"role_state":
			return _compare(int(role_state.get(c["field"], 0)), c["op"], c["value"])
		"alignment":
			return character.get_alignment() in c["in"]
	return false


## 금화·식량은 지갑(개인 재산이면 주머니), 그 밖의 문파 수치는 문파
static func _money_target(sect: SectData, field: String) -> SectData:
	return wallet if wallet != null and field in ["gold", "food"] else sect


## 얻을 비급이 남지 않았을 때 대신 주는 연구점
const NO_MANUAL_RESEARCH := 20


## 비급을 owned에 더한다. "random"이면 available(이미 연구할 수 있는 것)·owned·익힌 무공이 아닌 것 중 하나.
## 얻은 비급 이름을 돌려준다 (이미 있거나 남은 것이 없으면 "").
static func gain_manual(art_id: String, owned: Array[String], character: CharacterData, available: Array = []) -> String:
	if art_id == "random":
		var pool: Array[String] = []
		for art in MartialArtLibrary.get_all():
			if not owned.has(art.id) and not available.has(art.id) and not character.knows_martial_art(art.id):
				pool.append(art.id)
		if pool.is_empty():
			return ""
		art_id = pool.pick_random()
	if not MartialArtLibrary.has_art(art_id) or owned.has(art_id):
		return ""
	owned.append(art_id)
	return MartialArtLibrary.create_art(art_id).display_name


static func _compare(actual: float, op: String, expected: float) -> bool:
	match op:
		">=":
			return actual >= expected
		"<=":
			return actual <= expected
		">":
			return actual > expected
		"<":
			return actual < expected
		"==":
			return is_equal_approx(actual, expected)
		"!=":
			return not is_equal_approx(actual, expected)
	return false


## 효과 목록을 바로 반영한다 (전투 중 사건의 선택지 등). 결과 사전(message 등)을 돌려준다
static func apply_effects(effects: Array, character: CharacterData, sect: SectData, relationships: Array[RelationshipData], story_flags: Dictionary) -> Dictionary:
	var result: Dictionary = {"success": true, "message": ""}
	for effect in effects:
		if effect is Dictionary and effect.has("type"):
			_apply_effect(effect, character, sect, relationships, story_flags, result)
	return result


static func _apply_effect(
	e: Dictionary,
	character: CharacterData,
	sect: SectData,
	relationships: Array[RelationshipData],
	story_flags: Dictionary,
	result: Dictionary
) -> void:
	match e["type"]:
		"character":
			var field: String = e["field"]
			var new_value: int = int(character.get(field)) + int(e.get("add", 0))
			if field == "internal_energy_current":
				new_value = clampi(new_value, 0, character.internal_energy_max)
			character.set(field, new_value)
		"sect":
			var field: String = e["field"]
			var target: SectData = _money_target(sect, field)
			target.set(field, maxi(0, int(target.get(field)) + int(e.get("add", 0))))
		"experience":
			character.gain_experience(int(e["amount"]))
		"bond":
			var bond: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(e))
			if bond:
				bond.increase_bond(int(e.get("add", 0)))
		"flag":
			set_flag(story_flags, e["flag"], e.get("value", true))
		"combat":
			result["combat"] = CombatManager.create_by_id(e["combat"], character, sect)
		"world_sect":
			var world_sect: SectData = _find_world_sect(e["sect"])
			if world_sect:
				var value: int = int(world_sect.get(e["field"])) + int(e.get("add", 0))
				if e["field"] == "attitude":
					value = clampi(value, -100, 100)
				else:
					value = maxi(0, value)
				world_sect.set(e["field"], value)
		"set_bond_type":
			var rel: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(e))
			if rel:
				rel.bond_type = RelationshipData.BondType.get(e["bond_type"])
		"add_relationship":
			var target_id: String = _target(e)
			if NpcRoster.has_npc(target_id) and RelationshipManager.get_bond_with(relationships, target_id) == null:
				var made: RelationshipData = RelationshipManager.make_relationship(target_id, e["bond_type"], int(e.get("strength", 10)))
				if made:
					relationships.append(made)
		"marry":
			var rel: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(e))
			if rel and rel.bond_type != RelationshipData.BondType.SPOUSE:
				var wedding: String = RelationshipManager.marry(relationships, rel, world_sects)
				result["message"] = (str(result.get("message", "")) + " " + wedding).strip_edges()
				set_flag(story_flags, "married")
		"end_relationship":
			var rel: RelationshipData = RelationshipManager.get_bond_with(relationships, _target(e))
			if rel:
				relationships.erase(rel)
		"gain_manual":
			var library: Array = SectRegistry.get_sect_info(sect.id).get("manuals", []) if SectRegistry.has_sect(sect.id) else []
			var gained: String = gain_manual(str(e["art"]), owned_manuals, character, library)
			var note: String = "비급 [%s]을(를) 얻었습니다. 무공 연구소에서 연구할 수 있습니다." % gained if not gained.is_empty() \
				else "새로 얻을 비급이 없었습니다. 대신 연구점 +%d" % NO_MANUAL_RESEARCH
			if gained.is_empty():
				sect.research_points += NO_MANUAL_RESEARCH
			result["message"] = (str(result.get("message", "")) + " " + note).strip_edges()
		"learn_art":
			var art: MartialArtData = MartialArtLibrary.create_art(e["art"])
			if art:
				character.learn_martial_art(art)
		"end_game":
			result["end_game"] = e["ending"]
		"unlock":
			result["unlock"] = result.get("unlock", []) + [str(e["feature"])]
		"set_role":
			result["set_role"] = str(e["role"])
		"goal":
			result["goal"] = EventData.fill_text(str(e["text"]), _subject)
		"rumor":
			result["rumors"] = result.get("rumors", []) + [EventData.fill_text(str(e["text"]), _subject)]
		"role_state":
			if role_state.has(e["field"]):
				role_state[e["field"]] = clampi(int(role_state[e["field"]]) + int(e.get("add", 0)), 0, 100)
