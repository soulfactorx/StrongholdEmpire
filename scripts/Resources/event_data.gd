class_name EventData
extends Resource

## 기연 정의. data/events/*.json 한 파일이 하나의 EventData가 된다.
## 조건·효과 형식은 EventManager 상단 설명을 따른다.

@export var id: String = ""
@export var title: String = ""
@export var description: String = ""
@export var can_repeat: bool = false
## 모두 만족해야 발생하는 조건 목록
@export var conditions: Array[Dictionary] = []
## 선택지 목록: label, message, effects, (선택) branches, success
@export var choices: Array[Dictionary] = []


func get_choice_labels() -> PackedStringArray:
	var labels: PackedStringArray = []
	for choice in choices:
		labels.append(choice.get("label", ""))
	return labels


## 팝업과 GameManager.pending_event가 쓰는 형식
func to_popup_dict() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"description": description,
		"choices": get_choice_labels(),
		"can_repeat": can_repeat,
	}
