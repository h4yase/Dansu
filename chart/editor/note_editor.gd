extends TextureRect
class_name EditorNote

const NOTE_TYPE_HIT := 1
const NOTE_TYPE_MOVE := 2
const NOTE_TYPE_TRACE := 3
const NOTE_TYPE_SPIKE := 4
const NOTE_DRAW_SIZE := Vector2(50, 20)
@export var hit_texture: Texture2D = preload("res://resources/textures/editor/editor_hit.tres")
@export var trace_texture: Texture2D = preload("res://resources/textures/editor/editor_trace.tres")
@export var move_texture: Texture2D = preload("res://resources/textures/editor/editor_move.png")
@export var spike_texture: Texture2D = preload("res://resources/textures/editor/editor_spike.png")

var note: Note = null
var rail: Rail = null
var editor: ChartEditor = null
var _panel_size := Vector2.ZERO
var _judge_y := 0.0
var _pixels_per_ms := 0.0
var _current_time := 0.0
var _selected := false
var _passthrough := false
var _head_rect := Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = null

func sync_layout(panel_size: Vector2, judge_y: float, pixels_per_ms: float, current_time: float) -> void:
	var layout_changed := _panel_size != panel_size \
		or not is_equal_approx(_judge_y, judge_y) \
		or not is_equal_approx(_pixels_per_ms, pixels_per_ms) \
		or not is_equal_approx(_current_time, current_time)
	_panel_size = panel_size
	_judge_y = judge_y
	_pixels_per_ms = pixels_per_ms
	_current_time = current_time
	var should_be_visible := _is_visible_in_view()
	if visible != should_be_visible:
		visible = should_be_visible
		layout_changed = true
	if not should_be_visible:
		return

	if position != Vector2.ZERO:
		position = Vector2.ZERO
	if size != panel_size:
		size = panel_size
		layout_changed = true
	if layout_changed:
		queue_redraw()

func set_selected(is_selected: bool) -> void:
	if _selected == is_selected:
		return
	_selected = is_selected
	queue_redraw()

func set_passthrough(is_passthrough: bool) -> void:
	if _passthrough == is_passthrough:
		return
	_passthrough = is_passthrough
	queue_redraw()

func is_head_hit(global_mouse_position: Vector2) -> bool:
	_ensure_head_rect()
	var local_position := get_global_transform_with_canvas().affine_inverse() * global_mouse_position
	return _head_rect.grow(6.0).has_point(local_position)

func _draw() -> void:
	if note == null or rail == null:
		return

	_ensure_head_rect()
	var head_position = _head_rect.get_center()
	var _draw_texture = _get_note_texture()

	if note.length > 0:
		var trail_points := _sample_trail_points()
		if trail_points.size() >= 2:
			var trail_color := Color("7ed2ff") if int(note.type) == NOTE_TYPE_TRACE else Color("f5c26b")
			if _passthrough:
				trail_color.a = 0.35
			draw_polyline(trail_points, trail_color, 10.0, true)

	if draw_texture != null:
		var color := Color(1, 1, 1, 0.35) if _passthrough else Color.WHITE
		_draw_note_texture(_draw_texture, head_position, color)
	else:
		var fill := Color("7ed2ff")
		if _passthrough:
			fill.a = 0.35
		draw_rect(_head_rect, fill, true)

	if _selected:
		draw_rect(_head_rect.grow(4.0), Color("fff1a8"), false, 2.0)

func _get_note_texture() -> Texture2D:
	match int(note.type):
		NOTE_TYPE_HIT:
			return hit_texture
		NOTE_TYPE_TRACE:
			return trace_texture
		NOTE_TYPE_MOVE:
			return move_texture
		NOTE_TYPE_SPIKE:
			return spike_texture
		_:
			return hit_texture

func _draw_note_texture(_draw_texture: Texture2D, head_position: Vector2, color: Color) -> void:
	var local_rect := Rect2(-NOTE_DRAW_SIZE * 0.5, NOTE_DRAW_SIZE)
	if _should_flip_h():
		draw_set_transform(head_position, 0.0, Vector2(-1, 1))
		draw_texture_rect(_draw_texture, local_rect, false, color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	draw_texture_rect(_draw_texture, _head_rect, false, color)

func _should_flip_h() -> bool:
	return int(note.type) == NOTE_TYPE_MOVE and int(note.dir) == int(Note.Dir.RIGHT)

func _sample_trail_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var visible_range := _get_visible_time_range()
	var start_time := maxi(note.time, int(floor(visible_range.x)))
	var end_time: int = mini(note.end_time, int(ceil(visible_range.y)))
	if end_time < start_time:
		return points
	var duration = max(1, end_time - start_time)
	var steps = max(2, int(ceil(duration / 60.0)))

	for step in range(steps + 1):
		var alpha := float(step) / float(steps)
		var sample_time := int(round(lerpf(start_time, end_time, alpha)))
		points.append(_get_position_at_time(sample_time))

	return points

func _ensure_head_rect() -> void:
	if note == null or rail == null:
		_head_rect = Rect2()
		return

	var head_position := _get_position_at_time(note.time)
	_head_rect = Rect2(head_position - NOTE_DRAW_SIZE * 0.5, NOTE_DRAW_SIZE)

func _get_position_at_time(time_value: int) -> Vector2:
	return Vector2(
		rail._get_rail_x_at_time(time_value) * _panel_size.x,
		_judge_y + (_current_time - time_value) * _pixels_per_ms
	)

func _get_visible_time_range() -> Vector2:
	var margin_ms = 96.0 / max(_pixels_per_ms, 0.001)
	var judge_y := editor.get_judge_y() if editor != null else 0.0
	var visible_top = _current_time + (judge_y / max(_pixels_per_ms, 0.001)) + margin_ms
	var visible_bottom = _current_time - ((_panel_size.y - judge_y) / max(_pixels_per_ms, 0.001)) - margin_ms
	return Vector2(minf(visible_bottom, visible_top), maxf(visible_bottom, visible_top))

func _is_visible_in_view() -> bool:
	if note == null:
		return false
	var visible_range := _get_visible_time_range()
	var note_start := int(note.time)
	var note_end := note.end_time
	return note_end >= visible_range.x and note_start <= visible_range.y
