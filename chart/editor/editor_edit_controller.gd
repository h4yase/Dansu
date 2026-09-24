extends Node
class_name EditorEditController

@export var editor: ChartEditor
var clipboard := preload("res://chart/editor/editor_clipboard.gd").new()
var gesture := preload("res://chart/editor/editor_selection_gesture.gd").new()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and gesture != null and gesture.active:
		gesture.finish(editor.get_global_mouse_position(), true)

func handle_mouse_button(event: InputEventMouseButton) -> void:
	if editor == null or not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not editor._is_mouse_inside_chart():
			return
		if event.shift_pressed:
			adjust_selected_object(event.button_index == MOUSE_BUTTON_WHEEL_UP)
		elif event.ctrl_pressed:
			editor.adjust_editor_zoom(event.button_index == MOUSE_BUTTON_WHEEL_UP)
		else:
			var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			set_current_time(editor.timeline.step_time(int(round(Game.current_time)), direction))
		editor.get_viewport().set_input_as_handled()
		return

	if not editor._is_mouse_inside_chart():
		return

	var mouse_pos := editor.get_global_mouse_position()

	if event.button_index == MOUSE_BUTTON_RIGHT:
		if editor.selection.selected_rail != null:
			add_point_at_mouse(mouse_pos)
			editor.get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	gesture.press(editor, mouse_pos, event.ctrl_pressed, event.shift_pressed)
	editor.get_viewport().set_input_as_handled()

func handle_key_input(event: InputEventKey) -> void:
	if editor == null:
		return

	if event.ctrl_pressed:
		if event.keycode == KEY_C:
			copy_selected()
			return
		if event.keycode == KEY_V:
			paste_copied()
			return
		if event.keycode == KEY_Z:
			editor._undo_history()
			return
		if event.keycode == KEY_Y:
			editor._redo_history()
			return

	match event.keycode:
		KEY_R: create_rail()
		KEY_Z: create_hit_note()
		KEY_ESCAPE: editor.exit()
		KEY_X: create_trace_note()
		KEY_C: create_spike_note()
		KEY_A: create_left_note()
		KEY_D: create_right_note()
		KEY_DELETE: delete_selected()
		KEY_SPACE: editor.transport.toggle()
		KEY_LEFT: move_selected_notes(-1)
		KEY_RIGHT: move_selected_notes(1)

func copy_selected() -> bool:
	return editor != null and clipboard.copy(editor.selection)

func paste_copied() -> bool:
	return editor != null and clipboard.paste(editor)

func set_current_time(value: float) -> void:
	if editor == null or editor.timeline == null:
		return
	Game.current_time = editor.timeline.clamp_time(value)
	editor._update_time_ui(true)
	if editor.view_controller != null:
		editor.view_controller.mark_layout_dirty()
	if editor.transport.playing:
		editor.transport.seek()

func create_rail() -> void:
	if editor == null or editor.timeline == null:
		return
	editor._push_history_snapshot()
	var new_rail := EditorChartOps.create_default_rail(editor.timeline.snap_time(int(round(Game.current_time))))
	CM.ensure_parsed_chart().rails.append(new_rail)
	editor.selection.select_rail(new_rail)
	editor.refresh_views()

func create_hit_note() -> void:
	create_note(Note.NoteType.HIT, Note.Dir.NONE)

func create_trace_note() -> void:
	create_note(Note.NoteType.TRACE, Note.Dir.NONE)

func create_spike_note() -> void:
	create_note(Note.NoteType.SPIKE, Note.Dir.NONE)

func create_left_note() -> void:
	create_note(Note.NoteType.MOVE, Note.Dir.LEFT)

func create_right_note() -> void:
	create_note(Note.NoteType.MOVE, Note.Dir.RIGHT)

func create_note(note_type: Note.NoteType, dir: int) -> void:
	if editor == null or editor.timeline == null or editor.selection.selected_rail == null:
		return
	var note_time := editor.timeline.snap_time(int(round(Game.current_time)))
	if not EditorChartOps.is_note_time_inside_rail(editor.selection.selected_rail, note_time):
		Notification.notice("You cannot place notes outside the rails.", Notification.Type.WARNING)
		return
	editor._push_history_snapshot()
	var parsed_chart := CM.ensure_parsed_chart()
	EditorChartOps.remove_note_placement_conflicts(
		parsed_chart.rails,
		editor.selection.selected_rail,
		note_time,
		note_type
	)
	var new_note := EditorChartOps.create_note(note_type, note_time, dir)
	editor.selection.selected_rail.notes.append(new_note)
	editor.selection.selected_rail.sort_notes()
	editor.selection.select_note(editor.selection.selected_rail, new_note)
	editor.refresh_views()

func delete_selected() -> void:
	if editor == null:
		return
	if editor.selection.selected_notes.is_empty() and not editor.selection.has_point() and editor.selection.selected_rail == null:
		return
	editor._push_history_snapshot()
	var had_notes := not editor.selection.selected_notes.is_empty()
	for note: Note in editor.selection.selected_notes:
		EditorChartOps.remove_note(editor.selection.selected_notes[note], note)
	if not editor.selection.selected_points.is_empty():
		for point: RailPoint in editor.selection.selected_points:
			var _owner: Rail = editor.selection.selected_points[point]
			EditorChartOps.remove_point(_owner, _owner.points.find(point))
	elif not had_notes and editor.selection.selected_rail != null:
		EditorChartOps.remove_rail(editor.selection.selected_rail)
	editor.selection.clear()
	editor.refresh_views()

func add_point_at_mouse(global_mouse_pos: Vector2) -> void:
	if editor == null or editor.timeline == null or editor.chart_panel == null:
		return
	editor._push_history_snapshot()
	var local := editor.chart_panel.get_global_transform_with_canvas().affine_inverse() * global_mouse_pos
	var point_time := int(editor.timeline.snap_time(editor._local_y_to_time(local.y)))
	var point_x := editor._snap_point_x(local.x / max(1.0, editor.chart_panel.size.x))
	var point_index := EditorChartOps.add_point(editor.selection.selected_rail, point_time, point_x)
	editor.selection.select_point(editor.selection.selected_rail, point_index)
	editor.refresh_views()

func adjust_selected_object(is_positive: bool) -> void:
	if editor == null:
		return
	if not editor.note_passthrough and editor.selection.selected_note != null:
		var note := editor.selection.selected_note
		var direction := 1 if is_positive else -1
		var stepped_end_time := editor.timeline.step_time(note.end_time, direction)
		var next_length := EditorChartOps.clamp_note_length_to_rail(
			editor.selection.selected_rail,
			note,
			stepped_end_time - note.time
		)
		if next_length == note.length:
			return
		editor._push_history_snapshot()
		note.length = next_length
		if editor.view_controller != null:
			editor.view_controller.refresh_note(note)
		editor.selection_changed.emit()
		return
	if editor.selection.has_point():
		var point := editor.selection.get_point()
		var next_curve := clampf(point.curve + (0.1 if is_positive else -0.1), -1.0, 1.0)
		if is_equal_approx(point.curve, next_curve):
			return
		editor._push_history_snapshot()
		point.curve = next_curve
		if editor.view_controller != null:
			editor.view_controller.refresh_notes_for_rail(editor.selection.selected_rail)
			editor.view_controller.mark_layout_dirty()
		editor._sync_view_layouts()

func move_selected_notes(direction: int) -> void:
	if editor == null or CM.parsed_chart == null:
		return
	var moves := EditorChartOps.plan_note_rail_move(CM.parsed_chart.rails, editor.selection.selected_notes, direction)
	if moves.is_empty():
		return
	editor._push_history_snapshot()
	for note: Note in moves:
		var source: Rail = editor.selection.selected_notes[note]
		source.notes.erase(note)
	for note: Note in moves:
		var target: Rail = moves[note]
		target.notes.append(note)
		target.sort_notes()
		editor.selection.selected_notes[note] = target
	if editor.selection.selected_note != null:
		editor.selection.selected_rail = moves[editor.selection.selected_note]
	editor.selection.refresh()
	editor.refresh_views()
