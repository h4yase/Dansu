extends RefCounted
class_name Parser

const PARSER_V1 = "FILE_VERSION_1"

static func parse_meta(chart: Chart) -> bool:
	var file := FileAccess.open(chart.file_path, FileAccess.READ)
	if file == null:
		Notification.notice("Failed to open chart file: %s" % chart.file_path, Notification.Type.ERROR)
		return false

	var parser: MetaParser = null
	var version: String = file.get_line().strip_edges()
	if version == PARSER_V1:
		parser = MetaParserV1.new()

	if parser != null:
		parser.parse(file, chart)
		chart.build_search_string()
		return true

	Notification.notice("Unsupported chart version ! : %s" % version, Notification.Type.ERROR)
	return false

func parse_object(chart: Chart) -> ParseResult:
	var result := ParseResult.new()
	var file := FileAccess.open(chart.file_path, FileAccess.READ)
	var message: String
	if file == null:
		message = "Failed to open chart file: %s" % chart.file_path
		Notification.notice(message, Notification.Type.ERROR)
		return result.set_error(message)

	var parser: ObjectParser = null
	var version: String = file.get_line().strip_edges()
	if version == PARSER_V1:
		parser = ObjectParserV1.new()

	if parser != null:
		var parsed_chart := parser.parse(file, chart)
		if parsed_chart != null:
			chart.play_time_ms = parsed_chart.get_play_time_ms()
		return result.set_success(parsed_chart)

	message = "Unsupported chart version ! : %s" % version
	Notification.notice(message, Notification.Type.ERROR)
	return result.set_error(message)
