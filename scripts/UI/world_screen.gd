extends Control

## 강호 정세: 문파 세력과 주요 인물을 한눈에 보여 준다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _ChoicePopup = preload("res://scripts/UI/choice_popup.gd")

## 세력 문장과 인물 초상화 크기
const EMBLEM_SIZE := Vector2(56, 56)
const PORTRAIT_SIZE := Vector2(56, 70)

@onready var sect_list: VBoxContainer = %SectList
@onready var npc_list: VBoxContainer = %NpcList
@onready var log_label: Label = %LogLabel
## 외교 행동을 고르는 팝업과, 교섭 중인 세력 id
var choice_popup: Control
var _diplomacy_target: String = ""


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	# 세로(휴대폰): 세력 칸 위, 소식·인물 칸 아래
	LayoutMode.stack($Margin/VBox/HBox)
	choice_popup = _ChoicePopup.new()
	add_child(choice_popup)
	choice_popup.chosen.connect(_on_diplomacy_chosen)
	_build_sect_list()
	_build_news()
	_build_npc_list()
	if not DiplomacyManager.can_negotiate(GameManager.player_character):
		log_label.text = "외교는 문파를 대표하는 문주·중간관리자(총관)만 할 수 있습니다. 지금 역할(%s)로는 세력의 형편과 인물만 봅니다." % GameManager.player_character.get_role_name()


## 강호 소식은 인물 목록 위에 최근 것부터 보여 준다.
const NEWS_LINES := 8


## 강호 소식: 세력 AI의 행동 (최근 것이 위)
func _build_news() -> void:
	_add_heading(npc_list, "강호 소식")
	if GameManager.world_news.is_empty():
		_add_entry(npc_list, "조용한 강호", "아직 들려온 소식이 없습니다.")
		return
	var lines: Array[String] = GameManager.world_news.duplicate()
	lines.reverse()
	var label := Label.new()
	label.text = "\n".join(lines.slice(0, NEWS_LINES))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(label, 13)
	npc_list.add_child(label)


func _rebuild_sect_list() -> void:
	for child in sect_list.get_children():
		sect_list.remove_child(child)
		child.queue_free()
	_build_sect_list()


func _on_diplomacy_pressed(sect_id: String) -> void:
	AudioManager.play_click()
	if not DiplomacyManager.can_negotiate(GameManager.player_character):
		log_label.text = "외교는 문파를 대표하는 문주나 중간관리자만 할 수 있습니다."
		return
	var sect: SectData = GameManager.get_world_sect(sect_id)
	var options: Array[Dictionary] = []
	for option in DiplomacyManager.get_options(GameManager, sect):
		options.append({
			"id": option["id"], "title": option["title"], "description": option["description"],
			"disabled": not option["available"],
		})
	_diplomacy_target = sect_id
	var done: bool = sect.last_diplomacy_turn == GameManager._get_turn_index()
	choice_popup.open(
		"%s와(과)의 외교" % sect.sect_name,
		"세력마다 계절에 한 번 교섭할 수 있습니다.%s" % (" (이번 계절에는 이미 교섭했습니다)" if done else ""),
		options
	)


func _on_diplomacy_chosen(action_id: String) -> void:
	var sect_id: String = _diplomacy_target
	ActionPreview.confirm(
		self, "외교: %s" % DiplomacyManager.ACTIONS.get(action_id, action_id),
		DiplomacyManager.perform.bind(GameManager, sect_id, action_id), _do_diplomacy.bind(sect_id, action_id)
	)


func _do_diplomacy(sect_id: String, action_id: String) -> void:
	var result: Dictionary = GameManager.do_diplomacy(sect_id, action_id)
	var lines: PackedStringArray = result.get("dialogue", PackedStringArray())
	log_label.text = result["message"] + ("\n" + "\n".join(lines) if not lines.is_empty() else "")
	if result["success"]:
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	_rebuild_sect_list()


func _build_sect_list() -> void:
	_add_heading(sect_list, "문파 세력")
	var player_sect: SectData = GameManager.player_sect
	_add_entry(
		sect_list,
		"%s (%s) — 우리 문파" % [player_sect.sect_name, player_sect.get_alignment_name()],
		"문주 %s | 제자 %d | 명성 %d | 전력 %d\n직책: %s" % [
			player_sect.leader_name,
			player_sect.disciple_count,
			player_sect.reputation,
			SectWarManager.get_military_power(player_sect, GameManager.player_character),
			_officer_text(player_sect),
		],
		ArtAssets.emblem(player_sect.id), EMBLEM_SIZE
	)
	for sect in GameManager.get_world_sects_by_power():
		var status: String = "굴복" if sect.subjugated else sect.get_attitude_text()
		var tags: PackedStringArray = []
		if sect.allied:
			tags.append("동맹")
		if sect.married:
			tags.append("사돈")
		if sect.tribute:
			tags.append("공물")
		if GameManager.challenge_target == sect.id:
			tags.append("도전장")
		if not tags.is_empty():
			status += " · " + " · ".join(tags)
		_add_entry(
			sect_list,
			"%s (%s) — %s" % [sect.sect_name, sect.get_alignment_name(), status],
			"문주 %s | 제자 %d | 명성 %d | 태도 %+d | 전력 %d | 땅 %d\n전략: %s — %s\n직책: %s\n%s%s" % [
				sect.leader_name,
				sect.disciple_count,
				sect.reputation,
				sect.attitude,
				SectWarManager.get_sect_power(sect),
				WorldMap.count(GameManager.map_state, sect.id),
				FactionStrategy.get_title(FactionStrategy.of(sect)),
				FactionStrategy.get_description(FactionStrategy.of(sect)),
				_officer_text(sect),
				SectRegistry.get_description(sect.id),
				_last_report_line(sect.id),
			],
			ArtAssets.emblem(sect.id), EMBLEM_SIZE
		)
		# 외교를 할 수 없는 역할에게는 버튼을 보이지 않는다 (눌러도 아무 일이 없는 것처럼 보이지 않게)
		if not DiplomacyManager.can_negotiate(GameManager.player_character):
			continue
		var button := Button.new()
		button.text = "외교"
		button.custom_minimum_size = Vector2(160, 48)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.pressed.connect(_on_diplomacy_pressed.bind(sect.id))
		_UiTheme.style_button(button)
		sect_list.add_child(button)


## "남궁천(문주) · 남궁휘(후계자)" — 문주는 성향도 함께
func _officer_text(sect: SectData) -> String:
	var parts: PackedStringArray = []
	for officer in NpcAgent.get_officers(sect):
		parts.append("%s(%s)" % [NpcRoster.get_display_name(officer["npc"]), NpcAgent.POST_NAMES[officer["post"]]])
	var traits: Dictionary = NpcAgent.get_traits(sect.leader_id)
	return "%s — 문주 성향 야망 %d · 신중 %d · 인정 %d" % [" · ".join(parts), traits["ambition"], traits["caution"], traits["benevolence"]]


## 지난 계절 이 세력이 한 일 (세력 동향)
func _last_report_line(sect_id: String) -> String:
	for report in GameManager.last_faction_report:
		if report.get("sect_id", "") == sect_id:
			return "\n지난 계절: %s — %s" % [report.get("action", ""), report.get("detail", "")]
	return ""


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
			"%s%s\n%s\n성향: %s" % [sect_name, bond_text, npc.get("description", ""), NpcAgent.describe(npc["id"])],
			ArtAssets.portrait(npc["id"]), PORTRAIT_SIZE
		)


func _add_heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	_UiTheme.style_label_title(label, 20)
	parent.add_child(label)


## 항목: 제목과 본문. 그림(문장·초상화)이 있으면 왼쪽에 둔다.
func _add_entry(parent: Control, title: String, body: String, picture: Texture2D = null, picture_size := Vector2.ZERO) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", _UiTheme.COLORS["accent_gold"])
	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_UiTheme.set_font_size(body_label, 13)
	body_label.add_theme_color_override("font_color", _UiTheme.COLORS["text_primary"])
	box.add_child(title_label)
	box.add_child(body_label)
	var rect: TextureRect = ArtAssets.picture_rect(picture, picture_size)
	if rect == null:
		parent.add_child(box)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(rect)
	row.add_child(box)
	parent.add_child(row)


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)
