extends Control

## 강호 정세: 문파 세력과 주요 인물을 한눈에 보여 준다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

@onready var sect_list: VBoxContainer = %SectList
@onready var npc_list: VBoxContainer = %NpcList


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	_build_sect_list()
	_build_npc_list()


func _build_sect_list() -> void:
	_add_heading(sect_list, "문파 세력")
	var player_sect: SectData = GameManager.player_sect
	_add_entry(
		sect_list,
		"%s (%s) — 우리 문파" % [player_sect.sect_name, player_sect.get_alignment_name()],
		"문주 %s | 제자 %d | 명성 %d | 전력 %d" % [
			player_sect.leader_name,
			player_sect.disciple_count,
			player_sect.reputation,
			SectWarManager.get_military_power(player_sect, GameManager.player_character),
		]
	)
	for sect in GameManager.get_world_sects_by_power():
		var status: String = "굴복" if sect.subjugated else sect.get_attitude_text()
		_add_entry(
			sect_list,
			"%s (%s) — %s" % [sect.sect_name, sect.get_alignment_name(), status],
			"문주 %s | 제자 %d | 명성 %d | 태도 %+d | 전력 %d\n%s" % [
				sect.leader_name,
				sect.disciple_count,
				sect.reputation,
				sect.attitude,
				SectWarManager.get_sect_power(sect),
				SectRegistry.get_description(sect.id),
			]
		)


func _build_npc_list() -> void:
	_add_heading(npc_list, "주요 인물")
	# 관계가 있는 인물을 먼저, 그다음 소속 문파 순으로 보여 준다.
	var npcs: Array[Dictionary] = NpcRoster.get_all()
	var relationships: Array[RelationshipData] = GameManager.player_relationships
	npcs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_bond: bool = RelationshipManager.get_bond_with(relationships, a["id"]) != null
		var b_bond: bool = RelationshipManager.get_bond_with(relationships, b["id"]) != null
		if a_bond != b_bond:
			return a_bond
		return a["sect_id"] < b["sect_id"]
	)
	for npc in npcs:
		# 도적처럼 이름 없는 졸개는 인물 목록에서 뺀다.
		if not NpcRoster.is_listed(npc):
			continue
		var bond: RelationshipData = RelationshipManager.get_bond_with(
			GameManager.player_relationships, npc["id"]
		)
		var bond_text: String = ""
		if bond:
			bond_text = " | %s %d (%s)" % [bond.get_bond_name(), bond.bond_strength, bond.get_stage_name()]
		var sect_name: String = SectRegistry.get_sect_info(npc["sect_id"]).get("sect_name", "무소속")
		_add_entry(
			npc_list,
			"%s — %s" % [npc["display_name"], npc.get("title", "")],
			"%s%s\n%s" % [sect_name, bond_text, npc.get("description", "")]
		)


func _add_heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	_UiTheme.style_label_title(label, 20)
	parent.add_child(label)


func _add_entry(parent: Control, title: String, body: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", _UiTheme.COLORS["accent_gold"])
	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 13)
	body_label.add_theme_color_override("font_color", _UiTheme.COLORS["text_primary"])
	box.add_child(title_label)
	box.add_child(body_label)
	parent.add_child(box)


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)
