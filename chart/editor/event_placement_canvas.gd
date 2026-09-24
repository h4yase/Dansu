extends Control

var workspace: Node
class Hit extends EditorEventItem:
	var rect: Rect2
	var resize: bool

	func _init(p_rect: Rect2, p_event: ChartEvent, p_frame: ChartEventFrame = null, p_resize: bool = false) -> void:
		super(p_event, p_frame)
		rect = p_rect
		resize = p_resize

var _hits: Array[Hit] = []
var _drag: Hit
const DRAG_THRESHOLD := 5.0
var gesture_active := false
var _dragging := false
var _box := false
var _origin := Vector2.ZERO
var _cursor := Vector2.ZERO
var _anchor_time := 0
var _initial_items: Array[EditorEventItem] = []
var _state: EventEditState
var _snapshot: EditorSnapshot
var _range_anchor: Hit

func _time_y(time: int) -> float:
	return workspace.editor.get_judge_y() - (time - Game.current_time) * workspace.editor.get_pixels_per_ms()

func _mouse_time() -> int:
	return workspace.editor.timeline.snap_time(workspace.editor._local_y_to_time(get_local_mouse_position().y))

func slot_x(slot: int) -> float:
	return lerpf(size.x * 0.42, size.x - 18, float(slot) / 9.0)

func mouse_slot() -> int:
	return _slot_at(get_local_mouse_position().x)

func _slot_at(x: float) -> int:
	return clampi(roundi(inverse_lerp(size.x * 0.42, size.x - 18, x) * 9), 0, 9)

func _draw() -> void:
	_hits.clear()
	if workspace == null or not workspace.active:
		return
	var font := ThemeDB.fallback_font
	for event in workspace.get_events():
		var x := size.x * (0.1 if event is ThemeEvent else 0.22 if event is CameraEvent else 0.34)
		var color: Color = workspace.THEME_COLOR if event is ThemeEvent else workspace.CAMERA_COLOR if event is CameraEvent else workspace.SKIN_COLOR
		var letter := "t" if event is ThemeEvent else "c" if event is CameraEvent else "s"
		if event is OverlayEvent:
			x = slot_x(event.x)
			color = workspace.OVERLAY_COLOR
			var start := _time_y(event.time)
			var end := _time_y(event.end_time)
			var rect := Rect2(x - 6, maxf(-20, end), 12, minf(size.y + 20, start) - maxf(-20, end))
			if rect.size.y <= 0:
				continue
			draw_rect(rect, Color(color, 0.45))
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), color, 2)
			_hits.append(Hit.new(rect.grow(5), event, null, false))
			for endpoint in [start, end]:
				draw_circle(Vector2(x, endpoint), 8, color)
				draw_line(Vector2(x - 12, endpoint), Vector2(x + 12, endpoint), color, 3)
				_hits.append(Hit.new(Rect2(x - 14, endpoint - 10, 28, 20), event, null, endpoint == end))
			for frame in event.frames:
				var y := _time_y(event.time + frame.time)
				var selected: bool = workspace.selection_ops.is_selected(event, frame) or workspace.selection_ops.is_selected(event, null)
				var points := PackedVector2Array([Vector2(x, y - 6), Vector2(x + 6, y), Vector2(x, y + 6), Vector2(x - 6, y)])
				draw_colored_polygon(points, Color.WHITE if selected else Color("ffe8a5"))
				_hits.append(Hit.new(Rect2(x - 7, y - 7, 14, 14), event, frame, false))
			if workspace.selection_ops.is_selected(event, null):
				draw_rect(rect.grow(3), Color.WHITE, false, 1)
			continue
		if event is SkinEvent:
			_draw_marker(Vector2(x, _time_y(event.time)), letter, color, event, null, font)
		else:
			for frame in workspace.get_frames(event):
				_draw_marker(Vector2(x, _time_y(event.time + frame.time)), letter, color, event, frame, font)
	if gesture_active and _box and _dragging:
		var box := Rect2(_origin, _cursor - _origin).abs().intersection(Rect2(Vector2.ZERO, size))
		draw_rect(box, Color(0.45, 0.35, 0.85, 0.16))
		draw_rect(box, Color(0.7, 0.65, 1.0, 0.9), false, 1.0)

func _draw_marker(point: Vector2, letter: String, color: Color, event: ChartEvent, frame: ChartEventFrame, font: Font) -> void:
	if point.y < -16 or point.y > size.y + 16:
		return
	var selected: bool = workspace.selection_ops.is_selected(event, frame)
	draw_circle(point, 12, Color("101018"))
	draw_arc(point, 12, 0, TAU, 32, Color.WHITE if selected else color, 2, true)
	draw_string(font, point + Vector2(-4, 5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	_hits.append(Hit.new(Rect2(point - Vector2.ONE * 14, Vector2.ONE * 28), event, frame, false))

func handle_mouse(event: InputEvent) -> void:
	if event is InputEventMouseMotion and gesture_active:
		_motion(get_global_transform_with_canvas().affine_inverse() * event.position)
		workspace.editor.get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if gesture_active:
			_finish()
			workspace.editor.get_viewport().set_input_as_handled()
		return
	if not Rect2(Vector2.ZERO, size).has_point(point) or not event.pressed:
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		if event.ctrl_pressed:
			workspace.editor.adjust_editor_zoom(direction > 0)
		elif event.shift_pressed and workspace._get_selected_event() is OverlayEvent:
			var selected: OverlayEvent = workspace._get_selected_event()
			workspace.editor._push_history_snapshot()
			workspace.move_placement(selected, null, workspace.editor.timeline.step_time(selected.end_time, direction), selected.x, true)
			workspace.refresh_inspector()
		else:
			workspace.editor._set_current_time(workspace.editor.timeline.step_time(int(Game.current_time), direction))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		var x := point.x / maxf(size.x, 1)
		var kind := "theme" if x < 0.16 else "camera" if x < 0.28 else "skin" if x < 0.40 else "overlay"
		workspace.place(kind, workspace.editor.timeline.snap_time(workspace.editor._local_y_to_time(point.y)), _slot_at(point.x))
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_press(point, event.ctrl_pressed, event.shift_pressed)
	workspace.editor.get_viewport().set_input_as_handled()

func _press(point: Vector2, ctrl: bool, shift: bool) -> void:
	var hit: Hit
	for index in range(_hits.size() - 1, -1, -1):
		if _hits[index].rect.has_point(point):
			hit = _hits[index]
			break
	if shift and _select_range(hit):
		return
	if hit != null:
		if ctrl:
			workspace.selection_ops.toggle(hit.event, hit.frame)
			_range_anchor = hit
			return
		if not workspace.selection_ops.is_selected(hit.event, hit.frame):
			workspace.select_event(hit.event, workspace.get_frames(hit.event).find(hit.frame))
		_range_anchor = hit
		_drag = hit
		_anchor_time = hit.event.end_time if hit.resize else hit.event.time + (hit.frame.time if hit.frame != null else 0)
	else:
		_drag = null
	gesture_active = true
	_dragging = false
	_box = hit == null
	_origin = point
	_cursor = point
	_initial_items.clear()
	if ctrl or not _box:
		_initial_items.assign(workspace.selection_ops.items())
	_state = workspace.selection_ops.capture()
	_snapshot = null

func _select_range(hit: Hit) -> bool:
	if hit == null or hit.frame == null or _range_anchor == null:
		return false
	if hit.event != _range_anchor.event or _range_anchor.frame == null:
		return false
	if not workspace.get_frames(hit.event).has(_range_anchor.frame):
		return false
	var selected: Array[EditorEventItem] = []
	var low := mini(hit.frame.time, _range_anchor.frame.time)
	var high := maxi(hit.frame.time, _range_anchor.frame.time)
	for frame in workspace.get_frames(hit.event):
		if frame.time >= low and frame.time <= high:
			selected.append(EditorEventItem.new(hit.event, frame))
	workspace.selection_ops.set_items(selected)
	return true

func _motion(point: Vector2) -> void:
	_cursor = point
	if not _dragging and point.distance_to(_origin) < DRAG_THRESHOLD:
		return
	if not _dragging:
		workspace.editor.transport.pause()
		_dragging = true
	if _box:
		_select_box(Rect2(_origin, point - _origin).abs())
		return
	var dt := 0
	if absf(point.y - _origin.y) >= 3.0:
		dt = workspace.editor.timeline.snap_time(_anchor_time + roundi((_origin.y - point.y) / workspace.editor.get_pixels_per_ms())) - _anchor_time
	var dx := _slot_at(point.x) - _slot_at(_origin.x)
	var resize: ChartEvent = _drag.event if _drag.resize and _state.items.size() == 1 else null
	if _snapshot == null:
		_snapshot = EditorHistory.capture(workspace.editor)
	workspace.selection_ops.move(_state, dt, dx, resize)

func _select_box(rect: Rect2) -> void:
	rect = rect.intersection(Rect2(Vector2.ZERO, size))
	var selected: Array[EditorEventItem] = _initial_items.duplicate()
	for event in workspace.get_events():
		if event is OverlayEvent:
			var x := slot_x(event.x)
			var start := Vector2(x, _time_y(event.time))
			var end := Vector2(x, _time_y(event.end_time))
			if rect.has_point(start) and rect.has_point(end):
				selected.append(EditorEventItem.new(event, null))
				continue
			var frame_found := false
			for frame in event.frames:
				if rect.has_point(Vector2(x, _time_y(event.time + frame.time))):
					selected.append(EditorEventItem.new(event, frame))
					frame_found = true
			if not frame_found and x >= rect.position.x and x <= rect.end.x and end.y <= rect.end.y and start.y >= rect.position.y:
				selected.append(EditorEventItem.new(event, null))
		else:
			var x := size.x * (0.1 if event is ThemeEvent else 0.22 if event is CameraEvent else 0.34)
			if event is SkinEvent:
				if rect.has_point(Vector2(x, _time_y(event.time))):
					selected.append(EditorEventItem.new(event, null))
			else:
				for frame in workspace.get_frames(event):
					if rect.has_point(Vector2(x, _time_y(event.time + frame.time))):
						selected.append(EditorEventItem.new(event, frame))
	workspace.selection_ops.set_items(selected)
	queue_redraw()

func _has_changes() -> bool:
	for event in _state.events:
		var original: EventEditState.Placement = _state.events[event]
		if event.time != original.time or event.duration != original.duration:
			return true
		if event is OverlayEvent and event.x != original.x:
			return true
	for frame in _state.frames:
		if frame.time != _state.frames[frame]:
			return true
	return false

func _finish() -> void:
	if not _box and _snapshot != null and _has_changes():
		workspace.editor._history.push(_snapshot)
	elif _box and not _dragging:
		workspace.selection_ops.set_items(_initial_items)
	cancel_drag(false)
	workspace.refresh_inspector()

func cancel_drag(restore: bool = true) -> void:
	if restore and gesture_active and _state != null:
		if not _box and _has_changes():
			workspace.selection_ops.apply_values(_state.events, _state.frames)
		workspace.selection_ops.set_items(_state.items)
	gesture_active = false
	_dragging = false
	_drag = null
	_state = null
	_snapshot = null
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and gesture_active:
		cancel_drag()
