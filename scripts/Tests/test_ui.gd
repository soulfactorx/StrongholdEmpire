extends "res://scripts/Tests/test_base.gd"

## 스모크 테스트 — 저장 슬롯, 설정·연간 보고서·길잡이, 확인 대화상자, 단축키·설명 말풍선
## 실행 순서는 smoke_test.gd의 INIT_SEQUENCE·RUNTIME_SEQUENCE가 정한다.


func _test_save_slots() -> void:
	var gm: Node = root.get_node("GameManager")
	_clear_test_saves()
	_check(not gm.has_save_file(), "테스트 세이브 폴더는 비어서 시작")

	# 슬롯마다 따로 저장·불러오기
	gm.start_new_game("하나", "leader", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	gm.player_sect.gold = 111
	_check(gm.save_game(1)["success"] and gm.has_save_file(1) and not gm.has_save_file(2), "슬롯 1 저장")
	gm.start_new_game("둘", "wanderer", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	gm.player_sect.gold = 222
	gm.save_game(2)
	_check(not gm.save_game(9)["success"], "없는 슬롯 거부")
	_check(gm.load_game(1)["success"] and gm.player_character.display_name == "하나" and gm.player_sect.gold == 111, "슬롯 1 불러오기")
	_check(gm.load_game(2)["success"] and gm.player_character.display_name == "둘" and gm.player_sect.gold == 222, "슬롯 2 불러오기")
	_check(not gm.load_game(3)["success"], "빈 슬롯은 불러올 수 없음")
	var summary: Dictionary = SaveManager.get_slot_summary(2)
	_check(summary["exists"] and summary["detail"].contains("둘") and summary["detail"].contains("낭인") and summary["title"].contains("천하대란"), "슬롯 요약: 날짜·인물·역할·시나리오")
	_check(not SaveManager.get_slot_summary(3)["exists"], "빈 슬롯 요약")

	# 계절이 바뀔 때마다 자동 저장
	gm.start_new_game("자동", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	SaveManager.delete_save(SaveManager.AUTO_SLOT)
	gm.advance_turn()
	_check(gm.has_save_file(SaveManager.AUTO_SLOT), "계절 진행 시 자동 저장")
	var date: String = gm.get_date_text()
	gm.advance_turn()
	gm.load_game(SaveManager.AUTO_SLOT)
	_check(gm.get_date_text() != date and gm.player_character.display_name == "자동", "자동 저장은 가장 최근 계절")

	# 철인 모드: 수동 저장 불가, 자동 저장만
	gm.start_new_game("철인", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0}, true)
	_check(gm.ironman and not gm.save_game(3)["success"] and not gm.has_save_file(3), "철인 모드: 수동 저장 불가")
	gm.advance_turn()
	gm.start_new_game("다른 판", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	_check(not gm.ironman, "새 게임 기본은 철인 모드 아님")
	gm.load_game(SaveManager.AUTO_SLOT)
	_check(gm.ironman and gm.player_character.display_name == "철인", "철인 모드는 세이브에 남음")
	_check(SaveManager.get_slot_summary(SaveManager.AUTO_SLOT)["detail"].contains("철인"), "슬롯 요약에 철인 모드 표시")

	# 마이그레이션: 오래된 세이브는 버전마다 생긴 항목을 기본값으로 채운다
	var old: Dictionary = {"version": 3, "current_year": 2, "character": {"display_name": "옛사람"}, "sect": {"gold": 300}}
	var migrated: Dictionary = SaveManager.migrate(old.duplicate(true))
	_check(migrated["version"] == SaveManager.SAVE_VERSION, "마이그레이션: 현재 버전으로")
	var filled: bool = true
	for step in SaveManager.MIGRATIONS:
		for key in SaveManager.MIGRATIONS[step]:
			filled = filled and migrated.has(key)
	_check(filled and migrated["scenario_id"] == "cheonha" and migrated["world_news"] is Array, "마이그레이션: 버전별 항목 기본값")
	var newer: Dictionary = SaveManager.migrate({"version": 9, "role_state": {"bounty": 7}})
	_check(newer["role_state"]["bounty"] == 7 and not newer.has("flag_turns"), "마이그레이션: 이미 있는 항목·이전 버전 항목은 건드리지 않음")
	var file := FileAccess.open(SaveManager.get_slot_path(3), FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file = null
	_check(gm.load_game(3)["success"] and gm.player_character.display_name == "옛사람" and gm.current_year == 2, "버전 3 세이브 불러오기")
	_check(gm.player_sect.use_roster and gm.player_sect.disciples.size() == gm.player_sect.disciple_count, "옛 세이브도 제자 명단을 갖춤")
	file = FileAccess.open(SaveManager.get_slot_path(3), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": SaveManager.SAVE_VERSION + 1}))
	file = null
	_check(not gm.load_game(3)["success"], "더 새 버전의 세이브는 거부")
	file = FileAccess.open(SaveManager.get_slot_path(3), FileAccess.WRITE)
	file.store_string("{망가진")
	file = null
	_check(not gm.load_game(3)["success"] and SaveManager.get_slot_summary(3)["detail"].contains("손상"), "손상된 세이브 처리")
	_clear_test_saves()
	_completed["_test_save_slots"] = true


func _test_save_screens() -> void:
	var gm: Node = root.get_node("GameManager")
	_clear_test_saves()
	gm.start_new_game("화면", "leader", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0})
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	hub._on_save_pressed()
	_check(hub.save_popup.visible and hub.save_popup.get_option_count() == SaveManager.SLOT_COUNT, "저장 팝업: 슬롯 %d개" % SaveManager.SLOT_COUNT)
	hub.save_popup._on_option_pressed("2")
	_check(gm.has_save_file(2) and hub.log_label.text.contains("슬롯 2"), "화면에서 슬롯 2에 저장")
	hub.go_main_menu()
	await process_frame
	await process_frame
	_check(gm.has_save_file(SaveManager.AUTO_SLOT), "메인 메뉴로 나갈 때 자동 저장")
	var menu: Node = current_scene
	menu._on_load_pressed()
	var rows: Array = menu.load_popup._rows.get_children()
	_check(rows.size() == SaveManager.SLOT_COUNT + 1 and rows[3].disabled and not rows[2].disabled, "불러오기 팝업: 자동 + 슬롯, 빈 슬롯은 비활성")
	gm.start_new_game("다른", "young_disciple")
	menu.load_popup._on_option_pressed("2")
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.HUB and gm.player_character.display_name == "화면", "메인 메뉴에서 슬롯 2 불러오기")
	SceneRouter.goto(tree, SceneRouter.NEW_GAME)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	# 소속 문파: 고를 수 있고, 낭인은 무소속
	for i in screen._scenarios.size():
		if screen._scenarios[i].get("id") == ScenarioManager.DEFAULT_ID:
			screen._on_scenario_selected(i)
	screen._on_role_selected(screen._role_ids.find("young_disciple"))
	_check(not screen.sect_option.disabled and screen.sect_option.item_count > 1, "새 게임: 소속 문파를 고를 수 있음")
	screen.set_player_sect("namgung")
	_check(screen.get_faction_setup().get("player_sect") == "namgung", "새 게임: 고른 문파가 세력 설정에 담김")
	# 시작 인연: 처음엔 문파 기준, 직접 바꾸면 세력 설정에 담긴다
	_check(screen.get_bond_setup().get("npc_namgung_lord") == "MASTER_DISCIPLE" and not screen.get_faction_setup().has("bonds"), "새 게임: 시작 인연은 고른 문파 기준")
	screen.set_start_bond("npc_swallow", "SPOUSE")
	_check(screen.get_faction_setup().get("bonds", {}).get("npc_swallow") == "SPOUSE", "새 게임: 직접 정한 인연이 담김")
	screen._apply_bond_preset("clear")
	_check(screen.get_faction_setup().get("bonds", {}).is_empty() and screen.get_faction_setup().has("bonds"), "새 게임: 인연 모두 비우기")
	var wanderer_index: int = screen._role_ids.find("wanderer")
	if wanderer_index >= 0:
		screen._on_role_selected(wanderer_index)
		_check(screen.sect_option.disabled and screen.get_player_sect_choice().is_empty(), "새 게임: 낭인은 무소속")
		_check(screen.get_bond_setup().is_empty(), "새 게임: 낭인은 시작 인연 없음")
		screen._on_role_selected(screen._role_ids.find("young_disciple"))
	screen.ironman_check.button_pressed = true
	screen._on_start_pressed()
	await process_frame
	_check(gm.ironman, "새 게임 화면: 철인 모드 선택")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_clear_test_saves()
	_completed["_test_save_screens"] = true


func _test_settings_and_reports() -> void:
	var gm: Node = root.get_node("GameManager")

	# 설정: 저장·불러오기·적용
	GameSettings.set_and_save("sfx_volume", 0.5, tree)
	GameSettings.set_and_save("music_volume", 0.3, tree)
	GameSettings.set_and_save("text_scale", 1.3, tree)
	GameSettings.sfx_volume = 0.0
	GameSettings.music_volume = 1.0
	GameSettings.text_scale = 1.0
	GameSettings.load_settings()
	_check(
		is_equal_approx(GameSettings.sfx_volume, 0.5) and is_equal_approx(GameSettings.music_volume, 0.3)
		and is_equal_approx(GameSettings.text_scale, 1.3),
		"설정 저장·불러오기"
	)
	GameSettings.apply(tree)
	var sfx_bus: int = GameSettings.bus_index(GameSettings.SFX_BUS)
	var music_bus: int = GameSettings.bus_index(GameSettings.MUSIC_BUS)
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(sfx_bus)), 0.5), "효과음 음량 적용")
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)), 0.3), "배경음악 음량 적용 (따로)")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), 0.0), "Master 음량은 그대로")
	_check(root.theme != null and root.theme.default_font_size == roundi(16 * 1.3), "글자 크기: 화면 기본 글자 크기")
	_check(UiTheme.font_size(13) == roundi(UiTheme.MIN_FONT_SIZE * 1.3), "작은 글자도 최소 크기와 배율 적용")
	var label := Label.new()
	UiTheme.set_font_size(label, 20)
	var panel := PanelContainer.new()
	panel.add_child(label)
	UiTheme.apply_to_control(panel)
	UiTheme.apply_to_control(panel)
	_check(label.get_theme_font_size("font_size") == roundi(20 * 1.3), "글자 배율은 두 번 곱해지지 않음")
	panel.free()
	var config := ConfigFile.new()
	config.set_value("display", "text_scale", 7.0)
	config.save(GameSettings.settings_path)
	GameSettings.load_settings()
	_check(is_equal_approx(GameSettings.text_scale, 1.0), "잘못된 글자 배율은 보통으로")
	GameSettings.set_and_save("sfx_volume", 0.8, tree)
	GameSettings.set_and_save("text_scale", 1.0, tree)
	# 불러오기로 기본값(0.3)이 된 전투 간격을 다시 시험용 0으로
	GameSettings.combat_delay = 0.0
	GameSettings.action_preview = false
	GameSettings.faction_report = false
	_check(ProjectSettings.get_setting("display/window/stretch/aspect") == "expand", "화면 비율: 넓은 화면은 보이는 영역을 넓힘")

	# 연간 보고서
	_new_quiet_game(gm, "leader")
	var gold: int = gm.player_sect.gold
	for i in 3:
		gm.advance_turn()
	_check(gm.pending_year_report.is_empty(), "해가 바뀌기 전에는 연간 보고서 없음")
	gm.advance_turn()
	var report: Dictionary = gm.pending_year_report
	_check(report.get("title", "").contains("1년 결산"), "해가 바뀌면 지난해 결산")
	_check(report["lines"][0] == "금화: %d → %d (%+d)" % [gold, gm.player_sect.gold, gm.player_sect.gold - gold], "결산: 금화 변화")
	_check(gm.year_start["year"] == 2, "결산 뒤 새해 기준 기록")

	# 길잡이: 첫 단계는 바로, 나머지는 계절마다 (기연 빈도와 관계없이)
	gm.start_new_game("길잡이", "young_disciple", ScenarioManager.DEFAULT_ID, {"event_rate": 0.0}, false, true)
	var steps: PackedStringArray = []
	var research: int = gm.player_sect.research_points
	for i in 6:
		if not gm.pending_event.is_empty():
			steps.append(gm.pending_event["id"])
			gm.resolve_pending_event(1 if gm.pending_event["id"] == "tutorial_3_combat" else 0)
		gm.advance_turn()
	_check(steps == PackedStringArray(["tutorial_1_hub", "tutorial_2_events", "tutorial_3_combat", "tutorial_4_martial_art"]), "길잡이 4단계가 차례로 %s" % steps)
	_check(gm.story_flags.get("tutorial_done", false) and gm.player_sect.research_points >= research + 20, "길잡이 끝: 연구점 선물")
	_new_quiet_game(gm, "young_disciple")
	_check(gm.pending_event.is_empty(), "길잡이를 끄면 안내 기연 없음")
	_completed["_test_settings_and_reports"] = true


func _test_ui_flows() -> void:
	var gm: Node = root.get_node("GameManager")
	_clear_test_saves()
	_new_quiet_game(gm, "leader")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene

	# 설정 팝업
	hub._on_options_pressed()
	_check(hub.options_popup.visible, "경영 화면: 설정 팝업")
	hub.options_popup.volume_slider.value = 40
	_check(is_equal_approx(GameSettings.sfx_volume, 0.4), "설정: 음량 조절")
	hub.options_popup.volume_slider.value = 80
	hub.options_popup.music_slider.value = 20
	_check(is_equal_approx(GameSettings.music_volume, 0.2), "설정: 배경음악 음량 조절")
	hub.options_popup.music_slider.value = 60
	hub.options_popup.visible = false

	# 연간 보고서 팝업
	for i in 4:
		hub._on_advance_turn_pressed()
	await process_frame
	_check(hub.report_popup.visible and gm.pending_year_report.is_empty(), "해가 바뀌면 연간 보고서 팝업")
	hub.report_popup._answer(true)

	# 메인 메뉴로: 확인 후 이동
	hub._on_main_menu_pressed()
	await process_frame
	_check(hub.confirm_popup.visible and current_scene == hub, "메인 메뉴로 나가기 전 확인")
	hub.confirm_popup._answer(false)
	_check(not hub.confirm_popup.visible and current_scene == hub, "아니오: 머무름")
	hub._on_main_menu_pressed()
	hub.confirm_popup._answer(true)
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.MAIN_MENU and gm.has_save_file(SaveManager.AUTO_SLOT), "예: 자동 저장 후 메인 메뉴")

	# 진행 중인 판이 있으면 새 게임 전에 확인
	var menu: Node = current_scene
	menu._on_new_game_pressed()
	_check(menu.confirm_popup.visible and current_scene == menu, "새 게임 전 확인")
	menu.confirm_popup._answer(true)
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == SceneRouter.NEW_GAME, "확인하면 새 게임 화면")
	_check(current_scene.tutorial_check.button_pressed, "새 게임 화면: 길잡이는 기본으로 켜짐")

	# 전투 후퇴는 확인 후
	_new_quiet_game(gm, "leader")
	gm.start_combat(CombatManager.create_sparring(gm.player_character))
	await process_frame
	await process_frame
	var controller: Node = current_scene
	controller._on_back_pressed()
	_check(controller.confirm_popup.visible and gm.pending_combat != null, "후퇴 전 확인")
	controller.confirm_popup._answer(false)
	_check(gm.pending_combat != null, "계속 싸운다: 전투 유지")
	controller._on_back_pressed()
	controller.confirm_popup._answer(true)
	await process_frame
	await process_frame
	_check(gm.pending_combat == null and current_scene.scene_file_path == SceneRouter.HUB, "후퇴: 전투를 끝내고 경영 화면으로")
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_clear_test_saves()
	_completed["_test_ui_flows"] = true


## 경영 행동 미리보기: 수치 변화를 보여 주고, 취소하면 아무것도 바뀌지 않는다.
func _test_action_preview() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "leader")
	gm.player_sect.gold = 500
	gm.player_sect.food = 300
	var character: CharacterData = gm.player_character
	var strength: int = character.strength
	var disciples: int = gm.player_sect.disciple_count
	var news: int = gm.world_news.size()

	# 시뮬레이션 뒤 상태는 그대로
	var train := func() -> Dictionary: return SectManager.train_disciples(gm.player_sect, gm.player_character)
	var preview: Dictionary = ActionPreview.simulate_action(gm, train)
	_check(gm.player_sect.gold == 500 and character.strength == strength and gm.player_sect.disciple_count == disciples, "미리보기: 돌려 본 뒤 상태 되돌림")
	_check(gm.player_sect.disciples.size() == disciples, "미리보기: 제자 명단도 되돌림")
	var text: String = ActionPreview.format(preview)
	_check(text.contains("금화  500 → %d (-%d)" % [500 - GameBalance.TRAIN_GOLD, GameBalance.TRAIN_GOLD]), "미리보기: 금화 변화량")
	_check(text.contains("무력") and text.contains("제자 수") and not text.contains("운에 따라"), "미리보기: 능력치·제자 수, 운 없음")
	_check(not preview["random"] and gm.player_sect.disciples.size() == disciples, "운이 끼지 않는 행동: 결과 하나")

	# 운이 끼는 역할 행동 (막내 제자의 외출: 금화 또는 경험치) — 범위·확률
	_new_quiet_game(gm, "young_disciple")
	var gold: int = gm.player_sect.gold
	# 기연이 걸려 있으면 외출에서 새 기연을 찾지 않는다 (금화·경험치 둘 중 하나만)
	gm.pending_event = {"id": "dummy"}
	var outing := func() -> Dictionary: return RoleActions.perform(gm, "outing", "")
	preview = ActionPreview.simulate_action(gm, outing)
	text = ActionPreview.format(preview)
	_check(gm.player_sect.gold == gold and RoleActions.can_act(gm.role_state, gm._get_turn_index()), "역할 행동 미리보기 뒤 금화·행동 횟수 그대로")
	_check(preview["random"] and text.contains("운에 따라") and text.contains("금화") and text.contains("경험치"), "운이 끼는 행동: 범위와 결과별 확률")
	gm.pending_event = {}

	# 경영 화면: 켜 두면 확인창, 취소하면 그대로, 실행하면 적용
	_new_quiet_game(gm, "leader")
	gm.player_sect.gold = 500
	GameSettings.action_preview = true
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	hub._on_feast_pressed()
	var popup: Control = ActionPreview.get_popup(hub)
	_check(popup.visible and popup._message.text.contains("명성") and gm.player_sect.gold == 500, "연회 미리보기: 확인창, 아직 그대로")
	# 맨 위 층(CanvasLayer)의 확인창·말풍선도 한글 본문 글꼴 (엔진 기본 글꼴이면 휴대폰·웹에서 글자가 깨진다)
	var bubble_label: Label = LongPressTip._get_bubble(hub).get_child(0)
	_check(popup._message.get_theme_font("font") == ArtAssets.body_font() and bubble_label.get_theme_font("font") == ArtAssets.body_font(), "미리보기·말풍선 글꼴은 본문 글꼴")
	_check(ThemeDB.fallback_font == ArtAssets.body_font(), "엔진 기본 글꼴도 한글 글꼴")
	popup._answer(false)
	_check(gm.player_sect.gold == 500 and gm.can_do_seasonal("last_feast_turn"), "취소: 아무것도 바뀌지 않음")
	hub._on_feast_pressed()
	popup._answer(true)
	_check(gm.player_sect.gold == 500 - GameBalance.FEAST_GOLD and not gm.can_do_seasonal("last_feast_turn"), "실행: 미리 본 대로 적용")
	# 이미 한 행동(모두 실패)은 확인 없이 까닭만 알린다.
	hub._on_feast_pressed()
	_check(not popup.visible, "할 수 없는 행동은 미리보기 없이 안내")
	var date: String = gm.get_date_text()
	hub._on_advance_turn_pressed()
	_check(popup.visible and popup._message.text.contains("금화") and gm.get_date_text() == date, "계절 넘기기 미리보기: 예상 수입·유지비")
	popup._answer(false)
	_check(gm.get_date_text() == date and gm.world_news.size() >= news, "계절 넘기기 취소")
	# 웹: 새 버전이 배포되면 알림 창 (설치형 앱의 옛 파일 보관 때문에 안 바뀌는 문제)
	gm._on_web_update_available()
	_check(popup.visible and popup._message.text.contains("새로 배포") and popup._message.text.contains("자동 저장"), "웹 새 버전 알림")
	popup._answer(false)
	GameSettings.action_preview = false
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_action_preview"] = true


## 강호 연대기와 인물 대사: 기연 선택·대화·외교·역할 행동이 기록되고, 저장·불러오기 뒤에도 남는다.
func _test_chronicle_and_dialogue() -> void:
	var gm: Node = root.get_node("GameManager")
	_clear_test_saves()
	_new_quiet_game(gm, "leader")
	_check(gm.chronicle.size() == 1 and gm.chronicle[0]["kind"] == "시작", "연대기: 시작 기록")

	# 대화: 주인공과 상대의 대사, 인물 JSON의 고유 대사
	var result: Dictionary = gm.interact_with("npc_master", "talk")
	var lines: PackedStringArray = result.get("dialogue", PackedStringArray())
	var own: Array = NpcRoster.get_npc("npc_master")["dialogue"]["talk"]
	var master_rel: RelationshipData = RelationshipManager.get_bond_with(gm.player_relationships, "npc_master")
	var stage_replies: Array = DialogueLines.get_talk_data()["types"]["MASTER_DISCIPLE"]["stages"][DialogueLines.talk_stage(master_rel)]["reply"]
	_check(lines.size() >= 2 and lines.size() <= 3 and lines[0].begins_with(gm.player_character.display_name + ":"), "대화: 주인공 대사")
	var reply: String = lines[1].trim_prefix("청운검선: ")
	_check(lines[1].begins_with("청운검선:") and (own.has(reply) or stage_replies.has(reply)), "대화: 인물 고유 대사나 유대 단계에 맞는 답")
	_check(gm.chronicle[-1]["kind"] == "대화" and Array(gm.chronicle[-1]["lines"]) == Array(lines), "연대기: 대화와 오간 대사")
	# 고유 대사가 없는 관계는 관계 유형에 맞는 기본 대사
	var rel := RelationshipData.new()
	rel.target_id = "npc_unknown"
	rel.target_name = "무명객"
	rel.bond_type = RelationshipData.BondType.BLOOD_OATH
	var default_lines: PackedStringArray = DialogueLines.for_interaction(rel, "gift", "나", true)
	_check(default_lines.size() == 2 and default_lines[1].begins_with("무명객:"), "기본 대사")
	# 담소는 관계 유형과 유대 단계(0~4)에 따라 달라진다
	_check(DialogueLines.validate_talk_data(DialogueLines.get_talk_data()).is_empty(), "대화 대사 데이터: 모든 관계 유형에 5단계")
	var talk_data: Dictionary = DialogueLines.get_talk_data()["types"]
	var stage_ok: bool = true
	for type_key in RelationshipData.BondType.keys():
		for stage in DialogueLines.TALK_STAGES:
			var probe := RelationshipData.new()
			probe.target_id = "npc_unknown"
			probe.target_name = "무명객"
			probe.bond_type = RelationshipData.BondType.get(type_key)
			probe.bond_strength = stage * 20 + 5
			var talk: PackedStringArray = DialogueLines.for_talk(probe, "나")
			var step: Dictionary = talk_data[type_key]["stages"][stage]
			stage_ok = stage_ok and step["player"].has(talk[0].trim_prefix("나: ")) and step["reply"].has(talk[1].trim_prefix("무명객: "))
	_check(stage_ok, "대화: 모든 관계·단계에서 그 단계의 말과 답")
	var stranger := RelationshipData.new()
	stranger.target_id = "npc_unknown"
	stranger.target_name = "무명객"
	stranger.bond_type = RelationshipData.BondType.ROMANCE
	stranger.bond_strength = 5
	var shy: String = DialogueLines.for_talk(stranger, "나")[1]
	stranger.bond_strength = 95
	var deep: String = DialogueLines.for_talk(stranger, "나")[1]
	_check(talk_data["ROMANCE"]["stages"][0]["reply"].has(shy.trim_prefix("무명객: ")) and talk_data["ROMANCE"]["stages"][4]["reply"].has(deep.trim_prefix("무명객: ")), "연인: 유대 5와 95의 답이 다름")
	_check(not DialogueLines.validate({"talk": ["좋소"]}).size() and DialogueLines.validate({"shout": ["!"]}).size() == 1 and DialogueLines.validate({"talk": [1]}).size() == 1, "인물 대사 형식 검사")

	# 외교: 사절과 문주의 대사
	result = gm.do_diplomacy("namgung", "envoy")
	_check(result["success"] and result["dialogue"].size() == 2 and gm.chronicle[-1]["kind"] == "외교", "외교: 사절·문주 대사와 연대기")

	# 역할 행동: 문파 회의
	result = gm.do_role_action("council")
	_check(result["dialogue"].size() == 2 and gm.chronicle[-1]["kind"] == "행동", "역할 행동: 대사와 연대기")

	# 기연: 상황·선택·결과
	var event: EventData = EventManager.get_definitions()[0]
	gm.pending_event = event.to_popup_dict()
	gm.resolve_pending_event(0)
	var entry: Dictionary = gm.chronicle[-1]
	_check(entry["kind"] == "기연" and entry["text"].contains(event.title) and Array(entry["lines"]).any(func(line: String) -> bool: return line.begins_with("▶ 선택: ")), "연대기: 기연 제목과 고른 선택지")

	# 저장·불러오기 뒤에도 남는다
	var count: int = gm.chronicle.size()
	gm.save_game(1)
	_new_quiet_game(gm, "leader")
	gm.load_game(1)
	_check(gm.chronicle.size() == count and gm.chronicle[1]["kind"] == "대화", "연대기 저장·불러오기")

	# 경영 화면의 연대기 창: 갈래별로 골라 보기
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	hub._on_chronicle_pressed()
	var popup: Control = hub.chronicle_popup
	_check(popup.visible and popup.get_entry_count() == count, "연대기 창: 모든 기록")
	popup.set_filter(2)
	_check(popup.get_entry_count() == 3, "연대기 창: 대화·외교·행동만")
	popup.set_filter(3)
	_check(popup.get_entry_count() == 1, "연대기 창: 기록이 없으면 안내 한 줄")
	popup.visible = false
	# 인연 창: 방금 오간 대사
	hub.bond_popup.open()
	hub.bond_popup._interact("npc_master", "gift")
	_check(hub.bond_popup.dialogue_label.visible and hub.bond_popup.dialogue_label.text.contains("청운검선:"), "인연 창: 오간 대사 표시")
	hub.bond_popup.visible = false
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_clear_test_saves()
	_completed["_test_chronicle_and_dialogue"] = true


## 역할별 경영 화면: 시작 역할이 7가지이고, 역할마다 보이는 버튼·칸·안내가 다르다.
func _test_role_dashboard() -> void:
	var gm: Node = root.get_node("GameManager")
	_check(StartingRoles.ROLES.size() >= 7, "시작 역할 7가지")
	# 계절 넘기기 안내의 "아직 하지 않은 일"은 역할에 맞게
	_new_quiet_game(gm, "young_disciple")
	var unused: String = ", ".join(RoleDashboard.get_unused_actions(gm))
	_check(unused.contains("고유 행동(스승에게 가르침·외출)") and unused.contains("영약") and not unused.contains("연회") and not unused.contains("문파전") and not unused.contains("평정"), "막내 제자의 남은 일: %s" % unused)
	_new_quiet_game(gm, "leader")
	unused = ", ".join(RoleDashboard.get_unused_actions(gm))
	_check(unused.contains("문파 연회") and unused.contains("문파전") and unused.contains("땅 평정") and unused.contains("인연 돌보기"), "문주의 남은 일: %s" % unused)
	gm.hold_feast()
	_check(not ", ".join(RoleDashboard.get_unused_actions(gm)).contains("연회"), "이미 한 일은 빠짐")
	_new_quiet_game(gm, "spy")
	_check(gm.player_character.role == CharacterData.Role.SPY and gm.story_flags.get("spy_recruitment", false), "간자로 시작: 포섭 플래그")
	_new_quiet_game(gm, "assassin")
	_check(gm.player_character.role == CharacterData.Role.ASSASSIN and gm.story_flags.get("assassin_path", false), "자객으로 시작")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	var grid: Node = hub.action_grid
	_check(not grid.get_node("TrainButton").visible and not grid.get_node("SectWarButton").visible and grid.get_node("ElixirButton").visible, "자객: 문파 운영 버튼 숨김")
	_check(not hub.get_node("Margin/RootHBox/LeftPanel/FacilityPanel").visible and hub.sect_name_label.text.contains("내 재산") and hub.gold_label.text.begins_with("내 금화"), "자객: 시설 칸 숨김, 개인 재산")
	_check(hub.role_resource_label.text.contains("표적") and hub.role_action_box.get_child_count() == 2, "자객: 역할 안내와 고유 행동")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	hub._unhandled_key_input(key)
	_check(not hub.facility_popup.visible, "숨긴 버튼은 단축키로도 열리지 않음")
	# 역할이 바뀌면 화면도 바뀐다
	gm.apply_role_transition(CharacterData.Role.LEADER)
	await process_frame
	_check(grid.get_node("TrainButton").visible and grid.get_node("SectWarButton").visible and hub.get_node("Margin/RootHBox/LeftPanel/FacilityPanel").visible, "문주가 되면 모든 버튼")
	hub._unhandled_key_input(key)
	_check(hub.facility_popup.visible, "문주: 시설 단축키")
	hub.facility_popup.visible = false
	_check(RoleDashboard.describe_role(CharacterData.Role.MANAGER).contains("문주에게 건의"), "새 게임 화면 역할 소개: 고유 행동")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_role_dashboard"] = true


## 세로(휴대폰) 배치: 경영 화면은 탭과 할 일 목록, 두 칸 화면은 위아래로, 팝업 줄은 버튼을 아래로, 전투는 격자를 줄여 위에
func _test_portrait_layout() -> void:
	var gm: Node = root.get_node("GameManager")
	_check(not LayoutMode.decide(LayoutMode.Mode.AUTO) and LayoutMode.decide(LayoutMode.Mode.PORTRAIT) and not LayoutMode.decide(LayoutMode.Mode.LANDSCAPE), "화면 배치: PC 자동은 가로, 세로 지정")
	GameSettings.set_and_save("layout_mode", LayoutMode.Mode.PORTRAIT, tree)
	_check(LayoutMode.is_portrait() and root.content_scale_size == LayoutMode.PORTRAIT_SIZE, "세로: 기준 크기 720×1280")
	_new_quiet_game(gm, "leader")
	gm.player_sect.gold = 500
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	_check(hub.pages.size() == 5 and hub.get_current_page() == "todo" and not hub.get_node("Margin/RootHBox").visible, "세로 경영 화면: 쪽 5개, 처음은 할 일")
	var steps: Array = hub.todo_box.get_children().filter(func(c: Node) -> bool: return c is Button)
	_check(steps.size() == RoleDashboard.get_season_steps(gm).size() - 1, "할 일 목록: 단계마다 버튼 (고유 행동은 역할 칸)")
	var elixir_step: Button = hub.todo_box.get_node("Step_elixir")
	var energy: int = gm.player_character.internal_energy_max
	elixir_step.pressed.emit()
	await process_frame
	_check(gm.player_character.internal_energy_max > energy and not hub.todo_box.has_node("Step_elixir"), "할 일 버튼으로 바로 실행, 한 일은 목록에서 빠짐")
	_check(hub.status_label.text.contains("금화") and hub.status_label.text.contains("제자"), "맨 위 자원 한 줄")
	hub.show_page("sect")
	_check(hub.pages["sect"].visible and not hub.pages["todo"].visible and hub._action_buttons["TrainButton"].is_visible_in_tree(), "탭: 문파 쪽에 문파 운영 버튼")
	root.get_node("EventBus").action_message.emit("토스트 시험")
	_check(Toast.get_text(hub) == "토스트 시험", "세로: 다른 탭에서도 안내 메시지가 토스트로 보임")
	hub.show_page("world")
	_check(hub._action_buttons["MapButton"].is_visible_in_tree() and hub.world_report_label.text.contains("강호 동향"), "탭: 강호 쪽에 지도·동향")
	_check(hub._action_buttons["AdvanceTurnButton"].custom_minimum_size.y >= 60, "계절 넘기기는 크게, 늘 보임")
	# 기연 창: 세로에서는 초상화를 위에, 글을 아래에 (옆에 두면 화면 밖으로 잘린다)
	hub.event_popup.show_event(EventManager.get_definitions()[0].to_popup_dict())
	_check(hub.event_popup.title_label.get_parent().get_parent() is VBoxContainer and hub.event_popup.portrait.custom_minimum_size.x < 192, "세로 기연 창: 초상화 위, 글 아래")
	hub.event_popup.visible = false
	# 역할에 따라 버튼 숨김은 세로에서도 그대로
	gm.apply_role_transition(CharacterData.Role.WANDERER)
	await process_frame
	_check(not hub._action_buttons["TrainButton"].visible and not hub.facility_panel.visible, "세로에서도 역할별 버튼 숨김")
	# 팝업: 화면 폭에 맞고, 줄은 이름표 아래에 버튼
	hub._on_bond_pressed()
	var row: Node = hub.bond_popup._rows.get_child(0)
	_check(row is VBoxContainer and row.get_child(1) is HFlowContainer, "세로 팝업 줄: 이름표 아래에 버튼 줄바꿈")
	hub.bond_popup.visible = false
	# 두 칸 화면은 위아래로
	SceneRouter.goto(tree, SceneRouter.WORLD)
	await process_frame
	await process_frame
	_check(current_scene.get_node("Margin/VBox/HBox") is VBoxContainer, "강호 정세: 위아래로")
	SceneRouter.goto(tree, SceneRouter.NEW_GAME)
	await process_frame
	await process_frame
	_check(current_scene.get_node("Margin/VBox/Columns") is VBoxContainer, "새 게임: 위아래로")
	SceneRouter.goto(tree, SceneRouter.MARTIAL_ART)
	await process_frame
	await process_frame
	_check(current_scene.get_node("Margin/RootHBoxScroll/RootHBox") is VBoxContainer and current_scene.known_arts_label != null, "무공 연구소: 위아래로 쌓고 스크롤")
	current_scene._on_save_blueprint_pressed()
	_check(not Toast.get_text(current_scene).is_empty(), "무공 연구소: 결과가 토스트로 보임")
	# 전투: 손패는 두 줄, 화면 폭을 넘지 않는다
	gm.start_combat(CombatManager.create_sparring(gm.player_character))
	await process_frame
	await process_frame
	var c: Node = current_scene
	_check(c.hand_grid.columns == 2, "세로 대결: 손패 두 줄")
	_check(c.hand_grid.get_combined_minimum_size().x <= LayoutMode.PORTRAIT_SIZE.x and c.slot_row.get_combined_minimum_size().x <= LayoutMode.PORTRAIT_SIZE.x, "세로 대결: 칸·손패가 화면 폭 안")
	c.leave_combat()
	await process_frame
	await process_frame
	GameSettings.set_and_save("layout_mode", LayoutMode.Mode.AUTO, tree)
	_check(not LayoutMode.is_portrait() and root.content_scale_size == LayoutMode.LANDSCAPE_SIZE, "자동으로 돌리면 가로")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_completed["_test_portrait_layout"] = true


func _test_input_and_tips() -> void:
	var gm: Node = root.get_node("GameManager")
	_clear_test_saves()
	_new_quiet_game(gm, "leader")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene

	# 길게 눌러 설명
	var gold_tip: LongPressTip = hub.tips["gold"]
	_check(hub.gold_label.mouse_filter == Control.MOUSE_FILTER_STOP, "설명이 붙은 라벨은 누를 수 있음")
	hub.gold_label.gui_input.emit(_mouse(true))
	hub.gold_label.gui_input.emit(_mouse(false))
	await create_timer(LongPressTip.HOLD_TIME + 0.15).timeout
	_check(not LongPressTip.is_bubble_visible(hub.gold_label), "짧게 누르면 설명이 뜨지 않음")
	hub.gold_label.gui_input.emit(_mouse(true))
	await create_timer(LongPressTip.HOLD_TIME + 0.15).timeout
	_check(LongPressTip.is_bubble_visible(hub.gold_label), "길게 누르면 설명")
	var bubble_text: String = hub.get_node("TipLayer/Bubble").get_child(0).text
	_check(bubble_text.contains("유지비") and bubble_text.contains("제자 12명"), "금화 설명: 수입·유지비 계산 근거")
	gold_tip._input(_mouse(true))
	_check(not LongPressTip.is_bubble_visible(hub.gold_label), "다시 누르면 설명이 닫힘")
	for key in ["food", "reputation", "research", "stats", "facilities"]:
		hub.tips[key].show_now()
		_check(LongPressTip.is_bubble_visible(hub.gold_label) and not hub.get_node("TipLayer/Bubble").get_child(0).text.is_empty(), "설명: %s" % key)
		LongPressTip.hide_bubble(hub.gold_label)

	# 버튼 설명: 길게 누르면 설명이 뜨고, 손을 떼도 버튼은 눌리지 않는다
	var feast: Button = hub.find_child("FeastButton", true, false)
	_check(feast.has_meta("help_attached") and ButtonHelp.text_for(feast).contains("명성"), "버튼 설명이 붙음 (문파 연회)")
	var feast_presses: Array = [0]
	var count_press := func() -> void: feast_presses[0] += 1
	feast.pressed.connect(count_press)
	feast.gui_input.emit(_mouse(true))
	await create_timer(LongPressTip.HOLD_TIME + 0.15).timeout
	_check(LongPressTip.is_bubble_visible(feast) and hub.get_node("TipLayer/Bubble").get_child(0).text == ButtonHelp.text_for(feast), "버튼을 길게 누르면 기능 설명")
	_check(not feast.button_pressed and feast_presses[0] == 0, "길게 눌러 설명을 보면 버튼이 실행되지 않음")
	feast.pressed.disconnect(count_press)
	LongPressTip.hide_bubble(feast)
	var unknown := Button.new()
	unknown.text = "설명 없는 버튼"
	_check(ButtonHelp.text_for(unknown).is_empty(), "설명이 없는 버튼은 말풍선을 붙이지 않음")
	unknown.free()

	# 단축키
	hub._unhandled_key_input(_key(KEY_F))
	_check(hub.facility_popup.visible, "F: 시설 관리")
	hub._unhandled_key_input(_key(KEY_D))
	_check(not hub.disciple_popup.visible, "팝업이 열려 있으면 다른 단축키는 무시")
	hub._unhandled_key_input(_key(KEY_ESCAPE))
	_check(not hub.facility_popup.visible, "Esc: 팝업 닫기")
	var date: String = gm.get_date_text()
	hub._unhandled_key_input(_key(KEY_SPACE))
	_check(gm.get_date_text() != date, "Space: 계절 진행")
	hub._unhandled_key_input(_key(KEY_O))
	_check(hub.options_popup.visible and hub.options_popup.speed_option.item_count == GameSettings.COMBAT_DELAYS.size(), "O: 설정 (전투 속도 포함)")
	hub._unhandled_key_input(_key(KEY_ESCAPE))
	hub._unhandled_key_input(_key(KEY_ESCAPE))
	_check(hub.confirm_popup.visible, "팝업이 없을 때 Esc: 메인 메뉴로(확인)")
	hub.confirm_popup._answer(false)

	# 키보드·게임패드 포커스
	hub._on_save_pressed()
	_check(hub.save_popup._rows.get_child(0).has_focus(), "선택 팝업: 첫 항목에 포커스")
	hub.save_popup.visible = false

	# 전투: 단축키와 진행 속도
	gm.player_character.learn_martial_art(MartialArtLibrary.create_art("preset_soul_chase_sword"))
	gm.start_combat(CombatManager.create_sparring(gm.player_character))
	await process_frame
	await process_frame
	var c: Node = current_scene
	c._unhandled_key_input(_key(KEY_A))
	_check(not c.plan.has(null), "A: 자동 배치")
	# 전투 속도: 교전 줄 사이에 간격을 두고, 그동안은 조작할 수 없다
	GameSettings.combat_delay = 0.2
	c._unhandled_key_input(_key(KEY_SPACE))
	_check(c._busy and c.fight_button.disabled and c.engine.bout_total == 1, "Space: 겨루기, 교전이 지나가는 동안 조작 불가")
	var guard: int = 0
	while c._busy and guard < 100:
		guard += 1
		await create_timer(0.1).timeout
	_check(not c._busy and (c.engine.over or not c.fight_button.disabled), "교전이 끝나면 다시 배치")
	GameSettings.combat_delay = 0.0
	c.leave_combat()
	await process_frame
	await process_frame
	gm.start_new_game("정리", "young_disciple")
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_clear_test_saves()
	_completed["_test_input_and_tips"] = true


## 그림 자원: 배경·타일·장기말·UI 텍스처와 글꼴이 모두 불러와지고 화면·전투에 깔린다.
## 데이터 JSON과 스크립트 문자열에 쓰인 문자 중 글꼴에 없는 것 {문자: 파일}
func _missing_glyphs(font: Font) -> Dictionary:
	var missing: Dictionary = {}
	var files: PackedStringArray = []
	_collect_files("res://data", ".json", files)
	_collect_files("res://scripts/UI", ".gd", files)
	_collect_files("res://scripts/Systems", ".gd", files)
	_collect_files("res://scripts/Combat", ".gd", files)
	var quoted := RegEx.new()
	quoted.compile("\"(?:[^\"\\\\]|\\\\.)*\"")
	for path in files:
		var text: String = FileAccess.get_file_as_string(path)
		if path.ends_with(".gd"):
			var strings: PackedStringArray = []
			for line in text.split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				for found in quoted.search_all(line):
					strings.append(found.get_string())
			text = "".join(strings)
		for i in text.length():
			var code: int = text.unicode_at(i)
			if code > 127 and not font.has_char(code):
				missing[String.chr(code)] = path
	return missing


func _collect_files(dir_path: String, extension: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(extension):
			out.append(dir_path.path_join(file))
	for sub in DirAccess.get_directories_at(dir_path):
		_collect_files(dir_path.path_join(sub), extension, out)


func _test_art_assets() -> void:
	var gm: Node = root.get_node("GameManager")
	var names: Dictionary = {}
	for screen in ArtAssets.SCREEN_BACKGROUNDS:
		names[ArtAssets.SCREEN_BACKGROUNDS[screen]] = true
	for bg in names:
		_check(ArtAssets.background(bg) != null, "배경 그림 %s" % bg)
	for tile in ArtAssets.TERRAIN_TILES.values() + ["wall"]:
		_check(ArtAssets.tile(tile) != null, "지형 타일 %s" % tile)
	for token in ["player", "ally", "enemy", "highlight"]:
		_check(ArtAssets.token(token) != null, "장기말 %s" % token)
	for ui in ["panel", "button_normal", "button_hover", "button_pressed", "button_disabled"]:
		var texture: Texture2D = ArtAssets.ui(ui)
		_check(texture != null, "UI 텍스처 %s" % ui)
		# 테두리 바깥 여백은 투명해야 배경 위에 흰 경계가 생기지 않는다 (그림을 바꾸면 tools/art/trim_ui_edges.py)
		if texture:
			var image: Image = texture.get_image()
			if image.is_compressed():
				image.decompress()
			var w: int = image.get_width() - 1
			var h: int = image.get_height() - 1
			var corners_clear: bool = [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h), Vector2i(w / 2, 0), Vector2i(0, h / 2)].all(
				func(p: Vector2i) -> bool: return image.get_pixelv(p).a < 0.05
			)
			_check(corners_clear, "UI 텍스처 %s: 테두리 바깥이 투명 (흰 경계 없음)" % ui)
	_check(ArtAssets.body_font() != null and ArtAssets.brush_font() != null, "본문·붓글씨 글꼴")
	_check(root.theme != null and root.theme.default_font == ArtAssets.body_font(), "창 테마의 기본 글꼴")
	# 글꼴에 없는 문자는 네모로 깨진다: 게임 글(데이터 JSON, 스크립트의 문자열)의 모든 문자가 본문 글꼴에 있어야 한다.
	var missing_chars: Dictionary = _missing_glyphs(ArtAssets.body_font())
	_check(missing_chars.is_empty(), "본문 글꼴에 없는 문자 없음 %s" % [missing_chars])
	var brush: Font = ArtAssets.brush_font()
	_check(brush.fallbacks.has(ArtAssets.body_font()) and brush.has_char("—".unicode_at(0)), "붓글씨 제목의 문장부호는 본문 글꼴로 (대체 글꼴)")
	# 초상화·문장: 명부의 모든 인물, 모든 주인공 역할, 모든 문파
	var missing: PackedStringArray = []
	for npc in NpcRoster.get_all():
		if ArtAssets.portrait(npc["id"]) == null:
			missing.append(npc["id"])
	for role in CharacterData.Role.values():
		if ArtAssets.role_portrait(role) == null:
			missing.append(CharacterData.Role.keys()[role])
	for sect_id in ["qingyun", "namgung", "heukpung", "cheonma"]:
		if ArtAssets.emblem(sect_id) == null:
			missing.append(sect_id)
	_check(missing.is_empty(), "초상화·문장 모두 있음 %s" % [missing])
	# 기연 초상화: 명시한 npc가 없으면 조건·효과의 인물로
	_check(EventManager.get_event("rival_duel").npc == "npc_rival", "기연 인물 추론 (라이벌의 도전 → 남궁휘)")
	var bad_npc: PackedStringArray = EventManager.validate_event_dict({
		"id": "x", "title": "x", "description": "x", "npc": "npc_nobody", "choices": [{"label": "확인"}],
	})
	_check(bad_npc.size() == 1 and bad_npc[0].contains("npc"), "기연 검증: 명부에 없는 npc")
	var bad_emblem: PackedStringArray = SectRegistry.validate_sect_dict({
		"id": "x", "sect_name": "x", "alignment": "RIGHTEOUS", "leader_id": "npc_master", "emblem": "emblems/없음.png",
	})
	_check(bad_emblem.size() == 1 and bad_emblem[0].contains("문장"), "문파 검증: 없는 문장 그림")

	_new_quiet_game(gm, "leader")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var art: TextureRect = current_scene.get_node_or_null("Background/Art") as TextureRect
	_check(art != null and art.texture == ArtAssets.background("hub"), "문파 경영 화면에 배경 그림")
	var hub: Node = current_scene
	_check(hub.character_portrait != null and hub.character_portrait.texture == ArtAssets.role_portrait(gm.player_character.role), "경영 화면: 주인공 역할 초상화")
	hub.event_popup.show_event(EventManager.get_event("rival_duel").to_popup_dict())
	_check(hub.event_popup.portrait.visible and hub.event_popup.portrait.texture == ArtAssets.portrait("npc_rival"), "기연 팝업: 얽힌 인물 초상화")
	hub.event_popup.show_event({"title": "x", "description": "x", "choices": ["확인"]})
	_check(not hub.event_popup.portrait.visible, "기연 팝업: 인물이 없으면 초상화 숨김")
	hub.event_popup.visible = false
	SceneRouter.goto(tree, SceneRouter.WORLD)
	await process_frame
	await process_frame
	var pictures: int = current_scene.sect_list.find_children("*", "TextureRect", true, false).size()
	_check(pictures == 1 + gm.world_sects.size(), "강호 정세: 문파마다 문장")
	_check(current_scene.npc_list.find_children("*", "TextureRect", true, false).size() > 3, "강호 정세: 인물 초상화")

	gm.pending_combat = CombatManager.create_sparring_with("npc_rival", gm.player_character)
	SceneRouter.goto(tree, SceneRouter.COMBAT)
	await process_frame
	await process_frame
	var combat: Node = current_scene
	_check(combat.get_node_or_null("Background/Art") != null, "전투 화면에 배경 그림")
	_check(combat.foe_portrait.texture == ArtAssets.portrait("npc_rival") and combat.friend_portrait.texture != null, "대결 화면: 양쪽 초상화")
	combat.leave_combat()
	await process_frame
	await process_frame
	gm.pending_combat = null
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	_clear_test_saves()
	_completed["_test_art_assets"] = true


## 소리: 곡·효과음 파일이 불러와지고, 화면마다 곡이 바뀌고, 전투 행동에 효과음이 난다.
func _test_audio() -> void:
	var gm: Node = root.get_node("GameManager")
	var audio: Node = root.get_node("AudioManager")
	var tracks: Dictionary = {}
	for screen in audio.SCREEN_MUSIC:
		tracks[audio.SCREEN_MUSIC[screen]] = true
	for track in tracks:
		var stream: AudioStream = load(audio.MUSIC_DIR + track + ".ogg")
		_check(stream is AudioStreamOggVorbis and stream.get_length() > 20.0, "배경음악 %s" % track)
	for sfx in ["click", "success", "failure", "event", "hit", "art", "level_up", "battle_start", "victory", "defeat"]:
		_check(load(audio.SFX_DIR + sfx + ".ogg") is AudioStreamOggVorbis, "효과음 %s" % sfx)
	_check(AudioServer.get_bus_index(GameSettings.MUSIC_BUS) > 0 and AudioServer.get_bus_index(GameSettings.SFX_BUS) > 0, "배경음악·효과음 버스")
	_check(audio._sfx_players[0].bus == GameSettings.SFX_BUS and audio._music_players[0].bus == GameSettings.MUSIC_BUS, "재생기가 각자의 버스로")

	_new_quiet_game(gm, "leader")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	_check(audio.current_music == "hub", "문파 경영 화면: 경영 곡")
	var playing: AudioStreamPlayer = audio._music_players[audio._music_index]
	_check(playing.playing and playing.stream.loop, "배경음악은 반복 재생")

	gm.pending_combat = CombatManager.create_sparring_with("npc_rival", gm.player_character)
	SceneRouter.goto(tree, SceneRouter.COMBAT)
	await process_frame
	await process_frame
	var combat: Node = current_scene
	_check(audio.current_music == "combat", "전투 화면: 전투 곡")
	combat.plan.assign([DuelCard.basic_cards()[0], DuelCard.basic_cards()[0], DuelCard.basic_cards()[0]])
	combat.fight()
	_check(audio.last_sfx == "hit", "기본 동작으로 겨루기: 타격 소리")
	combat.engine.current_foe().hp = 1
	await combat.skip_to_result()
	_check(audio.last_sfx in ["victory", "level_up"], "승리: 승전 소리")
	gm.pending_combat = null

	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	await process_frame
	_check(audio.current_music == "main", "메인 메뉴: 메인 곡")
	audio.play_music("main")
	_check(audio.current_music == "main", "같은 곡이면 다시 시작하지 않음")
	_clear_test_saves()
	_completed["_test_audio"] = true


## 앱이 백그라운드로 가면(모바일 일시정지·창 닫기·포커스 잃음) 자동 저장한다.
func _test_suspend_autosave() -> void:
	var gm: Node = root.get_node("GameManager")
	_clear_test_saves()
	_new_quiet_game(gm, "young_disciple")
	_check(not SaveManager.has_save(SaveManager.AUTO_SLOT), "(준비) 자동 저장 없음")
	gm._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(SaveManager.has_save(SaveManager.AUTO_SLOT), "앱 일시정지: 자동 저장")
	SaveManager.delete_save(SaveManager.AUTO_SLOT)
	gm._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(SaveManager.has_save(SaveManager.AUTO_SLOT), "포커스를 잃음(웹 탭 전환): 자동 저장")
	SaveManager.delete_save(SaveManager.AUTO_SLOT)
	gm.is_game_active = false
	_check(not gm.save_on_suspend() and not SaveManager.has_save(SaveManager.AUTO_SLOT), "진행 중인 게임이 없으면 저장하지 않음")
	_clear_test_saves()
	_new_quiet_game(gm, "young_disciple")
	_completed["_test_suspend_autosave"] = true


func _test_role_guide() -> void:
	var gm: Node = root.get_node("GameManager")
	_new_quiet_game(gm, "young_disciple")
	# 조건 안내: 막내 제자는 승진·간자·배신·떠나기 길이 있고, 조건마다 채웠는지 표시
	var paths: Array[Dictionary] = RoleManager.get_transition_guide(gm)
	var titles: Array = paths.map(func(p: Dictionary) -> String: return p["title"])
	_check(titles.has("총관(중간관리자) 승진") and titles.has("간자(스파이) 임무") and titles.has("문파를 떠나 무소속으로"), "막내 제자의 길: 승진·간자·떠나기")
	var promote: Dictionary = paths[titles.find("총관(중간관리자) 승진")]
	_check(not promote["available"] and promote["conditions"].any(func(r: Dictionary) -> bool: return not r["ok"] and r["text"].contains("경지")), "승진: 경지 조건 미충족 표시")
	_new_quiet_game(gm, "wanderer")
	paths = RoleManager.get_transition_guide(gm)
	titles = paths.map(func(p: Dictionary) -> String: return p["title"])
	_check(titles.has("문파에 입문 (막내 제자)") and titles.has("의뢰인이 된다") and not titles.has("문파를 떠나 무소속으로"), "무소속 낭인의 길: 입문·의뢰인")
	# 신용이 하나도 없으면 특정 세력을 들지 않고, 지금 지역(주인 없는 땅)에서는 신용이 오르지 않는다고 안내
	var join_texts: Array = paths[titles.find("문파에 입문 (막내 제자)")]["conditions"].map(func(r: Dictionary) -> String: return r["text"])
	_check(join_texts.any(func(t: String) -> bool: return t.contains("지금 최고: 아직 없음")) and not ", ".join(join_texts).contains("청운검파"), "입문 안내: 신용이 없으면 세력 이름 없이")
	_check(join_texts.any(func(t: String) -> bool: return t.contains("낙양") and t.contains("신용이 오르지 않음")), "입문 안내: 주인 없는 땅에서는 신용이 오르지 않음")
	gm.travel_to("hefei")
	paths = RoleManager.get_transition_guide(gm)
	join_texts = paths[titles.find("문파에 입문 (막내 제자)")]["conditions"].map(func(r: Dictionary) -> String: return r["text"])
	_check(join_texts.any(func(t: String) -> bool: return t.contains("남궁세가 신용 +")), "입문 안내: 남궁세가 땅에서는 남궁세가 신용이 오름")
	RoleActions.change_credit(gm.role_state, "namgung", _Balance.JOIN_CREDIT_REQ)
	paths = RoleManager.get_transition_guide(gm)
	_check(paths[titles.find("문파에 입문 (막내 제자)")]["available"], "신용을 채우면 입문 가능 표시")
	# 역할 전환 버튼: 고를 전환이 없어도 창이 열려 안내를 보인다
	_new_quiet_game(gm, "young_disciple")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var hub: Node = current_scene
	hub._on_role_pressed()
	_check(hub.role_popup.visible and hub.role_popup.confirm_button.disabled and hub.role_popup.get_guide_line_count() > 5, "역할 전환 창: 전환이 없어도 조건 안내")
	hub.role_popup.visible = false
	# 지도에서 골라 이동: 낭인의 [이동 (지도)]는 지도를 열고, 지역을 고르면 [이곳으로 이동]
	_new_quiet_game(gm, "wanderer")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	current_scene._on_role_action_pressed("travel")
	await process_frame
	await process_frame
	var map: Node = current_scene
	_check(map.scene_file_path == SceneRouter.MAP and map.get_selected() == gm.player_region, "이동: 지도가 열리고 지금 지역이 골라져 있음")
	map.select_region("kaifeng")
	_check(map.action_button.visible and not map.action_button.disabled and map.action_button.text.contains("이동"), "다른 지역을 고르면 [이곳으로 이동]")
	map._on_action_pressed()
	_check(gm.player_region == "kaifeng" and map.summary_label.text.contains("개봉"), "지도에서 개봉으로 이동")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	_check(current_scene.character_role_label.text.contains("개봉") and current_scene.get_node("Background/Art").texture == ArtAssets.region_background("kaifeng"), "인물 정보에 지역, 배경은 그 지역 그림")
	_completed["_test_role_guide"] = true


func _test_list_drag_scroll() -> void:
	SceneRouter.goto(tree, SceneRouter.NEW_GAME)
	await process_frame
	await process_frame
	var screen: Node = current_scene
	var list: ItemList = screen.scenario_list
	var helper: DragScroll = list.get_node_or_null("DragScroll")
	_check(helper != null and screen.role_list.has_node("DragScroll"), "목록 끌어 스크롤: 화면의 목록마다 붙음")
	# 목록이 넘칠 만큼 낮게 만든다
	list.custom_minimum_size.y = 60
	list.size.y = 60
	await process_frame
	await process_frame
	var bar: VScrollBar = list.get_v_scroll_bar()
	var selected: int = list.get_selected_items()[0]
	var press: InputEventMouseButton = _mouse(true)
	press.position = Vector2(40, 50)
	helper._on_gui_input(press)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(40, 10)
	drag.relative = Vector2(0, -40)
	helper._on_gui_input(drag)
	var release: InputEventMouseButton = _mouse(false)
	release.position = Vector2(40, 10)
	helper._on_gui_input(release)
	_check(bar.value > 0 and list.get_selected_items()[0] == selected, "목록 끌어 스크롤: 끌면 스크롤되고 고르지 않음 (%.0f)" % bar.value)
	# 끌지 않고 누르면 그 자리의 항목을 고른다
	var target: int = list.get_item_at_position(Vector2(40, 30), true)
	var got: Array = []
	list.item_selected.connect(func(i: int) -> void: got.append(i))
	press.position = Vector2(40, 30)
	helper._on_gui_input(press)
	release.position = Vector2(41, 31)
	helper._on_gui_input(release)
	_check(target >= 0 and target != selected and list.is_selected(target) and got == [target], "목록 끌어 스크롤: 누르면 항목 선택 신호")
	# 실제 입력(창으로 들어오는 누름·끌기)으로도: 끄는 동안 목록이 항목을 고르지 않는다
	bar.value = 0
	var now: int = list.get_selected_items()[0]
	var origin: Vector2 = list.get_global_rect().position + Vector2(40, 50)
	# 창 좌표로 보낸다 (헤드리스 창은 작아서 화면 배율이 걸린다)
	var to_window: Transform2D = root.get_final_transform()
	var real_press: InputEventMouseButton = _mouse(true)
	real_press.position = to_window * origin
	real_press.global_position = real_press.position
	root.push_input(real_press)
	for step in 4:
		var move := InputEventMouseMotion.new()
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		move.position = to_window * (origin - Vector2(0, 10 * (step + 1)))
		move.global_position = move.position
		move.relative = to_window.basis_xform(Vector2(0, -10))
		root.push_input(move)
	var real_release: InputEventMouseButton = _mouse(false)
	real_release.position = to_window * (origin - Vector2(0, 40))
	real_release.global_position = real_release.position
	root.push_input(real_release)
	await process_frame
	_check(bar.value > 0 and list.get_selected_items()[0] == now, "목록 끌어 스크롤: 실제 입력으로 끌기 (%.0f)" % bar.value)
	SceneRouter.goto(tree, SceneRouter.MAIN_MENU)
	await process_frame
	ScenarioManager.activate(ScenarioManager.DEFAULT_ID)
	_completed["_test_list_drag_scroll"] = true
