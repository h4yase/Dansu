extends TextureRect
class_name EditorRail

const POINT_DIM_ALPHA := 0.3

@export var point_handle_template: TextureRect

var rail: Rail = null
var editor: ChartEditor = null
var _panel_size := Vector2.ZERO
var _judge_y := 0.0
var _pixels_per_ms := 0.0
var _current_time := 0.0
var _sampled_points := PackedVector2Array()
var _point_handles: Array = []
var _selected := false
var _selected_point_index := -1
var _point_handles_dimmed := false
var _rail_geometry_signature := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = null
	if point_handle_template != null:
		point_handle_template.visible = false

func sync_layout(panel_size: Vector2, judge_y: float, pixels_per_ms: float, current_time: float) -> void:
	var layout_changed := _panel_size != panel_size \
		or not is_equal_approx(_judge_y, judge_y) \
		or not is_equal_approx(_pixels_per_ms, pixels_per_ms) \
		or not is_equal_approx(_current_time, current_time)
	var geometry_signature := _build_rail_geometry_signature()
	var geometry_changed := _rail_geometry_signature != geometry_signature
	var should_be_visible := _is_visible_in_view(panel_size, judge_y, pixels_per_ms, current_time)
	if visible != should_be_visible:
		visible = should_be_visible
		layout_changed = true
	if not should_be_visible:
		_sampled_points.clear()
		_rail_geometry_signature = geometry_signature
		return

	_panel_size = panel_size
	_judge_y = judge_y
	_pixels_per_ms = pixels_per_ms
	_current_time = current_time
	_rail_geometry_signature = geometry_signature
	if position != Vector2.ZERO:
		position = Vector2.ZERO
	if size != panel_size:
		size = panel_size
		layout_changed = true
	if layout_changed or geometry_changed:
		_sampled_points = _sample_curve()
		_update_point_handles()
		queue_redraw()

func set_selection_state(is_selected: bool, selected_point_index: int) -> void:
	if _selected == is_selected and _selected_point_index == selected_point_index:
		_update_point_handles()
		return
	_selected = is_selected
	_selected_point_index = selected_point_index
	_update_point_handles()
	queue_redraw()


func set_point_handles_dimmed(is_dimmed: bool) -> void:
	if _point_handles_dimmed == is_dimmed:
		return
	_point_handles_dimmed = is_dimmed
	_update_point_handles()

func distance_to_curve(global_mouse_position: Vector2) -> float:
	if not visible:
		return INF
	if _sampled_points.size() < 2 and rail != null and rail.points.size() >= 2:
		_sampled_points = _sample_curve()
	if _sampled_points.size() < 2:
		return INF

	var local_position := get_global_transform_with_canvas().affine_inverse() * global_mouse_position
	var closest_distance := INF
	for index in range(_sampled_points.size() - 1):
		var closest_point := Geometry2D.get_closest_point_to_segment(local_position, _sampled_points[index], _sampled_points[index + 1])
		var distance := closest_point.distance_to(local_position)
		if distance < closest_distance:
			closest_distance = distance
	return closest_distance

func get_point_hit_index(global_mouse_position: Vector2, radius: float = 12.0) -> int:
	if rail == null:
		return -1

	var local_position := get_global_transform_with_canvas().affine_inverse() * global_mouse_position
	var closest_index := -1
	var closest_distance := radius

	for index in range(rail.points.size()):
		var point_position := _point_to_panel(rail.points[index])
		var distance := point_position.distance_to(local_position)
		if distance <= closest_distance:
			closest_distance = distance
			closest_index = index

	return closest_index

func _draw() -> void:
	if rail == null or rail.points.size() < 2:
		return

	if _sampled_points.size() < 2:
		return

	var color := Color("8fd0ff") if _selected else Color("f0f0f0")
	draw_polyline(_sampled_points, color, 5.0, true)

	for index in range(rail.points.size() - 1):
		var start_point := _point_to_panel(rail.points[index])
		var end_point := _point_to_panel(rail.points[index + 1])
		draw_line(start_point, end_point, Color(1, 1, 1, 0.2), 1.0, true)

func _sample_curve() -> PackedVector2Array:
	var sampled := PackedVector2Array()
	var visible_bounds := _get_visible_time_bounds()
	var visible_start: float = visible_bounds.x
	var visible_end: float = visible_bounds.y

	for index in range(rail.points.size() - 1):
		var start_point: RailPoint = rail.points[index]
		var end_point: RailPoint = rail.points[index + 1]
		if end_point.time < visible_start or start_point.time > visible_end:
			continue
		var duration = max(1, end_point.time - start_point.time)
		var clipped_start_time := clampf(visible_start, start_point.time, end_point.time)
		var clipped_end_time := clampf(visible_end, start_point.time, end_point.time)
		var start_alpha := clampf((clipped_start_time - start_point.time) / float(duration), 0.0, 1.0)
		var end_alpha := clampf((clipped_end_time - start_point.time) / float(duration), 0.0, 1.0)
		if end_alpha < start_alpha:
			var swap_alpha := start_alpha
			start_alpha = end_alpha
			end_alpha = swap_alpha
		var clipped_duration = max(1.0, clipped_end_time - clipped_start_time)
		var steps = max(2, int(ceil(clipped_duration / 60.0)))

		for step in range(steps + 1):
			var alpha := lerpf(start_alpha, end_alpha, float(step) / float(steps))
			var curved_alpha: float = float(rail._apply_curve(alpha, start_point.curve))
			var time_value := lerpf(start_point.time, end_point.time, alpha)
			var x_value := lerpf(start_point.x, end_point.x, curved_alpha)
			sampled.append(Vector2(x_value * _panel_size.x, _judge_y + (_current_time - time_value) * _pixels_per_ms))

	if sampled.is_empty():
		var last_point: RailPoint = rail.points[rail.points.size() - 1]
		sampled.append(_point_to_panel(last_point))
	return sampled

func _update_point_handles() -> void:
	while _point_handles.size() < rail.points.size():
		var handle := point_handle_template.duplicate() as TextureRect
		handle.visible = true
		add_child(handle)
		_point_handles.append(handle)

	while _point_handles.size() > rail.points.size():
		var extra_handle = _point_handles.pop_back()
		extra_handle.queue_free()

	for index in range(_point_handles.size()):
		var handle = _point_handles[index]
		var point: RailPoint = rail.points[index]
		var point_position := _point_to_panel(point)
		handle.position = point_position - handle.size * 0.5
		handle.visible = true
		var point_color := Color("ffd166") if editor != null and editor.selection.selected_points.has(point) \
			else Color(1, 1, 1, 0.9)
		if _point_handles_dimmed:
			point_color.a *= POINT_DIM_ALPHA
		handle.modulate = point_color

func _point_to_panel(point: RailPoint) -> Vector2:
	return Vector2(point.x * _panel_size.x, _judge_y + (_current_time - point.time) * _pixels_per_ms)

func _get_visible_time_bounds() -> Vector2:
	var margin_ms = 96.0 / max(_pixels_per_ms, 0.001)
	var judge_y := editor.get_judge_y() if editor != null else 0.0
	var visible_top = _current_time + (judge_y / max(_pixels_per_ms, 0.001)) + margin_ms
	var visible_bottom = _current_time - ((_panel_size.y - judge_y) / max(_pixels_per_ms, 0.001)) - margin_ms
	return Vector2(minf(visible_bottom, visible_top), maxf(visible_bottom, visible_top))

func _is_visible_in_view(panel_size: Vector2, judge_y: float, pixels_per_ms: float, current_time: float) -> bool:
	if rail == null or rail.points.size() < 2:
		return false
	var margin_ms = 96.0 / max(pixels_per_ms, 0.001)
	var visible_top = current_time + (judge_y / max(pixels_per_ms, 0.001)) + margin_ms
	var visible_bottom = current_time - ((panel_size.y - judge_y) / max(pixels_per_ms, 0.001)) - margin_ms
	var view_start := minf(visible_bottom, visible_top)
	var view_end := maxf(visible_bottom, visible_top)
	return rail.end_time >= view_start and rail.start_time <= view_end

func _build_rail_geometry_signature() -> String:
	if rail == null:
		return ""
	var parts: Array[String] = [str(rail.points.size())]
	for point: RailPoint in rail.points:
		parts.append("%s:%s:%s" % [point.time, point.x, point.curve])
	return "|".join(parts)
