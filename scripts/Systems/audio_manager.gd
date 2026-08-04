extends Node

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)


func play_click() -> void:
	_play_tone(440.0, 0.05)


func play_success() -> void:
	_play_tone(523.25, 0.1)


func play_failure() -> void:
	_play_tone(220.0, 0.12)


func play_event() -> void:
	_play_tone(349.23, 0.1)


func _play_tone(frequency: float, duration: float) -> void:
	var sample_rate: int = 22050
	var frame_count: int = int(sample_rate * duration)
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_8_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false
	var data := PackedByteArray()
	data.resize(frame_count)
	for i in frame_count:
		var t: float = float(i) / float(sample_rate)
		var envelope: float = 1.0 - (float(i) / float(frame_count))
		var sample: float = sin(TAU * frequency * t) * envelope
		data[i] = int((sample * 0.5 + 0.5) * 255.0)
	audio.data = data
	_player.stream = audio
	_player.play()