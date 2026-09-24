extends RefCounted
class_name Autoplay


enum Action {
	RELEASE,
	PREPARE,
	NOTES,
}


class Group extends RefCounted:
	var time: int
	var entries: Array[GameplayNoteState] = []

	func _init(at: int) -> void:
		time = at


class Event extends RefCounted:
	var time: int
	var action: Action
	var entries: Array[GameplayNoteState]
	var target: Rail
	var note_time: int

	func _init(
		at: int,
		kind: Action,
		items: Array[GameplayNoteState],
		rail: Rail = null,
		due: int = 0,
	) -> void:
		time = at
		action = kind
		entries = items
		target = rail
		note_time = due


var events: Array[Event] = []

var _index := 0
var _rails: Array[Rail] = []


func setup(
	rail_states: Array[GameplayRailState],
	note_states: Array[GameplayNoteState],
	start_time: int = 0,
) -> void:
	events.clear()
	_index = 0
	_rails.clear()

	for rail_state in rail_states:
		_rails.append(rail_state.rail)

	var groups := _build_groups(note_states, start_time)
	var releases := _build_releases(note_states, start_time)
	var boundaries := _build_boundaries(groups, releases)

	var group_index := 0
	var release_index := 0
	var previous_time := start_time
	var planned_rail: Rail = null

	for time in boundaries:
		var release_entries: Array[GameplayNoteState] = []
		while release_index < releases.size() and releases[release_index].note.end_time == time:
			release_entries.append(releases[release_index])
			release_index += 1

		if not release_entries.is_empty():
			events.append(Event.new(time, Action.RELEASE, release_entries))

		if group_index < groups.size() and groups[group_index].time == time:
			var group := groups[group_index]
			var target := _required_rail(group.entries)

			if planned_rail == null:
				planned_rail = _default_rail(time)

			if target == null:
				target = _safe_rail_from(planned_rail, group.entries, time)

			_add_prepare_steps(
				planned_rail,
				target,
				group.entries,
				previous_time,
				time,
				start_time,
			)

			events.append(
				Event.new(
					time,
					Action.NOTES,
					group.entries,
					target,
					time,
				)
			)

			if target != null:
				planned_rail = target

			group_index += 1

		previous_time = time

	events.sort_custom(_sort_events)


func event_times() -> Array[int]:
	var times: Array[int] = []
	for event in events:
		times.append(event.time)
	return times


func advance(gameplay: GameRule, time: int) -> void:
	while _index < events.size() and events[_index].time <= time:
		var event := events[_index]
		_index += 1

		match event.action:
			Action.RELEASE:
				for state in event.entries:
					gameplay.release_note(state.note, event.time)

			Action.PREPARE:
				_prepare(gameplay, event)

			Action.NOTES:
				# Normally all movement is already done by PREPARE events.
				# This gives one last legal movement if the rail layout changed.
				_prepare(gameplay, event)

				for state in event.entries:
					match state.note.type:
						Note.NoteType.HIT:
							gameplay.hit(event.time)

						Note.NoteType.MOVE:
							gameplay.move(state.note.dir, event.time, false)


func _build_groups(
	note_states: Array[GameplayNoteState],
	start_time: int,
) -> Array[Group]:
	var groups: Array[Group] = []
	var current: Group = null

	for state in note_states:
		var note := state.note
		if note.type == Note.NoteType.NONE or note.time < start_time:
			continue

		if current == null or current.time != note.time:
			current = Group.new(note.time)
			groups.append(current)

		current.entries.append(state)

	return groups


func _build_releases(
	note_states: Array[GameplayNoteState],
	start_time: int,
) -> Array[GameplayNoteState]:
	var releases: Array[GameplayNoteState] = []

	for state in note_states:
		var note := state.note
		if note.time < start_time or note.length <= 0:
			continue
		if note.type != Note.NoteType.HIT and note.type != Note.NoteType.MOVE:
			continue
		if note.end_time < start_time:
			continue
		releases.append(state)

	releases.sort_custom(func(a: GameplayNoteState, b: GameplayNoteState) -> bool:
		if a.note.end_time == b.note.end_time:
			return a.order < b.order
		return a.note.end_time < b.note.end_time
	)

	return releases


func _build_boundaries(
	groups: Array[Group],
	releases: Array[GameplayNoteState],
) -> Array[int]:
	var times: Array[int] = []

	for group in groups:
		times.append(group.time)

	for state in releases:
		times.append(state.note.end_time)

	times.sort()
	_dedupe_times(times)
	return times


func _dedupe_times(times: Array[int]) -> void:
	if times.size() < 2:
		return

	var write := 1
	for read in range(1, times.size()):
		if times[read] == times[write - 1]:
			continue
		times[write] = times[read]
		write += 1

	times.resize(write)


func _add_prepare_steps(
	from: Rail,
	target: Rail,
	entries: Array[GameplayNoteState],
	from_time: int,
	note_time: int,
	start_time: int,
) -> void:
	var move_count := _count_moves(from, target, note_time)
	if move_count <= 0:
		return

	var begin := maxi(from_time, start_time)
	var duration := note_time - begin
	if duration <= 1:
		return

	var last_time := begin - 1

	for index in range(move_count):
		var ratio := float(index + 1) / float(move_count + 1)
		var move_time := begin + roundi(float(duration) * ratio)

		if index == move_count - 1 and target != null:
			move_time = maxi(move_time, target.start_time - Score.T.GREAT)

		move_time = maxi(move_time, last_time + 1)
		move_time = mini(move_time, note_time - 1)

		if move_time <= last_time:
			break

		events.append(
			Event.new(
				move_time,
				Action.PREPARE,
				entries,
				target,
				note_time,
			)
		)
		last_time = move_time


func _count_moves(from: Rail, target: Rail, time: int) -> int:
	if target == null:
		return 0
	if from == target:
		return 0

	var rails := _active_rails(time)
	if not rails.has(target):
		rails.append(target)

	_sort_rails_by_x(rails, time)

	var target_index := rails.find(target)
	if target_index < 0:
		return 1

	var from_index := rails.find(from) if from != null else -1
	if from_index < 0:
		var from_x := 0.5
		if from != null:
			from_x = _rail_x(from, time)
		from_index = _closest_rail_index(rails, from_x, time)

	if from_index < 0:
		return 1

	return absi(target_index - from_index)


func _active_rails(time: int) -> Array[Rail]:
	var result: Array[Rail] = []
	for rail in _rails:
		if _rail_active(rail, time):
			result.append(rail)
	return result


func _sort_rails_by_x(rails: Array[Rail], time: int) -> void:
	rails.sort_custom(func(a: Rail, b: Rail) -> bool:
		var a_x := _rail_x(a, time)
		var b_x := _rail_x(b, time)
		if is_equal_approx(a_x, b_x):
			return a.id < b.id
		return a_x < b_x
	)


func _closest_rail_index(
	rails: Array[Rail],
	x: float,
	time: int,
) -> int:
	var best_index := -1
	var best_distance := INF

	for index in range(rails.size()):
		var distance := absf(_rail_x(rails[index], time) - x)
		if distance < best_distance:
			best_index = index
			best_distance = distance

	return best_index


func _required_rail(entries: Array[GameplayNoteState]) -> Rail:
	for state in entries:
		if state.note.type == Note.NoteType.HIT or state.note.type == Note.NoteType.MOVE:
			return state.rail_state.rail

	for state in entries:
		if state.note.type == Note.NoteType.TRACE:
			return state.rail_state.rail

	return null


func _prepare(gameplay: GameRule, event: Event) -> void:
	if gameplay.has_hold():
		return

	var target := event.target
	if target == null:
		target = _safe_rail(gameplay, event)

	if target == null:
		return

	gameplay.move_toward(target, event.time)


func _safe_rail(gameplay: GameRule, event: Event) -> Rail:
	var current := gameplay.get_standing_rail()
	var forbidden := _forbidden_rails(event.entries)

	if (
		current != null
		and not forbidden.has(current)
		and current.end_time >= event.note_time
	):
		return current

	var current_x := _rail_x(current, event.time) if current != null else 0.5
	var nearest: Rail = null
	var distance := INF

	for rail in _rails:
		if forbidden.has(rail):
			continue
		if rail.end_time < event.note_time:
			continue
		if not gameplay.is_rail_active(rail, event.time):
			continue

		var gap := absf(_rail_x(rail, event.time) - current_x)
		if gap < distance:
			nearest = rail
			distance = gap

	return nearest


func _safe_rail_from(
	current: Rail,
	entries: Array[GameplayNoteState],
	time: int,
) -> Rail:
	var forbidden := _forbidden_rails(entries)

	if current != null and not forbidden.has(current) and current.end_time >= time:
		return current

	var current_x := _rail_x(current, time) if current != null else 0.5
	var nearest: Rail = null
	var distance := INF

	for rail in _rails:
		if forbidden.has(rail):
			continue
		if rail.end_time < time:
			continue
		if not _rail_active(rail, time):
			continue

		var gap := absf(_rail_x(rail, time) - current_x)
		if gap < distance:
			nearest = rail
			distance = gap

	return nearest


func _forbidden_rails(entries: Array[GameplayNoteState]) -> Array[Rail]:
	var result: Array[Rail] = []
	for state in entries:
		if state.note.type == Note.NoteType.SPIKE:
			result.append(state.rail_state.rail)
	return result


func _default_rail(time: int) -> Rail:
	var best: Rail = null
	var distance := INF

	for rail in _rails:
		if not _rail_active(rail, time):
			continue

		var gap := absf(_rail_x(rail, time) - 0.5)
		if gap < distance:
			best = rail
			distance = gap

	return best


func _rail_active(rail: Rail, time: int) -> bool:
	return time >= rail.start_time - Score.T.GREAT and time <= rail.end_time


func _rail_x(rail: Rail, time: int) -> float:
	if rail == null:
		return 0.5
	return rail._get_rail_x_at_time(clampi(time, rail.start_time, rail.end_time))


func _sort_events(a: Event, b: Event) -> bool:
	if a.time == b.time:
		return a.action < b.action
	return a.time < b.time
