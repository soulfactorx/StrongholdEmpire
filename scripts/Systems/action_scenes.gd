class_name ActionScenes
extends RefCounted

## 행동 대화 장면: 경영 화면에서 행동(수련·영약·연회·전각·제자·신분 행동 등)을 하면 결과 알림 대신
## 그 일에 얽힌 인물과 주고받는 짧은 대화 장면이 뜬다. 장면은 data/scenes/actions/*.json에 행동마다 여러 개를 두고,
## 조건(계절·신분·문파 형편 등, 기연 조건 문법)과 결과(성공·실패)에 맞는 것 가운데 하나를 고른다.
## 형식은 docs/행동_장면_데이터_형식.md 참고.
## gm은 GameManager 노드다. (정적 함수라 오토로드 이름을 직접 쓰지 않는다)

const SCENE_DIR := "res://data/scenes/actions/"
## 말할 사람 지정: 고정 인물 id 또는 아래 토큰 (배열이면 앞에서부터 처음으로 찾은 사람)
const SPEAKER_TOKENS: PackedStringArray = [
	"$leader", "$master", "$bond", "$counterpart", "$target", "$target_leader", "$disciple", "$narrator",
	"$officer:leader", "$officer:instructor", "$officer:healer", "$officer:elder", "$officer:steward", "$officer:heir",
]
const RESULTS: PackedStringArray = ["any", "success", "fail"]
## 선택지 효과에서 말한 인물을 가리키는 자리 (유대 등)
const SPEAKER_REF := "$speaker"

static var _scenes: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if not _loaded:
		reload_data()


static func reload_data(dir_path: String = SCENE_DIR) -> void:
	_scenes.clear()
	_loaded = true
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for path in EventManager.collect_json_files(dir_path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			push_warning("행동 장면 JSON 파싱 실패: %s" % path)
			continue
		var errors: PackedStringArray = validate(data)
		if not errors.is_empty():
			push_warning("행동 장면 정의 오류 (%s): %s" % [path, "; ".join(errors)])
			continue
		var action: String = str(data["action"])
		var list: Array = _scenes.get(action, [])
		list.append_array(data["scenes"])
		_scenes[action] = list


static func has_action(action_id: String) -> bool:
	_ensure_loaded()
	return _scenes.has(action_id)


static func get_scenes(action_id: String) -> Array:
	_ensure_loaded()
	return _scenes.get(action_id, [])


static func get_actions() -> Array:
	_ensure_loaded()
	return _scenes.keys()


## 장면 파일 하나를 검사한다
static func validate(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	if str(data.get("action", "")).is_empty():
		errors.append("action이 비어 있음")
	var scenes: Variant = data.get("scenes")
	if not scenes is Array or (scenes as Array).is_empty():
		errors.append("scenes가 비어 있음")
		return errors
	var ids: Dictionary = {}
	for scene in scenes:
		if not scene is Dictionary:
			errors.append("장면은 객체여야 함")
			continue
		var id: String = str(scene.get("id", ""))
		if id.is_empty() or ids.has(id):
			errors.append("장면 id가 없거나 겹침: %s" % id)
		ids[id] = true
		if not str(scene.get("result", "any")) in RESULTS:
			errors.append("%s: result는 any·success·fail" % id)
		var lines: Variant = scene.get("lines")
		if not lines is Array or (lines as Array).is_empty():
			errors.append("%s: lines가 비어 있음" % id)
		var speakers: Array = scene.get("speaker", []) if scene.get("speaker") is Array else [scene.get("speaker", "$narrator")]
		for speaker in speakers:
			var token: String = str(speaker)
			if not token in SPEAKER_TOKENS and not NpcRoster.has_npc(token):
				errors.append("%s: 알 수 없는 말하는 사람: %s" % [id, token])
		EventManager.validate_conditions(scene.get("if", []), errors)
		for choice in scene.get("choices", []):
			if not choice is Dictionary or str(choice.get("label", "")).is_empty():
				errors.append("%s: 선택지에 label 필요" % id)
				continue
			for effect in choice.get("effects", []):
				# 말한 인물은 장면을 고를 때 정해지므로, 검사할 때는 아무 명부 인물로 바꿔 본다
				var probe: Variant = effect.duplicate() if effect is Dictionary else effect
				if probe is Dictionary and str(probe.get("target", "")) == SPEAKER_REF:
					probe["target"] = "npc_master"
				EventManager._validate_effect(probe, errors)
	return errors


## 행동에 맞는 장면 하나를 골라 창 자료로 만든다. 없으면 {}.
## context: {title(행동 이름), counterpart_id, target_id, target_name, target_leader_id, disciple_name, detail}
## 반환: {title, description, choices: [이름], npc, scene_id, speaker_id, options: [{label, message, effects}]}
static func build(gm: Node, action_id: String, result: Dictionary, context: Dictionary = {}, recent: Array = [], rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var success: bool = result.get("success", false)
	var candidates: Array = []
	for scene in get_scenes(action_id):
		var wanted: String = str(scene.get("result", "any"))
		if (wanted == "success" and not success) or (wanted == "fail" and success):
			continue
		if not EventManager.conditions_met(scene.get("if", []), gm.player_character, gm.player_sect, gm.player_relationships, gm.get_current_season(), gm.story_flags):
			continue
		var speaker: Dictionary = resolve_speaker(gm, scene.get("speaker", "$narrator"), context)
		if speaker.is_empty():
			continue
		candidates.append({"scene": scene, "speaker": speaker})
	if candidates.is_empty():
		return {}
	# 방금 본 장면은 다른 것이 있으면 피한다
	var fresh: Array = candidates.filter(func(c: Dictionary) -> bool: return not str(c["scene"]["id"]) in recent)
	if not fresh.is_empty():
		candidates = fresh
	var total: float = 0.0
	for c in candidates:
		total += float(c["scene"].get("weight", 1.0))
	var roll: float = rng.randf() * total
	var chosen: Dictionary = candidates[-1]
	for c in candidates:
		roll -= float(c["scene"].get("weight", 1.0))
		if roll <= 0.0:
			chosen = c
			break
	return _compose(gm, chosen["scene"], chosen["speaker"], result, context)


static func _compose(gm: Node, scene: Dictionary, speaker: Dictionary, result: Dictionary, context: Dictionary) -> Dictionary:
	var values: Dictionary = {
		"player": gm.player_character.display_name,
		"speaker": speaker["name"],
		"sect": gm.player_sect.sect_name,
		"season": gm.get_current_season(),
		"target": str(context.get("target_name", "")),
		"detail": str(context.get("detail", "")),
		"disciple": str(context.get("disciple_name", "제자")),
	}
	var lines: PackedStringArray = []
	for line in scene["lines"]:
		var text: String = str(line)
		# 말할 인물이 없으면(서술) "{speaker}: 대사"는 따옴표 대사로, 나머지 {speaker}는 "상대"로
		if speaker["name"].is_empty():
			if text.begins_with("{speaker}: "):
				text = "“%s”" % text.trim_prefix("{speaker}: ")
			text = text.replace("{speaker}", "상대")
		lines.append(_fill(text, values))
	var options: Array = []
	for choice in scene.get("choices", []):
		var effects: Array = []
		for effect in choice.get("effects", []):
			var e: Dictionary = effect.duplicate(true)
			if str(e.get("target", "")) == SPEAKER_REF:
				if speaker["id"].is_empty():
					continue
				e["target"] = speaker["id"]
			effects.append(e)
		options.append({"label": _fill(str(choice["label"]), values), "message": _fill(str(choice.get("message", "")), values), "effects": effects})
	if options.is_empty():
		options.append({"label": "고개를 끄덕인다", "message": "", "effects": []})
	var message: String = str(result.get("message", ""))
	var title: String = str(context.get("title", ""))
	if scene.has("title"):
		title = "%s — %s" % [title, _fill(str(scene["title"]), values)] if not title.is_empty() else _fill(str(scene["title"]), values)
	return {
		"title": title,
		"description": "\n".join(lines) + ("\n\n【%s】" % message if not message.is_empty() else ""),
		"choices": options.map(func(o: Dictionary) -> String: return o["label"]),
		"npc": speaker["id"],
		"scene_id": str(scene["id"]),
		"speaker_id": speaker["id"],
		"options": options,
		"action_scene": true,
	}


static func _fill(text: String, values: Dictionary) -> String:
	for key in values:
		text = text.replace("{%s}" % key, str(values[key]))
	return text


## 말할 사람을 찾는다: {id(명부 인물이면), name}. 못 찾으면 {}
static func resolve_speaker(gm: Node, spec: Variant, context: Dictionary) -> Dictionary:
	var tokens: Array = spec if spec is Array else [spec]
	for token in tokens:
		var found: Dictionary = _resolve_one(gm, str(token), context)
		if not found.is_empty():
			return found
	return {}


static func _resolve_one(gm: Node, token: String, context: Dictionary) -> Dictionary:
	match token:
		"$narrator":
			return {"id": "", "name": ""}
		"$leader":
			var leader: String = gm.player_sect.leader_id
			if gm.player_character.role == CharacterData.Role.LEADER or gm.player_sect.id.is_empty():
				return {}
			return _npc(gm, leader)
		"$master":
			for rel in gm.player_relationships:
				if rel.bond_type == RelationshipData.BondType.MASTER_DISCIPLE:
					return _npc(gm, rel.target_id)
			return {}
		"$bond":
			var best: RelationshipData = null
			for rel in gm.player_relationships:
				if _npc(gm, rel.target_id).is_empty() or rel.bond_type == RelationshipData.BondType.HATRED:
					continue
				if best == null or rel.bond_strength > best.bond_strength:
					best = rel
			return _npc(gm, best.target_id) if best else {}
		"$counterpart", "$target", "$target_leader":
			var key: String = {"$counterpart": "counterpart_id", "$target": "target_id", "$target_leader": "target_leader_id"}[token]
			return _npc(gm, str(context.get(key, "")))
		"$disciple":
			var name: String = str(context.get("disciple_name", ""))
			if name.is_empty() and not gm.player_sect.disciples.is_empty():
				name = gm.player_sect.disciples[randi() % gm.player_sect.disciples.size()].display_name
			if name.is_empty():
				if gm.player_sect.disciple_count <= 0:
					return {}
				name = "제자"
			return {"id": "", "name": name}
	if token.begins_with("$officer:"):
		if gm.player_sect.id.is_empty():
			return {}
		var post: String = token.trim_prefix("$officer:")
		for officer in NpcAgent.get_officers(gm.player_sect):
			if officer["post"] == post and not (post == "leader" and gm.player_character.role == CharacterData.Role.LEADER):
				return _npc(gm, str(officer["npc"]))
		return {}
	return _npc(gm, token)


## 명부 인물 (이 시나리오에 나오지 않는 인물이나 주인공 자신은 빼고)
static func _npc(gm: Node, npc_id: String) -> Dictionary:
	if npc_id.is_empty() or not NpcRoster.has_npc(npc_id) or NpcRoster.is_hidden(npc_id) or npc_id == str(gm.get("player_npc_id")):
		return {}
	return {"id": npc_id, "name": NpcRoster.get_display_name(npc_id)}
