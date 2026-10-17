extends Node

## 배경음악과 효과음.
## 소리 파일은 assets/audio/ (tools/audio/generate_audio.py로 만든다). 같은 이름의 파일로 덮어쓰면 바뀐다.
## 배경음악은 화면이 바뀔 때 그 화면의 곡으로 서서히 넘어가고, 효과음은 여러 개가 겹쳐 울릴 수 있다.

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
## 배경음악이 넘어가는 시간(초)
const CROSSFADE := 1.2
## 동시에 울릴 수 있는 효과음 수
const SFX_VOICES := 6

## 화면 씬 파일 이름 → 곡 이름
const SCREEN_MUSIC: Dictionary = {
	"main": "main",
	"new_game_screen": "main",
	"help_screen": "main",
	"management_screen": "hub",
	"world_screen": "hub",
	"martial_art_screen": "hub",
	"combat_scene": "combat",
	"sect_war_screen": "combat",
	"ending_screen": "ending",
}

## 지금 고른 곡 이름 (없으면 "")
var current_music: String = ""
## 마지막으로 낸 효과음 이름 (테스트용)
var last_sfx: String = ""

var _music_players: Array[AudioStreamPlayer] = []
## 지금 울리는 쪽 배경음악 재생기 번호
var _music_index: int = 0
var _music_tween: Tween
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _cache: Dictionary = {}


func _ready() -> void:
	for i in 2:
		var music := AudioStreamPlayer.new()
		music.bus = GameSettings.MUSIC_BUS
		add_child(music)
		_music_players.append(music)
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = GameSettings.SFX_BUS
		add_child(player)
		_sfx_players.append(player)
	# 버스가 없으면 만든다 (GameSettings.apply가 음량을 정한다).
	GameSettings.bus_index(GameSettings.MUSIC_BUS)
	GameSettings.bus_index(GameSettings.SFX_BUS)
	get_tree().scene_changed.connect(_on_scene_changed)
	# 첫 화면(main_scene)은 scene_changed 없이 열리므로 한 번 직접 고른다.
	_on_scene_changed.call_deferred()


## 재생 중인 소리를 멈춘다. (헤드리스 테스트가 끝날 때 재생 중인 스트림이 남지 않게)
func stop_all() -> void:
	if _music_tween:
		_music_tween.kill()
	for player in _music_players + _sfx_players:
		player.stop()
		player.stream = null
	current_music = ""


func _on_scene_changed() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var screen: String = scene.scene_file_path.get_file().get_basename()
	if SCREEN_MUSIC.has(screen):
		play_music(SCREEN_MUSIC[screen])


## 곡을 바꾼다. 같은 곡이면 그대로 둔다. 파일이 없으면 조용히 넘어간다.
func play_music(track: String) -> void:
	if track == current_music:
		return
	var stream: AudioStream = _load(MUSIC_DIR + track + ".ogg")
	if stream == null:
		return
	current_music = track
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var old: AudioStreamPlayer = _music_players[_music_index]
	_music_index = 1 - _music_index
	var new: AudioStreamPlayer = _music_players[_music_index]
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(new, "volume_db", 0.0, CROSSFADE)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", -40.0, CROSSFADE)
		_music_tween.chain().tween_callback(old.stop)


func play_click() -> void:
	play_sfx("click")


func play_success() -> void:
	play_sfx("success")


func play_failure() -> void:
	play_sfx("failure")


func play_event() -> void:
	play_sfx("event")


func play_hit() -> void:
	play_sfx("hit")


func play_art() -> void:
	play_sfx("art")


func play_level_up() -> void:
	play_sfx("level_up")


func play_battle_start() -> void:
	play_sfx("battle_start")


func play_victory() -> void:
	play_sfx("victory")


func play_defeat() -> void:
	play_sfx("defeat")


## 효과음을 낸다. 비어 있는 재생기를 먼저 쓰고, 모두 울리고 있으면 가장 오래된 것을 끊는다.
func play_sfx(sfx_name: String) -> void:
	last_sfx = sfx_name
	var stream: AudioStream = _load(SFX_DIR + sfx_name + ".ogg")
	if stream == null:
		return
	var player: AudioStreamPlayer = null
	for candidate in _sfx_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = _sfx_players[_sfx_next]
		_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stream = stream
	player.play()


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]
