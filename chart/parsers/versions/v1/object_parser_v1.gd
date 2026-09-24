extends ObjectParser
class_name ObjectParserV1

class ClipHeader extends RefCounted:
	var id: String
	var time: int
	var duration: int

	func _init(p_id: String, p_time: int, p_duration: int) -> void:
		id = p_id
		time = p_time
		duration = p_duration

class OptionalToken extends RefCounted:
	var key: String
	var value: String

	func _init(p_key: String = "", p_value: String = "") -> void:
		key = p_key
		value = p_value


enum { OBJECT, HITSOUNDS, EVENTS }

func parse(file: FileAccess, chart: Chart) -> ParsedChart:
	var parsed_chart := ParsedChart.new(chart)
	parsed_chart.hitsounds.append_array(HitSound.load_builtin_hitsounds())
	var mode := -1
	var current_rail: Rail = null
	var current_event: ChartEvent = null
	if chart != null:
		chart.reset_default_hitsounds()

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		if line.begins_with("@"):
			current_event = null
			match line.replace(" ", ""):
				"@HITSOUNDS":
					mode = HITSOUNDS
				"@OBJECT":
					mode = OBJECT
				"@EVENTS":
					mode = EVENTS
			continue

		match mode:
			OBJECT:
				current_rail = _parse_rail_line(line, current_rail, parsed_chart)
			HITSOUNDS:
				_parse_hitsound_line(chart, line, parsed_chart)
			EVENTS:
				current_event = _parse_event_line(line, current_event, parsed_chart)

	parsed_chart.sort_events()
	return parsed_chart

func _parse_event_line(line: String, current_event: ChartEvent, parsed_chart: ParsedChart) -> ChartEvent:
	if line == "end":
		return null

	if line.begins_with("camera:"):
		var camera := _parse_camera_event(line)
		if camera != null:
			parsed_chart.events.append(camera)
		return camera
	if line.begins_with("overlay:"):
		var overlay := _parse_overlay_event(line)
		if overlay != null:
			parsed_chart.events.append(overlay)
		return overlay
	if line.begins_with("theme:"):
		var theme := _parse_theme_event(line)
		if theme != null:
			parsed_chart.events.append(theme)
		return theme
	if line.begins_with("skin:"):
		var skin := _parse_skin_event(line)
		if skin != null:
			parsed_chart.events.append(skin)
		return null

	if current_event == null or not line.begins_with("[") or not line.ends_with("]"):
		return current_event

	if current_event is CameraEvent:
		var camera_frame := _parse_camera_frame(line)
		if camera_frame != null:
			(current_event as CameraEvent).frames.append(camera_frame)
	elif current_event is OverlayEvent:
		var overlay_frame := _parse_overlay_frame(line)
		if overlay_frame != null:
			var overlay_event := current_event as OverlayEvent
			overlay_event.frames.append(overlay_frame)
			if overlay_event.anchor == "center" and overlay_frame.anchor != "center":
				overlay_event.anchor = overlay_frame.anchor
	elif current_event is ThemeEvent:
		var theme_frame := _parse_theme_frame(line)
		if theme_frame != null:
			(current_event as ThemeEvent).frames.append(theme_frame)

	return current_event

func _parse_camera_event(line: String) -> CameraEvent:
	var event := CameraEvent.new()
	event.id = line.trim_prefix("camera:").strip_edges()
	return event

func _parse_overlay_event(line: String) -> OverlayEvent:
	var values := _parse_clip_header(line, "overlay:")
	if values == null:
		return null
	var event := OverlayEvent.new()
	_assign_clip_header(event, values)
	var parts := line.trim_prefix("overlay:").split(",", false)
	for index in range(3, parts.size()):
		var token := _parse_optional_token(parts[index])
		match token.key:
			"x":
				var layer_text := token.value
				if layer_text.is_valid_int():
					event.x = clampi(int(layer_text), 0, 9)
			"a":
				var anchor := token.value
				if OverlayEventFrame.is_valid_anchor(anchor):
					event.anchor = anchor
				else:
					push_error("FILE : WRONG OVERLAY ANCHOR PRESET : %s" % anchor)
	return event

func _parse_theme_event(line: String) -> ThemeEvent:
	var event := ThemeEvent.new()
	event.id = line.trim_prefix("theme:").strip_edges()
	return event

func _parse_skin_event(line: String) -> SkinEvent:
	var parts := line.trim_prefix("skin:").split(",", false)
	if parts.size() != 3:
		push_error("FILE : WRONG SKIN EVENT FORMAT : %s" % line)
		return null
	var event_id := parts[0].strip_edges()
	var time_text := parts[1].strip_edges()
	var skin_json := parts[2].strip_edges()
	if event_id.is_empty() or not time_text.is_valid_int() or not EventResourceRef.is_valid(skin_json):
		push_error("FILE : WRONG SKIN EVENT FORMAT : %s" % line)
		return null
	var event := SkinEvent.new()
	event.id = event_id
	event.time = int(time_text)
	event.duration = 0
	event.skin_json = skin_json
	return event

func _parse_clip_header(line: String, prefix: String) -> ClipHeader:
	var parts := line.trim_prefix(prefix).split(",", false)
	if parts.size() < 3:
		push_error("FILE : WRONG EVENT HEADER FORMAT : %s" % line)
		return null
	var event_id := parts[0].strip_edges()
	var time_text := parts[1].strip_edges()
	var duration_text := parts[2].strip_edges()
	if event_id.is_empty() or not time_text.is_valid_int() or not duration_text.is_valid_int():
		push_error("FILE : WRONG EVENT HEADER FORMAT : %s" % line)
		return null
	return ClipHeader.new(event_id, int(time_text), int(duration_text))

func _assign_clip_header(event: ChartEvent, values: ClipHeader) -> void:
	event.id = values.id
	event.time = values.time
	event.duration = values.duration

func _parse_camera_frame(line: String) -> CameraEventFrame:
	var parts := _parse_frame_parts(line)
	if parts.size() < 5:
		push_error("FILE : WRONG CAMERA FRAME FORMAT : %s" % line)
		return null
	var follow_text := parts[1].strip_edges().to_lower()
	if not parts[0].strip_edges().is_valid_int() \
			or follow_text not in ["0", "1", "false", "true"] \
			or not _are_valid_floats(parts, 2, 5):
		push_error("FILE : WRONG CAMERA FRAME FORMAT : %s" % line)
		return null

	var frame := CameraEventFrame.new()
	frame.time = int(parts[0].strip_edges())
	frame.follow_character = follow_text == "1" or follow_text == "true"
	frame.position = Vector2(float(parts[2]), float(parts[3]))
	frame.zoom = float(parts[4])
	frame.ease = _parse_ease(parts, 5)
	return frame

func _parse_overlay_frame(line: String) -> OverlayEventFrame:
	var parts := _parse_frame_parts(line)
	if parts.size() < 6 or not parts[0].strip_edges().is_valid_int() or not _are_valid_floats(parts, 1, 6):
		push_error("FILE : WRONG OVERLAY FRAME FORMAT : %s" % line)
		return null

	var frame := OverlayEventFrame.new()
	frame.time = int(parts[0].strip_edges())
	frame.position = Vector2(float(parts[1]), float(parts[2]))
	frame.scale = Vector2(float(parts[3]), float(parts[4]))
	frame.rotation = float(parts[5])
	var optional_start := 6
	if parts.size() > 6 and not parts[6].contains(":"):
		if parts.size() < 8 or not _are_valid_floats(parts, 6, 8):
			push_error("FILE : WRONG OVERLAY FRAME ANCHOR FORMAT : %s" % line)
			return null
		var legacy_anchor := Vector2(
			clampf(float(parts[6]), 0.0, 1.0),
			clampf(float(parts[7]), 0.0, 1.0)
		)
		frame.anchor = OverlayEventFrame.vector_to_anchor(legacy_anchor)
		optional_start = 8
	for index in range(optional_start, parts.size()):
		var token := _parse_optional_token(parts[index])
		match token.key:
			"a":
				var anchor := token.value
				if OverlayEventFrame.is_valid_anchor(anchor):
					frame.anchor = anchor
				else:
					push_error("FILE : WRONG OVERLAY ANCHOR PRESET : %s" % anchor)
			"s":
				var sprite := token.value
				if EventResourceRef.is_valid(sprite):
					frame.sprite = sprite
				else:
					push_error("FILE : WRONG EVENT RESOURCE REFERENCE : %s" % sprite)
			"o":
				var opacity_text := token.value
				if opacity_text.is_valid_float():
					frame.opacity = float(opacity_text)
					frame.has_opacity = true
			"e":
				frame.ease = token.value
	return frame

func _parse_theme_frame(line: String) -> ThemeEventFrame:
	var parts := _parse_frame_parts(line)
	if parts.size() < 4 or not parts[0].strip_edges().is_valid_int():
		push_error("FILE : WRONG THEME FRAME FORMAT : %s" % line)
		return null
	for index in range(1, 4):
		if not Color.html_is_valid(parts[index].strip_edges()):
			push_error("FILE : WRONG THEME FRAME COLOR : %s" % line)
			return null

	var frame := ThemeEventFrame.new()
	frame.time = int(parts[0].strip_edges())
	frame.bg_color = Color.from_string(parts[1].strip_edges(), Color.BLACK)
	frame.bg_color_2 = Color.from_string(parts[2].strip_edges(), Color.BLACK)
	frame.rail_color = Color.from_string(parts[3].strip_edges(), Color.WHITE)
	frame.ease = _parse_ease(parts, 4)
	return frame

func _parse_frame_parts(line: String) -> PackedStringArray:
	return line.substr(1, line.length() - 2).split(",", false)

func _are_valid_floats(parts: PackedStringArray, from_index: int, to_index: int) -> bool:
	for index in range(from_index, to_index):
		if not parts[index].strip_edges().is_valid_float():
			return false
	return true

func _parse_ease(parts: PackedStringArray, from_index: int) -> String:
	for index in range(from_index, parts.size()):
		var token := _parse_optional_token(parts[index])
		if token.key == "e":
			return token.value
	return ""

func _parse_optional_token(text: String) -> OptionalToken:
	var token := text.strip_edges()
	var separator_index := token.find(":")
	if separator_index <= 0:
		return OptionalToken.new()
	return OptionalToken.new(token.substr(0, separator_index).strip_edges(), token.substr(separator_index + 1).strip_edges())

func _parse_note_line(line: String) -> Note:
	var parts := line.split(",", false)
	if parts.size() < 3:
		push_error("FILE : WRONG NOTE FORMAT : %s" % line)
		return null

	var new_note := Note.new()
	new_note.time = int(parts[0])
	new_note.type = int(parts[1]) as Note.NoteType
	new_note.length = int(parts[2])

	for i in range(3, parts.size()):
		var token := parts[i].strip_edges()
		var idx := token.find(":")
		if idx == -1:
			continue

		var key := token.substr(0, idx)
		var value := token.substr(idx + 1)
		match key:
			"a":
				new_note.animation = int(value)
			"h":
				new_note.hitsound = int(value)
			"d":
				new_note.dir = int(value) as Note.Dir

	return new_note

func _parse_hitsound_line(chart: Chart, line: String, parsed_chart: ParsedChart) -> void:
	if line.begins_with("defaults:"):
		var values := line.trim_prefix("defaults:").split(",", false)
		for index in range(min(values.size(), Chart.DEFAULT_HITSOUND_SLOT_COUNT)):
			var value_text := values[index].strip_edges()
			if value_text.is_valid_int():
				chart.set_default_hitsound_id(index, value_text.to_int())
		return

	var separator := ":" if line.find(":") != -1 else ","
	var idx := line.find(separator)
	if idx == -1:
		return

	var id_text := line.substr(0, idx).strip_edges()
	var file_name := line.substr(idx + 1).strip_edges()
	if not id_text.is_valid_int():
		return

	var hitsound_id := int(id_text)
	for existing in parsed_chart.hitsounds:
		if existing != null and existing.id == hitsound_id:
			existing.setup(chart, hitsound_id, file_name)
			return

	var hitsound := HitSound.new()
	hitsound.setup(chart, hitsound_id, file_name)
	parsed_chart.hitsounds.append(hitsound)

func _parse_rail_line(line: String, current_rail: Rail, parsed_chart: ParsedChart) -> Rail:
	if line.begins_with("rail:"):
		var id_text := line.trim_prefix("rail:").strip_edges()
		if not id_text.is_valid_int():
			return current_rail

		var new_rail := Rail.new()
		new_rail.id = int(id_text)
		parsed_chart.rails.append(new_rail)
		return new_rail

	if line == "end":
		return null
	if current_rail == null:
		return null

	if line.begins_with("[") and line.ends_with("]"):
		line = line.substr(1, line.length() - 2)
		var parts := line.split(",", false)
		if parts.size() < 3:
			return current_rail

		var point := RailPoint.new()
		point.time = int(parts[0])
		point.curve = float(parts[1])
		point.x = float(parts[2])
		current_rail.points.append(point)
	else:
		var note: Note = _parse_note_line(line)
		if note != null:
			current_rail.notes.append(note)

	return current_rail
