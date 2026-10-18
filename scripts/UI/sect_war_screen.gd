extends Control

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")
const _Balance = preload("res://scripts/Systems/game_balance.gd")

var _commands: Array[SectWarManager.Command] = []
var _targets: Array[SectData] = []
var _generals: Array[Dictionary] = []
## 진형 선택지 순서 (FormationOption 인덱스 → Formation)
var _formations: Array = [
	SectWarManager.Formation.NONE,
	SectWarManager.Formation.CRANE,
	SectWarManager.Formation.FISH,
	SectWarManager.Formation.CIRCLE,
]

@onready var title_label: Label = %Title
@onready var target_option: OptionButton = %TargetOption
@onready var enemy_label: Label = %EnemyLabel
@onready var scout_button: Button = %ScoutButton
@onready var formation_option: OptionButton = %FormationOption
@onready var general_option: OptionButton = %GeneralOption
@onready var power_label: Label = %PowerLabel
@onready var round_label: Label = %RoundLabel
@onready var plan_label: Label = %PlanLabel
@onready var log_label: Label = %LogLabel
@onready var execute_button: Button = %ExecuteButton


func _ready() -> void:
	_UiTheme.apply_to_control(self)
	# 세로(휴대폰): 준비 칸 위, 명령 칸 아래
	LayoutMode.stack($Margin/VBox/Columns, [1.0, 1.2])
	for formation in _formations:
		var name: String = SectWarManager.FORMATION_NAMES[formation]
		if SectWarManager.FORMATION_BOOSTS.has(formation):
			var boosted: SectWarManager.Command = SectWarManager.FORMATION_BOOSTS[formation]
			var weak: SectWarManager.Command = SectWarManager.COMMAND_BEATS.find_key(boosted)
			name += " (%s 강화, %s 약화)" % [SectWarManager.COMMAND_NAMES[boosted], SectWarManager.COMMAND_NAMES[weak]]
		formation_option.add_item(name)
	_fill_targets()
	if not GameManager.can_wage_war():
		log_label.text = "이번 계절에는 이미 문파전을 치렀습니다. 다음 계절을 기다리세요."
	elif not GameManager.pending_region_target.is_empty():
		log_label.text = "%s 공략: 이기면 이 땅을 차지합니다." % WorldMap.get_region(GameManager.pending_region_target).get("name", "")
	_update_display()


func _fill_targets() -> void:
	_targets = GameManager.get_war_targets()
	target_option.clear()
	for sect in _targets:
		target_option.add_item("%s (%s)" % [sect.sect_name, sect.get_alignment_name()])
	if not _targets.is_empty():
		target_option.select(0)
	# 지도에서 [공략]으로 왔으면 그 땅의 주인을 먼저 고른다.
	var region_id: String = GameManager.pending_region_target
	if not region_id.is_empty():
		var owner: String = WorldMap.get_owner(GameManager.map_state, region_id)
		for i in _targets.size():
			if _targets[i].id == owner:
				target_option.select(i)
	_fill_generals()


func _fill_generals() -> void:
	var target: SectData = _get_target()
	_generals = GameManager.get_war_generals(target.id if target else "")
	general_option.clear()
	general_option.add_item("없음")
	for general in _generals:
		var specialty: String = ""
		if general["specialty"] >= 0:
			specialty = ", %s 특기" % SectWarManager.COMMAND_NAMES[general["specialty"]]
		general_option.add_item("%s (전력 +%d%s)" % [general["name"], general["power"], specialty])
	general_option.select(0)


func _get_target() -> SectData:
	var index: int = target_option.selected
	if index < 0 or index >= _targets.size():
		return null
	return _targets[index]


func get_selected_formation() -> SectWarManager.Formation:
	return _formations[maxi(0, formation_option.selected)]


func get_selected_general() -> Dictionary:
	var index: int = general_option.selected - 1
	return _generals[index] if index >= 0 and index < _generals.size() else {}


func _update_display() -> void:
	var target: SectData = _get_target()
	var general: Dictionary = get_selected_general()
	var power: int = SectWarManager.get_military_power(GameManager.player_sect, GameManager.player_character)
	var ally_power: int = DiplomacyManager.get_ally_support(GameManager.world_sects)
	power_label.text = "아군 전력: %d%s%s | %s (%s)" % [
		power + int(general.get("power", 0)) + ally_power,
		" (장수 +%d)" % general["power"] if not general.is_empty() else "",
		" (동맹 원군 +%d)" % ally_power if ally_power > 0 else "",
		GameManager.player_character.display_name,
		GameManager.player_character.get_role_name(),
	]

	var plan: Dictionary = {}
	if target == null:
		title_label.text = "문파전 지휘"
		enemy_label.text = "강호의 모든 세력이 굴복했습니다."
		scout_button.disabled = true
	else:
		plan = GameManager.prepare_war(target.id)
		title_label.text = "문파전 지휘 — %s" % target.sect_name
		enemy_label.text = "%s | 문주 %s | 제자 %d | 명성 %d | 태도 %s\n적 전력: %d | 진형: %s | 즐겨 쓰는 명령: %s" % [
			target.get_alignment_name(),
			target.leader_name,
			target.disciple_count,
			target.reputation,
			target.get_attitude_text(),
			SectWarManager.get_sect_power(target),
			SectWarManager.FORMATION_NAMES[plan["enemy_formation"]],
			SectWarManager.COMMAND_NAMES[SectWarManager.get_preferred_command(target)],
		]
		if not target.observed_commands.is_empty():
			enemy_label.text += "\n적은 지난 전투에서 본 아군의 수를 기억하고 대비합니다."
		var all_known: bool = not plan["revealed"].has(false)
		scout_button.disabled = all_known or not GameManager.can_wage_war()
		scout_button.text = "정찰 완료" if all_known else "정찰 (금화 %d)" % SectWarManager.get_scout_cost(plan, GameManager.player_character)

	# 라운드별 계획: 아군 명령과 정찰로 알아낸 적 명령
	var lines: PackedStringArray = []
	for i in _Balance.WAR_ROUNDS:
		var ours: String = SectWarManager.COMMAND_NAMES[_commands[i]] if i < _commands.size() else "—"
		var theirs: String = "?"
		if not plan.is_empty() and plan["revealed"][i]:
			theirs = SectWarManager.COMMAND_NAMES[plan["enemy_commands"][i]]
		lines.append("%d라운드: 아군 %s  /  적 %s" % [i + 1, ours, theirs])
	plan_label.text = "\n".join(lines)
	round_label.text = "지휘 명령: %d / %d" % [_commands.size(), _Balance.WAR_ROUNDS]
	execute_button.disabled = (
		_commands.size() < _Balance.WAR_ROUNDS or target == null or not GameManager.can_wage_war()
	)


func _add_command(command: SectWarManager.Command) -> void:
	if _commands.size() >= _Balance.WAR_ROUNDS:
		log_label.text = "이미 %d개 명령을 골랐습니다. 초기화 후 다시 고르세요." % _Balance.WAR_ROUNDS
		return
	_commands.append(command)
	log_label.text = "%d라운드: %s" % [_commands.size(), SectWarManager.COMMAND_NAMES[command]]
	_update_display()


func _on_target_selected(_index: int) -> void:
	_fill_generals()
	_update_display()


func _on_option_changed(_index: int) -> void:
	_update_display()


func _on_scout_pressed() -> void:
	var target: SectData = _get_target()
	if target == null:
		return
	AudioManager.play_click()
	var result: Dictionary = GameManager.scout_war(target.id)
	log_label.text = result["message"]
	_update_display()


func _on_charge_pressed() -> void:
	_add_command(SectWarManager.Command.CHARGE)


func _on_defend_pressed() -> void:
	_add_command(SectWarManager.Command.DEFEND)


func _on_flank_pressed() -> void:
	_add_command(SectWarManager.Command.FLANK)


func _on_retreat_pressed() -> void:
	_add_command(SectWarManager.Command.RETREAT)


func _on_reset_pressed() -> void:
	_commands.clear()
	log_label.text = "명령을 초기화했습니다."
	_update_display()


func _on_execute_pressed() -> void:
	var target: SectData = _get_target()
	if target == null:
		return
	var result: Dictionary = GameManager.resolve_sect_war(
		target.id, _commands, get_selected_formation(), get_selected_general().get("id", "")
	)
	var lines: PackedStringArray = [result["message"], ""]
	lines.append_array(result.get("logs", PackedStringArray()))
	log_label.text = "\n".join(lines)
	if result.get("victory", false):
		AudioManager.play_success()
	else:
		AudioManager.play_failure()
	_commands.clear()
	if result.get("subjugated", false):
		_fill_targets()
	_update_display()


func _on_back_pressed() -> void:
	SceneRouter.goto(get_tree(), SceneRouter.HUB)
