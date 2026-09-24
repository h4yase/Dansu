extends RefCounted
class_name Replay

const DIRECTORY := "user://replays"
const EXTENSION := ".replay"

var inputs: Array[ReplayInput] = []
var chart: Chart


var chart_uuid := ""

@warning_ignore("shadowed_global_identifier")
var hash: String


func setup(chart_value: Chart) -> void:
	chart = chart_value
	chart_uuid = chart_value.uuid if chart_value != null else ""
	hash = chart_value.filehash.to_lower() if chart_value != null else ""


func add_input(timing: int, type: int) -> ReplayInput:
	if not ReplayInput.is_valid_type(type):
		return null
	var replay_input := ReplayInput.new(timing, type as ReplayInput.InputType)
	replay_input.order = inputs.size()
	inputs.append(replay_input)
	return replay_input


func to_bytes() -> PackedByteArray:
	var input_parts := PackedStringArray()
	var ordered_inputs := inputs.duplicate()
	ordered_inputs.sort_custom(func(a: ReplayInput, b: ReplayInput) -> bool:
		if a.timing == b.timing:
			return a.order < b.order
		return a.timing < b.timing
	)
	for replay_input in ordered_inputs:
		if replay_input != null and ReplayInput.is_valid_type(int(replay_input.type)):
			input_parts.append("%d,%d" % [replay_input.timing, int(replay_input.type)])
	return ("%s\n%s\n%s" % [chart_uuid, hash.to_lower(), ";".join(input_parts)]).to_utf8_buffer()


func sha256() -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(to_bytes()) != OK:
		return ""
	return context.finish().hex_encode()


func save(submission_id: String) -> String:
	if submission_id.is_empty() or chart_uuid.is_empty() or hash.length() != 64:
		return ""
	if DirAccess.make_dir_recursive_absolute(DIRECTORY) != OK:
		return ""
	var path := path_for(submission_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(to_bytes())
	file.close()
	return path


static func path_for(submission_id: String) -> String:
	if submission_id.is_empty():
		return ""
	return DIRECTORY.path_join(submission_id + EXTENSION)


static func load_file(path: String, chart_value: Chart = null) -> Replay:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var replay := from_bytes(file.get_buffer(file.get_length()), chart_value)
	file.close()
	return replay


static func from_bytes(data: PackedByteArray, chart_value: Chart = null) -> Replay:
	var text := data.get_string_from_utf8().replace("\r\n", "\n")
	if text.ends_with("\n"):
		text = text.left(-1)
	var lines := text.split("\n", true)
	if lines.size() != 3:
		return null
	var replay := Replay.new()
	replay.chart_uuid = lines[0]
	replay.hash = lines[1].to_lower()
	if not _is_uuid(replay.chart_uuid) or not _is_sha256(replay.hash):
		return null
	if chart_value != null:
		if replay.chart_uuid.to_lower() != chart_value.uuid.to_lower():
			return null
		if replay.hash != chart_value.filehash.to_lower():
			return null
		replay.chart = chart_value
	var previous_timing := -9223372036854775807
	if not lines[2].is_empty():
		for encoded_input in lines[2].split(";", false):
			var parts := encoded_input.split(",", true)
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				return null
			var timing := int(parts[0])
			var type := int(parts[1])
			if timing < previous_timing or not ReplayInput.is_valid_type(type):
				return null
			replay.add_input(timing, type)
			previous_timing = timing
	return replay


static func _is_uuid(value: String) -> bool:
	if value.length() != 36:
		return false
	for index in range(value.length()):
		if index in [8, 13, 18, 23]:
			if value[index] != "-":
				return false
		elif value[index].to_lower() not in "0123456789abcdef":
			return false
	return true


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value.to_lower():
		if character not in "0123456789abcdef":
			return false
	return true
