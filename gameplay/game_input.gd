extends RefCounted
class_name GameInput

var _clock: GameClock
var _replay: Replay
var _autoplay := false

var _timestamp_input: Object
var _timestamp_active := false
var _last_cutoff_usec := -1
var _corrected_events := 0
var _replay_index := 0
var _input_order := 0
var _last_builtin_frame := -1

func setup(clock: GameClock, replay: Replay, autoplay: bool) -> void:
	_clock = clock
	_replay = replay
	_autoplay = autoplay
	_replay_index = 0
	_input_order = 0
	_last_builtin_frame = -1
	_corrected_events = 0
	_pending_error = ""

	stop()
	if _replay == null and not _autoplay:
		_start_timestamp_input()

func stop() -> void:
	if _timestamp_input != null:
		_timestamp_input.stop()
	_timestamp_input = null
	_timestamp_active = false
	_last_cutoff_usec = -1

func is_timestamp_active() -> bool:
	return _timestamp_active

func corrected_event_count() -> int:
	return _corrected_events

func current_time() -> int:
	if _timestamp_active and _last_cutoff_usec >= 0:
		return _clock.to_game_time(_last_cutoff_usec)
	return _clock.now()

func reference_usec() -> int:
	if _timestamp_active and _last_cutoff_usec >= 0:
		return _last_cutoff_usec
	return Time.get_ticks_usec()

func discard() -> void:
	if _timestamp_active:
		_poll_timestamp(true)

func poll(last_simulated_time: int) -> GameInputFrame:
	var frame := GameInputFrame.new()
	frame.exclusive = _replay == null and not _autoplay

	if _timestamp_active:
		var batch := _poll_timestamp(false)
		if batch.failed:
			frame.failed = true
			frame.error = batch.error
			return frame

		frame.time = _clock.to_game_time(batch.cutoff_usec)
		frame.simulation_target = _clock.to_game_time(batch.cutoff_usec + 1)
		frame.inputs = _collect_timestamp_inputs(batch, last_simulated_time)
		if _pending_error != "":
			frame.failed = true
			frame.error = _pending_error
			_pending_error = ""
		return frame

	frame.time = _clock.now()
	frame.simulation_target = frame.time

	if _autoplay:
		return frame
	if _replay != null:
		frame.inputs = _collect_replay_inputs(frame.time)
	else:
		frame.inputs = _collect_builtin_inputs(frame.time)
	return frame


class TimeStampBatch:
	var cutoff_usec := -1
	var events: Array = []
	var failed := false
	var error := ""


var _pending_error := ""

func _start_timestamp_input() -> void:
	if not OS.has_feature("windows") or not Engine.has_singleton("TimeStampInput"):
		print("Falling back to Godot input.")
		return

	_timestamp_input = Engine.get_singleton("TimeStampInput")
	if not _timestamp_input.start():
		push_warning("TimeStampInput failed to start. Falling back to Godot input.")
		_timestamp_input = null
		return

	_timestamp_active = true
	_last_cutoff_usec = -1
	var first_batch := _poll_timestamp(true)
	if first_batch.failed:
		push_error(first_batch.error)
		stop()

func _poll_timestamp(discard_events: bool) -> TimeStampBatch:
	var result := TimeStampBatch.new()

	# TimeStampInput is an external GDExtension API and currently returns Dictionary.
	# Keep the untyped value at this boundary only, then convert it immediately.
	var raw: Dictionary = _timestamp_input.poll_events(discard_events)
	result.cutoff_usec = int(raw.cutoff_timestamp_usec)

	if result.cutoff_usec < _last_cutoff_usec:
		result.failed = true
		result.error = "TimeStampInput cutoff regressed."
		return result

	for event in raw.events:
		var event_time := int(event.timestamp_usec)
		if event_time <= _last_cutoff_usec or event_time > result.cutoff_usec:
			result.failed = true
			result.error = "TimeStampInput event crossed a closed poll cutoff."
			return result
		result.events.append(event)

	_last_cutoff_usec = result.cutoff_usec
	_corrected_events += int(raw.corrected_events)
	return result

func _collect_timestamp_inputs(batch: TimeStampBatch, last_simulated_time: int) -> Array[ReplayInput]:
	var collected: Array[ReplayInput] = []
	for event in batch.events:
		if event == null:
			continue

		var type := _input_type_for_key(int(event.keycode), bool(event.pressed))
		if type == ReplayInput.InputType.NONE:
			continue

		var timing := _clock.to_game_time(int(event.timestamp_usec))
		if timing <= last_simulated_time:
			_pending_error = "New live input timing %d is already simulated through %d." % [timing, last_simulated_time]
			return []
		collected.append(_make_input(timing, type))
	return collected

func _collect_replay_inputs(time_ms: int) -> Array[ReplayInput]:
	var due: Array[ReplayInput] = []
	while _replay_index < _replay.inputs.size():
		var replay_input: ReplayInput = _replay.inputs[_replay_index]
		if replay_input.timing > time_ms:
			break
		due.append(replay_input)
		_replay_index += 1
	return due

func _collect_builtin_inputs(time_ms: int) -> Array[ReplayInput]:
	var collected: Array[ReplayInput] = []
	var frame := Engine.get_process_frames()
	if frame == _last_builtin_frame:
		return collected
	_last_builtin_frame = frame

	_append_action(collected, "action_hit1", ReplayInput.InputType.HIT1_DOWN, ReplayInput.InputType.HIT1_UP, time_ms)
	_append_action(collected, "action_hit2", ReplayInput.InputType.HIT2_DOWN, ReplayInput.InputType.HIT2_UP, time_ms)
	_append_action(collected, "action_left", ReplayInput.InputType.MOVELEFT_DOWN, ReplayInput.InputType.MOVELEFT_UP, time_ms)
	_append_action(collected, "action_right", ReplayInput.InputType.MOVERIGHT_DOWN, ReplayInput.InputType.MOVERIGHT_UP, time_ms)
	return collected

func _append_action(
	output: Array[ReplayInput],
	action: StringName,
	down_type: ReplayInput.InputType,
	up_type: ReplayInput.InputType,
	time_ms: int
) -> void:
	if Input.is_action_just_pressed(action):
		output.append(_make_input(time_ms, down_type))
	if Input.is_action_just_released(action):
		output.append(_make_input(time_ms, up_type))

func _make_input(timing: int, type: ReplayInput.InputType) -> ReplayInput:
	var input := ReplayInput.new(timing, type)
	input.order = _input_order
	_input_order += 1
	return input

func _input_type_for_key(keycode: int, pressed: bool) -> ReplayInput.InputType:
	if keycode == int(Config.action_hit1):
		return ReplayInput.InputType.HIT1_DOWN if pressed else ReplayInput.InputType.HIT1_UP
	if keycode == int(Config.action_hit2):
		return ReplayInput.InputType.HIT2_DOWN if pressed else ReplayInput.InputType.HIT2_UP
	if keycode == int(Config.action_left):
		return ReplayInput.InputType.MOVELEFT_DOWN if pressed else ReplayInput.InputType.MOVELEFT_UP
	if keycode == int(Config.action_right):
		return ReplayInput.InputType.MOVERIGHT_DOWN if pressed else ReplayInput.InputType.MOVERIGHT_UP
	return ReplayInput.InputType.NONE
