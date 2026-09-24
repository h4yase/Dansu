extends RefCounted
class_name ParseResult

var success := false
var parsed_chart: ParsedChart = null
var error_message := ""

func set_error(message: String) -> ParseResult:
	success = false
	error_message = message
	parsed_chart = null
	return self

func set_success(value: ParsedChart) -> ParseResult:
	success = value != null
	parsed_chart = value
	error_message = ""
	return self
