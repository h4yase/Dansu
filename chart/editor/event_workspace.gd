extends EditorEventController

const CanvasScript := preload("res://chart/editor/event_placement_canvas.gd")
const SLOT_COUNT := 10

var active := false
var canvas: Control
var frame_view: Control
var game_view: Control
var preview_column: VBoxContainer
var event_tools: VBoxContainer
var _normal_tools: Array[Control] = []
var _event_properties: ScrollContainer
var selection_ops := preload("res://chart/editor/event_selection_ops.gd").new()
var _placement_kind := "theme"

func setup() -> void:
	if _setup_complete:
		return
	_setup_complete = true
	selection_ops.workspace = self
	resource_import_dialog = FileDialog.new()
	resource_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	resource_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	editor.add_child(resource_import_dialog)
	_resource_importer.setup(resource_import_dialog)
	_resource_importer.imported.connect(_on_resource_imported)
	canvas = CanvasScript.new()
	canvas.workspace = self
	editor.chart_panel.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.hide()
	_build_properties()
	_build_tools()
	_build_preview()
	editor.selection.changed.connect(_selection_updated)
	set_process(true)
	refresh_inspector()

func _build_properties() -> void:
	_event_properties = ScrollContainer.new()
	_event_properties.name = "EventProperties"
	editor.get_node("Inspector/Property").add_child(_event_properties)
	_event_properties.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_event_properties.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_event_properties.add_child(margin)
	inspector_content = VBoxContainer.new()
	inspector_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_content.add_theme_constant_override("separation", 8)
	margin.add_child(inspector_content)
	_event_properties.hide()

func _build_tools() -> void:
	var tools: VBoxContainer = editor.get_node("Object")
	for path in ["Label", "Hit2", "Hit", "Trace", "Left", "Right", "Spike"]:
		_normal_tools.append(tools.get_node(path))
	event_tools = VBoxContainer.new()
	event_tools.add_theme_constant_override("separation", 6)
	tools.add_child(event_tools)
	tools.move_child(event_tools, 0)
	for item in [["Theme (T)", "theme"], ["Camera (C)", "camera"], ["Skin (S)", "skin"], ["Overlay (O)", "overlay"]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(func(): place(item[1], int(Game.current_time), 5))
		event_tools.add_child(button)
	var frame_button := Button.new()
	frame_button.text = "Frame (F)"
	frame_button.pressed.connect(add_frame)
	event_tools.add_child(frame_button)
	event_tools.hide()
	for pair in [["Delete", delete_selection], ["Copy", copy_selected_frames], ["Paste", paste_copied_frames]]:
		var button: Button = tools.get_node(pair[0])
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection.callable)
		button.pressed.connect(func():
			if active:
				pair[1].call()
			elif pair[0] == "Delete":
				editor.edit_controller.delete_selected()
			elif pair[0] == "Copy":
				editor.edit_controller.copy_selected()
			elif pair[0] == "Paste":
				editor.edit_controller.paste_copied()
		)
	for pair in [["Undo", editor._undo_history], ["Redo", editor._redo_history]]:
		var button: Button = tools.get_node(pair[0])
		if button.pressed.get_connections().is_empty():
			button.pressed.connect(pair[1])

func _build_preview() -> void:
	preview_column = editor.get_node("PreviewColumn")
	game_view = editor.get_node("PreviewColumn/GameFrame/GamePreview")
	frame_view = editor.get_node("PreviewColumn/OverlayFrameView")
	frame_view.hide()
	_sync_preview_mode()

func _sync_preview_mode() -> void:
	game_view.set_preview_enabled(active)
	editor.get_node("PreviewColumn/GameFrame").visible = active

func _process(_delta: float) -> void:
	editor.get_node("PreviewColumn/GameFrame").custom_minimum_size.y = preview_column.size.x * 9.0 / 16.0
	canvas.queue_redraw()
	if frame_view.visible:
		frame_view.queue_redraw()

func toggle() -> void:
	canvas.cancel_drag()
	active = not active
	_sync_preview_mode()
	editor.point_dragging = false
	editor.selection.clear()
	canvas.visible = active
	event_tools.visible = active
	for control in _normal_tools:
		control.visible = not active
	editor.view_controller.rail_layer.modulate.a = 0.22 if active else 1.0
	editor.view_controller.note_layer.modulate.a = 0.22 if active else 1.0
	_event_properties.visible = active
	editor.get_node("Inspector/Property/ScrollContainer").visible = not active
	editor.get_node("Inspector").current_tab = 1
	canvas.cancel_drag()
	refresh_inspector()

func _selection_updated() -> void:
	if active and _get_selected_event() != null:
		editor.get_node("Inspector").current_tab = 1
	frame_view.visible = active and _get_selected_event() is OverlayEvent and _get_selected_frame() != null
	refresh_inspector()
	refresh_timeline()

func refresh_timeline() -> void:
	if canvas != null:
		canvas.queue_redraw()
	if frame_view != null:
		frame_view.queue_redraw()
	if game_view != null:
		game_view.events_dirty = true

func on_history_restored() -> void:
	_selected_frames.clear()
	canvas.cancel_drag(false)
	_selection_updated()
	game_view.chart_dirty = true

func select_event(event: ChartEvent, frame_index: int = -1, _switch_tab: bool = true, _additive: bool = false) -> void:
	_selected_frames.clear()
	if _additive:
		selection_ops.toggle(event, get_frames(event)[frame_index] if frame_index >= 0 else null)
	else:
		editor.selection.select_event(event, frame_index)

func can_place_overlay(event: OverlayEvent, start: int, duration: int, slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT or duration <= 0:
		return false
	for other in get_events():
		if other is OverlayEvent and other != event and other.x == slot:
			if start < other.end_time and start + duration > other.time:
				return false
	return true

func place(kind: String, raw_time: int, slot: int) -> void:
	_placement_kind = kind
	var time: int = editor.timeline.snap_time(raw_time)
	if kind == "camera" or kind == "theme":
		var stream: ChartEvent = null
		for event in get_events():
			if (kind == "camera" and event is CameraEvent) or (kind == "theme" and event is ThemeEvent):
				stream = event
				break
		if stream != null:
			for frame in get_frames(stream):
				if stream.time + frame.time == time:
					select_event(stream, get_frames(stream).find(frame))
					return
		editor._push_history_snapshot()
		if stream == null:
			stream = CameraEvent.new() if kind == "camera" else ThemeEvent.new()
			stream.id = kind
			stream.time = 0
			stream.duration = 0
			CM.ensure_parsed_chart().events.append(stream)
		var frames := get_frames(stream)
		var frame: ChartEventFrame = _create_default_frame(stream)
		for source in frames:
			if stream.time + source.time <= time:
				frame = source.clone()
		frame.time = time - stream.time
		frames.append(frame)
		stream.sort_frames()
		select_event(stream, frames.find(frame))
	elif kind == "skin":
		for event in get_events():
			if event is SkinEvent and event.time == time:
				select_event(event)
				return
		editor._push_history_snapshot()
		var skin := SkinEvent.new()
		skin.id = _make_unique_id("skin")
		skin.time = time
		CM.ensure_parsed_chart().events.append(skin)
		select_event(skin)
	else:
		var duration := maxi(1, int(editor.timeline.get_snap_interval_ms(time) * 4))
		if not can_place_overlay(null, time, duration, slot):
			Notification.notice("Overlay position is occupied", Notification.Type.WARNING)
			return
		editor._push_history_snapshot()
		var overlay := OverlayEvent.new()
		overlay.id = _make_unique_id("overlay")
		overlay.time = time
		overlay.duration = duration
		overlay.x = slot
		overlay.frames.append(_create_default_frame(overlay))
		CM.ensure_parsed_chart().events.append(overlay)
		select_event(overlay, 0)
	CM.parsed_chart.sort_events()
	refresh_timeline()

func move_placement(event: ChartEvent, frame: ChartEventFrame, time: int, slot: int, resize: bool = false) -> bool:
	time = editor.timeline.snap_time(time)
	if event is OverlayEvent and frame == null:
		var start := event.time if resize else time
		var duration := time - event.time if resize else event.duration
		if not can_place_overlay(event, start, duration, slot):
			return false
		event.time = start
		event.duration = duration
		event.x = slot
		for item in event.frames:
			item.time = mini(item.time, duration)
	elif frame != null:
		var offset := time - event.time
		if event is OverlayEvent:
			offset = clampi(offset, 0, event.duration)
		for other in get_frames(event):
			if other != frame and other.time == offset:
				return false
		frame.time = offset
		event.sort_frames()
		editor.selection.selected_event_frame_index = get_frames(event).find(frame)
	else:
		for other in get_events():
			if other != event and other is SkinEvent and other.time == time:
				return false
		event.time = time
	CM.parsed_chart.sort_events()
	refresh_timeline()
	return true

func add_frame() -> void:
	var event := _get_selected_event()
	if not event is OverlayEvent:
		return
	var time: int = clampi(editor.timeline.snap_time(int(Game.current_time)) - event.time, 0, event.duration)
	for frame in event.frames:
		if frame.time == time:
			select_event(event, event.frames.find(frame))
			return
	editor._push_history_snapshot()
	var frame: ChartEventFrame = _get_selected_frame()
	frame = frame.clone() if frame != null else _create_default_frame(event)
	frame.time = time
	event.frames.append(frame)
	event.sort_frames()
	select_event(event, event.frames.find(frame))
	refresh_timeline()

func delete_selection() -> bool:
	return selection_ops.delete_selected()

func copy_selected_frames() -> bool:
	return selection_ops.copy_selected()

func paste_copied_frames() -> bool:
	return selection_ops.paste()

func handle_key(event: InputEventKey) -> void:
	if event.ctrl_pressed:
		match event.keycode:
			KEY_Z: editor._undo_history()
			KEY_Y: editor._redo_history()
			KEY_C: copy_selected_frames()
			KEY_V: paste_copied_frames()
			KEY_S: editor._save_chart()
	else:
		match event.keycode:
			KEY_T: place("theme", int(Game.current_time), canvas.mouse_slot())
			KEY_C: place("camera", int(Game.current_time), canvas.mouse_slot())
			KEY_S: place("skin", int(Game.current_time), canvas.mouse_slot())
			KEY_O: place("overlay", int(Game.current_time), canvas.mouse_slot())
			KEY_F: add_frame()
			KEY_DELETE: delete_selection()
			KEY_SPACE: editor.transport.toggle()
			KEY_LEFT, KEY_RIGHT:
				var before := EditorHistory.capture(editor)
				if selection_ops.move(selection_ops.capture(), 0, -1 if event.keycode == KEY_LEFT else 1):
					if not EditorHistory.same_snapshot(before, EditorHistory.capture(editor)):
						editor._history.push(before)
					refresh_inspector()

func refresh_inspector() -> void:
	if inspector_content == null:
		return
	_syncing = true
	for child in inspector_content.get_children():
		inspector_content.remove_child(child)
		child.queue_free()
	var event := _get_selected_event()
	var frame := _get_selected_frame()
	if event != null:
		_add_title(_get_event_type_name(event).to_upper())
		if event is OverlayEvent:
			_add_number_row("Start (ms)", event.time, editor.timeline.get_min_time(), editor.timeline.get_max_time(), 1, _change_start.bind(event))
			_add_number_row("Duration", event.duration, 1, editor.timeline.get_max_time(), 1, _change_duration.bind(event))
			_add_number_row("X order", event.x, 0, SLOT_COUNT - 1, 1, _change_slot.bind(event))
			_add_overlay_anchor_row(event.anchor, _on_overlay_anchor_changed.bind(event))
			_add_frame_toolbar(event)
		if frame != null:
			_add_number_row("Time (ms)", event.time + frame.time, editor.timeline.get_min_time(), editor.timeline.get_max_time(), 1, _change_frame_time.bind(event, frame))
			if frame is ThemeEventFrame:
				_build_theme_frame_inspector(event, frame)
			elif frame is CameraEventFrame:
				_build_camera_frame_inspector(event, frame)
			elif frame is OverlayEventFrame:
				_build_overlay_frame_inspector(event, frame)
		if event is SkinEvent:
			_add_number_row("Time (ms)", event.time, editor.timeline.get_min_time(), editor.timeline.get_max_time(), 1, _change_start.bind(event))
			_add_resource_row("Skin JSON", event.skin_json, "skin", event, null)
	UIFocusUtils.disable_focus_recursive(inspector_content)
	_syncing = false

func _change_start(value: float, event: ChartEvent) -> void:
	if _syncing:
		return
	editor._push_history_snapshot()
	move_placement(event, null, int(value), event.x if event is OverlayEvent else 0)
	refresh_inspector()

func _change_duration(value: float, event: OverlayEvent) -> void:
	if _syncing:
		return
	editor._push_history_snapshot()
	move_placement(event, null, event.time + int(value), event.x, true)
	refresh_inspector()

func _change_slot(value: float, event: OverlayEvent) -> void:
	if _syncing:
		return
	editor._push_history_snapshot()
	move_placement(event, null, event.time, int(value))
	refresh_inspector()

func _change_frame_time(value: float, event: ChartEvent, frame: ChartEventFrame) -> void:
	if _syncing:
		return
	editor._push_history_snapshot()
	move_placement(event, frame, int(value), 0)
	refresh_inspector()

func duplicate_frame() -> void:
	copy_selected_frames()
	var selected := _get_selected_frame()
	if selected != null:
		var previous_time := Game.current_time
		Game.current_time = editor.timeline.step_time(_get_selected_event().time + selected.time, 1)
		paste_copied_frames()
		Game.current_time = previous_time
