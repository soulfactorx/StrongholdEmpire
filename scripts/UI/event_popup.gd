extends Control

@onready var title_label: Label = %EventTitleLabel
@onready var desc_label: Label = %EventDescLabel
@onready var choice1_button: Button = %Choice1Button
@onready var choice2_button: Button = %Choice2Button


func show_event(event_data: Dictionary) -> void:
	title_label.text = event_data.get("title", "기연")
	desc_label.text = event_data.get("description", "")
	var choices: Array = event_data.get("choices", [])
	choice1_button.text = choices[0] if choices.size() > 0 else "확인"
	choice2_button.text = choices[1] if choices.size() > 1 else ""
	choice2_button.visible = choices.size() > 1
	visible = true


func _on_choice1_pressed() -> void:
	GameManager.resolve_pending_event(0)
	visible = false


func _on_choice2_pressed() -> void:
	GameManager.resolve_pending_event(1)
	visible = false