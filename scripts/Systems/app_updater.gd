class_name AppUpdater
extends Node

## 설치형 앱(Android·Windows·Linux)의 새 버전 업데이트.
## GitHub의 최신 릴리스(main에 머지될 때마다 CI가 만든다)를 확인해 지금 버전보다 새로우면 알리고,
## [업데이트]를 누르면 이 플랫폼의 파일을 받아 SHA256SUMS.txt로 검증한 뒤 바꾼다.
## - Windows·Linux: 받은 zip을 풀어 실행 파일을 바꾸고 다시 시작한다. 실행 중인 파일은 이름을 바꿔(.old) 두고 다음 실행 때 지운다.
## - Android: 받은 APK로 시스템 설치 화면을 연다 (Godot의 FileProvider가 파일을 넘긴다). 릴리스 키로 서명돼 덮어 설치된다.
## 웹은 서비스 워커가 따로 알린다 (GameManager._on_web_update_available).
## GameManager가 자식으로 하나 만들어 두며, 창은 장면이 바뀌어도 남도록 자기 아래 층(CanvasLayer)에 둔다.

const _UiTheme = preload("res://scripts/UI/ui_theme.gd")

const REPO := "soulfactorx/StrongholdEmpire"
const RELEASE_API := "https://api.github.com/repos/%s/releases/latest" % REPO
const RELEASE_PAGE := "https://github.com/%s/releases/latest" % REPO
const SUMS_NAME := "SHA256SUMS.txt"
const DOWNLOAD_DIR := "user://updates"
## 플랫폼마다 릴리스에서 받을 파일 이름의 끝
const ASSET_SUFFIX: Dictionary = {
	"android": "-android.apk",
	"windows": "-windows.zip",
	"linux": "-linux.zip",
}
## 실행 중이던 파일을 옮겨 둘 때 붙이는 끝
const OLD_SUFFIX := ".old"
## 시작한 뒤 이만큼(초) 지나 조용히 확인한다 (첫 화면이 먼저 뜨게)
const STARTUP_DELAY := 2.0

enum State { IDLE, CHECKING, FOUND, DOWNLOADING, READY, APPLYING }

signal state_changed(state: int)

var state: int = State.IDLE
## 찾은 새 버전: {version, tag, asset_name, asset_url, size, sums_url, page}
var found: Dictionary = {}
## 받은 파일 경로 (user://)
var downloaded_path: String = ""
## 마지막 오류 (화면에 보인 글)
var last_error: String = ""
## 개발 시험용: 프록시·인증서 (실제 기기에서는 쓰지 않는다)
var proxy_host: String = ""
var proxy_port: int = 0
var tls_options: TLSOptions = null

var _http: HTTPRequest
var _manual: bool = false
var _layer: CanvasLayer
var _popup: Control
var _title: Label
var _message: Label
var _bar: ProgressBar
var _yes: Button
var _no: Button
var _on_yes: Callable
var _on_no: Callable


# ── 판단 (정적, 시험 가능) ──

## 이 플랫폼의 이름 (android·windows·linux). 그 밖(웹·맥)은 빈 문자열
static func platform_key() -> String:
	if OS.has_feature("web"):
		return ""
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("windows"):
		return "windows"
	if OS.has_feature("linuxbsd"):
		return "linux"
	return ""


## 업데이트를 쓸 수 있는 빌드인지: 내보낸 설치형 앱이고, 자체 점검 중이 아님
static func supported() -> bool:
	return OS.has_feature("template") and not platform_key().is_empty() and not SelfCheck.requested()


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## 버전 비교: a가 새로우면 1, 같으면 0, 낡았으면 -1. "v1.2.3", "1.2.3-beta" 모두 받는다.
## 숫자가 같으면 꼬리표(-beta 등)가 없는 쪽이 새롭다.
static func compare_versions(a: String, b: String) -> int:
	var pa: Array = _version_parts(a)
	var pb: Array = _version_parts(b)
	for i in 3:
		if pa[i] != pb[i]:
			return 1 if pa[i] > pb[i] else -1
	if pa[3] == pb[3]:
		return 0
	if pa[3].is_empty():
		return 1
	if pb[3].is_empty():
		return -1
	return 1 if pa[3] > pb[3] else -1


static func _version_parts(text: String) -> Array:
	var clean: String = text.strip_edges().trim_prefix("v")
	var dash: int = clean.find("-")
	var pre: String = clean.substr(dash + 1) if dash >= 0 else ""
	var nums: PackedStringArray = (clean.substr(0, dash) if dash >= 0 else clean).split(".")
	var parts: Array = []
	for i in 3:
		parts.append(int(nums[i]) if i < nums.size() and nums[i].is_valid_int() else 0)
	parts.append(pre)
	return parts


## 릴리스 응답(JSON)에서 이 플랫폼에 필요한 것을 뽑는다. 파일이 없으면 빈 사전
static func parse_release(release: Dictionary, platform: String) -> Dictionary:
	var suffix: String = ASSET_SUFFIX.get(platform, "")
	var tag: String = str(release.get("tag_name", ""))
	if suffix.is_empty() or tag.is_empty():
		return {}
	var info: Dictionary = {
		"tag": tag, "version": tag.trim_prefix("v"),
		"page": str(release.get("html_url", RELEASE_PAGE)), "sums_url": "",
	}
	for asset in release.get("assets", []):
		var asset_name: String = str(asset.get("name", ""))
		if asset_name == SUMS_NAME:
			info["sums_url"] = str(asset.get("browser_download_url", ""))
		elif asset_name.ends_with(suffix):
			info["asset_name"] = asset_name
			info["asset_url"] = str(asset.get("browser_download_url", ""))
			info["size"] = int(asset.get("size", 0))
	return info if info.has("asset_url") else {}


## SHA256SUMS.txt ("해시  파일이름" 줄들) → {파일이름: 해시}
static func parse_sums(text: String) -> Dictionary:
	var sums: Dictionary = {}
	for line in text.split("\n", false):
		var parts: PackedStringArray = line.strip_edges().split(" ", false)
		if parts.size() >= 2:
			sums[parts[parts.size() - 1].trim_prefix("*")] = parts[0].to_lower()
	return sums


## 받은 zip을 풀어 실행 파일 자리에 넣는다. 원래 파일은 .old로 옮겨 두고, 하나라도 실패하면 모두 되돌린다.
## zip 안의 실행 파일(.exe·.x86_64)은 지금 실행 파일의 이름으로 들어간다 (사용자가 이름을 바꿨어도).
## 돌려주는 값: {success, message, exe}
static func apply_desktop(zip_path: String, exe_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"success": false, "message": "받은 파일을 열 수 없습니다."}
	var dir: String = exe_path.get_base_dir()
	var moved: Array[String] = []
	var written: Array[String] = []
	var exe_found: bool = false
	var error: String = ""
	for entry in reader.get_files():
		if entry.ends_with("/"):
			continue
		var is_exe: bool = entry.get_extension() in ["exe", "x86_64"] and not entry.contains(".console.")
		var dest: String = exe_path if is_exe else dir.path_join(entry)
		exe_found = exe_found or is_exe
		var data: PackedByteArray = reader.read_file(entry)
		if data.is_empty():
			error = "받은 파일이 비어 있습니다: %s" % entry
			break
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		if FileAccess.file_exists(dest):
			var old: String = dest + OLD_SUFFIX
			if FileAccess.file_exists(old) and DirAccess.remove_absolute(old) != OK:
				old = "%s.%d%s" % [dest, Time.get_ticks_msec(), OLD_SUFFIX]
			if DirAccess.rename_absolute(dest, old) != OK:
				error = "실행 중인 파일을 옮기지 못했습니다 (쓰기 권한이 없는 폴더일 수 있습니다): %s" % dest.get_file()
				break
			moved.append(old)
			moved.append(dest)
		var file := FileAccess.open(dest, FileAccess.WRITE)
		if file == null:
			error = "새 파일을 쓰지 못했습니다: %s" % dest.get_file()
			break
		file.store_buffer(data)
		file.close()
		written.append(dest)
		if is_exe and not OS.has_feature("windows"):
			FileAccess.set_unix_permissions(dest, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER
				| FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_EXECUTE_GROUP | FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_EXECUTE_OTHER)
	reader.close()
	if error.is_empty() and not exe_found:
		error = "받은 파일에 실행 파일이 없습니다."
	if not error.is_empty():
		# 새로 쓴 것을 지우고 옮겨 둔 원래 파일을 제자리로
		for path in written:
			DirAccess.remove_absolute(path)
		for i in range(0, moved.size(), 2):
			DirAccess.rename_absolute(moved[i], moved[i + 1])
		return {"success": false, "message": error}
	return {"success": true, "message": "새 버전을 넣었습니다.", "exe": exe_path}


## 지난 업데이트에서 옮겨 둔 옛 파일(.old)을 지운다. 지운 개수
static func cleanup_old(dir: String) -> int:
	var count: int = 0
	var access := DirAccess.open(dir)
	if access == null:
		return 0
	for file_name in access.get_files():
		if file_name.ends_with(OLD_SUFFIX) and access.remove(file_name) == OK:
			count += 1
	return count


## 받아 둔 업데이트 파일을 지운다 (설치가 끝난 뒤 다음 실행 때)
static func clear_downloads() -> void:
	var access := DirAccess.open(DOWNLOAD_DIR)
	if access == null:
		return
	for file_name in access.get_files():
		access.remove(file_name)


# ── 진행 ──

func _ready() -> void:
	set_process(false)
	if not supported():
		return
	if platform_key() != "android":
		cleanup_old(OS.get_executable_path().get_base_dir())
	clear_downloads()
	if GameSettings.check_updates:
		get_tree().create_timer(STARTUP_DELAY).timeout.connect(check)


## 최신 릴리스를 확인한다. manual이면 새 버전이 없어도·오류가 나도 알린다 (설정의 [지금 확인])
func check(manual: bool = false) -> void:
	_manual = manual
	if not supported():
		if manual:
			_show("업데이트", "이 빌드에서는 앱 안 업데이트를 쓸 수 없습니다.%s" % (
				" 웹은 새 버전이 배포되면 따로 알립니다." if OS.has_feature("web") else " 릴리스 페이지에서 받으세요."
			), _open_page, "릴리스 페이지", "닫기")
		return
	if state != State.IDLE and state != State.FOUND:
		return
	_set_state(State.CHECKING)
	if manual:
		_show("업데이트 확인", "새 버전이 있는지 확인하고 있습니다…", Callable(), "", "닫기")
	_request(RELEASE_API, _on_release_checked)


func _on_release_checked(result: int, code: int, body: PackedByteArray) -> void:
	_set_state(State.IDLE)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("새 버전을 확인하지 못했습니다 (인터넷 연결을 확인하세요).", false)
		return
	var release: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not release is Dictionary:
		_fail("릴리스 정보를 읽지 못했습니다.", false)
		return
	handle_release(release)


## 릴리스 정보로 새 버전인지 판단해 알린다 (시험에서 직접 부른다)
func handle_release(release: Dictionary) -> void:
	var info: Dictionary = parse_release(release, platform_key())
	if info.is_empty() or compare_versions(info["version"], current_version()) <= 0:
		if _manual:
			_show("업데이트", "지금이 최신 버전입니다 (v%s)." % current_version(), Callable(), "", "닫기")
		elif _popup:
			_popup.visible = false
		return
	found = info
	_set_state(State.FOUND)
	var how: String = {
		"android": "받은 뒤 설치 화면이 열립니다. 처음 한 번은 \"이 출처 허용\"을 켜야 합니다.",
		"windows": "받은 뒤 게임을 새 버전으로 바꾸고 다시 시작합니다.",
		"linux": "받은 뒤 게임을 새 버전으로 바꾸고 다시 시작합니다.",
	}.get(platform_key(), "")
	_show(
		"새 버전 v%s" % info["version"],
		"지금 버전은 v%s입니다. 새 버전(%s)을 받을까요?\n%s%s" % [
			current_version(), _size_text(int(info.get("size", 0))), how,
			"\n진행 중인 이야기는 먼저 자동 저장합니다." if _game().is_game_active else "",
		],
		download, "업데이트", "나중에",
	)


## 찾은 새 버전 파일을 받는다
func download() -> void:
	if found.is_empty() or state == State.DOWNLOADING:
		return
	DirAccess.make_dir_recursive_absolute(DOWNLOAD_DIR)
	downloaded_path = DOWNLOAD_DIR.path_join(found["asset_name"])
	_set_state(State.DOWNLOADING)
	_show("새 버전 받는 중", "v%s을(를) 받고 있습니다…" % found["version"], Callable(), "", "취소")
	_on_no = cancel
	_bar.visible = true
	_bar.value = 0
	set_process(true)
	_request(found["asset_url"], _on_asset_downloaded, downloaded_path)


func cancel() -> void:
	if _http:
		_http.cancel_request()
	set_process(false)
	_set_state(State.FOUND if not found.is_empty() else State.IDLE)
	if not downloaded_path.is_empty():
		DirAccess.remove_absolute(downloaded_path)
	if _popup:
		_popup.visible = false


func _process(_delta: float) -> void:
	if state != State.DOWNLOADING or _http == null:
		set_process(false)
		return
	var total: int = _http.get_body_size()
	if total <= 0:
		total = int(found.get("size", 0))
	var done: int = _http.get_downloaded_bytes()
	if total > 0:
		_bar.value = 100.0 * done / total
		_message.text = "v%s을(를) 받고 있습니다… %d%% (%s / %s)" % [found["version"], roundi(_bar.value), _size_text(done), _size_text(total)]


func _on_asset_downloaded(result: int, code: int, _body: PackedByteArray) -> void:
	set_process(false)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_state(State.FOUND)
		_fail("새 버전을 받지 못했습니다 (인터넷 연결을 확인하세요).", true)
		return
	_message.text = "받은 파일을 확인하고 있습니다…"
	_request(found["sums_url"], _on_sums_downloaded)


func _on_sums_downloaded(result: int, code: int, body: PackedByteArray) -> void:
	var expected: String = ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		expected = parse_sums(body.get_string_from_utf8()).get(found["asset_name"], "")
	var check: Dictionary = verify_download(downloaded_path, expected)
	if not check["success"]:
		_set_state(State.FOUND)
		DirAccess.remove_absolute(downloaded_path)
		_fail(check["message"], true)
		return
	_set_state(State.READY)
	_bar.visible = false
	if platform_key() == "android":
		_show("설치 준비 끝", "v%s을(를) 받았습니다. 설치 화면에서 [업데이트]를 누르세요.\n처음이면 \"이 출처 허용\"을 켜고 돌아와 다시 누르세요." % found["version"],
			install, "설치", "나중에")
	else:
		install()


## 받은 파일이 비어 있지 않고 해시가 맞는지
static func verify_download(path: String, expected_sha256: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() == 0:
		return {"success": false, "message": "받은 파일이 없습니다."}
	if expected_sha256.is_empty():
		return {"success": false, "message": "파일 검증 정보(SHA256SUMS.txt)를 받지 못했습니다."}
	if FileAccess.get_sha256(path) != expected_sha256:
		return {"success": false, "message": "받은 파일이 손상되었습니다. 다시 시도하세요."}
	return {"success": true, "message": ""}


## 받은 새 버전을 적용한다: Android는 설치 화면, 데스크톱은 파일을 바꾸고 다시 시작
func install() -> void:
	# 내보낸 앱에서만: 편집기·시험으로 실행했을 때 엔진 실행 파일을 바꾸지 않게
	if state != State.READY or not supported():
		return
	var gm: Node = _game()
	if gm.is_game_active and not gm.is_game_over():
		gm.autosave()
	if platform_key() == "android":
		var err: Error = OS.shell_open(ProjectSettings.globalize_path(downloaded_path))
		if err != OK:
			_fail("설치 화면을 열지 못했습니다.", true)
		return
	_set_state(State.APPLYING)
	var exe: String = OS.get_executable_path()
	var applied: Dictionary = apply_desktop(ProjectSettings.globalize_path(downloaded_path), exe)
	if not applied["success"]:
		_set_state(State.FOUND)
		_fail(applied["message"], true)
		return
	_show("업데이트 완료", "v%s(으)로 바꿨습니다. 게임을 다시 시작합니다." % found["version"], Callable(), "", "")
	await get_tree().create_timer(1.0).timeout
	OS.create_process(exe, [])
	get_tree().quit()


func _game() -> Node:
	return get_node("/root/GameManager")


func _open_page() -> void:
	OS.shell_open(found.get("page", RELEASE_PAGE))


## 오류: 직접 확인한 것이거나 받는 중이었으면 알리고, 시작할 때 조용히 확인한 것이면 넘어간다
func _fail(message: String, always: bool) -> void:
	last_error = message
	push_warning("업데이트: " + message)
	if not (always or _manual):
		return
	_show("업데이트", message + "\n릴리스 페이지에서 직접 받을 수도 있습니다.", _open_page, "릴리스 페이지", "닫기")


func _set_state(value: int) -> void:
	state = value
	state_changed.emit(value)


func _request(url: String, callback: Callable, file_path: String = "") -> void:
	if _http == null:
		_http = HTTPRequest.new()
		_http.use_threads = true
		_http.timeout = 600.0
		add_child(_http)
		if not proxy_host.is_empty():
			_http.set_https_proxy(proxy_host, proxy_port)
		if tls_options:
			_http.set_tls_options(tls_options)
	for connection in _http.request_completed.get_connections():
		_http.request_completed.disconnect(connection["callable"])
	_http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void: callback.call(result, code, body), CONNECT_ONE_SHOT)
	_http.download_file = file_path
	var headers: PackedStringArray = ["User-Agent: StrongholdEmpire/%s" % current_version(), "Accept: application/vnd.github+json"]
	if _http.request(url, headers) != OK:
		callback.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())


static func _size_text(bytes: int) -> String:
	return "%.1fMB" % (bytes / 1048576.0)


# ── 창 ──

## 창을 띄운다. yes_text가 비면 확인 버튼을 숨기고, no_text가 비면 닫기 버튼을 숨긴다.
func _show(title: String, message: String, on_yes: Callable, yes_text: String, no_text: String) -> void:
	_build_popup()
	_title.text = title
	_message.text = message
	_bar.visible = false
	_yes.text = yes_text
	_yes.visible = not yes_text.is_empty()
	_no.text = no_text
	_no.visible = not no_text.is_empty()
	_on_yes = on_yes
	_on_no = Callable()
	_popup.visible = true
	if _yes.visible:
		_yes.grab_focus()


func _build_popup() -> void:
	if _popup:
		return
	_layer = CanvasLayer.new()
	_layer.name = "UpdateLayer"
	_layer.layer = 95
	add_child(_layer)
	_popup = Control.new()
	_popup.name = "UpdatePopup"
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	# CanvasLayer 아래는 창 테마를 이어받지 않으므로 직접 준다 (글꼴이 깨지지 않게)
	_popup.theme = get_tree().root.theme
	_layer.add_child(_popup)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(dimmer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(center)
	var panel := PanelContainer.new()
	LayoutMode.fit_width(panel, 560)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = Label.new()
	_UiTheme.style_label_title(_title, 24)
	box.add_child(_title)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 20)
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = _UiTheme.COLORS["accent_gold"]
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_yes = Button.new()
	_yes.name = "YesButton"
	_no = Button.new()
	_no.name = "NoButton"
	for button in [_yes, _no]:
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(button)
	_yes.pressed.connect(_answer.bind(true))
	_no.pressed.connect(_answer.bind(false))
	_UiTheme.apply_to_control(panel)


func _answer(yes: bool) -> void:
	var callback: Callable = _on_yes if yes else _on_no
	_popup.visible = false
	if callback.is_valid():
		callback.call()


## 시험용: 창이 보이는지·제목·본문
func popup_visible() -> bool:
	return _popup != null and _popup.visible


func popup_text() -> String:
	return "%s\n%s" % [_title.text, _message.text] if _popup else ""
