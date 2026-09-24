extends Control
class_name EditorRailTimeline

const END_POINT_RADIUS := 4.5
const SELECTED_POINT_RADIUS := 7.0
const POINT_HIT_RADIUS := 11.0
const RAIL_LINE_WIDTH := 4.0
const NOTE_LINE_WIDTH := 1.0

const RAIL_COLOR := Color("8d79ee")
const RAIL_SHADOW_COLOR := Color(0.08, 0.07, 0.14, 0.9)
const POINT_COLOR := Color("eeeaff")
const SELECTED_POINT_COLOR := Color("ffd166")
const NOTE_BOUNDARY_COLOR := Color(1.0, 1.0, 1.0, 0.5)

var editor: ChartEditor = null
var song_slider: HSlider = null

var _dragged_point: RailPoint = null
var _drag_history_pending := false
var _visual_signature := ""


func _ready() -> void:
	editor = owner as ChartEditor
	song_slider = get_parent() as HSlider
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	if editor != null and not editor.selection.changed.is_connected(_on_selection_changed):
		editor.selection.changed.connect(_on_selection_changed)
	_on_selection_changed()


func _process(_delta: float) -> void:
	if _dragged_point != null and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_drag()

	var next_signature := _build_visual_signature()
	if next_signature != _visual_signature:
		_visual_signature = next_signature
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if _dragged_point != null:
			_drag_point_to(mouse_motion.position.x)
			accept_event()
		else:
			_update_mouse_cursor(mouse_motion.position)
		return

	if not event is InputEventMouseButton:
		return

	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	if mouse_button.pressed:
		_begin_drag(mouse_button.position)
	else:
		_end_drag()
	accept_event()


func _draw() -> void:
	var rail := _get_selected_rail()
	if rail == null or rail.points.is_empty() or song_slider == null:
		return

	var center_y := size.y * 0.5
	var note_bounds := EditorChartOps.get_rail_note_time_bounds(rail)
	if note_bounds != null:
		var first_note_x := _time_to_x(int(note_bounds.first))
		var last_note_x := _time_to_x(int(note_bounds.last))
		_draw_note_boundary(first_note_x)
		if not is_equal_approx(first_note_x, last_note_x):
			_draw_note_boundary(last_note_x)

	var rail_start_x := _time_to_x(rail.start_time)
	var rail_end_x := _time_to_x(rail.end_time)
	draw_line(
		Vector2(rail_start_x, center_y + 1.0),
		Vector2(rail_end_x, center_y + 1.0),
		RAIL_SHADOW_COLOR,
		RAIL_LINE_WIDTH + 3.0,
		true
	)
	draw_line(
		Vector2(rail_start_x, center_y),
		Vector2(rail_end_x, center_y),
		RAIL_COLOR,
		RAIL_LINE_WIDTH,
		true
	)

	for index in _get_visible_point_indices(rail):
		var point: RailPoint = rail.points[index]
		var point_position := Vector2(_time_to_x(point.time), center_y)
		var is_selected := editor.selection.has_point() \
			and editor.selection.selected_point_index == index
		if is_selected:
			draw_circle(
				point_position + Vector2(0.0, 1.0),
				SELECTED_POINT_RADIUS + 2.0,
				RAIL_SHADOW_COLOR
			)
			draw_circle(point_position, SELECTED_POINT_RADIUS, SELECTED_POINT_COLOR)
		else:
			draw_circle(point_position, END_POINT_RADIUS + 1.0, RAIL_SHADOW_COLOR)
			draw_arc(point_position, END_POINT_RADIUS, 0.0, TAU, 20, POINT_COLOR, 2.0, true)


func _draw_note_boundary(x_position: float) -> void:
	draw_line(
		Vector2(x_position, 1.0),
		Vector2(x_position, size.y - 1.0),
		NOTE_BOUNDARY_COLOR,
		NOTE_LINE_WIDTH,
		true
	)


func _begin_drag(local_position: Vector2) -> void:
	var rail := _get_selected_rail()
	if rail == null:
		return

	var point_index := _get_point_hit_index(local_position, rail)
	if point_index < 0:
		return

	_dragged_point = rail.points[point_index]
	_drag_history_pending = true
	editor.selection.select_point(rail, point_index)
	mouse_default_cursor_shape = Control.CURSOR_HSIZE


func _drag_point_to(local_x: float) -> void:
	var rail := _get_selected_rail()
	if rail == null or _dragged_point == null or not rail.points.has(_dragged_point):
		_end_drag()
		return

	var next_time := int(round(_x_to_time(local_x)))
	if editor.timeline != null:
		next_time = editor.timeline.snap_time(next_time)
		next_time = int(round(editor.timeline.clamp_time(next_time)))
	next_time = EditorChartOps.constrain_rail_point_time(rail, _dragged_point, next_time)
	if _dragged_point.time == next_time:
		return

	if _drag_history_pending:
		editor.push_history_snapshot()
		_drag_history_pending = false

	_dragged_point.time = next_time
	rail.sort_points()
	editor.selection.selected_point_index = rail.points.find(_dragged_point)
	if editor.view_controller != null:
		editor.view_controller.refresh_geometry([rail])
	editor.selection.refresh()
	queue_redraw()


func _end_drag() -> void:
	_dragged_point = null
	_drag_history_pending = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _get_point_hit_index(local_position: Vector2, rail: Rail) -> int:
	var closest_index := -1
	var closest_distance := POINT_HIT_RADIUS
	var center_y := size.y * 0.5
	for index in _get_visible_point_indices(rail):
		var point_position := Vector2(_time_to_x(rail.points[index].time), center_y)
		var distance := local_position.distance_to(point_position)
		if distance <= closest_distance:
			closest_index = index
			closest_distance = distance
	return closest_index


func _get_visible_point_indices(rail: Rail) -> Array[int]:
	var indices: Array[int] = []
	if rail == null or rail.points.is_empty():
		return indices

	indices.append(0)
	var last_index := rail.points.size() - 1
	if last_index != 0:
		indices.append(last_index)

	if editor != null and editor.selection.has_point():
		var selected_index := editor.selection.selected_point_index
		if selected_index >= 0 and selected_index < rail.points.size() and not indices.has(selected_index):
			indices.append(selected_index)
	return indices


func _update_mouse_cursor(local_position: Vector2) -> void:
	var rail := _get_selected_rail()
	var is_over_point := rail != null and _get_point_hit_index(local_position, rail) >= 0
	mouse_default_cursor_shape = Control.CURSOR_HSIZE if is_over_point else Control.CURSOR_ARROW


func _time_to_x(time_ms: int) -> float:
	var bounds := _get_track_bounds()
	var value_range := song_slider.max_value - song_slider.min_value
	if value_range <= 0.0:
		return bounds.x
	var ratio := clampf((float(time_ms) - song_slider.min_value) / value_range, 0.0, 1.0)
	return lerpf(bounds.x, bounds.y, ratio)


func _x_to_time(local_x: float) -> float:
	var bounds := _get_track_bounds()
	var track_width := bounds.y - bounds.x
	if track_width <= 0.0:
		return song_slider.min_value
	var ratio := clampf((local_x - bounds.x) / track_width, 0.0, 1.0)
	return lerpf(song_slider.min_value, song_slider.max_value, ratio)


func _get_track_bounds() -> Vector2:
	var half_grabber_width := 0.0
	if song_slider != null and song_slider.has_theme_icon("grabber"):
		half_grabber_width = song_slider.get_theme_icon("grabber").get_width() * 0.5
	return Vector2(half_grabber_width, maxf(half_grabber_width, size.x - half_grabber_width))


func _get_selected_rail() -> Rail:
	if editor == null or editor.selection == null:
		return null
	if editor.event_controller != null and editor.event_controller.active:
		return null
	return editor.selection.selected_rail


func _build_visual_signature() -> String:
	var rail := _get_selected_rail()
	if rail == null or song_slider == null:
		return ""

	var parts: Array[String] = [
		str(rail.get_instance_id()),
		str(editor.selection.selected_point_index),
		str(size.x),
		str(song_slider.min_value),
		str(song_slider.max_value),
	]
	for point: RailPoint in rail.points:
		parts.append(str(point.time))
	var note_bounds := EditorChartOps.get_rail_note_time_bounds(rail)
	if note_bounds != null:
		parts.append("n%s:%s" % [note_bounds.first, note_bounds.last])
	return "|".join(parts)


func _on_selection_changed() -> void:
	var rail := _get_selected_rail()
	visible = rail != null and not rail.points.is_empty()
	if _dragged_point != null and (rail == null or not rail.points.has(_dragged_point)):
		_end_drag()
	queue_redraw()
