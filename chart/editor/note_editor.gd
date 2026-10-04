extends TextureRect
class_name EditorNote

const NOTE_TYPE_HIT := 1
const NOTE_TYPE_MOVE := 2
const NOTE_TYPE_TRACE := 3
const NOTE_TYPE_SPIKE := 4
const NOTE_DRAW_SIZE := Vector2(68, 42)
const PLACEMENT_DURATION := 0.28
const TAIL_DRAW_SIZE := Vector2(32, 24)
const TAIL_TEXTURE := preload("res://resources/textures/editor/editor_note_tail.svg")
const OUTLINE_SHADER := preload("res://resources/shaders/editor_note_outline.gdshader")
@export var hit_texture: Texture2D = preload("res://resources/textures/editor/editor_hit.svg")
@export var trace_texture: Texture2D = preload("res://resources/textures/editor/editor_trace.svg")
@export var move_texture: Texture2D = preload("res://resources/textures/editor/editor_move.svg")
@export var spike_texture: Texture2D = preload("res://resources/textures/editor/editor_spike.svg")

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
var _hovered := false
var _hover_scale := 1.0
var _tail_hovered := false
var _tail_hover_scale := 1.0
var _click_time := 1.0
var _placement_time := PLACEMENT_DURATION
var _pass_strength := 0.0
var _motion_time := 0.0
var _trail: Control
var _tail_handle: Control
var _head_material: ShaderMaterial
var _tail_material: ShaderMaterial

func set_hovered(value: bool, tail: bool = false) -> void:
	_hovered = value and not tail
	_tail_hovered = value and tail

func play_click() -> void:
	_click_time = 0.0

func play_placement() -> void:
	_placement_time = 0.0
	queue_redraw()

func play_pass() -> void:
	_pass_strength = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	var passing := _pass_strength > 0.0
	_pass_strength = move_toward(_pass_strength, 0.0, delta * 4.5)
	if not visible:
		return
	var previous_scale := _hover_scale
	var previous_tail_scale := _tail_hover_scale
	_hover_scale = move_toward(_hover_scale, 1.1 if _hovered else 1.0, delta * 1.4)
	_tail_hover_scale = move_toward(_tail_hover_scale, 1.2 if _tail_hovered else 1.0, delta * 2.0)
	var clicking := _click_time < 0.3
	var placing := _placement_time < PLACEMENT_DURATION
	_click_time += delta
	_placement_time += delta
	if _selected or clicking or placing or passing \
		or not is_equal_approx(previous_scale, _hover_scale) \
		or not is_equal_approx(previous_tail_scale, _tail_hover_scale):
		_motion_time += delta
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = null
	_head_material = ShaderMaterial.new()
	_head_material.shader = OUTLINE_SHADER
	_head_material.set_shader_parameter("draw_size", NOTE_DRAW_SIZE)
	_head_material.set_shader_parameter("selected", _selected)
	material = _head_material
	# Draw trails behind all note heads, and tail handles in front.
	z_as_relative = false
	z_index = 1
	_trail = Control.new()
	_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trail.z_as_relative = false
	_trail.z_index = 0
	_trail.draw.connect(_draw_trail)
	add_child(_trail)
	_tail_handle = Control.new()
	_tail_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail_handle.z_as_relative = false
	_tail_handle.z_index = 2
	_tail_material = ShaderMaterial.new()
	_tail_material.shader = OUTLINE_SHADER
	_tail_material.set_shader_parameter("draw_size", TAIL_DRAW_SIZE)
	_tail_material.set_shader_parameter("selected", _selected)
	_tail_handle.material = _tail_material
	_tail_handle.draw.connect(_draw_tail_handle)
	add_child(_tail_handle)
	set_process(visible)

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
	set_process(should_be_visible)
	if not should_be_visible:
		_pass_strength = 0.0
		_click_time = 1.0
		_placement_time = PLACEMENT_DURATION
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
	if _head_material != null:
		_head_material.set_shader_parameter("selected", _selected)
		_tail_material.set_shader_parameter("selected", _selected)
	queue_redraw()

func set_passthrough(is_passthrough: bool) -> void:
	if _passthrough == is_passthrough:
		return
	_passthrough = is_passthrough
	queue_redraw()

func is_head_hit(global_mouse_position: Vector2) -> bool:
	if not visible:
		return false
	_ensure_head_rect()
	var local_position := get_global_transform_with_canvas().affine_inverse() * global_mouse_position
	return _head_rect.grow(2.0).has_point(local_position)

func is_tail_hit(global_mouse_position: Vector2) -> bool:
	if not visible or note == null or note.length <= 0 or _passthrough:
		return false
	var local_position := get_global_transform_with_canvas().affine_inverse() * global_mouse_position
	var tail_position := _get_position_at_time(note.end_time)
	return Rect2(tail_position - TAIL_DRAW_SIZE * 0.5, TAIL_DRAW_SIZE).has_point(local_position)

func _draw() -> void:
	_trail.queue_redraw()
	_tail_handle.queue_redraw()
	if note == null or rail == null:
		return

	_ensure_head_rect()
	var head_position := _head_rect.get_center()
	var note_texture := _get_note_texture()

	if note_texture != null:
		var color := Color(1, 1, 1, 0.35) if _passthrough else Color.WHITE
		var brightness := (1.18 if _selected else 1.0) + _pass_strength * 0.35
		color = Color(brightness, brightness, brightness, color.a)
		_draw_note_texture(note_texture, head_position, color)
	else:
		var fill := Color("7ed2ff")
		if _passthrough:
			fill.a = 0.35
		draw_rect(_head_rect, fill, true)

func _draw_trail() -> void:
	if note == null or rail == null or note.length <= 0:
		return
	var trail_points := _sample_trail_points()
	if trail_points.size() < 2:
		return
	var trail_color := _get_note_color()
	if _passthrough:
		trail_color.a = 0.35
	_trail.draw_polyline(trail_points, trail_color, 10.0, true)

func _draw_tail_handle() -> void:
	if note == null or rail == null or note.length <= 0:
		return
	var tail_position := _get_position_at_time(note.end_time)
	var rect := Rect2(-TAIL_DRAW_SIZE * 0.5, TAIL_DRAW_SIZE)
	var color := _get_note_color()
	if _passthrough:
		color.a = 0.35
	_tail_handle.draw_set_transform(tail_position, 0.0, Vector2.ONE * _tail_hover_scale)
	_tail_handle.draw_texture_rect(TAIL_TEXTURE, rect, false, color)
	_tail_handle.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _get_note_color() -> Color:
	match int(note.type):
		NOTE_TYPE_MOVE:
			return Color("ef3d4d")
		NOTE_TYPE_TRACE:
			return Color("be77f8")
		NOTE_TYPE_SPIKE:
			return Color("a89eb8")
		_:
			return Color("858df4")

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

func _draw_note_texture(note_texture: Texture2D, head_position: Vector2, color: Color) -> void:
	var click_scale := 1.0
	if _click_time < 0.3:
		click_scale -= sin(_click_time / 0.3 * PI) * 0.15
	var draw_scale := Vector2.ONE * _hover_scale * click_scale * (1.0 + _pass_strength * 0.2)
	if _placement_time < PLACEMENT_DURATION:
		var placement_scale: float = Tween.interpolate_value(0.55, 0.45, _placement_time, PLACEMENT_DURATION, Tween.TRANS_BACK, Tween.EASE_OUT)
		draw_scale *= placement_scale
	if _should_flip_h():
		draw_scale.x *= -1.0
	var sway_angle := sin(_motion_time * 2.5) * deg_to_rad(4.0) if _selected else 0.0
	draw_set_transform(head_position, sway_angle, draw_scale)
	draw_texture_rect(note_texture, Rect2(-NOTE_DRAW_SIZE * 0.5, NOTE_DRAW_SIZE), false, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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
