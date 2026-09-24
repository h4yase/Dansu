extends RefCounted
class_name GameClock

const DEFAULT_LEAD_IN_MS := 3000.0

var playback_start_ms := 0.0
var start_target_usec := 0
var offset_ms := 0.0

var _pause_begin_usec := 0

func setup(start_ms: float, lead_in_ms: float = DEFAULT_LEAD_IN_MS) -> void:
	playback_start_ms = maxf(0.0, start_ms)
	offset_ms = Config.offset
	start_target_usec = Time.get_ticks_usec() + int(lead_in_ms * 1000.0)
	_pause_begin_usec = 0

func to_game_time(timestamp_usec: int) -> int:
	return roundi(
		playback_start_ms
		+ float(timestamp_usec - start_target_usec) / 1000.0
		- offset_ms
	)

func now() -> int:
	return to_game_time(Time.get_ticks_usec())

func pause(reference_usec: int) -> void:
	_pause_begin_usec = reference_usec

func resume(reference_usec: int) -> void:
	if _pause_begin_usec == 0:
		return
	start_target_usec += reference_usec - _pause_begin_usec
	_pause_begin_usec = 0
