extends Control
class_name EditorEventPreview

const HANDLE_RADIUS := 6.0
const ROTATE_RING_INNER := 9.0
const ROTATE_RING_OUTER := 16.0
const MIN_SCALE_MAGNITUDE := 0.02
const MIN_PREVIEW_ZOOM := 0.25
const MAX_PREVIEW_ZOOM := 8.0
const PREVIEW_ZOOM_STEP := 1.12
const DRAG_MODE_MOVE := "move"
const DRAG_MODE_SCALE := "scale"
const DRAG_MODE_ROTATE := "rotate"

class OverlayDrawState:
	var event: OverlayEvent = null
	var frame_index := -1
	var center := Vector2.ZERO
	var scale := Vector2.ONE
	var rotation := 0.0
	var texture_size := Vector2.ZERO
	var stage_scale := 1.0

class OverlayHandle:
	var axes := Vector2.ZERO
	var position := Vector2.ZERO

class OverlayInteraction:
	var kind := ""
	var overlay: OverlayDrawState = null
	var axes := Vector2.ZERO

	func is_empty() -> bool:
		return kind.is_empty() or overlay == null

@export var event_editor: Node

var _texture_cache_paths: Array[String] = []
var _texture_cache_values: Array[Texture2D] = []
var _drawn_overlays: Array = []
var _drag_frame: OverlayEventFrame = null
var _drag_mode := ""
var _drag_mouse_origin := Vector2.ZERO
var _drag_position_origin := Vector2.ZERO
var _drag_scale_origin := Vector2.ONE
var _drag_rotation_origin := 0.0
var _drag_reference_angle := 0.0
var _drag_center := Vector2.ZERO
var _drag_texture_half_size := Vector2.ZERO
var _drag_handle_axes := Vector2.ZERO
var _drag_overlay_rotation := 0.0
var _drag_stage_scale := 1.0
var _drag_history_pushed := false
var _drag_changed := false
var _virtual_stage_size := Vector2(1920.0, 1080.0)
var _preview_zoom := 1.0
var _preview_pan := Vector2.ZERO
var _preview_panning := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_virtual_stage_size.x = float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	_virtual_stage_size.y = float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))

func _draw() -> void:
	_drawn_overlays.clear()
	var chart: Chart = event_editor.chart if event_editor != null else null
	var events: Array[ChartEvent] = []
	if CM.parsed_chart != null:
		events = CM.parsed_chart.events
	var theme_colors := _evaluate_theme(events, Game.current_time)
	_draw_gradient(theme_colors[0], theme_colors[1])
	_draw_stage_grid()
	_draw_overlays(chart, events, Game.current_time)

func _gui_input(input_event: InputEvent) -> void:
	if event_editor == null:
		return
	if input_event is InputEventMouseMotion:
		var motion := input_event as InputEventMouseMotion
		if _preview_panning:
			if (motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE) == 0:
				_preview_panning = false
				mouse_default_cursor_shape = Control.CURSOR_ARROW
				return
			_preview_pan += motion.relative
			queue_redraw()
			accept_event()
			return
		if _drag_mode.is_empty():
			mouse_default_cursor_shape = _cursor_for_interaction(_pick_interaction(motion.position))
			return
		_apply_drag(motion.position)
		accept_event()
		return
	if not input_event is InputEventMouseButton:
		return
	var mouse_button := input_event as InputEventMouseButton
	if _handle_preview_navigation(mouse_button):
		return
	if mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_button.pressed:
		var interaction := _pick_interaction(mouse_button.position)
		if interaction == null or interaction.is_empty():
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			return
		mouse_default_cursor_shape = _cursor_for_interaction(interaction) as Control.CursorShape
		_select_overlay_from_pick(interaction.overlay)
		var frame := _resolve_frame_from_pick(interaction.overlay)
		if frame == null:
			return
		_start_drag(interaction, frame, mouse_button.position)
		accept_event()
		return
	if not _drag_mode.is_empty():
		_finish_drag()
		accept_event()

func _handle_preview_navigation(mouse_button: InputEventMouseButton) -> bool:
	if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not mouse_button.pressed:
			return true
		var factor := PREVIEW_ZOOM_STEP if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / PREVIEW_ZOOM_STEP
		_zoom_preview_at(mouse_button.position, factor)
		accept_event()
		return true
	if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
		_preview_panning = mouse_button.pressed
		mouse_default_cursor_shape = Control.CURSOR_DRAG if _preview_panning else Control.CURSOR_ARROW
		accept_event()
		return true
	return false

func _zoom_preview_at(screen_position: Vector2, factor: float) -> void:
	var old_zoom := _preview_zoom
	var next_zoom := clampf(_preview_zoom * factor, MIN_PREVIEW_ZOOM, MAX_PREVIEW_ZOOM)
	if is_equal_approx(old_zoom, next_zoom):
		return
	var virtual_position := _screen_to_stage_position(screen_position)
	_preview_zoom = next_zoom
	var stage_scale := _get_stage_scale()
	var base_position := _get_unpanned_stage_position()
	_preview_pan = screen_position - base_position - virtual_position * stage_scale
	queue_redraw()

func _draw_gradient(top_color: Color, bottom_color: Color) -> void:
	var strips := 48
	for index in range(strips):
		var alpha := float(index) / float(maxi(1, strips - 1))
		var y := size.y * float(index) / float(strips)
		draw_rect(Rect2(0.0, y, size.x, ceilf(size.y / strips) + 1.0), top_color.lerp(bottom_color, alpha))

func _draw_stage_grid() -> void:
	var stage_rect := _get_stage_rect()
	var center := stage_rect.position + stage_rect.size * 0.5
	for index in range(1, 8):
		var x := stage_rect.position.x + stage_rect.size.x * float(index) / 8.0
		draw_line(Vector2(x, stage_rect.position.y), Vector2(x, stage_rect.end.y), Color(1.0, 1.0, 1.0, 0.045), 1.0)
	for index in range(1, 6):
		var y := stage_rect.position.y + stage_rect.size.y * float(index) / 6.0
		draw_line(Vector2(stage_rect.position.x, y), Vector2(stage_rect.end.x, y), Color(1.0, 1.0, 1.0, 0.045), 1.0)
	draw_line(Vector2(center.x, stage_rect.position.y), Vector2(center.x, stage_rect.end.y), Color(1.0, 1.0, 1.0, 0.12), 1.0)
	draw_line(Vector2(stage_rect.position.x, center.y), Vector2(stage_rect.end.x, center.y), Color(1.0, 1.0, 1.0, 0.12), 1.0)
	draw_rect(stage_rect, Color(1.0, 1.0, 1.0, 0.18), false, 1.0)

func _draw_overlays(chart: Chart, events: Array, time_ms: float) -> void:
	var overlays: Array[OverlayEvent] = []
	for event in events:
		if event is OverlayEvent and time_ms >= event.time and time_ms <= event.end_time:
			overlays.append(event)
	overlays.sort_custom(func(a: OverlayEvent, b: OverlayEvent) -> bool:
		if a.x == b.x:
			return a.time < b.time
		return a.x < b.x
	)
	for overlay in overlays:
		var state := ChartEventEvaluator.evaluate_overlay(overlay, time_ms - overlay.time)
		if state == null:
			continue
		var texture := _load_event_texture(chart, state.sprite)
		if texture == null:
			continue
		var anchor := OverlayEventFrame.anchor_to_vector(overlay.anchor)
		var stage_rect := _get_stage_rect()
		var stage_scale := _get_stage_scale()
		var center := stage_rect.position + stage_rect.size * anchor + state.position * stage_scale
		var overlay_data := OverlayDrawState.new()
		overlay_data.event = overlay
		overlay_data.frame_index = state.frame_index
		overlay_data.center = center
		overlay_data.scale = state.scale * stage_scale
		overlay_data.rotation = deg_to_rad(state.rotation)
		overlay_data.texture_size = texture.get_size()
		overlay_data.stage_scale = stage_scale
		_drawn_overlays.append(overlay_data)
		draw_set_transform(center, overlay_data.rotation, overlay_data.scale)
		draw_texture(texture, -texture.get_size() * 0.5, Color(1.0, 1.0, 1.0, clampf(state.opacity, 0.0, 1.0)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if _is_selected_overlay(overlay_data):
			_draw_overlay_selection(overlay_data)

func _evaluate_theme(events: Array, time_ms: float) -> Array[Color]:
	var result: Array[Color] = [Color("101018"), Color("1a1c28")]
	var active: ThemeEvent = null
	for event in events:
		if event is ThemeEvent and time_ms >= event.time and time_ms <= event.end_time:
			if active == null or event.time >= active.time:
				active = event
	if active == null or active.frames.is_empty():
		return result
	var pair_indices := ChartEventEvaluator.frame_pair_indices(active.frames, time_ms - active.time)
	var previous: ThemeEventFrame = active.frames[pair_indices.x]
	var next: ThemeEventFrame = active.frames[pair_indices.y]
	var alpha := ChartEventEvaluator.frame_alpha(previous, next, time_ms - active.time)
	result[0] = previous.bg_color.lerp(next.bg_color, alpha)
	result[1] = previous.bg_color_2.lerp(next.bg_color_2, alpha)
	return result

func _load_event_texture(chart: Chart, reference: String) -> Texture2D:
	if chart == null or reference.is_empty() or not EventResourceRef.is_valid(reference):
		return null
	var path := EventResourceRef.resolve_sprite(chart, reference)
	var cache_index := _texture_cache_paths.find(path)
	if cache_index >= 0:
		return _texture_cache_values[cache_index]
	var texture: Texture2D = null
	if path.begins_with("res://"):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_texture_cache_paths.append(path)
	_texture_cache_values.append(texture)
	return texture

func _draw_overlay_selection(overlay_data: OverlayDrawState) -> void:
	var half_size := overlay_data.texture_size * 0.5
	var corners := PackedVector2Array([
		_overlay_to_screen(overlay_data, Vector2(-half_size.x, -half_size.y)),
		_overlay_to_screen(overlay_data, Vector2(half_size.x, -half_size.y)),
		_overlay_to_screen(overlay_data, Vector2(half_size.x, half_size.y)),
		_overlay_to_screen(overlay_data, Vector2(-half_size.x, half_size.y)),
	])
	draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]), Color(1.0, 0.86, 0.52, 0.95), 2.0, true)
	draw_circle(overlay_data.center, 3.0, Color(1.0, 0.86, 0.52, 0.95))
	for handle in _get_overlay_handles(overlay_data):
		draw_circle(handle.position, HANDLE_RADIUS, Color(1.0, 0.96, 0.9, 0.98))
		draw_circle(handle.position, HANDLE_RADIUS + 1.5, Color(0.08, 0.09, 0.16, 0.82), false, 1.0)

func _overlay_to_screen(overlay_data: OverlayDrawState, local_point: Vector2) -> Vector2:
	return overlay_data.center + Vector2(local_point.x * overlay_data.scale.x, local_point.y * overlay_data.scale.y).rotated(overlay_data.rotation)

func _is_selected_overlay(overlay_data: OverlayDrawState) -> bool:
	if event_editor == null or event_editor.selection.selected_event != overlay_data.event:
		return false
	var selected_index: int = event_editor.selection.selected_event_frame_index
	return selected_index < 0 or selected_index == overlay_data.frame_index

func _get_overlay_handles(overlay_data: OverlayDrawState) -> Array:
	var half_size := overlay_data.texture_size * 0.5
	return [
		_make_handle(overlay_data, Vector2(-1, -1), Vector2(-half_size.x, -half_size.y)),
		_make_handle(overlay_data, Vector2(0, -1), Vector2(0.0, -half_size.y)),
		_make_handle(overlay_data, Vector2(1, -1), Vector2(half_size.x, -half_size.y)),
		_make_handle(overlay_data, Vector2(1, 0), Vector2(half_size.x, 0.0)),
		_make_handle(overlay_data, Vector2(1, 1), Vector2(half_size.x, half_size.y)),
		_make_handle(overlay_data, Vector2(0, 1), Vector2(0.0, half_size.y)),
		_make_handle(overlay_data, Vector2(-1, 1), Vector2(-half_size.x, half_size.y)),
		_make_handle(overlay_data, Vector2(-1, 0), Vector2(-half_size.x, 0.0)),
	]

func _make_handle(overlay_data: OverlayDrawState, axes: Vector2, local_point: Vector2) -> OverlayHandle:
	var handle := OverlayHandle.new()
	handle.axes = axes
	handle.position = _overlay_to_screen(overlay_data, local_point)
	return handle

func _pick_interaction(point: Vector2) -> OverlayInteraction:
	for index in range(_drawn_overlays.size() - 1, -1, -1):
		var overlay_data := _drawn_overlays[index] as OverlayDrawState
		var handle_interaction := _pick_handle_interaction(overlay_data, point)
		if handle_interaction != null:
			return handle_interaction
		if _overlay_contains_point(overlay_data, point):
			var move_interaction := OverlayInteraction.new()
			move_interaction.kind = DRAG_MODE_MOVE
			move_interaction.overlay = overlay_data
			return move_interaction
	return null

func _pick_handle_interaction(overlay_data: OverlayDrawState, point: Vector2) -> OverlayInteraction:
	var best_scale: OverlayHandle = null
	var best_rotate: OverlayHandle = null
	var best_scale_distance := INF
	var best_rotate_distance := INF
	for handle in _get_overlay_handles(overlay_data):
		var typed_handle := handle as OverlayHandle
		var distance := point.distance_to(typed_handle.position)
		if distance <= HANDLE_RADIUS and distance < best_scale_distance:
			best_scale = typed_handle
			best_scale_distance = distance
		elif distance >= ROTATE_RING_INNER \
				and distance <= ROTATE_RING_OUTER \
				and not _overlay_contains_point(overlay_data, point) \
				and distance < best_rotate_distance:
			best_rotate = typed_handle
			best_rotate_distance = distance
	if best_scale != null:
		return _make_interaction(DRAG_MODE_SCALE, overlay_data, best_scale.axes)
	if best_rotate != null:
		return _make_interaction(DRAG_MODE_ROTATE, overlay_data, best_rotate.axes)
	return null

func _make_interaction(kind: String, overlay_data: OverlayDrawState, axes: Vector2 = Vector2.ZERO) -> OverlayInteraction:
	var interaction := OverlayInteraction.new()
	interaction.kind = kind
	interaction.overlay = overlay_data
	interaction.axes = axes
	return interaction

func _overlay_contains_point(overlay_data: OverlayDrawState, point: Vector2) -> bool:
	if absf(overlay_data.scale.x) <= 0.0001 or absf(overlay_data.scale.y) <= 0.0001:
		return false
	var local := (point - overlay_data.center).rotated(-overlay_data.rotation)
	local = Vector2(local.x / overlay_data.scale.x, local.y / overlay_data.scale.y)
	var half_size := overlay_data.texture_size * 0.5
	return absf(local.x) <= half_size.x and absf(local.y) <= half_size.y

func _select_overlay_from_pick(overlay_data: OverlayDrawState) -> void:
	if overlay_data == null or overlay_data.event == null or event_editor.event_controller == null:
		return
	event_editor.event_controller.select_event(overlay_data.event, overlay_data.frame_index)

func _resolve_frame_from_pick(overlay_data: OverlayDrawState) -> OverlayEventFrame:
	if overlay_data == null or overlay_data.event == null:
		return null
	if overlay_data.frame_index < 0 or overlay_data.frame_index >= overlay_data.event.frames.size():
		return null
	return overlay_data.event.frames[overlay_data.frame_index]

func _start_drag(interaction: OverlayInteraction, frame: OverlayEventFrame, mouse_position: Vector2) -> void:
	_drag_frame = frame
	_drag_mode = interaction.kind
	_drag_mouse_origin = mouse_position
	_drag_position_origin = frame.position
	_drag_scale_origin = frame.scale
	_drag_rotation_origin = frame.rotation
	_drag_center = interaction.overlay.center
	_drag_texture_half_size = interaction.overlay.texture_size * 0.5
	_drag_handle_axes = interaction.axes
	_drag_overlay_rotation = interaction.overlay.rotation
	_drag_stage_scale = interaction.overlay.stage_scale
	_drag_reference_angle = (mouse_position - _drag_center).angle()
	_drag_history_pushed = false
	_drag_changed = false

func _apply_drag(mouse_position: Vector2) -> void:
	if _drag_frame == null:
		return
	if _drag_mode == DRAG_MODE_MOVE:
		var next_position := _drag_position_origin + (mouse_position - _drag_mouse_origin) / maxf(_drag_stage_scale, 0.0001)
		if next_position == _drag_frame.position:
			return
		_push_drag_history_once()
		_drag_frame.position = next_position
	elif _drag_mode == DRAG_MODE_SCALE:
		var local_mouse := (mouse_position - _drag_center).rotated(-_drag_overlay_rotation) / maxf(_drag_stage_scale, 0.0001)
		var next_scale := _drag_scale_origin
		if _drag_handle_axes.x != 0.0 and _drag_texture_half_size.x > 0.0:
			next_scale.x = local_mouse.x / (_drag_texture_half_size.x * _drag_handle_axes.x)
			next_scale.x = _sanitize_scale_component(next_scale.x, _drag_scale_origin.x if not is_zero_approx(_drag_scale_origin.x) else _drag_handle_axes.x)
		if _drag_handle_axes.y != 0.0 and _drag_texture_half_size.y > 0.0:
			next_scale.y = local_mouse.y / (_drag_texture_half_size.y * _drag_handle_axes.y)
			next_scale.y = _sanitize_scale_component(next_scale.y, _drag_scale_origin.y if not is_zero_approx(_drag_scale_origin.y) else _drag_handle_axes.y)
		if next_scale == _drag_frame.scale:
			return
		_push_drag_history_once()
		_drag_frame.scale = next_scale
	elif _drag_mode == DRAG_MODE_ROTATE:
		var current_angle := (mouse_position - _drag_center).angle()
		var delta_angle := wrapf(current_angle - _drag_reference_angle, -PI, PI)
		var next_rotation := _drag_rotation_origin + rad_to_deg(delta_angle)
		if is_equal_approx(next_rotation, _drag_frame.rotation):
			return
		_push_drag_history_once()
		_drag_frame.rotation = next_rotation
	else:
		return
	_drag_changed = true
	if event_editor.event_controller != null:
		event_editor.event_controller.refresh_timeline()
	queue_redraw()

func _finish_drag() -> void:
	var changed := _drag_changed
	_drag_frame = null
	_drag_mode = ""
	_drag_history_pushed = false
	_drag_changed = false
	if changed and event_editor != null:
		event_editor.selection.refresh()
	queue_redraw()

func _push_drag_history_once() -> void:
	if _drag_history_pushed or event_editor == null:
		return
	event_editor._push_history_snapshot()
	_drag_history_pushed = true

func _sanitize_scale_component(value: float, fallback_sign: float) -> float:
	if absf(value) >= MIN_SCALE_MAGNITUDE:
		return clampf(value, -20.0, 20.0)
	var sign_source := fallback_sign if not is_zero_approx(fallback_sign) else 1.0
	return clampf(signf(sign_source) * MIN_SCALE_MAGNITUDE, -20.0, 20.0)

func _cursor_for_interaction(interaction: OverlayInteraction) -> Control.CursorShape:
	if interaction == null or interaction.is_empty():
		return Control.CURSOR_ARROW
	if interaction.kind == DRAG_MODE_MOVE:
		return Control.CURSOR_MOVE
	if interaction.kind == DRAG_MODE_ROTATE:
		return Control.CURSOR_CROSS
	if interaction.axes.x == 0.0:
		return Control.CURSOR_VSIZE
	if interaction.axes.y == 0.0:
		return Control.CURSOR_HSIZE
	return Control.CURSOR_BDIAGSIZE if interaction.axes.x == interaction.axes.y else Control.CURSOR_FDIAGSIZE

func _get_stage_scale() -> float:
	if _virtual_stage_size.x <= 0.0 or _virtual_stage_size.y <= 0.0:
		return 1.0
	return minf(size.x / _virtual_stage_size.x, size.y / _virtual_stage_size.y) * _preview_zoom

func _get_stage_rect() -> Rect2:
	var stage_scale := _get_stage_scale()
	var stage_size := _virtual_stage_size * stage_scale
	return Rect2(_get_unpanned_stage_position() + _preview_pan, stage_size)

func _get_unpanned_stage_position() -> Vector2:
	var stage_size := _virtual_stage_size * _get_stage_scale()
	return (size - stage_size) * 0.5

func _screen_to_stage_position(screen_position: Vector2) -> Vector2:
	var stage_rect := _get_stage_rect()
	var stage_scale := _get_stage_scale()
	if stage_scale <= 0.0:
		return Vector2.ZERO
	return (screen_position - stage_rect.position) / stage_scale
