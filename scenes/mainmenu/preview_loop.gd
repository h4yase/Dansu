extends RefCounted
class_name MenuPreviewLoop

const FADE_OUT_SECONDS := 1.0
const FADE_IN_SECONDS := 0.35
const RESTART_DELAY_SECONDS := 3.0

var _player: AudioStreamPlayer
var _wait_remaining := -1.0
var _fade_in_elapsed := FADE_IN_SECONDS


func arm(player: AudioStreamPlayer, fade_in: bool = false) -> void:
	_player = player
	_wait_remaining = -1.0
	_fade_in_elapsed = 0.0 if fade_in else FADE_IN_SECONDS
	if fade_in:
		_player.volume_db = -80.0


func cancel() -> void:
	_player = null
	_wait_remaining = -1.0


func is_waiting() -> bool:
	return _player != null and _wait_remaining >= 0.0


func update(delta: float) -> void:
	if not is_instance_valid(_player) or _player.stream == null or _player.stream_paused:
		return
	var length := _player.stream.get_length()
	if length <= 0.0:
		return
	if _wait_remaining >= 0.0:
		_wait_remaining -= delta
		if _wait_remaining > 0.0:
			return
		_wait_remaining = -1.0
		_fade_in_elapsed = 0.0
		_player.volume_db = -80.0
		_player.play(0.0)
		return
	if not _player.playing:
		_wait_remaining = RESTART_DELAY_SECONDS
		_player.volume_db = -80.0
		return
	_fade_in_elapsed += delta
	var remaining := maxf(0.0, length - _player.get_playback_position() - AudioServer.get_time_since_last_mix())
	var fade_out := clampf(remaining / FADE_OUT_SECONDS, 0.0, 1.0)
	var fade_in := clampf(_fade_in_elapsed / FADE_IN_SECONDS, 0.0, 1.0)
	_player.volume_db = maxf(-80.0, linear_to_db(minf(fade_in, fade_out)))
