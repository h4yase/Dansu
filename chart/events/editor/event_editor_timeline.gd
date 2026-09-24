extends Control
class_name EditorEventTimeline

const LABEL_WIDTH := 112.0
const RULER_HEIGHT := 30.0
const LANE_HEIGHT := 38.0
const GRID_COLOR := Color(0.28, 0.31, 0.38, 0.32)
const TEXT_COLOR := Color(0.82, 0.85, 0.9)
const MUTED_TEXT_COLOR := Color(0.5, 0.54, 0.62)


class FrameHit:
	var event: ChartEvent
	var frame: ChartEventFrame
	var frame_index: int

	func _init(hit_event: ChartEvent, hit_frame: ChartEventFrame, hit_index: int) -> void:
		event = hit_event
		frame = hit_frame
		frame_index = hit_index


var controller: EditorEventController = null
var pixels_per_ms := 0.08
var view_start_ms := 0.0
var follow_playhead := true

var _drag_event: ChartEvent = null
var _drag_frame: ChartEventFrame = null
var _drag_time_offset := 0.0
var _drag_history_pushed := false
var _drag_resize := false
var _panning := false
var _scrubbing := false
var _last_pointer_x := 0.0
var _last_playhead := INF
var _track_scroll := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process(true)

func _process(_delta: float) -> void:
	if not is_equal_approx(_last_playhead, Game.current_time):
		_last_playhead = Game.current_time
		if follow_playhead and controller != null and controller.editor != null and controller.editor.transport.playing:
			_keep_time_visible(Game.current_time)
		queue_redraw()

func set_zoom(value: float, focus_time: float = Game.current_time) -> void:
	var old_zoom := pixels_per_ms
	pixels_per_ms = clampf(value, 0.015, 0.4)
	if is_equal_approx(old_zoom, pixels_per_ms):
		return
	var focus_x := LABEL_WIDTH + (focus_time - view_start_ms) * old_zoom
	view_start_ms = focus_time - (focus_x - LABEL_WIDTH) / pixels_per_ms
	_clamp_view_start()
	queue_redraw()

func center_on(time_ms: float) -> void:
	var timeline_width := maxf(1.0, size.x - LABEL_WIDTH)
	view_start_ms = time_ms - timeline_width / pixels_per_ms * 0.5
	_clamp_view_start()
	queue_redraw()

func set_follow_playhead(enabled: bool) -> void:
	follow_playhead = enabled
	if enabled:
		center_on(Game.current_time)

func ensure_lane_visible(lane: int) -> void:
	if controller == null or lane < 0 or lane >= controller.get_lane_count():
		return
	var viewport_height := maxf(1.0, size.y - RULER_HEIGHT)
	var lane_top := lane * LANE_HEIGHT
	var lane_bottom := lane_top + LANE_HEIGHT
	if lane_top < _track_scroll:
		_track_scroll = lane_top
	elif lane_bottom > _track_scroll + viewport_height:
		_track_scroll = lane_bottom - viewport_height
	_clamp_track_scroll()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("11151d"))
	draw_rect(Rect2(0.0, 0.0, LABEL_WIDTH, size.y), Color("171c26"))
	draw_rect(Rect2(LABEL_WIDTH, 0.0, maxf(0.0, size.x - LABEL_WIDTH), RULER_HEIGHT), Color("151a23"))

	_draw_time_grid()
	_draw_tracks()
	_draw_events()
	_draw_playhead()

func _draw_time_grid() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var interval: float = _get_ruler_interval()
	var first_time: float = floorf(view_start_ms / interval) * interval
	var visible_end: float = _get_visible_end()
	var time: float = first_time
	while time <= visible_end:
		var x := _time_to_x(time)
		if x >= LABEL_WIDTH:
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), GRID_COLOR, 1.0)
			var label := _format_ruler_time(int(round(time)))
			draw_string(font, Vector2(x + 4.0, 19.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size - 2, MUTED_TEXT_COLOR)
		time += interval
	draw_line(Vector2(LABEL_WIDTH, 0.0), Vector2(LABEL_WIDTH, size.y), Color(0.36, 0.39, 0.47, 0.8), 1.0)
	draw_line(Vector2(0.0, RULER_HEIGHT), Vector2(size.x, RULER_HEIGHT), Color(0.36, 0.39, 0.47, 0.55), 1.0)

func _draw_tracks() -> void:
	if controller == null:
		return
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for lane in range(controller.get_lane_count()):
		var y := _get_lane_y(lane)
		if y + LANE_HEIGHT < RULER_HEIGHT or y > size.y:
			continue
		var lane_color: Color = controller.get_lane_color(lane)
		var active := controller.is_active_overlay_lane(lane)
		var track_color := lane_color if active else Color.WHITE
		var track_alpha := 0.045 if active else 0.035 if lane % 2 == 0 else 0.018
		draw_rect(Rect2(LABEL_WIDTH, y, maxf(0.0, size.x - LABEL_WIDTH), LANE_HEIGHT), Color(track_color, track_alpha))
		if active:
			draw_rect(Rect2(0.0, y, LABEL_WIDTH, LANE_HEIGHT), Color(lane_color, 0.18))
		draw_rect(Rect2(0.0, y, 7.0 if active else 4.0, LANE_HEIGHT), lane_color)
		draw_string(font, Vector2(13.0, y + 24.0), controller.get_lane_name(lane), HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 20.0, font_size - 1, Color.WHITE if active else TEXT_COLOR)
		draw_line(Vector2(0.0, y + LANE_HEIGHT), Vector2(size.x, y + LANE_HEIGHT), Color(0.24, 0.27, 0.33, 0.65), 1.0)

func _draw_events() -> void:
	if controller == null:
		return
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var track_rect := Rect2(LABEL_WIDTH, RULER_HEIGHT, maxf(0.0, size.x - LABEL_WIDTH), maxf(0.0, size.y - RULER_HEIGHT))
	for event in controller.get_events():
		if event == null:
			continue
		var lane := controller.get_event_lane(event)
		if lane < 0:
			continue
		var rect := _get_event_rect(event)
		var clipped_rect := rect.intersection(track_rect)
		if clipped_rect.size.x <= 0.0 or clipped_rect.size.y <= 0.0:
			continue
		var color: Color = controller.get_lane_color(lane)
		var selected: bool = controller.editor != null and controller.editor.selection.selected_event == event
		draw_rect(clipped_rect, Color(color, 0.78 if selected else 0.52), true)
		draw_rect(clipped_rect, Color.WHITE if selected else Color(color, 0.92), false, 2.0 if selected else 1.0)
		if selected and not event is SkinEvent:
			var handle_x := minf(rect.end.x - 4.0, clipped_rect.end.x - 4.0)
			if handle_x >= clipped_rect.position.x + 4.0:
				draw_line(Vector2(handle_x, clipped_rect.position.y + 4.0), Vector2(handle_x, clipped_rect.end.y - 4.0), Color("101720"), 2.0)
		if event is SkinEvent:
			var center_x := rect.position.x + rect.size.x * 0.5
			if center_x >= LABEL_WIDTH and center_x <= size.x:
				draw_line(Vector2(center_x, clipped_rect.position.y - 3.0), Vector2(center_x, clipped_rect.end.y + 3.0), color, 2.0)
		else:
			var clip_label := "L%d · %s" % [(event as OverlayEvent).x, event.id] if event is OverlayEvent else event.id
			draw_string(font, Vector2(clipped_rect.position.x + 6.0, clipped_rect.position.y + 20.0), clip_label, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, clipped_rect.size.x - 12.0), font_size - 2, Color("0a1118"))
		_draw_event_frames(event, lane, color)

func _draw_event_frames(event: ChartEvent, lane: int, color: Color) -> void:
	if controller == null:
		return
	var frames := controller.get_frames(event)
	for frame_index in range(frames.size()):
		var frame: ChartEventFrame = frames[frame_index]
		if frame == null:
			continue
		var center := Vector2(_time_to_x(event.time + frame.time), _get_lane_y(lane) + LANE_HEIGHT * 0.5)
		if center.x < LABEL_WIDTH - 8.0 or center.x > size.x + 8.0:
			continue
		var selected := controller.is_frame_selected(event, frame)
		var radius := 6.5 if selected else 5.0
		var points := PackedVector2Array([
			center + Vector2(0.0, -radius),
			center + Vector2(radius, 0.0),
			center + Vector2(0.0, radius),
			center + Vector2(-radius, 0.0),
		])
		draw_colored_polygon(points, Color.WHITE if selected else color.lightened(0.25))
		if selected:
			draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color("15202a"), 2.0)

func _draw_playhead() -> void:
	var x := _time_to_x(Game.current_time)
	if x < LABEL_WIDTH or x > size.x:
		return
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color("ff5f67"), 2.0)
	var marker := PackedVector2Array([
		Vector2(x - 6.0, 0.0),
		Vector2(x + 6.0, 0.0),
		Vector2(x, 8.0),
	])
	draw_colored_polygon(marker, Color("ff5f67"))

func _gui_input(input_event: InputEvent) -> void:
	if controller == null or controller.editor == null:
		return
	if input_event is InputEventMouseButton:
		_handle_mouse_button(input_event)
	elif input_event is InputEventMouseMotion:
		_handle_mouse_motion(input_event)

func _handle_mouse_button(mouse_event: InputEventMouseButton) -> void:
	if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		UIFocusUtils.release_text_input_focus(get_viewport())

	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var direction := 1.0 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		if mouse_event.shift_pressed:
			_track_scroll -= direction * LANE_HEIGHT * 1.5
			_clamp_track_scroll()
			queue_redraw()
		elif mouse_event.ctrl_pressed:
			var focus_time := _x_to_time(mouse_event.position.x)
			set_zoom(pixels_per_ms * (1.18 if direction > 0.0 else 1.0 / 1.18), focus_time)
			controller.sync_zoom_control(pixels_per_ms)
		else:
			view_start_ms -= direction * _get_visible_duration() * 0.12
			_clamp_view_start()
			queue_redraw()
		accept_event()
		return

	if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = mouse_event.pressed
		_last_pointer_x = mouse_event.position.x
		accept_event()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not mouse_event.pressed:
		_scrubbing = false
		_end_drag()
		accept_event()
		return

	var lane := _get_lane_at(mouse_event.position.y)
	var clicked_time := _x_to_time(mouse_event.position.x)
	if mouse_event.position.x < LABEL_WIDTH:
		if controller.is_overlay_lane(lane):
			controller.select_overlay_lane(lane)
			queue_redraw()
			accept_event()
		return

	var frame_hit := _find_frame_at(mouse_event.position)
	if frame_hit != null:
		controller.select_event(frame_hit.event, frame_hit.frame_index, true, mouse_event.shift_pressed)
		if mouse_event.shift_pressed:
			_drag_event = null
			_drag_frame = null
			accept_event()
			return
		_drag_event = frame_hit.event
		_drag_frame = frame_hit.frame
		_drag_time_offset = clicked_time - float(frame_hit.event.time + frame_hit.frame.time)
		_drag_history_pushed = false
		accept_event()
		return

	var event_hit := _find_event_at(mouse_event.position)
	if event_hit != null:
		if mouse_event.double_click and not event_hit is SkinEvent:
			controller.select_event(event_hit)
			controller.add_frame_to_event(event_hit, int(round(clicked_time)))
			accept_event()
			return
		controller.select_event(event_hit)
		_drag_event = event_hit
		_drag_frame = null
		_drag_resize = not event_hit is SkinEvent and absf(mouse_event.position.x - _get_event_rect(event_hit).end.x) <= 8.0
		_drag_time_offset = clicked_time - float(event_hit.end_time if _drag_resize else event_hit.time)
		_drag_history_pushed = false
		accept_event()
		return

	if controller.is_overlay_lane(lane):
		controller.select_overlay_lane(lane)
	controller.editor._set_current_time(clicked_time)
	if mouse_event.double_click and lane >= 0:
		controller.create_event_for_lane(lane, int(round(clicked_time)))
	else:
		_scrubbing = true
	accept_event()

func _handle_mouse_motion(mouse_event: InputEventMouseMotion) -> void:
	if _panning:
		view_start_ms -= (mouse_event.position.x - _last_pointer_x) / pixels_per_ms
		_last_pointer_x = mouse_event.position.x
		_clamp_view_start()
		queue_redraw()
		accept_event()
		return

	if _scrubbing:
		if (mouse_event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_scrubbing = false
			return
		controller.editor._set_current_time(_x_to_time(mouse_event.position.x))
		queue_redraw()
		accept_event()
		return

	if _drag_event == null or (mouse_event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	var target_time := _x_to_time(mouse_event.position.x) - _drag_time_offset
	if not _drag_history_pushed:
		controller.editor._push_history_snapshot()
		_drag_history_pushed = true
	if _drag_frame != null:
		controller.move_frame_to_absolute_time(_drag_event, _drag_frame, int(round(target_time)))
	elif _drag_resize:
		controller.resize_event_to_end(_drag_event, int(round(target_time)))
	else:
		controller.move_event_to_time(_drag_event, int(round(target_time)))
	queue_redraw()
	accept_event()

func _end_drag() -> void:
	var changed := _drag_history_pushed
	_drag_event = null
	_drag_frame = null
	_drag_resize = false
	_drag_history_pushed = false
	if changed and controller != null:
		controller.refresh_inspector()

func _find_event_at(position: Vector2) -> ChartEvent:
	var events := controller.get_events()
	for index in range(events.size() - 1, -1, -1):
		var event: ChartEvent = events[index]
		if event != null and _get_event_rect(event).has_point(position):
			return event
	return null

func _find_frame_at(position: Vector2) -> FrameHit:
	for event in controller.get_events():
		if event == null:
			continue
		var lane := controller.get_event_lane(event)
		var frames := controller.get_frames(event)
		for frame_index in range(frames.size()):
			var frame: ChartEventFrame = frames[frame_index]
			var center := Vector2(_time_to_x(event.time + frame.time), _get_lane_y(lane) + LANE_HEIGHT * 0.5)
			if center.distance_to(position) <= 9.0:
				return FrameHit.new(event, frame, frame_index)
	return null

func _get_event_rect(event: ChartEvent) -> Rect2:
	var lane := controller.get_event_lane(event)
	var x := _time_to_x(event.time)
	var width := 10.0 if event is SkinEvent else maxf(14.0, event.duration * pixels_per_ms)
	var y := _get_lane_y(lane) + 6.0
	return Rect2(x, y, width, LANE_HEIGHT - 12.0)

func _get_lane_at(y: float) -> int:
	if controller == null or y < RULER_HEIGHT:
		return -1
	var lane := int(floor((y - RULER_HEIGHT + _track_scroll) / LANE_HEIGHT))
	return lane if lane >= 0 and lane < controller.get_lane_count() else -1

func _get_lane_y(lane: int) -> float:
	return RULER_HEIGHT + lane * LANE_HEIGHT - _track_scroll

func _time_to_x(time_ms: float) -> float:
	return LABEL_WIDTH + (time_ms - view_start_ms) * pixels_per_ms

func _x_to_time(x: float) -> float:
	return view_start_ms + (x - LABEL_WIDTH) / pixels_per_ms

func _get_visible_duration() -> float:
	return maxf(1.0, size.x - LABEL_WIDTH) / pixels_per_ms

func _get_visible_end() -> float:
	return view_start_ms + _get_visible_duration()

func _clamp_view_start() -> void:
	if controller == null or controller.editor == null or controller.editor.timeline == null:
		return
	var min_time := float(controller.editor.timeline.get_min_time())
	var max_time := float(controller.editor.timeline.get_max_time())
	var max_start := maxf(min_time, max_time - _get_visible_duration())
	view_start_ms = clampf(view_start_ms, min_time, max_start)

func _clamp_track_scroll() -> void:
	if controller == null:
		_track_scroll = 0.0
		return
	var content_height := controller.get_lane_count() * LANE_HEIGHT
	var viewport_height := maxf(1.0, size.y - RULER_HEIGHT)
	_track_scroll = clampf(_track_scroll, 0.0, maxf(0.0, content_height - viewport_height))

func _keep_time_visible(time_ms: float) -> void:
	var margin := _get_visible_duration() * 0.12
	if time_ms < view_start_ms + margin or time_ms > _get_visible_end() - margin:
		center_on(time_ms)

func _get_ruler_interval() -> float:
	for interval in [100.0, 250.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 30000.0]:
		if interval * pixels_per_ms >= 72.0:
			return interval
	return 60000.0

func _format_ruler_time(time_ms: int) -> String:
	var seconds := maxf(0.0, time_ms / 1000.0)
	var minutes := int(seconds) / 60
	return "%d:%05.2f" % [minutes, fmod(seconds, 60.0)]
