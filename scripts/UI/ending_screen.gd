extends Control

@onready var title_label: Label = %EndingTitleLabel
@onready var desc_label: Label = %EndingDescLabel
@onready var legacy_label: Label = %LegacyLabel


func _ready() -> void:
	_display_ending()


func _display_ending() -> void:
	var ending_id: String = GameManager.current_ending_id
	if ending_id.is_empty():
		title_label.text = "아직 엔딩에 도달하지 않았습니다"
		desc_label.text = (
			"문주가 되어 정파를 통일하거나,\n"
			+ "스파이/암살자의 길을 걷거나,\n"
			+ "낭인으로 전설을 쌓아보세요."
		)
	else:
		var ending: Dictionary = EndingManager.get_ending(ending_id)
		title_label.text = "엔딩: %s" % ending["title"]
		desc_label.text = ending["description"]

	if GameManager.legacy_records.is_empty():
		legacy_label.text = "레거시 기록 없음"
	else:
		var lines: PackedStringArray = []
		for legacy in GameManager.legacy_records:
			lines.append(legacy.summary)
		legacy_label.text = "레거시:\n" + "\n".join(lines)


func _on_succession_pressed() -> void:
	var result: Dictionary = GameManager.start_legacy_succession()
	desc_label.text = result["message"]
	if result["success"]:
		GameManager.current_ending_id = ""
		_display_ending()


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)