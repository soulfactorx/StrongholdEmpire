class_name EventData
extends Resource

## 기연 정의. data/events/*.json 한 파일이 하나의 EventData가 된다.
## 조건·효과 형식은 EventManager 상단 설명을 따른다.

@export var id: String = ""
@export var title: String = ""
@export var description: String = ""
@export var can_repeat: bool = false
## 발생 후보 중 뽑힐 상대적 확률
@export var weight: float = 1.0
## 우선 기연: 조건을 채우면 기연 발생 확률과 관계없이 그 계절에 먼저 일어난다 (인연 단계 변화 등)
@export var priority: bool = false
## 다른 기연의 선택지 next로만 일어나는 기연 (계절마다 뽑는 후보에 들지 않음)
@export var follow_up: bool = false
## 강호 연표에 보일 큰 사건: {title, hint, branches: [{text, if}]} (비면 연표에 없음)
@export var timeline: Dictionary = {}
## 창에 초상화를 보일 인물 id (없으면 "")
@export var npc: String = ""
## 관계 대상 기연이면 대상을 고르는 기준 (EventManager 상단 설명). 아니면 비어 있다.
@export var subject: Dictionary = {}
## 장면 대사: [{speaker: 인물 id 또는 "player", text}] — 설명 아래에 인물들의 대사로 보인다
@export var scene: Array[Dictionary] = []
## 모두 만족해야 발생하는 조건 목록
@export var conditions: Array[Dictionary] = []
## 선택지 목록: label, message, effects, (선택) branches, success
@export var choices: Array[Dictionary] = []


func get_choice_labels() -> PackedStringArray:
	var labels: PackedStringArray = []
	for choice in choices:
		labels.append(choice.get("label", ""))
	return labels


## 창과 GameManager.pending_event가 쓰는 형식. 관계 대상 기연이면 subject_id 인물로 글({name}·{title})을 채운다.
## visible: 보일 선택지 번호 (선택지 조건). 비우면 모두. choice_map은 보이는 순번 → 원래 선택지 번호
## scene_lines: 보일 대사 줄 번호 (줄의 if 조건). 비우면(기본) 조건을 따지지 않고 모두.
func to_popup_dict(subject_id: String = "", visible: Array = [], scene_lines: Array = [-1]) -> Dictionary:
	var shown: Array = visible if not visible.is_empty() else range(choices.size())
	var labels: PackedStringArray = []
	for index in shown:
		labels.append(fill_text(str(choices[index].get("label", "")), subject_id))
	var text: String = fill_text(description, subject_id)
	var scene_text: String = get_scene_text(subject_id, scene_lines)
	if not scene_text.is_empty():
		text += "\n\n" + scene_text
	return {
		"id": id,
		"title": fill_text(title, subject_id),
		"description": text,
		"choices": labels,
		"choice_map": shown,
		"can_repeat": can_repeat,
		"npc": subject_id if not subject_id.is_empty() else npc,
		"subject": subject_id,
	}


## 이름 뒤 조사: 받침이 있으면 앞, 없으면 뒤를 쓴다. ("(으)로"는 받침이 없거나 ㄹ이면 "로")
const PARTICLES: Array = [["이(가)", "이", "가"], ["을(를)", "을", "를"], ["은(는)", "은", "는"], ["와(과)", "과", "와"], ["(으)로", "으로", "로"], ["아(야)", "아", "야"]]


## 장면 대사를 "이름: 대사" 줄로. 주인공이 연기하는 인물의 대사는 빼고(주인공은 "player" 줄로 말한다),
## "only"(인물 id 목록)가 있는 줄은 그 인물로 플레이할 때만 보인다.
func get_scene_text(subject_id: String = "", only_lines: Array = [-1]) -> String:
	var lines: PackedStringArray = []
	for i in scene.size():
		var line: Dictionary = scene[i]
		if only_lines != [-1] and not only_lines.has(i):
			continue
		var speaker: String = str(line.get("speaker", ""))
		if speaker == EventManager.player_npc_id and not speaker.is_empty():
			continue
		var only: Array = line.get("only", [])
		if not only.is_empty() and not only.has(EventManager.player_npc_id):
			continue
		var text: String = fill_text(str(line.get("text", "")), subject_id)
		if speaker.is_empty():
			lines.append(text)
			continue
		var who: String = EventManager.player_name if speaker == "player" else NpcRoster.get_display_name(speaker)
		lines.append("%s: %s" % [who, text])
	return "\n".join(lines)


## 글 속 {player}(주인공 이름), {name}(이름)·{title}(호칭)을 대상 인물로 바꾼다. 이름 바로 뒤의 "이(가)" 같은 조사는 받침에 맞춰 고른다.
static func fill_text(text: String, subject_id: String) -> String:
	if text.contains("{player}"):
		text = _fill_name(text, "{player}", EventManager.player_name)
	if subject_id.is_empty():
		return text
	var npc_data: Dictionary = NpcRoster.get_npc(subject_id)
	text = _fill_name(text, "{name}", str(npc_data.get("display_name", "무명")))
	return text.replace("{title}", str(npc_data.get("title", "")))


## token을 이름으로 바꾸고, 바로 뒤의 조사를 받침에 맞춘다.
static func _fill_name(text: String, token: String, npc_name: String) -> String:
	if npc_name.is_empty():
		npc_name = "그대"
	var code: int = npc_name.unicode_at(npc_name.length() - 1) - 0xAC00
	var has_final: bool = code >= 0 and code < 11172 and code % 28 != 0
	var final_rieul: bool = has_final and code % 28 == 8
	for particle in PARTICLES:
		var use_first: bool = has_final and not (particle[0] == "(으)로" and final_rieul)
		text = text.replace(token + particle[0], npc_name + (particle[1] if use_first else particle[2]))
	return text.replace(token, npc_name)
