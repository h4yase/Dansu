extends MetaParser
class_name MetaParserV1

enum { METADATA, TIMINGS }

func parse(file: FileAccess, chart: Chart) -> bool:
	var mode := -1
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		if line.begins_with("@"):
			match line:
				"@METADATA":
					mode = METADATA
				"@TIMINGS":
					mode = TIMINGS
				"@ENDMETA":
					break
			continue

		match mode:
			METADATA:
				_parse_metadata_line(chart, line)
			TIMINGS:
				_parse_timing_line(chart, line)

	return true

func _parse_metadata_line(chart: Chart, line: String) -> void:
	var idx := line.find(":")
	if idx == -1:
		return

	var key := line.substr(0, idx).strip_edges().to_lower()
	var value := line.substr(idx + 1).strip_edges()

	match key:
		"uuid":
			chart.uuid = value
		"chartset_uuid":
			if chart.chart_set == null:
				chart.chart_set = ChartSet.new()
			chart.chart_set.uuid = value
		"title":
			chart.title = value
		"artist":
			chart.artist = value
		"creator":
			chart.creator = value
		"difficulty":
			chart.difficulty = value
		"file_audio":
			chart.file_audio = value
		"file_skin":
			chart.file_skin = value
		"file_cover_art":
			chart.file_cover_art = value
		"source":
			chart.source = value
		"tags":
			chart.tags = value
		"version":
			chart.version = int(value) if value.is_valid_int() else chart.version
		"preview_time":
			chart.preview_time = float(value) if value.is_valid_float() else chart.preview_time

func _parse_timing_line(chart: Chart, line: String) -> void:
	var parts := line.split(",", false)
	if parts.size() < 2:
		return

	var new_timing := Timing.new()
	new_timing.time = int(parts[0])
	new_timing.bpm = float(parts[1])
	chart.timings.append(new_timing)
