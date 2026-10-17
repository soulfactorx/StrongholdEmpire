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

	# 전투: 이동 취소, 단축키
	gm.player_character.learn_martial_art(MartialArtLibrary.create_art("preset_soul_chase_sword"))
	gm.start_combat(CombatManager.create_sparring(gm.player_character))
	await process_frame
	await process_frame
	var c: Node = current_scene
	var player: CombatUnit = c._get_player()
	var start: Vector2i = player.grid_pos
	var ap: int = player.action_points
	var target: Vector2i = start + Vector2i(1, 0)
	c._try_move(player, target)
	_check(player.grid_pos == target and not c.undo_move_button.disabled, "이동하면 이동 취소 가능")
	c._unhandled_key_input(_key(KEY_Z))
	_check(player.grid_pos == start and player.action_points == ap and c.undo_move_button.disabled, "Z: 이동 취소 (위치·행동력 복원)")
	c._try_move(player, target)
	var enemy: CombatUnit = c._get_alive_enemies()[0]
	enemy.grid_pos = player.grid_pos + Vector2i(1, 0)
	c._perform_attack(player, enemy)
	c._on_undo_move_pressed()
	_check(player.grid_pos == target, "공격한 뒤에는 이동 취소 불가")
	c._unhandled_key_input(_key(KEY_A))
	_check(c._action_mode == c.ActionMode.ATTACK, "A: 공격 모드")
	c._unhandled_key_input(_key(KEY_1))
	_check(c._selected_art != null and c._action_mode == c.ActionMode.MARTIAL_ART, "1: 첫 무공 선택")
	c._unhandled_key_input(_key(KEY_M))
	_check(c._action_mode == c.ActionMode.MOVE, "M: 이동 모드")

	# 전투 속도: 적 차례 사이에 간격을 두고, 그동안은 조작할 수 없다
	GameSettings.combat_delay = 0.2
	c._unhandled_key_input(_key(KEY_SPACE))
	_check(c._enemy_acting and c._get_controlled() == null and c.end_turn_button.disabled, "적이 움직이는 동안 조작 불가")
	await create_timer(0.5).timeout
	_check(not c._enemy_acting and c._get_controlled() == player, "간격 뒤 적이 행동하고 다시 내 차례")
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
		_check(ArtAssets.ui(ui) != null, "UI 텍스처 %s" % ui)
	_check(ArtAssets.body_font() != null and ArtAssets.brush_font() != null, "본문·붓글씨 글꼴")
	_check(root.theme != null and root.theme.default_font == ArtAssets.body_font(), "창 테마의 기본 글꼴")

	_new_quiet_game(gm, "leader")
	SceneRouter.goto(tree, SceneRouter.HUB)
	await process_frame
	await process_frame
	var art: TextureRect = current_scene.get_node_or_null("Background/Art") as TextureRect
	_check(art != null and art.texture == ArtAssets.background("hub"), "문파 경영 화면에 배경 그림")

	gm.pending_combat = CombatManager.create_sparring_with("npc_rival", gm.player_character)
	SceneRouter.goto(tree, SceneRouter.COMBAT)
	await process_frame
	await process_frame
	var combat: Node = current_scene
	_check(combat.get_node_or_null("Background/Art") != null, "전투 화면에 배경 그림")
	var tile_count: int = 0
	for child in combat.grid_overlay.get_children():
		if child is TextureRect and not child.is_queued_for_deletion():
			tile_count += 1
	_check(tile_count == combat.GRID_WIDTH * combat.GRID_HEIGHT, "전투 칸마다 지형 그림")
	var token_count: int = 0
	for child in combat.units_layer.get_children():
		if not child.is_queued_for_deletion():
			token_count += 1
	_check(token_count == 2, "비무 양쪽 장기말")
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
	var player_unit: CombatUnit = combat._get_player()
	var enemy: CombatUnit = combat._get_alive_enemies()[0]
	enemy.grid_pos = player_unit.grid_pos + Vector2i(1, 0)
	combat._perform_attack(player_unit, enemy)
	_check(audio.last_sfx == "hit", "기본 공격: 타격 소리")
	enemy.hp = 1
	player_unit.action_points = 5
	combat._perform_attack(player_unit, enemy)
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
