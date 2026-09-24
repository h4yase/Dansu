extends RefCounted
class_name ObjectSpawner

const NOTE_SCENE := preload("res://scenes/gameplay/note.tscn")
const RAIL_SCENE := preload("res://scenes/gameplay/rail.tscn")

var rail_states: Array[GameplayRailState] = []
var note_states: Array[GameplayNoteState] = []
var touch_states: Array[GameplayNoteState] = []
var long_states: Array[GameplayNoteState] = []

var _chart
var _rail_container: Node3D
var _rail_spawn_index := 0
var _note_spawn_index := 0
var _rail_color := GameRail.DEFAULT_ACCENT_COLOR

func setup(chart, rail_container: Node3D) -> void:
	_chart = chart
	_rail_container = rail_container

func build() -> void:
	clear_nodes()
	rail_states.clear()
	note_states.clear()
	touch_states.clear()
	long_states.clear()
	_rail_spawn_index = 0
	_note_spawn_index = 0

	for rail in _chart.rails:
		if rail == null or rail.points.is_empty():
			continue
		rail.sort_points()
		rail_states.append(GameplayRailState.new(rail, rail_states.size()))

	rail_states.sort_custom(func(a: GameplayRailState, b: GameplayRailState) -> bool:
		if a.rail.points[0].time == b.rail.points[0].time:
			return a.rail.id < b.rail.id
		return a.rail.points[0].time < b.rail.points[0].time
	)
	for index in range(rail_states.size()):
		rail_states[index].order = index

	for rail_state in rail_states:
		for note in rail_state.rail.notes:
			var state := GameplayNoteState.new(note, rail_state, note_states.size())
			note_states.append(state)
			if note.type == Note.NoteType.TRACE or note.type == Note.NoteType.SPIKE:
				touch_states.append(state)
			elif note.length > 0 and (note.type == Note.NoteType.HIT or note.type == Note.NoteType.MOVE):
				long_states.append(state)

	note_states.sort_custom(_sort_notes)
	touch_states.sort_custom(_sort_notes)
	long_states.sort_custom(func(a: GameplayNoteState, b: GameplayNoteState) -> bool:
		if a.note.end_time == b.note.end_time:
			return a.order < b.order
		return a.note.end_time < b.note.end_time
	)

	_prebake_long_notes()
	var rails: Array[Rail] = []
	for state in rail_states:
		rails.append(state.rail)
	GameRail.prebake_for_rails(rails)

func clear_nodes() -> void:
	if _rail_container != null:
		for child in _rail_container.get_children():
			child.queue_free()
	for rail_state in rail_states:
		rail_state.node = null
	for note_state in note_states:
		note_state.node = null

func reset_runtime() -> void:
	_rail_spawn_index = 0
	_note_spawn_index = 0
	for state in note_states:
		state.node = null
		state.processed = false
		state.judgement = Score.NONE
		state.release_processed = false
		state.release_judgement = Score.NONE
	for state in rail_states:
		state.node = null

func spawn(time_ms: int, standing_rail: Rail) -> void:
	var spawn_time := time_ms + int(GameplayPlayfield.get_visible_travel_time_ms())

	while _rail_spawn_index < rail_states.size():
		var rail_state := rail_states[_rail_spawn_index]
		if rail_state.rail.start_time > spawn_time:
			break
		_spawn_rail(rail_state, standing_rail)
		_rail_spawn_index += 1

	while _note_spawn_index < note_states.size():
		var note_state := note_states[_note_spawn_index]
		if note_state.note.time > spawn_time:
			break
		_spawn_note(note_state)
		_note_spawn_index += 1

func prepare_preview(time_ms: float) -> void:
	_rail_spawn_index = 0
	_note_spawn_index = 0

	for state in note_states:
		state.processed = state.note.end_time < time_ms
		state.node = null

	while _rail_spawn_index < rail_states.size() and rail_states[_rail_spawn_index].rail.end_time < time_ms:
		_rail_spawn_index += 1

func set_preview_visibility(time_ms: float, standing_rail: Rail) -> void:
	for rail_state in rail_states:
		if rail_state.node == null:
			continue
		rail_state.node.visible = rail_state.rail.end_time >= time_ms
		rail_state.node.is_standing = rail_state.rail == standing_rail

	for note_state in note_states:
		if note_state.node != null:
			note_state.node.visible = note_state.note.end_time >= time_ms

func set_standing_rail(rail: Rail) -> void:
	for state in rail_states:
		if state.node != null:
			state.node.is_standing = state.rail == rail

func set_rail_color(color: Color) -> void:
	if _rail_color.is_equal_approx(color):
		return
	_rail_color = color
	for state in rail_states:
		if state.node != null:
			state.node.set_theme_color(_rail_color)

func consume_note(state: GameplayNoteState, judgement: int) -> void:
	if state == null or state.node == null:
		return
	state.node.consume(judgement)

func finish_long_note(state: GameplayNoteState, judgement: int) -> void:
	if state == null or state.node == null:
		return
	state.node.finish_long_note(judgement)

func active_rail_at(time_ms: int) -> Rail:
	for state in rail_states:
		if state.rail.start_time <= time_ms and state.rail.end_time >= time_ms:
			return state.rail
	return null

func get_rails() -> Array[Rail]:
	var result: Array[Rail] = []
	for state in rail_states:
		result.append(state.rail)
	return result

func _spawn_rail(state: GameplayRailState, standing_rail: Rail) -> void:
	if state.node != null:
		return
	var node := RAIL_SCENE.instantiate() as GameRail
	if node == null:
		return
	node.rail = state.rail
	node.set_theme_color(_rail_color)
	_rail_container.add_child(node)
	node.position.y = state.order * 0.0002
	node.is_standing = state.rail == standing_rail
	state.node = node

func _spawn_note(state: GameplayNoteState) -> void:
	if state.processed or state.node != null or state.rail_state.node == null:
		return
	var node := NOTE_SCENE.instantiate() as GameNote
	if node == null:
		return
	node.note = state.note
	node.rail = state.rail_state.rail
	node.consumed.connect(_on_note_consumed.bind(state))
	state.rail_state.node.note_container.add_child(node)
	state.node = node

func _on_note_consumed(_judgement: int, note_node: GameNote, state: GameplayNoteState) -> void:
	if state.node == note_node and not note_node.waiting_for_long_release:
		state.node = null

func _prebake_long_notes() -> void:
	GameplayLongNoteVisual.clear_mesh_cache()
	if long_states.is_empty():
		return
	var prototype := NOTE_SCENE.instantiate() as GameNote
	if prototype == null:
		return
	for state in long_states:
		prototype.prebake_long_note_visual(state.note, state.rail_state.rail)
	prototype.free()

func _sort_notes(a: GameplayNoteState, b: GameplayNoteState) -> bool:
	if a.note.time == b.note.time:
		return a.order < b.order
	return a.note.time < b.note.time
