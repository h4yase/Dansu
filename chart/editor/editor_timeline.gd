extends RefCounted
class_name EditorTimeline

const DEFAULT_MIN_TIME := -3000
const DEFAULT_TAIL_PADDING := 3000

var chart: Chart = null

var beat_division: int = 4:
	set(value):
		beat_division = max(1, value)

var _min_time_ms: int = DEFAULT_MIN_TIME
var _song_length_ms: int = 0
var _song_length_sec: float = 0.0
var _tail_padding_ms: int = DEFAULT_TAIL_PADDING

func _init(
	chart_value: Chart = null,
	sec: float = 0.0,
	min_time_ms: int = DEFAULT_MIN_TIME,
	tail_padding_ms: int = DEFAULT_TAIL_PADDING
) -> void:
	chart = chart_value
	_min_time_ms = min_time_ms
	_song_length_sec = sec
	_song_length_ms = int(round(sec * 1000.0))
	_tail_padding_ms = maxi(0, tail_padding_ms)

func ensure_timings() -> void:
	if chart == null:
		return

	if chart.timings == null:
		chart.timings = []

	if chart.timings.is_empty():
		var default_timing := Timing.new()
		default_timing.time = 0
		default_timing.bpm = 120.0
		chart.timings.append(default_timing)

	chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)

func get_min_time() -> int:
	return _min_time_ms

func get_max_time() -> int:
	return _song_length_ms + _tail_padding_ms

func clamp_time(value: float) -> float:
	return clamp(value, float(_min_time_ms), float(get_max_time()))

func get_active_timing(time_ms: int) -> Timing:
	ensure_timings()

	var active: Timing = chart.timings[0]
	for timing in chart.timings:
		if timing.time > time_ms:
			break
		active = timing
	return active

func get_next_timing_after(time_ms: int) -> Timing:
	ensure_timings()
	for timing in chart.timings:
		if timing.time > time_ms:
			return timing
	return null

func get_previous_timing_before(time_ms: int) -> Timing:
	ensure_timings()
	var previous: Timing = null
	for timing in chart.timings:
		if timing.time >= time_ms:
			break
		previous = timing
	return previous

func get_snap_interval_ms(time_ms: int) -> float:
	var timing := get_active_timing(time_ms)
	return 60000.0 / timing.bpm / float(beat_division)

func snap_time(time_ms: int) -> int:
	var timing := get_active_timing(time_ms)
	var interval := get_snap_interval_ms(time_ms)
	var snapped_steps = round((time_ms - timing.time) / interval)
	return int(round(timing.time + snapped_steps * interval))

func step_time(time_ms: int, direction: int) -> int:
	if direction == 0:
		return int(clamp_time(time_ms))

	var timing := get_active_timing(time_ms)
	var interval := get_snap_interval_ms(time_ms)
	var relative: float = (time_ms - timing.time) / interval
	var target_steps: int

	if direction > 0:
		target_steps = int(ceil(relative - 0.0001))
	else:
		target_steps = int(floor(relative + 0.0001))

	var target_time := int(round(timing.time + target_steps * interval))
	if direction > 0 and target_time <= time_ms:
		target_steps += 1
		target_time = int(round(timing.time + target_steps * interval))
	elif direction < 0 and target_time >= time_ms:
		target_steps -= 1
		target_time = int(round(timing.time + target_steps * interval))

	if direction > 0:
		var next_timing := get_next_timing_after(time_ms)
		if next_timing != null and target_time > next_timing.time:
			target_time = next_timing.time
	elif target_time < timing.time:
		var previous_timing := get_previous_timing_before(timing.time)
		if previous_timing != null:
			var previous_interval: float = 60000.0 / previous_timing.bpm / float(beat_division)
			var previous_relative: float = (time_ms - previous_timing.time) / previous_interval
			var previous_steps := int(ceil(previous_relative - 0.0001)) - 1
			target_time = int(round(previous_timing.time + previous_steps * previous_interval))

	return int(clamp_time(target_time))

func get_division_denominator(time_ms: int) -> int:
	var timing := get_active_timing(time_ms)
	var interval := get_snap_interval_ms(time_ms)
	var step := int(round((time_ms - timing.time) / interval))
	var beat_step := posmod(step, beat_division)

	if beat_step == 0:
		return 1

	@warning_ignore("integer_division")
	return int(beat_division / _gcd(beat_step, beat_division))

func format_time_label(current_time: float) -> String:
	var current_ms := int(round(current_time))
	return "%s/%s (%dms)" % [_format_clock(current_ms), _format_clock(_song_length_ms), current_ms]

func _format_clock(time_ms: int) -> String:
	var total_seconds = max(0, int(floor(float(time_ms) / 1000.0)))
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	return "%d:%02d" % [minutes, seconds]

func _gcd(a: int, b: int) -> int:
	a = abs(a)
	b = abs(b)
	while b != 0:
		var next := a % b
		a = b
		b = next
	return max(1, a)
