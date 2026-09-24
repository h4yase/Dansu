extends RefCounted
class_name EditorHistory

static func capture(editor: ChartEditor) -> EditorSnapshot:
	var parsed_chart := CM.ensure_parsed_chart()
	var snapshot := EditorSnapshot.new()
	snapshot.chart = _capture_chart(editor.chart)
	snapshot.timings = _capture_timings(editor.chart)
	snapshot.hitsounds = _capture_hitsounds(parsed_chart.hitsounds)
	snapshot.rails = _capture_rails(parsed_chart.rails)
	snapshot.events = _capture_events(parsed_chart.events)
	snapshot.selection = _capture_selection(editor.selection)
	snapshot.current_time = Game.current_time
	snapshot.beat_division = editor.timeline.beat_division if editor.timeline != null else 4
	return snapshot

static func restore(editor: ChartEditor, snapshot: EditorSnapshot) -> void:
	if editor == null or editor.chart == null or snapshot == null:
		return
	_restore_chart(editor.chart, snapshot.chart)
	editor.chart.cover_image = null
	editor.transport.chart = editor.chart
	editor.transport.load_stream()
	editor.chart.timings = _restore_timings(snapshot.timings)
	CM.parsed_chart = ParsedChart.new(editor.chart)
	CM.parsed_chart.hitsounds = _restore_hitsounds(editor.chart, snapshot.hitsounds)
	CM.parsed_chart.rails = _restore_rails(snapshot.rails)
	CM.parsed_chart.events = _restore_events(snapshot.events)
	CM.parsed_chart.sort_events()
	editor.timeline = EditorTimeline.new(editor.chart, editor.transport.stream_length_sec)
	editor.timeline.beat_division = snapshot.beat_division
	editor.transport.timeline = editor.timeline
	Game.current_time = editor.timeline.clamp_time(snapshot.current_time)
	editor.hitsound_manager.rebuild_cache()
	editor.selection.clear()
	editor.refresh_inspector()
	editor._update_slider_range()
	editor.refresh_views()
	_restore_selection(editor, snapshot.selection)
	editor._update_time_ui(true)
	editor._update_save_button_state()
	editor.hitsounds_changed.emit()

static func same_snapshot(a: EditorSnapshotValue, b: EditorSnapshotValue) -> bool:
	return a == b or (a != null and b != null and var_to_str(a.comparison_values()) == var_to_str(b.comparison_values()))

static func capture_events_data(events: Array[ChartEvent]) -> Array[EditorSnapshot.EventData]:
	return _capture_events(events)

static func restore_events_data(data: Array[EditorSnapshot.EventData]) -> Array[ChartEvent]:
	return _restore_events(data)

static func _capture_chart(chart: Chart) -> EditorSnapshot.ChartData:
	if chart == null:
		return null
	var data := EditorSnapshot.ChartData.new()
	data.version = chart.version
	data.uuid = chart.uuid
	data.folder_name = chart.folder_name
	data.file_name = chart.file_name
	data.title = chart.title
	data.artist = chart.artist
	data.creator = chart.creator
	data.source = chart.source
	data.tags = chart.tags
	data.difficulty = chart.difficulty
	data.rating = chart.rating
	data.preview_time = chart.preview_time
	data.file_audio = chart.file_audio
	data.file_cover_art = chart.file_cover_art
	data.file_skin = chart.file_skin
	data.default_hitsounds = chart.default_hitsounds.duplicate()
	return data

static func _restore_chart(chart: Chart, data: EditorSnapshot.ChartData) -> void:
	if data == null:
		return
	chart.version = data.version
	chart.uuid = data.uuid
	chart.folder_name = data.folder_name
	chart.file_name = data.file_name
	chart.title = data.title
	chart.artist = data.artist
	chart.creator = data.creator
	chart.source = data.source
	chart.tags = data.tags
	chart.difficulty = data.difficulty
	chart.rating = data.rating
	chart.preview_time = data.preview_time
	chart.file_audio = data.file_audio
	chart.file_cover_art = data.file_cover_art
	chart.file_skin = data.file_skin
	chart.default_hitsounds = data.default_hitsounds.duplicate()

static func _capture_timings(chart: Chart) -> Array[EditorSnapshot.TimingData]:
	var result: Array[EditorSnapshot.TimingData] = []
	if chart == null:
		return result
	for timing in chart.timings:
		if timing == null:
			continue
		result.append(EditorSnapshot.TimingData.new(timing.time, timing.bpm))
	return result

static func _restore_timings(data: Array[EditorSnapshot.TimingData]) -> Array[Timing]:
	var result: Array[Timing] = []
	for item in data:
		var timing := Timing.new()
		timing.time = item.time
		timing.bpm = item.bpm
		result.append(timing)
	return result

static func _capture_hitsounds(hitsounds: Array[HitSound]) -> Array[EditorSnapshot.HitSoundData]:
	var result: Array[EditorSnapshot.HitSoundData] = []
	for hitsound in hitsounds:
		if hitsound == null:
			continue
		result.append(EditorSnapshot.HitSoundData.new(hitsound.id, hitsound.file_name))
	return result

static func _restore_hitsounds(chart: Chart, data: Array[EditorSnapshot.HitSoundData]) -> Array[HitSound]:
	var result: Array[HitSound] = []
	for item in data:
		var hitsound := HitSound.new()
		hitsound.setup(chart, item.id, item.file_name)
		result.append(hitsound)
	return result

static func _capture_rails(rails: Array[Rail]) -> Array[EditorSnapshot.RailData]:
	var result: Array[EditorSnapshot.RailData] = []
	for rail in rails:
		if rail == null:
			continue
		var rail_data := EditorSnapshot.RailData.new()
		rail_data.id = rail.id
		for point in rail.points:
			if point == null:
				continue
			rail_data.points.append(EditorSnapshot.PointData.new(point.x, point.curve, point.time))
		for note in rail.notes:
			if note == null:
				continue
			rail_data.notes.append(EditorSnapshot.NoteData.new(note.time, note.type, note.dir, note.length, note.animation, note.hitsound))
		result.append(rail_data)
	return result

static func _restore_rails(data: Array[EditorSnapshot.RailData]) -> Array[Rail]:
	var result: Array[Rail] = []
	for rail_data in data:
		var rail := Rail.new()
		rail.id = rail_data.id
		for point_data in rail_data.points:
			var point := RailPoint.new()
			point.x = point_data.x
			point.curve = point_data.curve
			point.time = point_data.time
			rail.points.append(point)
		for note_data in rail_data.notes:
			var note := Note.new()
			note.time = note_data.time
			note.type = note_data.type
			note.dir = note_data.dir
			note.length = note_data.length
			note.animation = note_data.animation
			note.hitsound = note_data.hitsound
			rail.notes.append(note)
		rail.sort_points()
		rail.sort_notes()
		result.append(rail)
	return result

static func _capture_events(events: Array[ChartEvent]) -> Array[EditorSnapshot.EventData]:
	var result: Array[EditorSnapshot.EventData] = []
	for event in events:
		if event == null:
			continue
		var event_data := EditorSnapshot.EventData.new()
		event_data.id = event.id
		event_data.time = event.time
		event_data.duration = event.duration
		if event is CameraEvent:
			event_data.type = EditorSnapshot.EventData.Kind.CAMERA
			for frame in (event as CameraEvent).frames:
				if frame == null:
					continue
				var frame_data := EditorSnapshot.FrameData.new()
				frame_data.time = frame.time
				frame_data.ease = frame.ease
				frame_data.follow_character = frame.follow_character
				frame_data.position = frame.position
				frame_data.zoom = frame.zoom
				event_data.frames.append(frame_data)
		elif event is OverlayEvent:
			event_data.type = EditorSnapshot.EventData.Kind.OVERLAY
			event_data.x = (event as OverlayEvent).x
			event_data.anchor = (event as OverlayEvent).anchor
			for frame in (event as OverlayEvent).frames:
				if frame == null:
					continue
				var frame_data := EditorSnapshot.FrameData.new()
				frame_data.time = frame.time
				frame_data.ease = frame.ease
				frame_data.position = frame.position
				frame_data.scale = frame.scale
				frame_data.rotation = frame.rotation
				frame_data.sprite = frame.sprite
				frame_data.opacity = frame.opacity
				frame_data.has_opacity = frame.has_opacity
				event_data.frames.append(frame_data)
		elif event is ThemeEvent:
			event_data.type = EditorSnapshot.EventData.Kind.THEME
			for frame in (event as ThemeEvent).frames:
				if frame == null:
					continue
				var frame_data := EditorSnapshot.FrameData.new()
				frame_data.time = frame.time
				frame_data.ease = frame.ease
				frame_data.bg_color = frame.bg_color
				frame_data.bg_color_2 = frame.bg_color_2
				frame_data.rail_color = frame.rail_color
				event_data.frames.append(frame_data)
		elif event is SkinEvent:
			event_data.type = EditorSnapshot.EventData.Kind.SKIN
			event_data.skin_json = (event as SkinEvent).skin_json
		else:
			continue
		result.append(event_data)
	return result

static func _restore_events(data: Array[EditorSnapshot.EventData]) -> Array[ChartEvent]:
	var result: Array[ChartEvent] = []
	for event_data in data:
		var event: ChartEvent = null
		match event_data.type:
			EditorSnapshot.EventData.Kind.CAMERA:
				var camera := CameraEvent.new()
				for frame_data in event_data.frames:
					var frame := CameraEventFrame.new()
					frame.time = frame_data.time
					frame.ease = frame_data.ease
					frame.follow_character = frame_data.follow_character
					frame.position = frame_data.position
					frame.zoom = frame_data.zoom
					camera.frames.append(frame)
				event = camera
			EditorSnapshot.EventData.Kind.OVERLAY:
				var overlay := OverlayEvent.new()
				overlay.x = event_data.x
				for frame_data in event_data.frames:
					var frame := OverlayEventFrame.new()
					frame.time = frame_data.time
					frame.ease = frame_data.ease
					frame.position = frame_data.position
					frame.scale = frame_data.scale
					frame.rotation = frame_data.rotation
					frame.sprite = frame_data.sprite
					frame.opacity = frame_data.opacity
					frame.has_opacity = frame_data.has_opacity
					overlay.frames.append(frame)
				var overlay_anchor := event_data.anchor
				if OverlayEventFrame.is_valid_anchor(overlay_anchor):
					overlay.anchor = overlay_anchor
				event = overlay
			EditorSnapshot.EventData.Kind.THEME:
				var theme := ThemeEvent.new()
				for frame_data in event_data.frames:
					var frame := ThemeEventFrame.new()
					frame.time = frame_data.time
					frame.ease = frame_data.ease
					frame.bg_color = frame_data.bg_color
					frame.bg_color_2 = frame_data.bg_color_2
					frame.rail_color = frame_data.rail_color
					theme.frames.append(frame)
				event = theme
			EditorSnapshot.EventData.Kind.SKIN:
				var skin := SkinEvent.new()
				skin.skin_json = event_data.skin_json
				event = skin
		if event == null:
			continue
		event.id = event_data.id
		event.time = event_data.time
		event.duration = event_data.duration
		result.append(event)
	return result

static func _capture_selection(selection: ChartEditorSelection) -> EditorSnapshot.SelectionData:
	var data := EditorSnapshot.SelectionData.new()
	if selection != null and selection.selected_event != null:
		data.kind = EditorSnapshot.SelectionData.Kind.EVENT
		for item: EditorEventItem in selection.selected_event_items:
			var frames: Array = item.event.frames if not item.event is SkinEvent else []
			data.items.append(EditorSnapshot.EventIndex.new(CM.parsed_chart.events.find(item.event), frames.find(item.frame)))
		data.event_index = CM.parsed_chart.events.find(selection.selected_event) if CM.parsed_chart != null else -1
		data.event_id = selection.selected_event.id
		data.event_time = selection.selected_event.time
		data.frame_index = selection.selected_event_frame_index
		return data
	if selection == null or selection.selected_rail == null:
		return data
	data.kind = EditorSnapshot.SelectionData.Kind.RAIL
	data.rail_id = selection.selected_rail.id
	for note: Note in selection.selected_notes:
		var owner: Rail = selection.selected_notes[note]
		data.notes.append(EditorSnapshot.NoteIndex.new(owner.id, owner.notes.find(note)))
	for point: RailPoint in selection.selected_points:
		var owner: Rail = selection.selected_points[point]
		data.points.append(EditorSnapshot.PointIndex.new(owner.id, owner.points.find(point)))
	if selection.selected_note != null:
		data.kind = EditorSnapshot.SelectionData.Kind.NOTE
		data.note_index = selection.selected_rail.notes.find(selection.selected_note)
	elif selection.has_point():
		data.kind = EditorSnapshot.SelectionData.Kind.POINT
		data.point_index = selection.selected_point_index
	return data

static func _restore_selection(editor: ChartEditor, data: EditorSnapshot.SelectionData) -> void:
	if data == null:
		editor.selection.clear()
		return
	_restore_primary_selection(editor, data)
	if CM.parsed_chart == null:
		return
	if data.kind == EditorSnapshot.SelectionData.Kind.EVENT:
		editor.selection.selected_event_items.clear()
		for item: EditorSnapshot.EventIndex in data.items:
			var index := item.event_index
			if index < 0 or index >= CM.parsed_chart.events.size():
				continue
			var event: ChartEvent = CM.parsed_chart.events[index]
			var frames: Array = event.frames if not event is SkinEvent else []
			var fi := item.frame_index
			editor.selection.selected_event_items.append(EditorEventItem.new(event, frames[fi] if fi >= 0 and fi < frames.size() else null))
	for entry: EditorSnapshot.NoteIndex in data.notes:
		for rail: Rail in CM.parsed_chart.rails:
			var index := entry.note_index
			if rail.id == entry.rail_id and index >= 0 and index < rail.notes.size():
				editor.selection.selected_notes[rail.notes[index]] = rail
	for entry: EditorSnapshot.PointIndex in data.points:
		for rail: Rail in CM.parsed_chart.rails:
			var index := entry.point_index
			if rail.id == entry.rail_id and index >= 0 and index < rail.points.size():
				editor.selection.selected_points[rail.points[index]] = rail
	editor.selection.refresh()

static func _restore_primary_selection(editor: ChartEditor, data: EditorSnapshot.SelectionData) -> void:
	var kind := data.kind
	if kind == EditorSnapshot.SelectionData.Kind.CLEAR:
		editor.selection.clear()
		return
	if kind == EditorSnapshot.SelectionData.Kind.EVENT:
		if CM.parsed_chart == null:
			editor.selection.clear()
			return
		var target_event: ChartEvent = null
		var event_index := data.event_index
		if event_index >= 0 and event_index < CM.parsed_chart.events.size():
			target_event = CM.parsed_chart.events[event_index]
		if target_event == null \
				or target_event.id != data.event_id \
				or target_event.time != data.event_time:
			target_event = null
			for event in CM.parsed_chart.events:
				if event != null \
						and event.id == data.event_id \
						and event.time == data.event_time:
					target_event = event
					break
		if target_event == null:
			editor.selection.clear()
			return
		editor.selection.select_event(target_event, data.frame_index)
		return
	var rail_id := data.rail_id
	var target_rail: Rail = null
	if CM.parsed_chart == null:
		editor.selection.clear()
		return
	for rail in CM.parsed_chart.rails:
		if rail != null and rail.id == rail_id:
			target_rail = rail
			break
	if target_rail == null:
		editor.selection.clear()
		return
	if kind == EditorSnapshot.SelectionData.Kind.NOTE:
		var note_index := data.note_index
		if note_index >= 0 and note_index < target_rail.notes.size():
			editor.selection.select_note(target_rail, target_rail.notes[note_index])
			return
	if kind == EditorSnapshot.SelectionData.Kind.POINT:
		var point_index := data.point_index
		if point_index >= 0 and point_index < target_rail.points.size():
			editor.selection.select_point(target_rail, point_index)
			return
	editor.selection.select_rail(target_rail)
