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
## 팝업에 초상화를 보일 인물 id (없으면 "")
@export var npc: String = ""
## 관계 대상 기연이면 대상을 고르는 기준 (EventManager 상단 설명). 아니면 비어 있다.
@export var subject: Dictionary = {}
## 모두 만족해야 발생하는 조건 목록
@export var conditions: Array[Dictionary] = []
## 선택지 목록: label, message, effects, (선택) branches, success
@export var choices: Array[Dictionary] = []


func get_choice_labels() -> PackedStringArray:
	var labels: PackedStringArray = []
	for choice in choices:
		labels.append(choice.get("label", ""))
	return labels


## 팝업과 GameManager.pending_event가 쓰는 형식. 관계 대상 기연이면 subject_id 인물로 글({name}·{title})을 채운다.
func to_popup_dict(subject_id: String = "") -> Dictionary:
	var labels: PackedStringArray = []
	for label in get_choice_labels():
		labels.append(fill_text(label, subject_id))
	return {
		"id": id,
		"title": fill_text(title, subject_id),
		"description": fill_text(description, subject_id),
		"choices": labels,
		"can_repeat": can_repeat,
		"npc": subject_id if not subject_id.is_empty() else npc,
		"subject": subject_id,
	}


## 이름 뒤 조사: 받침이 있으면 앞, 없으면 뒤를 쓴다. ("(으)로"는 받침이 없거나 ㄹ이면 "로")
const PARTICLES: Array = [["이(가)", "이", "가"], ["을(를)", "을", "를"], ["은(는)", "은", "는"], ["와(과)", "과", "와"], ["(으)로", "으로", "로"], ["아(야)", "아", "야"]]


## 글 속 {name}(이름)·{title}(호칭)을 대상 인물로 바꾼다. 이름 바로 뒤의 "이(가)" 같은 조사는 받침에 맞춰 고른다.
static func fill_text(text: String, subject_id: String) -> String:
	if subject_id.is_empty():
		return text
	var npc_data: Dictionary = NpcRoster.get_npc(subject_id)
	var npc_name: String = str(npc_data.get("display_name", "무명"))
	var code: int = npc_name.unicode_at(npc_name.length() - 1) - 0xAC00
	var has_final: bool = code >= 0 and code < 11172 and code % 28 != 0
	var final_rieul: bool = has_final and code % 28 == 8
	for particle in PARTICLES:
		var use_first: bool = has_final and not (particle[0] == "(으)로" and final_rieul)
		text = text.replace("{name}" + particle[0], npc_name + (particle[1] if use_first else particle[2]))
	return text.replace("{name}", npc_name).replace("{title}", str(npc_data.get("title", "")))
