extends RefCounted
class_name Rating

class OccupancyState extends RefCounted:
	var occupied_rail_id: int = -1
	var free_x: float = 0.0


const SEGMENT_DURATION_MS := 3000
const POWER := 9.0
const WEIGHT := 3.2
const CACHE_VERSION := 1

const SPEED_CONTRIBUTION := 0.55
const READING_CONTRIBUTION := 0.45
const READING_FULL_COMPLEXITY := 0.4
const KEY_COMFORT_IPS := 7.0
const KEY_BURDEN_CONTRIBUTION := 0.35
const MAX_KEY_BURDEN := 1.5

const HIGH_RATING_START := 30.0
const HIGH_RATING_SCALE := 20.0
const HIGH_RATING_INITIAL_SLOPE := 0.6

const HIT_NOTE_INPUT_WEIGHT := 1.0
const MOVE_NOTE_INPUT_WEIGHT := 1.1
const TRACE_NOTE_INPUT_WEIGHT := 0.3
const HIDDEN_MOVE_INPUT_WEIGHT := 1.2

static func get_color_from_rating(value: float,fade: bool = false) -> Color:

	var color_map = {
		0: Color("9ca3eb"),
		5: Color("374cd0"),
		10: Color("91cc53"),
		15: Color("d1bd28"),
		20: Color("ee5c3c"),
		25: Color("ad232d"),
		30: Color("845696"), 
		35: Color("483f7d"),
	}
	var keys = color_map.keys()
	keys.sort()

	if value <= keys[0]:
		return color_map[keys[0]]
	if value >= keys[-1]:
		return color_map[keys[-1]]
	
	for i in range(keys.size() - 1):
		var a = keys[i]
		var b = keys[i + 1]
		if fade:
			if value >= a and value <= b:
				var t = (value - a) / float(b - a)
				return color_map[a].lerp(color_map[b], t)
		else:
			if value >= a and value < b:
				return color_map[a]
	return color_map[keys[0]]

static func calculate_rating(chart: ParsedChart) -> float:
	if chart == null:
		return 0.0

	var notes: Array[Note] = chart.get_notes()
	var rails: Array[Rail] = chart.rails.duplicate()

	if notes.is_empty() or rails.is_empty():
		return 0.0

	notes.sort_custom(func(a, b): return a.time < b.time)

	var start_time := _get_first_note_time(notes)
	var end_time := _get_last_relevant_time(notes, rails)

	if end_time <= start_time:
		return 0.0

	@warning_ignore("integer_division")
	var segment_count := int((end_time - start_time) / SEGMENT_DURATION_MS) + 1
	var segments: Array[float] = []
	segments.resize(segment_count)
	for i in range(segment_count):
		segments[i] = 0.0

	var notes_by_time := _group_notes_by_time(notes)
	var note_owner_by_note := _build_note_owner_by_note(rails)
	var reading_complexity := _calculate_reading_complexity(notes, note_owner_by_note)
	var key_segments := _create_key_segments(segment_count)
	var hit_key_totals := [0.0, 0.0]
	var event_times := _build_event_times(notes, rails)
	if event_times.is_empty():
		return 0.0

	var state := OccupancyState.new()

	for time_ms in event_times:
		_resolve_occupancy_at_time(state, rails, time_ms)

		if notes_by_time.has(time_ms):
			_process_notes_at_time(
				state,
				rails,
				note_owner_by_note,
				time_ms,
				notes_by_time[time_ms],
				segments,
				start_time,
				key_segments,
				hit_key_totals
			)

	var key_peak_ips := _calculate_key_peak_ips(key_segments)
	var weighted_power_sum := 0.0
	var total_input_weight := 0.0
	var segment_duration_seconds := SEGMENT_DURATION_MS / 1000.0

	for input_count in segments:
		if input_count <= 0.0:
			continue
		var ips := input_count / segment_duration_seconds
		weighted_power_sum += input_count * pow(ips, POWER)
		total_input_weight += input_count

	if total_input_weight <= 0.0:
		return 0.0

	var mean := pow(weighted_power_sum / total_input_weight, 1.0 / POWER)
	var reading_ratio := clampf(reading_complexity / READING_FULL_COMPLEXITY, 0.0, 1.0)
	var key_burden := clampf((key_peak_ips / KEY_COMFORT_IPS) - 1.0, 0.0, MAX_KEY_BURDEN)
	var difficulty_multiplier := (
		SPEED_CONTRIBUTION
		+ READING_CONTRIBUTION * reading_ratio
		+ KEY_BURDEN_CONTRIBUTION * key_burden
	)
	var raw_rating := mean * WEIGHT * difficulty_multiplier
	return _apply_rating_curve(raw_rating)


static func _apply_rating_curve(raw_rating: float) -> float:
	if raw_rating <= 0.0:
		return 0.0
	if raw_rating <= HIGH_RATING_START:
		return raw_rating

	var high_delta := raw_rating - HIGH_RATING_START
	return HIGH_RATING_START + HIGH_RATING_SCALE * log(
		1.0 + HIGH_RATING_INITIAL_SLOPE * high_delta / HIGH_RATING_SCALE
	)

static func _get_first_note_time(notes: Array[Note]) -> int:
	if notes.is_empty():
		return 0
	return int(notes[0].time)


static func _get_last_relevant_time(notes: Array[Note], rails: Array[Rail]) -> int:
	var last_time := 0

	for note in notes:
		last_time = max(last_time, int(note.time))
		last_time = max(last_time, note.end_time)

	for rail in rails:
		if rail == null:
			continue
		if rail.points.is_empty():
			continue
		last_time = max(last_time, int(rail.points[rail.points.size() - 1].time))

	return last_time


static func _group_notes_by_time(notes: Array[Note]) -> Dictionary:
	var result := {}

	for note in notes:
		var time_ms := int(note.time)
		if not result.has(time_ms):
			result[time_ms] = []
		result[time_ms].append(note)

	return result


static func _build_note_owner_by_note(rails: Array[Rail]) -> Dictionary:
	var result := {}

	for rail in rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note != null:
				result[note] = rail

	return result


static func _calculate_reading_complexity(
	notes: Array[Note],
	note_owner_by_note: Dictionary
) -> float:
	var tokens: Array[String] = []
	var novel_count := 0

	for note in notes:
		if note == null:
			continue
		var owner_rail: Rail = note_owner_by_note.get(note)
		if owner_rail == null:
			continue

		var token := "%d:%d:%d" % [int(note.type), int(note.dir), int(owner_rail.id)]
		if (
			tokens.size() >= 2
			and token != tokens[tokens.size() - 1]
			and token != tokens[tokens.size() - 2]
		):
			novel_count += 1
		tokens.append(token)

	if tokens.size() <= 2:
		return 0.0
	return float(novel_count) / float(tokens.size() - 2)


static func _create_key_segments(segment_count: int) -> Array:
	var key_segments: Array = []
	key_segments.resize(segment_count)
	for i in range(segment_count):
		key_segments[i] = [0.0, 0.0, 0.0, 0.0]
	return key_segments


static func _calculate_key_peak_ips(key_segments: Array) -> float:
	var peak_ips := 0.0
	var segment_duration_seconds := SEGMENT_DURATION_MS / 1000.0
	for key_loads in key_segments:
		for key_load in key_loads:
			peak_ips = maxf(peak_ips, float(key_load) / segment_duration_seconds)
	return peak_ips


static func _add_key_inputs_at_time(
	key_segments: Array,
	start_time: int,
	time_ms: int,
	key_index: int,
	amount: float
) -> void:
	if amount <= 0.0 or key_index < 0 or key_index >= 4:
		return
	@warning_ignore("integer_division")
	var segment_index := int((time_ms - start_time) / SEGMENT_DURATION_MS)
	if segment_index < 0 or segment_index >= key_segments.size():
		return
	key_segments[segment_index][key_index] += amount


static func _add_note_key_input(
	note: Note,
	key_segments: Array,
	hit_key_totals: Array,
	start_time: int,
	time_ms: int
) -> void:
	if note == null:
		return
	match note.type:
		Note.NoteType.HIT:
			var hit_key_index := 0 if hit_key_totals[0] <= hit_key_totals[1] else 1
			hit_key_totals[hit_key_index] += HIT_NOTE_INPUT_WEIGHT
			_add_key_inputs_at_time(
				key_segments,
				start_time,
				time_ms,
				2 + hit_key_index,
				HIT_NOTE_INPUT_WEIGHT
			)
		Note.NoteType.MOVE:
			var move_key_index := -1
			if note.dir == Note.Dir.LEFT:
				move_key_index = 0
			elif note.dir == Note.Dir.RIGHT:
				move_key_index = 1
			_add_key_inputs_at_time(
				key_segments,
				start_time,
				time_ms,
				move_key_index,
				MOVE_NOTE_INPUT_WEIGHT
			)


static func _build_event_times(notes: Array[Note], rails: Array[Rail]) -> Array[int]:
	var time_map := {}

	for note in notes:
		time_map[int(note.time)] = true

	for rail in rails:
		if rail == null:
			continue
		if rail.points.is_empty():
			continue

		var start_time := int(rail.points[0].time)
		var end_time := int(rail.points[rail.points.size() - 1].time)

		time_map[start_time] = true
		time_map[end_time] = true

	var result: Array[int] = []
	for key in time_map.keys():
		result.append(int(key))

	result.sort()
	return result

static func _resolve_occupancy_at_time(state: OccupancyState, rails: Array[Rail], time_ms: int) -> void:
	var occupied_rail_id := int(state.occupied_rail_id)
	var active_rails := _get_sorted_active_rails_at_time(rails, time_ms)

	if occupied_rail_id != -1:
		var occupied_rail = _find_rail_by_id(rails, occupied_rail_id)

		if occupied_rail != null and _is_rail_active_at_time(occupied_rail, time_ms):
			state.free_x = occupied_rail._get_rail_x_at_time(time_ms)
			return

		if occupied_rail != null:
			var last_time :int = occupied_rail.end_time
			state.free_x = occupied_rail._get_rail_x_at_time(last_time)

		state.occupied_rail_id = -1
		occupied_rail_id = -1

	if occupied_rail_id == -1 and not active_rails.is_empty():
		var target_rail = _find_closest_rail_by_x(active_rails, float(state.free_x), time_ms)
		if target_rail != null:
			state.occupied_rail_id = int(target_rail.id)
			state.free_x = target_rail._get_rail_x_at_time(time_ms)


static func _process_notes_at_time(
	state: OccupancyState,
	rails: Array[Rail],
	note_owner_by_note: Dictionary,
	time_ms: int,
	note_group: Array,
	segments: Array[float],
	start_time: int,
	key_segments: Array,
	hit_key_totals: Array
) -> void:
	var active_rails := _get_sorted_active_rails_at_time(rails, time_ms)
	if active_rails.is_empty():
		return

	var blocked_rail_ids := {}
	var playable_notes: Array = []

	for note in note_group:
		var owner_rail: Rail = note_owner_by_note.get(note)
		if owner_rail == null:
			continue
		var rail_id := int(owner_rail.id)
		if note.type == Note.NoteType.SPIKE:
			blocked_rail_ids[rail_id] = true
		else:
			playable_notes.append(note)

	if int(state.occupied_rail_id) == -1:
		var auto_rail = _find_closest_rail_by_x(active_rails, float(state.free_x), time_ms)
		if auto_rail != null:
			state.occupied_rail_id = int(auto_rail.id)
			state.free_x = auto_rail._get_rail_x_at_time(time_ms)

	var occupied_rail_id := int(state.occupied_rail_id)

	if not playable_notes.is_empty():
		var candidate_targets := _collect_unique_playable_target_rails(
			playable_notes,
			note_owner_by_note,
			blocked_rail_ids
		)

		if candidate_targets.is_empty():
			return

		var best_target_rail_id := _choose_best_target_rail(
			occupied_rail_id,
			candidate_targets,
			active_rails,
			time_ms
		)

		if best_target_rail_id == -1:
			return

		var hidden_move_steps := _get_required_move_inputs_by_order(
			occupied_rail_id,
			best_target_rail_id,
			active_rails
		)

		_add_inputs_at_time(
			segments,
			start_time,
			time_ms,
			float(hidden_move_steps) * HIDDEN_MOVE_INPUT_WEIGHT
		)
		_add_key_inputs_at_time(
			key_segments,
			start_time,
			time_ms,
			_get_move_key_index_by_order(
				occupied_rail_id,
				best_target_rail_id,
				active_rails
			),
			float(hidden_move_steps) * HIDDEN_MOVE_INPUT_WEIGHT
		)

		var note_input_weight := 0.0
		var move_note: Note = null
		for note in playable_notes:
			var owner_rail: Rail = note_owner_by_note.get(note)
			if owner_rail != null and int(owner_rail.id) == best_target_rail_id:
				note_input_weight += _get_note_input_weight(note)
				_add_note_key_input(note, key_segments, hit_key_totals, start_time, time_ms)
				if move_note == null and note.type == Note.NoteType.MOVE:
					move_note = note

		_add_inputs_at_time(segments, start_time, time_ms, note_input_weight)

		state.occupied_rail_id = best_target_rail_id
		var target_rail = _find_rail_by_id(rails, best_target_rail_id)
		if target_rail != null:
			state.free_x = target_rail._get_rail_x_at_time(time_ms)

		if move_note != null:
			var move_target := _find_nearest_rail_in_direction(
				active_rails,
				best_target_rail_id,
				move_note.dir,
				time_ms
			)
			if move_target != null:
				state.occupied_rail_id = int(move_target.id)
				state.free_x = move_target._get_rail_x_at_time(time_ms)

		return

	if occupied_rail_id != -1 and blocked_rail_ids.has(occupied_rail_id):
		var safe_target_rail_id := _choose_nearest_safe_rail(
			occupied_rail_id,
			active_rails,
			blocked_rail_ids
		)

		if safe_target_rail_id != -1:
			var evade_steps := _get_required_move_inputs_by_order(
				occupied_rail_id,
				safe_target_rail_id,
				active_rails
			)

			_add_inputs_at_time(
				segments,
				start_time,
				time_ms,
				float(evade_steps) * HIDDEN_MOVE_INPUT_WEIGHT
			)
			_add_key_inputs_at_time(
				key_segments,
				start_time,
				time_ms,
				_get_move_key_index_by_order(
					occupied_rail_id,
					safe_target_rail_id,
					active_rails
				),
				float(evade_steps) * HIDDEN_MOVE_INPUT_WEIGHT
			)

			state.occupied_rail_id = safe_target_rail_id
			var safe_rail: Rail = _find_rail_by_id(rails, safe_target_rail_id)
			if safe_rail != null:
				state.free_x = safe_rail._get_rail_x_at_time(time_ms)

static func _collect_unique_playable_target_rails(
	playable_notes: Array,
	note_owner_by_note: Dictionary,
	blocked_rail_ids: Dictionary
) -> Array[int]:
	var result: Array[int] = []
	var seen := {}

	for note in playable_notes:
		var owner_rail: Rail = note_owner_by_note.get(note)
		if owner_rail == null:
			continue
		var rail_id := int(owner_rail.id)
		if blocked_rail_ids.has(rail_id):
			continue
		if seen.has(rail_id):
			continue
		seen[rail_id] = true
		result.append(rail_id)

	return result


static func _choose_best_target_rail(
	occupied_rail_id: int,
	candidate_targets: Array[int],
	active_rails: Array,
	_time_ms: int
) -> int:
	if candidate_targets.is_empty():
		return -1

	if occupied_rail_id == -1:
		return candidate_targets[0]

	var best_target := -1
	var best_cost := INF

	for rail_id in candidate_targets:
		var cost := _get_required_move_inputs_by_order(occupied_rail_id, rail_id, active_rails)
		if cost < best_cost:
			best_cost = cost
			best_target = rail_id

	return best_target


static func _choose_nearest_safe_rail(
	occupied_rail_id: int,
	active_rails: Array,
	blocked_rail_ids: Dictionary
) -> int:
	var current_index := _get_rail_index_in_sorted_active(active_rails, occupied_rail_id)
	if current_index == -1:
		return -1

	var best_rail_id := -1
	var best_cost := INF

	for i in range(active_rails.size()):
		var rail_id := int(active_rails[i].id)
		if rail_id == occupied_rail_id:
			continue
		if blocked_rail_ids.has(rail_id):
			continue

		var cost = abs(i - current_index)
		if cost < best_cost:
			best_cost = cost
			best_rail_id = rail_id

	return best_rail_id


static func _get_required_move_inputs_by_order(
	current_rail_id: int,
	target_rail_id: int,
	active_rails: Array
) -> int:
	if current_rail_id == target_rail_id:
		return 0

	var current_index := _get_rail_index_in_sorted_active(active_rails, current_rail_id)
	var target_index := _get_rail_index_in_sorted_active(active_rails, target_rail_id)

	if current_index == -1 or target_index == -1:
		return 0

	return abs(target_index - current_index)


static func _get_move_key_index_by_order(
	current_rail_id: int,
	target_rail_id: int,
	active_rails: Array
) -> int:
	var current_index := _get_rail_index_in_sorted_active(active_rails, current_rail_id)
	var target_index := _get_rail_index_in_sorted_active(active_rails, target_rail_id)
	if current_index == -1 or target_index == -1 or current_index == target_index:
		return -1
	return 0 if target_index < current_index else 1


static func _get_note_input_weight(note: Note) -> float:
	if note == null:
		return 0.0

	match note.type:
		Note.NoteType.HIT:
			return HIT_NOTE_INPUT_WEIGHT
		Note.NoteType.MOVE:
			return MOVE_NOTE_INPUT_WEIGHT
		Note.NoteType.TRACE:
			return TRACE_NOTE_INPUT_WEIGHT
		_:
			return 0.0


static func _find_nearest_rail_in_direction(
	active_rails: Array[Rail],
	current_rail_id: int,
	dir: Note.Dir,
	time_ms: int
) -> Rail:
	var current_rail := _find_rail_by_id(active_rails, current_rail_id)
	if current_rail == null:
		return null

	var current_x := current_rail._get_rail_x_at_time(time_ms)
	var nearest_rail: Rail = null
	var nearest_distance := INF

	for rail in active_rails:
		if rail == current_rail:
			continue

		var delta_x := rail._get_rail_x_at_time(time_ms) - current_x
		var is_in_direction := (
			(dir == Note.Dir.LEFT and delta_x < 0.0)
			or (dir == Note.Dir.RIGHT and delta_x > 0.0)
		)
		if not is_in_direction:
			continue

		var distance := absf(delta_x)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_rail = rail

	return nearest_rail


static func _get_rail_index_in_sorted_active(active_rails: Array[Rail], rail_id: int) -> int:
	for i in range(active_rails.size()):
		if int(active_rails[i].id) == rail_id:
			return i
	return -1


static func _get_sorted_active_rails_at_time(rails: Array[Rail], time_ms: int) -> Array[Rail]:
	var active :Array[Rail]= []

	for rail in rails:
		if rail == null:
			continue
		if _is_rail_active_at_time(rail, time_ms):
			active.append(rail)

	active.sort_custom(func(a:Rail, b:Rail):
		var ax = a._get_rail_x_at_time(time_ms)
		var bx = b._get_rail_x_at_time(time_ms)

		if is_equal_approx(ax, bx):
			return int(a.id) < int(b.id)

		return ax < bx
	)

	return active


static func _is_rail_active_at_time(rail: Rail, time_ms: int) -> bool:
	if rail == null:
		return false
	if rail.points.is_empty():
		return false

	var start_time := rail.start_time
	var end_time := rail.end_time

	return time_ms >= start_time and time_ms <= end_time

static func _find_rail_by_id(rails: Array[Rail], rail_id: int) -> Rail:
	for rail in rails:
		if rail == null:
			continue
		if int(rail.id) == rail_id:
			return rail
	return null


static func _find_closest_rail_by_x(active_rails: Array[Rail], x: float, time_ms: int) -> Rail:
	var best_rail = null
	var best_dist := INF

	for rail in active_rails:
		var rail_x :float = rail._get_rail_x_at_time(time_ms)
		var dist = abs(rail_x - x)

		if dist < best_dist:
			best_dist = dist
			best_rail = rail

	return best_rail

static func _add_inputs_at_time(
	segments: Array[float],
	start_time: int,
	time_ms: int,
	amount: float
) -> void:
	if amount <= 0.0:
		return

	@warning_ignore("integer_division")
	var seg_index := int((time_ms - start_time) / SEGMENT_DURATION_MS)
	if seg_index < 0 or seg_index >= segments.size():
		return

	segments[seg_index] += amount
