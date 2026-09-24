extends RefCounted
class_name GameRule

signal note_judged(state, judgement, gap, is_release)
signal spike_dodged(state)
signal combo_changed(value, pop)
signal standing_rail_changed(rail)
signal failed(message)

const MAX_TIME := 9223372036854775807

var score := Score.new()
var combo := 0
var standing_rail: Rail
var last_simulated_time := 0
var failed_state := false

var _player: Player
var _rail_states: Array[GameplayRailState] = []
var _note_states: Array[GameplayNoteState] = []
var _touch_states: Array[GameplayNoteState] = []
var _long_states: Array[GameplayNoteState] = []

var _next_hit_index := 0
var _next_move_left_index := 0
var _next_move_right_index := 0
var _miss_index := 0
var _touch_index := 0
var _long_index := 0

var _holding_move: GameplayNoteState
var _pending_move_dir := Note.Dir.NONE
var _holding_hit: GameplayNoteState
var _holding_hit_keycode := 0

var _pending_inputs: Array[ReplayInput] = []
var _event_times: Array[int] = []
var _event_index := 0
var _autoplay: Autoplay

func setup(
	player: Player,
	rail_states: Array[GameplayRailState],
	note_states: Array[GameplayNoteState],
	touch_states: Array[GameplayNoteState],
	long_states: Array[GameplayNoteState]
) -> void:
	_player = player
	_rail_states = rail_states
	_note_states = note_states
	_touch_states = touch_states
	_long_states = long_states

func reset(start_time: int, autoplay_enabled: bool, playback_start_ms: int) -> void:
	score = Score.new()
	combo = 0
	standing_rail = null
	failed_state = false
	last_simulated_time = start_time - 1

	_next_hit_index = 0
	_next_move_left_index = 0
	_next_move_right_index = 0
	_miss_index = 0
	_touch_index = 0
	_long_index = 0
	_holding_move = null
	_pending_move_dir = Note.Dir.NONE
	_holding_hit = null
	_holding_hit_keycode = 0
	_pending_inputs.clear()

	_autoplay = Autoplay.new() if autoplay_enabled else null
	if _autoplay != null:
		_autoplay.setup(_rail_states, _note_states, playback_start_ms)

	_build_event_times()

func skip_before(time_ms: int) -> void:
	for state in _note_states:
		if state.note.time >= time_ms:
			break
		state.processed = true
		state.judgement = Score.NONE
		if state.note.length > 0:
			state.release_processed = true
			state.release_judgement = Score.NONE

	while _touch_index < _touch_states.size() and _touch_states[_touch_index].note.time < time_ms:
		_touch_index += 1
	while _long_index < _long_states.size() and _long_states[_long_index].release_processed:
		_long_index += 1

	_next_hit_index = 0
	_next_move_left_index = 0
	_next_move_right_index = 0
	_miss_index = 0

func process(target_time: int, inputs: Array[ReplayInput], exclusive: bool) -> void:
	if failed_state:
		return
	_pending_inputs.append_array(inputs)
	_pending_inputs.sort_custom(func(a: ReplayInput, b: ReplayInput) -> bool:
		if a.timing == b.timing:
			return a.order < b.order
		return a.timing < b.timing
	)

	var closed_time := target_time - 1 if exclusive else target_time
	if closed_time < last_simulated_time:
		return
	if not _pending_inputs.is_empty() and _pending_inputs[0].timing <= last_simulated_time:
		_fail("Simulation received an input at an already closed timestamp.")
		return

	var input_index := 0
	while true:
		var next_auto_time := MAX_TIME
		if _event_index < _event_times.size():
			next_auto_time = _event_times[_event_index]

		var next_input_time := MAX_TIME
		if input_index < _pending_inputs.size():
			next_input_time = _pending_inputs[input_index].timing

		var event_time := mini(next_auto_time, next_input_time)
		if event_time > closed_time:
			break

		if _autoplay != null:
			_autoplay.advance(self, event_time)

		while input_index < _pending_inputs.size() and _pending_inputs[input_index].timing == event_time:
			_handle_input(_pending_inputs[input_index], event_time)
			input_index += 1

		_update_standing_rail(event_time)
		_check_miss(event_time)
		_check_long_release_miss(event_time)
		_check_touch_notes(event_time)

		while _event_index < _event_times.size() and _event_times[_event_index] == event_time:
			_event_index += 1
		last_simulated_time = event_time

	if input_index > 0:
		_pending_inputs = _pending_inputs.slice(input_index)
	last_simulated_time = closed_time

func processed_count() -> int:
	var count := 0
	for state in _note_states:
		if state.processed:
			count += 1
	return count

func note_count() -> int:
	return _note_states.size()

func set_standing_rail(rail: Rail) -> void:
	if standing_rail == rail:
		return
	standing_rail = rail
	standing_rail_changed.emit(standing_rail)


# Public rule actions. Autoplay uses only these methods and never touches private state.
func has_hold() -> bool:
	return _holding_hit != null or _holding_move != null


func get_standing_rail() -> Rail:
	return standing_rail


func is_rail_active(rail: Rail, time: int) -> bool:
	return rail != null and time >= rail.start_time - Score.T_V2.GREAT and time <= rail.end_time


func hit(time: int) -> void:
	var keycode := int(Config.action_hit2) if _holding_hit != null else int(Config.action_hit1)
	_input_action(time, keycode)


func move(dir: Note.Dir, time: int, allow_free_movement: bool = true) -> void:
	_move_action(dir, time, allow_free_movement)


func release_note(note: Note, time: int) -> void:
	if _holding_hit != null and _holding_hit.note == note:
		_release_long_hit(time)
		return
	if _holding_move != null and _holding_move.note == note:
		_release_long_move(time)


func move_toward(target: Rail, time: int) -> bool:
	if target == null or has_hold():
		return false
	if standing_rail == target:
		return true

	if standing_rail == null:
		if not is_rail_active(target, time):
			return false
		set_standing_rail(target)
		_player.move_to_rail(target)
		return true

	var current_time := clampi(time, standing_rail.start_time, standing_rail.end_time)
	var target_time := clampi(time, target.start_time, target.end_time)
	var current_x := GameplayPlayfield.normalized_x_to_world(
		standing_rail._get_rail_x_at_time(current_time)
	)
	var target_x := GameplayPlayfield.normalized_x_to_world(
		target._get_rail_x_at_time(target_time)
	)

	if is_equal_approx(current_x, target_x):
		return false

	var dir := Note.Dir.LEFT if target_x < current_x else Note.Dir.RIGHT
	_move_player(dir, true, time)
	return standing_rail == target


func _input_action(time: int, keycode: int) -> void:
	var state := _get_next_hit_note()
	if state == null or standing_rail == null:
		_player.play_hit_animation()
		return
	if state.rail_state.rail != standing_rail:
		_player.play_hit_animation()
		return

	var gap := state.note.time - time
	var judgement := _get_judgement(gap)
	if judgement == Score.NONE:
		_player.play_hit_animation()
		return

	_process_note(state, judgement, gap)
	if state.note.length > 0:
		_holding_hit = state
		_holding_hit_keycode = keycode
		_player.set_hold_animation(true)

func _move_action(dir: Note.Dir, time: int, allow_free_movement: bool = true) -> void:
	var state := _get_next_move_note(dir)
	if state != null and state.rail_state.rail == standing_rail:
		var gap := state.note.time - time
		var judgement := _get_judgement(gap)
		if judgement != Score.NONE:
			_player.play_move_note_animation(state.note, dir)
			_process_note(state, judgement, gap)
			if state.note.length > 0:
				_holding_move = state
				_pending_move_dir = dir
				_player.set_hold_animation(true)
				return
			_move_player(dir, false, time)
			return

	if allow_free_movement:
		_move_player(dir, true, time)

func _build_event_times() -> void:
	_event_times.clear()
	if _autoplay != null:
		for time in _autoplay.event_times():
			_event_times.append(time)
	for rail_state in _rail_states:
		_event_times.append(rail_state.rail.start_time - Score.T_V2.GREAT)
		_event_times.append(rail_state.rail.end_time + 1)
	for state in _note_states:
		if state.note.type == Note.NoteType.TRACE or state.note.type == Note.NoteType.SPIKE:
			_event_times.append(state.note.time)
		elif state.note.type == Note.NoteType.HIT or state.note.type == Note.NoteType.MOVE:
			_event_times.append(state.note.time + Score.T_V2.BAD + 1)
			if state.note.length > 0:
				_event_times.append(state.note.end_time + Score.T_V2.BAD + 1)

	_event_times.sort()
	_dedupe_event_times()
	_event_index = 0
	while _event_index < _event_times.size() and _event_times[_event_index] < last_simulated_time:
		_event_index += 1

func _dedupe_event_times() -> void:
	if _event_times.size() < 2:
		return
	var write := 1
	for read in range(1, _event_times.size()):
		if _event_times[read] == _event_times[write - 1]:
			continue
		_event_times[write] = _event_times[read]
		write += 1
	_event_times.resize(write)

func _handle_input(input: ReplayInput, time: int) -> void:
	match input.type:
		ReplayInput.InputType.HIT1_DOWN:
			_input_action(time, int(Config.action_hit1))
		ReplayInput.InputType.HIT2_DOWN:
			_input_action(time, int(Config.action_hit2))
		ReplayInput.InputType.HIT1_UP:
			if _holding_hit != null and _holding_hit_keycode == int(Config.action_hit1):
				_release_long_hit(time)
		ReplayInput.InputType.HIT2_UP:
			if _holding_hit != null and _holding_hit_keycode == int(Config.action_hit2):
				_release_long_hit(time)
		ReplayInput.InputType.MOVELEFT_DOWN:
			_move_action(Note.Dir.LEFT, time, _holding_move == null and _holding_hit == null)
		ReplayInput.InputType.MOVERIGHT_DOWN:
			_move_action(Note.Dir.RIGHT, time, _holding_move == null and _holding_hit == null)
		ReplayInput.InputType.MOVELEFT_UP:
			if _holding_move != null and _pending_move_dir == Note.Dir.LEFT:
				_release_long_move(time)
		ReplayInput.InputType.MOVERIGHT_UP:
			if _holding_move != null and _pending_move_dir == Note.Dir.RIGHT:
				_release_long_move(time)

func _update_standing_rail(time: int) -> void:
	if standing_rail != null and is_rail_active(standing_rail, time):
		return
	var new_rail := _find_closest_rail(time)
	if new_rail != null and new_rail != standing_rail:
		set_standing_rail(new_rail)
		_player.move_to_rail(new_rail)

func _find_closest_rail(time: int) -> Rail:
	var current_x := 0.0
	if standing_rail != null:
		current_x = GameplayPlayfield.normalized_x_to_world(
			standing_rail._get_rail_x_at_time(mini(time, standing_rail.end_time))
		)

	var closest: Rail
	var min_dist := INF
	for state in _rail_states:
		var rail := state.rail
		if not is_rail_active(rail, time):
			continue
		var rail_x := GameplayPlayfield.normalized_x_to_world(rail._get_rail_x_at_time(time))
		var dist := absf(rail_x - current_x)
		if dist < min_dist or (is_equal_approx(dist, min_dist) and (closest == null or rail.id < closest.id)):
			min_dist = dist
			closest = rail
	return closest

func _find_nearest_rail(dir: Note.Dir, time: int) -> Rail:
	var current_x := GameplayPlayfield.normalized_x_to_world(
		standing_rail._get_rail_x_at_time(time) if standing_rail != null else 0.5
	)
	var best: Rail
	var min_dist := INF
	for state in _rail_states:
		var rail := state.rail
		if rail == standing_rail or not is_rail_active(rail, time):
			continue
		var rail_x := GameplayPlayfield.normalized_x_to_world(rail._get_rail_x_at_time(time))
		var delta_x := rail_x - current_x
		var in_dir := (dir == Note.Dir.LEFT and delta_x < 0.0) or (dir == Note.Dir.RIGHT and delta_x > 0.0)
		if not in_dir:
			continue
		var dist := absf(delta_x)
		if dist < min_dist or (is_equal_approx(dist, min_dist) and (best == null or rail.id < best.id)):
			min_dist = dist
			best = rail
	return best

func _move_player(dir: Note.Dir, play_animation: bool, time: int) -> void:
	if _holding_hit != null or _holding_move != null:
		return
	var rail := _find_nearest_rail(dir, time)
	if rail == null:
		return

	var previous_rail := standing_rail
	if previous_rail != null and previous_rail != rail:
		_miss_past_notes_on_rail(previous_rail, time)

	set_standing_rail(rail)
	_player.move_to_rail(rail, play_animation)

func _check_miss(time: int) -> void:
	while _miss_index < _note_states.size():
		var state := _note_states[_miss_index]
		if state.processed or (state.note.type != Note.NoteType.HIT and state.note.type != Note.NoteType.MOVE):
			_miss_index += 1
			continue

		var gap := state.note.time - time
		if gap >= -Score.T_V2.BAD:
			break

		_process_note(state, Score.MISS, gap)
		_miss_index += 1

func _check_long_release_miss(time: int) -> void:
	while _long_index < _long_states.size():
		var state := _long_states[_long_index]
		if state.release_processed:
			_long_index += 1
			continue
		if time <= state.note.end_time + Score.T_V2.BAD:
			break
		_process_release(state, Score.MISS, float(state.note.end_time) - time)
		_clear_hold(state)
		_long_index += 1

func _check_touch_notes(time: int) -> void:
	while _touch_index < _touch_states.size():
		var state := _touch_states[_touch_index]
		if state.processed:
			_touch_index += 1
			continue
		var gap := state.note.time - time
		if gap > 0:
			break

		match state.note.type:
			Note.NoteType.TRACE:
				_process_note(
					state,
					Score.PERFECT_PLUS if standing_rail == state.rail_state.rail else Score.MISS,
					gap
				)
			Note.NoteType.SPIKE:
				if standing_rail == state.rail_state.rail:
					_process_note(state, Score.MISS, gap)
				else:
					state.processed = true
					state.judgement = Score.NONE
					score.add_spike_dodge(state.note)
					_increment_combo(true)
					spike_dodged.emit(state)
		_touch_index += 1

func _release_long_hit(time: int) -> void:
	var state := _holding_hit
	_clear_hold(state)
	_judge_release(state, time)
	if state != null:
		_player.play_hit_animation()

func _release_long_move(time: int) -> void:
	var state := _holding_move
	var dir := _pending_move_dir
	_clear_hold(state)
	_judge_release(state, time)
	_move_player(dir, false, time)
	if state != null:
		_player.play_hit_animation()

func _judge_release(state: GameplayNoteState, time: int) -> void:
	if state == null or state.release_processed:
		return
	var gap := float(state.note.end_time) - time
	var judgement := _get_judgement(gap)
	if judgement == Score.NONE:
		judgement = Score.MISS
	_process_release(state, judgement, gap)

func _clear_hold(state: GameplayNoteState) -> void:
	if state == _holding_hit:
		_holding_hit = null
		_holding_hit_keycode = 0
	if state == _holding_move:
		_holding_move = null
		_pending_move_dir = Note.Dir.NONE
	_player.set_hold_animation(_holding_hit != null or _holding_move != null)

func _get_next_hit_note() -> GameplayNoteState:
	while _next_hit_index < _note_states.size():
		var state := _note_states[_next_hit_index]
		if state.processed or state.note.type != Note.NoteType.HIT:
			_next_hit_index += 1
			continue
		return state
	return null


func _get_next_move_note(dir: Note.Dir) -> GameplayNoteState:
	var index := _next_move_left_index if dir == Note.Dir.LEFT else _next_move_right_index
	while index < _note_states.size():
		var state := _note_states[index]
		if state.processed or state.note.type != Note.NoteType.MOVE or state.note.dir != dir:
			index += 1
			continue
		if dir == Note.Dir.LEFT:
			_next_move_left_index = index
		else:
			_next_move_right_index = index
		return state

	if dir == Note.Dir.LEFT:
		_next_move_left_index = index
	else:
		_next_move_right_index = index
	return null


func _miss_past_notes_on_rail(rail: Rail, time: int) -> void:
	for index in range(_miss_index, _note_states.size()):
		var state := _note_states[index]
		if state.note.time >= time:
			break
		if state.processed:
			continue
		if state.note.type != Note.NoteType.HIT and state.note.type != Note.NoteType.MOVE:
			continue
		if state.rail_state.rail != rail:
			continue
		_process_note(state, Score.MISS, state.note.time - time)


func _get_judgement(gap: float) -> int:
	var absolute := absf(gap)
	if absolute <= Score.T_V2.PERFECT_PLUS:
		return Score.PERFECT_PLUS
	if absolute <= Score.T_V2.PERFECT:
		return Score.PERFECT
	if absolute <= Score.T_V2.GREAT:
		return Score.GREAT
	if absolute <= Score.T_V2.OK:
		return Score.OK
	if absolute <= Score.T_V2.BAD:
		return Score.BAD
	return Score.NONE


func _process_note(state: GameplayNoteState, judgement: int, gap: float) -> void:
	state.processed = true
	state.judgement = judgement
	_apply_judgement(state, judgement, gap, false)

func _process_release(state: GameplayNoteState, judgement: int, gap: float) -> void:
	if state == null or state.release_processed:
		return
	state.release_processed = true
	state.release_judgement = judgement
	_apply_judgement(state, judgement, gap, true)

func _apply_judgement(state: GameplayNoteState, judgement: int, gap: float, is_release: bool) -> void:
	score.add_note_result(state.note, judgement, gap)
	if judgement == Score.MISS:
		combo = 0
		combo_changed.emit(combo, false)
	elif judgement != Score.NONE:
		_increment_combo(true)
	note_judged.emit(state, judgement, gap, is_release)

func _increment_combo(pop: bool) -> void:
	combo += 1
	score.high_combo = maxi(score.high_combo, combo)
	combo_changed.emit(combo, pop)

func _fail(message: String) -> void:
	failed_state = true
	failed.emit(message)
