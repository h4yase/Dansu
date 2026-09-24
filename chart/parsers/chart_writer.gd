extends RefCounted
class_name ChartWriter

const CHART_FILE_VERSION := 1

func write_chart(parsed_chart: ParsedChart, destination_path := "") -> bool:
	if parsed_chart == null or parsed_chart.chart == null:
		push_error("Failed to write chart: parsed chart is missing chart metadata")
		return false

	var chart := parsed_chart.chart
	if chart.chart_set == null:
		push_error("Failed to write chart: chart set is missing")
		return false
	if chart.chart_set.uuid.is_empty():
		chart.chart_set.build_uuid()
	var output_path := chart.file_path if destination_path.is_empty() else destination_path
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open chart file for writing: %s" % output_path)
		return false

	_write_header(file)
	_write_metadata(file, chart)
	_write_timings(file, chart)
	_write_hitsounds(file, parsed_chart)
	parsed_chart.sort_events()
	_write_events(file, parsed_chart.events)
	_write_rails(file, parsed_chart.rails)
	file.flush()
	file.close()
	return true

func _write_header(file: FileAccess) -> void:
	file.store_line("FILE_VERSION_" + str(CHART_FILE_VERSION))

func _write_metadata(file: FileAccess, chart: Chart) -> void:
	file.store_line("@METADATA")
	if not chart.uuid:
		chart.build_uuid()
	file.store_line("uuid: %s" % _safe_string(chart.uuid))
	file.store_line("chartset_uuid: %s" % _safe_string(chart.chart_set.uuid))
	file.store_line("title: %s" % _safe_string(chart.title))
	file.store_line("artist: %s" % _safe_string(chart.artist))
	file.store_line("creator: %s" % _safe_string(chart.creator))
	file.store_line("source: %s" % _safe_string(chart.source))
	file.store_line("preview_time: %s" % _safe_string(chart.preview_time))
	file.store_line("difficulty: %s" % _safe_string(chart.difficulty))
	file.store_line("file_audio: %s" % _safe_string(chart.file_audio))
	file.store_line("file_skin: %s" % _safe_string(chart.file_skin))
	file.store_line("file_cover_art: %s" % _safe_string(chart.file_cover_art))
	file.store_line("version: %s" % _safe_string(chart.version))
	file.store_line("tags: %s" % _safe_string(chart.tags))
	file.store_line("")

func _write_timings(file: FileAccess, chart: Chart) -> void:
	file.store_line("@TIMINGS")
	for timing in chart.timings:
		if timing != null:
			file.store_line("%d,%s" % [timing.time, timing.bpm])
	file.store_line("")
	file.store_line("@ENDMETA")
	file.store_line("")

func _write_hitsounds(file: FileAccess, parsed_chart: ParsedChart) -> void:
	file.store_line("@HITSOUNDS")
	var chart := parsed_chart.chart
	var referenced_ids := _collect_referenced_hitsound_ids(parsed_chart)
	for hitsound in parsed_chart.hitsounds:
		if hitsound == null or hitsound.id < 0:
			continue
		if hitsound.is_builtin() and not referenced_ids.has(hitsound.id):
			continue
		file.store_line("%d:%s" % [hitsound.id, _safe_string(hitsound.file_name)])
	file.store_line("defaults:%s" % ",".join(_default_hitsound_texts(chart)))
	file.store_line("")

func _write_events(file: FileAccess, events: Array[ChartEvent]) -> void:
	file.store_line("@EVENTS")
	file.store_line("# camera:id")
	file.store_line("# [time,follow_character,x,y,zoom,e:ease]")
	file.store_line("# overlay:id,time,duration,x:position(0-9),a:anchor")
	file.store_line("# [offset,x,y,scale_x,scale_y,rotation,s:sprite,o:opacity,e:ease]")
	file.store_line("# theme:id")
	file.store_line("# [time,bg_color,bg_color_2,rail_color,e:ease]")
	file.store_line("# skin:id,time,skin_json")

	for event in events:
		if event == null or not _is_valid_event_id(event.id):
			continue
		if event is CameraEvent:
			_write_camera_event(file, event as CameraEvent)
		elif event is OverlayEvent:
			_write_overlay_event(file, event as OverlayEvent)
		elif event is ThemeEvent:
			_write_theme_event(file, event as ThemeEvent)
		elif event is SkinEvent:
			_write_skin_event(file, event as SkinEvent)

	file.store_line("")

func _write_camera_event(file: FileAccess, event: CameraEvent) -> void:
	file.store_line("camera:%s" % event.id.strip_edges())
	event.sort_frames()
	for frame in event.frames:
		if frame == null:
			continue
		var tokens: Array[String] = [
			str(event.time + frame.time),
			"1" if frame.follow_character else "0",
			_float_to_text(frame.position.x),
			_float_to_text(frame.position.y),
			_float_to_text(frame.zoom),
		]
		_append_ease(tokens, frame.ease)
		file.store_line("[%s]" % ",".join(tokens))
	file.store_line("end")
	file.store_line("")

func _write_overlay_event(file: FileAccess, event: OverlayEvent) -> void:
	var header_tokens: Array[String] = [event.id.strip_edges(), str(event.time), str(event.duration)]
	if event.x != 0:
		header_tokens.append("x:%d" % event.x)
	if event.anchor != "center":
		if OverlayEventFrame.is_valid_anchor(event.anchor):
			header_tokens.append("a:%s" % event.anchor)
		else:
			push_warning("Replaced invalid overlay anchor with center: %s" % event.anchor)
	file.store_line("overlay:%s" % ",".join(header_tokens))
	event.sort_frames()
	for frame in event.frames:
		if frame == null:
			continue
		var tokens: Array[String] = [
			str(frame.time),
			_float_to_text(frame.position.x),
			_float_to_text(frame.position.y),
			_float_to_text(frame.scale.x),
			_float_to_text(frame.scale.y),
			_float_to_text(frame.rotation),
		]
		if not frame.sprite.is_empty():
			if EventResourceRef.is_valid(frame.sprite):
				tokens.append("s:%s" % frame.sprite.strip_edges())
			else:
				push_warning("Skipped invalid event resource reference: %s" % frame.sprite)
		if frame.has_opacity:
			tokens.append("o:%s" % _float_to_text(frame.opacity))
		_append_ease(tokens, frame.ease)
		file.store_line("[%s]" % ",".join(tokens))
	file.store_line("end")
	file.store_line("")

func _write_theme_event(file: FileAccess, event: ThemeEvent) -> void:
	file.store_line("theme:%s" % event.id.strip_edges())
	event.sort_frames()
	for frame in event.frames:
		if frame == null:
			continue
		var tokens: Array[String] = [
			str(event.time + frame.time),
			_color_to_text(frame.bg_color),
			_color_to_text(frame.bg_color_2),
			_color_to_text(frame.rail_color),
		]
		_append_ease(tokens, frame.ease)
		file.store_line("[%s]" % ",".join(tokens))
	file.store_line("end")
	file.store_line("")

func _write_skin_event(file: FileAccess, event: SkinEvent) -> void:
	if not EventResourceRef.is_valid(event.skin_json):
		push_warning("Skipped invalid skin event resource reference: %s" % event.skin_json)
		return
	file.store_line("skin:%s,%d,%s" % [event.id.strip_edges(), event.time, event.skin_json.strip_edges()])
	file.store_line("")

func _append_ease(tokens: Array[String], _ease: String) -> void:
	var value := _ease.strip_edges()
	if not value.is_empty() and not value.contains(",") and not value.contains("\n") and not value.contains("\r"):
		tokens.append("e:%s" % value)

func _is_valid_event_id(event_id: String) -> bool:
	var value := event_id.strip_edges()
	return not value.is_empty() and not value.contains(",") and not value.contains("\n") and not value.contains("\r")

func _color_to_text(color: Color) -> String:
	return "#" + color.to_html(not is_equal_approx(color.a, 1.0))

func _write_rails(file: FileAccess, rails: Array[Rail]) -> void:
	file.store_line("@OBJECT")
	file.store_line("# rail:{id}")
	file.store_line("# [time,curve,x]")
	file.store_line("# time,type,length,direction(d:optional),animation(a:optional),hitsound(h:optional)")
	file.store_line("# end")

	for rail in rails:
		if rail == null or rail.id < 0:
			continue

		file.store_line("rail:%d" % rail.id)
		for point: RailPoint in rail.points:
			if point != null:
				file.store_line("[%d,%s,%s]" % [int(point.time), _float_to_text(float(point.curve)), _float_to_text(float(point.x))])

		for note: Note in rail.notes:
			if note == null:
				continue

			var tokens: Array[String] = [str(int(note.time)), str(int(note.type)), str(int(note.length))]
			if int(note.animation) != 0:
				tokens.append("a:%d" % int(note.animation))
			if int(note.hitsound) >= 0:
				tokens.append("h:%d" % int(note.hitsound))
			if int(note.type) == 2 and int(note.dir) != -1:
				tokens.append("d:%d" % int(note.dir))
			file.store_line(",".join(tokens))

		file.store_line("end")
		file.store_line("")

	file.store_line("")

func _safe_string(value) -> String:
	return str(value).strip_edges()

func _float_to_text(value: float) -> String:
	var text := str(value)
	if "." in text:
		while text.ends_with("0"):
			text = text.left(text.length() - 1)
		if text.ends_with("."):
			text += "0"
	return text

func _collect_referenced_hitsound_ids(parsed_chart: ParsedChart) -> Dictionary:
	var ids: Dictionary = {}
	if parsed_chart == null:
		return ids
	var chart := parsed_chart.chart
	if chart != null:
		for value in chart.default_hitsounds:
			if int(value) >= 0:
				ids[int(value)] = true
	for rail in parsed_chart.rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note != null and int(note.hitsound) >= 0:
				ids[int(note.hitsound)] = true
	return ids

func _default_hitsound_texts(chart: Chart) -> Array[String]:
	var values: Array[String] = []
	if chart == null:
		for _index in range(Chart.DEFAULT_HITSOUND_SLOT_COUNT):
			values.append("-1")
		return values
	for index in range(Chart.DEFAULT_HITSOUND_SLOT_COUNT):
		values.append(str(chart.get_default_hitsound_id(index)))
	return values
