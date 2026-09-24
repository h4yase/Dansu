extends RefCounted

const DRAG_THRESHOLD := 5.0
var editor: ChartEditor
var active := false
var dragging := false
var box_mode := false
var origin := Vector2.ZERO
var anchor_time := 0
var range_anchor: Note
var range_rail: Rail
var initial_notes: Dictionary = {}
var initial_points: Dictionary = {}
var note_times: Dictionary = {}
var point_values: Dictionary = {}
var initial_selection: EditorSnapshot.SelectionData
var snapshot: EditorSnapshot
var click_rail: Rail
var marquee: Panel
var delta_time := 0
var delta_x := 0.0

func press(owner: ChartEditor, position: Vector2, ctrl: bool, shift: bool) -> void:
	editor = owner
	var notes := editor._find_note_at(position)
	var points := editor._find_point_at(position)
	if shift and select_range(position):
		return
	if points != null:
		var rail: Rail = points.rail
		var point: RailPoint = rail.points[points.point_index]
		if ctrl:
			editor.selection.select_point(rail, points.point_index, true)
			return
		if not editor.selection.selected_points.has(point):
			editor.selection.select_point(rail, points.point_index)
		begin(position, false)
		anchor_time = point.time
	elif notes != null:
		var note: Note = notes.note
		range_anchor = note
		range_rail = notes.rail
		if ctrl:
			editor.selection.toggle_note(notes.rail, note)
			return
		if not editor.selection.selected_notes.has(note):
			editor.selection.select_note(notes.rail, note)
		begin(position, false)
		anchor_time = note.time
	else:
		click_rail = editor._find_rail_at(position)
		begin(position, true)
		if not ctrl:
			initial_notes.clear()
			initial_points.clear()

func begin(position: Vector2, box: bool) -> void:
	active = true
	dragging = false
	box_mode = box
	origin = local_position(position)
	delta_time = 0
	delta_x = 0.0
	snapshot = null
	initial_selection = EditorHistory._capture_selection(editor.selection)
	initial_notes = editor.selection.selected_notes.duplicate()
	initial_points = editor.selection.selected_points.duplicate()
	note_times.clear()
	point_values.clear()
	for note: Note in initial_notes:
		note_times[note] = note.time
	for point: RailPoint in initial_points:
		point_values[point] = Vector2(point.time, point.x)

func select_range(position: Vector2) -> bool:
	if range_anchor == null or not editor.selection.selected_notes.has(range_anchor):
		range_anchor = editor.selection.selected_note
		range_rail = editor.selection.selected_rail
		if range_anchor == null and not editor.selection.selected_notes.is_empty():
			range_anchor = editor.selection.selected_notes.keys()[0]
			range_rail = editor.selection.selected_notes[range_anchor]
	if range_anchor == null or range_rail == null or not range_rail.notes.has(range_anchor):
		return false
	var end := editor._local_y_to_time(local_position(position).y)
	var low := mini(range_anchor.time, end)
	var high := maxi(range_anchor.time, end)
	editor.selection.select_note(range_rail, range_anchor)
	for note: Note in range_rail.notes:
		if note.time >= low and note.time <= high:
			editor.selection.selected_notes[note] = range_rail
	editor.selection.refresh()
	return true

func motion(position: Vector2) -> void:
	if not active:
		return
	var local := local_position(position)
	if not dragging and local.distance_to(origin) < DRAG_THRESHOLD:
		return
	if not dragging:
		editor.transport.pause()
		dragging = true
	if box_mode:
		update_box(Rect2(origin, local - origin).abs())
	else:
		var proposed := 0
		if absf(local.y - origin.y) >= 3.0:
			proposed = editor.timeline.snap_time(anchor_time + int(round((origin.y - local.y) / editor.get_pixels_per_ms()))) - anchor_time
		var dx := 0.0
		if initial_notes.is_empty() and not initial_points.is_empty():
			dx = snappedf((local.x - origin.x) / maxf(editor.chart_panel.size.x, 1.0), 0.05)
		apply_delta(proposed, dx)

func update_box(rect: Rect2) -> void:
	if marquee == null:
		marquee = Panel.new()
		marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marquee.z_index = 3
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.45, 0.35, 0.85, 0.12)
		style.border_color = Color(0.7, 0.65, 1.0, 0.9)
		style.set_border_width_all(1)
		marquee.add_theme_stylebox_override("panel", style)
		editor.chart_panel.add_child(marquee)
	marquee.show()
	var clipped := rect.intersection(Rect2(Vector2.ZERO, editor.chart_panel.size))
	marquee.position = clipped.position
	marquee.size = clipped.size
	var notes := initial_notes.duplicate()
	var points := initial_points.duplicate()
	for rail: Rail in CM.parsed_chart.rails:
		for note: Note in rail.notes:
			if clipped.has_point(element_position(note.time, rail._get_rail_x_at_time(note.time))):
				notes[note] = rail
		for point: RailPoint in rail.points:
			if clipped.has_point(element_position(point.time, point.x)):
				points[point] = rail
	set_selection(notes, points)

func set_selection(notes: Dictionary, points: Dictionary) -> void:
	editor.selection.clear()
	if not notes.is_empty():
		var first: Note = notes.keys()[0]
		editor.selection.select_note(notes[first], first)
	elif not points.is_empty():
		var first: RailPoint = points.keys()[0]
		var rail: Rail = points[first]
		editor.selection.select_point(rail, rail.points.find(first))
	editor.selection.selected_notes = notes
	editor.selection.selected_points = points
	editor.selection.refresh()

func apply_delta(proposed: int, dx: float) -> void:
	var bounds := Vector2(-INF, INF)
	for note: Note in note_times:
		bounds.x = maxf(bounds.x, editor.timeline.get_min_time() - int(note_times[note]))
	for point: RailPoint in point_values:
		bounds.x = maxf(bounds.x, editor.timeline.get_min_time() - point_values[point].x)
		if initial_notes.is_empty():
			dx = clampf(dx, -point_values[point].y, 1.0 - point_values[point].y)
	for rail: Rail in CM.parsed_chart.rails:
		if not initial_notes.values().has(rail) and not initial_points.values().has(rail):
			continue
		for i in range(rail.points.size() - 1):
			var a := rail.points[i]
			var b := rail.points[i + 1]
			bounds = constrain(bounds, original_point_time(a), int(point_values.has(a)), original_point_time(b) - 1, int(point_values.has(b)))
		for note: Note in rail.notes:
			var time := int(note_times.get(note, note.time))
			var moving := int(note_times.has(note))
			var first := rail.points[0]
			var last := rail.points[-1]
			bounds = constrain(bounds, original_point_time(first), int(point_values.has(first)), time, moving)
			bounds = constrain(bounds, time + maxi(note.length, 0), moving, original_point_time(last), int(point_values.has(last)))
	if bounds.x > bounds.y:
		return
	var dt := int(clampf(proposed, bounds.x, bounds.y))
	for note: Note in note_times:
		var rail: Rail = initial_notes[note]
		var time := int(note_times[note]) + dt
		for other: Note in rail.notes:
			if note_times.has(other):
				continue
			if absi(time - other.time) <= 1 or (time < other.end_time and other.time < time + maxi(note.length, 0)):
				return
	if dt == delta_time and is_equal_approx(dx, delta_x):
		return
	if snapshot == null:
		snapshot = EditorHistory.capture(editor)
	delta_time = dt
	delta_x = dx
	for note: Note in note_times:
		note.time = int(note_times[note]) + dt
	for point: RailPoint in point_values:
		point.time = int(point_values[point].x) + dt
		point.x = point_values[point].y + dx
	refresh_geometry()

# a + a_moves * dt <= b + b_moves * dt
func constrain(bounds: Vector2, a: int, a_moves: int, b: int, b_moves: int) -> Vector2:
	var coefficient := a_moves - b_moves
	if coefficient > 0:
		bounds.y = minf(bounds.y, b - a)
	elif coefficient < 0:
		bounds.x = maxf(bounds.x, a - b)
	return bounds

func original_point_time(point: RailPoint) -> int:
	return int(point_values[point].x) if point_values.has(point) else point.time

func refresh_geometry() -> void:
	var primary := editor.selection.get_point()
	var affected_rails: Array[Rail] = []
	for rail: Rail in CM.parsed_chart.rails:
		if initial_notes.values().has(rail) or initial_points.values().has(rail):
			rail.sort_points()
			rail.sort_notes()
			affected_rails.append(rail)
	if primary != null:
		editor.selection.selected_point_index = editor.selection.selected_rail.points.find(primary)
	editor.view_controller.refresh_geometry(affected_rails)
	editor.selection.refresh()

func finish(position: Vector2, cancel: bool = false) -> void:
	if not active:
		return
	if cancel:
		for note: Note in note_times:
			note.time = note_times[note]
		for point: RailPoint in point_values:
			point.time = int(point_values[point].x)
			point.x = point_values[point].y
		refresh_geometry()
		EditorHistory._restore_selection(editor, initial_selection)
	elif not dragging and box_mode:
		if click_rail != null:
			editor.selection.select_rail(click_rail)
		else:
			editor.selection.clear()
	elif not box_mode and snapshot != null and (delta_time != 0 or not is_zero_approx(delta_x)):
		if initial_notes.is_empty() and initial_points.size() == 1:
			editor._point_drag_history_pending = false
			editor.view_controller.finalize_selected_point_drag(position)
		editor._history.push(snapshot)
	if marquee != null:
		marquee.hide()
	editor.transport.rebuild_playback_notes()
	active = false
	dragging = false
	snapshot = null

func local_position(position: Vector2) -> Vector2:
	return editor.chart_panel.get_global_transform_with_canvas().affine_inverse() * position

func element_position(time: int, x: float) -> Vector2:
	return Vector2(x * editor.chart_panel.size.x, editor.get_judge_y() + (Game.current_time - time) * editor.get_pixels_per_ms())
