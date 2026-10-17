class_name ActionPreview
extends RefCounted

## 행동 미리보기: 행동을 지금 상태에서 몰래 돌려 보고 수치 변화를 모은 뒤 상태를 원래대로 되돌린다.
## 운이 끼는 행동은 여러 번 돌려 변화 범위와 성공 확률을 보여 준다.
## 돌려 볼 때는 EventBus와 인물 신호를 막아 화면·소리·기록이 바뀌지 않게 한다.
## gm은 GameManager 노드다. (정적 함수라 오토로드 이름을 직접 쓰지 않는다)

## 운이 끼는 행동을 돌려 볼 횟수
const SAMPLES := 16
## 상태를 되돌릴 GameManager 변수 (배열·딕셔너리는 깊은 복사로 보관)
const GM_FIELDS: PackedStringArray = [
	"story_flags", "flag_turns", "role_history", "role_state", "observed_arts", "challenge_target",
	"pending_invasion", "world_news", "analyzed_elements", "triggered_event_ids", "current_ending_id",
	"game_over_id", "pending_event", "pending_role_transitions", "is_game_active", "last_turn_report",
	"player_relationships", "world_sects", "player_character", "player_sect", "pending_combat",
	"pending_war_plan", "year_start", "chronicle",
]
const STAT_NAMES: Dictionary = {
	"strength": "무력", "agility": "신법", "wisdom": "지혜", "charisma": "매력",
}
const ROLE_FIELD_NAMES: Dictionary = {
	"discontent": "불만도", "trust": "신임도", "exposure": "노출도", "bounty": "현상금",
	"failures": "건의 실패", "intel_count": "정보 수집",
}
const FACILITY_NAMES: Dictionary = {
	"library_level": "서고", "training_ground_level": "무술장", "treasury_level": "금고",
	"apothecary_level": "약방", "meditation_hall_level": "연공실",
}


## 경영 화면 등에서 쓰는 확인 흐름: 미리보기를 켜 두었고 보여 줄 변화가 있으면 확인창을 띄우고,
## 아니면 바로 실행한다. simulate는 상태를 바꾸고 결과 딕셔너리({success, message, combat?, event?})를 돌려주는 함수,
## run은 실제로 실행할 함수다.
static func confirm(host: Node, title: String, simulate: Callable, run: Callable) -> void:
	if not GameSettings.action_preview or not host.is_inside_tree():
		run.call()
		return
	var preview: Dictionary = simulate_action(host.get_node("/root/GameManager"), simulate)
	# 모두 실패(자원 부족 등)면 실행해 그 까닭을 알린다.
	if preview["success_rate"] <= 0.0:
		run.call()
		return
	get_popup(host).open(title + " — 미리보기", format(preview), run, "실행", "취소")


## 화면마다 확인창 하나를 맨 위 층에 두고 같이 쓴다.
static func get_popup(host: Node) -> Control:
	var tree: SceneTree = host.get_tree()
	var scene: Node = tree.current_scene if tree.current_scene else tree.root
	var layer: CanvasLayer = scene.get_node_or_null("PreviewLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "PreviewLayer"
		layer.layer = 90
		scene.add_child(layer)
		var popup: Control = preload("res://scripts/UI/confirm_popup.gd").new()
		popup.name = "PreviewPopup"
		layer.add_child(popup)
	return layer.get_node("PreviewPopup")


## 행동을 돌려 보고 결과를 모은다.
## 돌려주는 값: {before: {이름: 값}, after: {이름: [값...]}, success_rate, messages: {메시지: 횟수}, combat, event, samples}
static func simulate_action(gm: Node, action: Callable) -> Dictionary:
	var before: Dictionary = read_values(gm)
	var snapshot: Dictionary = _capture(gm)
	var bus: Node = gm.get_node_or_null("/root/EventBus")
	var bus_blocked: bool = bus.is_blocking_signals() if bus else false
	if bus:
		bus.set_block_signals(true)
	var character: CharacterData = gm.player_character
	character.set_block_signals(true)
	var result := {
		"before": before, "after": {}, "success_rate": 0.0, "messages": {},
		"combat": false, "event": false, "samples": 0, "random": false,
	}
	var successes: int = 0
	var base_seed: int = randi()
	for i in SAMPLES:
		seed(base_seed + i * 7919)
		var outcome: Dictionary = action.call()
		var after: Dictionary = read_values(gm)
		for key in after:
			if not result["after"].has(key):
				result["after"][key] = []
			result["after"][key].append(after[key])
		if outcome.get("success", false):
			successes += 1
		var message: String = str(outcome.get("message", ""))
		result["messages"][message] = result["messages"].get(message, 0) + 1
		if outcome.has("combat"):
			result["combat"] = true
		if outcome.has("event"):
			result["event"] = true
		_restore(gm, snapshot)
		result["samples"] += 1
	randomize()
	character.set_block_signals(false)
	if bus:
		bus.set_block_signals(bus_blocked)
	result["success_rate"] = float(successes) / result["samples"]
	result["random"] = result["messages"].size() > 1 or not _same_values(result["after"])
	return result


static func _same_values(after: Dictionary) -> bool:
	for key in after:
		var values: Array = after[key]
		if values.min() != values.max():
			return false
	return true


## 미리보기 문장: 바뀌는 수치마다 "금화 500 → 470 (-30)"
static func format(preview: Dictionary) -> String:
	var lines: PackedStringArray = []
	var before: Dictionary = preview["before"]
	var after: Dictionary = preview["after"]
	for key in after:
		# 새로 생긴 항목(새 제자 등)은 묶음 수치(제자 수 등)로 보여 준다.
		if not before.has(key):
			continue
		var values: Array = after[key]
		var old: int = before[key]
		var low: int = values.min()
		var high: int = values.max()
		if low == old and high == old:
			continue
		if low == high:
			lines.append("%s  %d → %d (%s)" % [key, old, low, _signed(low - old)])
		else:
			lines.append("%s  %d → %d~%d (%s ~ %s)" % [key, old, low, high, _signed(low - old), _signed(high - old)])
	var text: String
	var random: bool = preview["random"]
	if lines.is_empty():
		lines.append("눈에 보이는 수치 변화는 없습니다.")
	text = "예상 변화\n" + "\n".join(lines)
	if random:
		text += "\n\n결과가 운에 따라 달라집니다. (성공 확률 약 %d%%)" % roundi(preview["success_rate"] * 100)
		var outcomes: PackedStringArray = []
		for message in preview["messages"]:
			if not str(message).is_empty():
				outcomes.append("· %s (%d%%)" % [message, roundi(100.0 * preview["messages"][message] / preview["samples"])])
		if not outcomes.is_empty():
			text += "\n" + "\n".join(outcomes.slice(0, 4))
	elif preview["messages"].size() == 1:
		var only: String = str(preview["messages"].keys()[0])
		if not only.is_empty():
			text += "\n\n결과: " + only
	if preview["combat"]:
		text += "\n\n이어서 전투가 벌어집니다. (전투 결과는 위 변화에 들어 있지 않습니다)"
	if preview["event"]:
		text += "\n\n기연이 일어날 수 있습니다. (기연의 선택 결과는 위 변화에 들어 있지 않습니다)"
	return text


static func _signed(value: int) -> String:
	return "%+d" % value


## 미리보기에서 비교할 수치들 (이름 → 정수). 바뀐 것만 보여 주므로 넉넉히 담는다.
static func read_values(gm: Node) -> Dictionary:
	var values: Dictionary = {}
	var sect: SectData = gm.player_sect
	var character: CharacterData = gm.player_character
	values["금화"] = sect.gold
	values["식량"] = sect.food
	values["명성"] = sect.reputation
	values["연구점"] = sect.research_points
	values["제자 수"] = sect.disciple_count
	for field in FACILITY_NAMES:
		values["%s 단계" % FACILITY_NAMES[field]] = sect.get(field)
	values["레벨"] = character.level
	values["경험치"] = character.experience
	for field in STAT_NAMES:
		values[STAT_NAMES[field]] = character.get(field)
	values["최대 내공"] = character.internal_energy_max
	values["내공"] = character.internal_energy_current
	values["선악"] = character.morality
	values["익힌 무공 수"] = character.martial_arts.size()
	for field in ROLE_FIELD_NAMES:
		if gm.role_state.has(field):
			values[ROLE_FIELD_NAMES[field]] = int(gm.role_state[field])
	for rel in gm.player_relationships:
		values["유대: %s" % rel.target_name] = rel.bond_strength
	for other in gm.world_sects:
		values["%s 태도" % other.sect_name] = other.attitude
		values["%s 제자" % other.sect_name] = other.disciple_count
		values["%s 금화" % other.sect_name] = other.gold
	for disciple in sect.disciples:
		values["%s 레벨" % disciple.display_name] = disciple.level
		values["%s 경험치" % disciple.display_name] = disciple.experience
	return values


# ── 상태 보관·복원 ──

static func _capture(gm: Node) -> Dictionary:
	var fields: Dictionary = {}
	for field in GM_FIELDS:
		var value: Variant = gm.get(field)
		# 인물·세력 목록은 원소(같은 객체)만 보관하고 객체 내용은 아래에서 따로 보관한다.
		fields[field] = value.duplicate(field != "player_relationships" and field != "world_sects") if value is Array or value is Dictionary else value
	var objects: Array = [gm.player_character, gm.player_sect]
	objects.append_array(gm.player_relationships)
	objects.append_array(gm.world_sects)
	objects.append_array(gm.player_sect.disciples)
	var states: Array = []
	for object in objects:
		states.append([object, _capture_object(object)])
	return {"fields": fields, "objects": states}


static func _capture_object(object: Object) -> Dictionary:
	var props: Dictionary = {}
	for prop in object.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value: Variant = object.get(prop["name"])
		props[prop["name"]] = value.duplicate(true) if value is Array or value is Dictionary else value
	return props


static func _restore(gm: Node, snapshot: Dictionary) -> void:
	for field in snapshot["fields"]:
		var value: Variant = snapshot["fields"][field]
		if value is Array:
			var target: Array = gm.get(field)
			target.assign(value.duplicate(field != "player_relationships" and field != "world_sects"))
		elif value is Dictionary:
			# 다른 곳이 같은 딕셔너리를 잡고 있을 수 있어 제자리에서 되돌린다.
			var dict: Dictionary = gm.get(field)
			dict.clear()
			dict.merge(value.duplicate(true))
		else:
			gm.set(field, value)
	for entry in snapshot["objects"]:
		var object: Object = entry[0]
		var props: Dictionary = entry[1]
		for name in props:
			var value: Variant = props[name]
			if value is Array:
				var target: Array = object.get(name)
				target.assign(value.duplicate(true))
			elif value is Dictionary:
				object.set(name, value.duplicate(true))
			else:
				object.set(name, value)
