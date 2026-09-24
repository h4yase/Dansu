extends RefCounted
class_name EventResourceRef

const CHART_DIRECTORY_NAME := "eventres"
const BUILTIN_PREFIX := "res/"
const BUILTIN_SPRITE_BASE_PATH := "res://resources/events/sprites"
const BUILTIN_SKIN_BASE_PATH := "res://resources/events/skins"
const INVALID_FILE_NAME_CHARACTERS := ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", ","]
const SPRITE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "svg"]

static func is_builtin(_reference: String) -> bool:
	return _reference.strip_edges().begins_with(BUILTIN_PREFIX)

static func is_valid(_reference: String) -> bool:
	var file_name := _reference.strip_edges()
	if file_name.begins_with(BUILTIN_PREFIX):
		file_name = file_name.trim_prefix(BUILTIN_PREFIX)
	if file_name.is_empty() or file_name == "." or file_name == "..":
		return false
	for character in INVALID_FILE_NAME_CHARACTERS:
		if file_name.contains(character):
			return false
	return true

static func resolve(chart: Chart, _reference: String, builtin_base_path: String) -> String:
	var normalized := _reference.strip_edges()
	if not is_valid(normalized):
		return ""
	if is_builtin(normalized):
		return builtin_base_path.path_join(normalized.trim_prefix(BUILTIN_PREFIX))
	if chart == null:
		return ""
	return chart.folder_path.path_join(CHART_DIRECTORY_NAME).path_join(normalized)

static func resolve_sprite(chart: Chart, _reference: String) -> String:
	return resolve(chart, _reference, BUILTIN_SPRITE_BASE_PATH)

static func resolve_skin(chart: Chart, _reference: String) -> String:
	return resolve(chart, _reference, BUILTIN_SKIN_BASE_PATH)

static func import_sprite(chart: Chart, source_path: String) -> String:
	return _import_chart_resource(chart, source_path, SPRITE_EXTENSIONS, "sprite")

static func _import_chart_resource(chart: Chart, source_path: String, allowed_extensions: PackedStringArray, fallback_name: String) -> String:
	if chart == null:
		return ""

	var normalized_source := source_path.simplify_path()
	if not FileAccess.file_exists(normalized_source):
		return ""

	var extension := normalized_source.get_extension().to_lower()
	if not allowed_extensions.has(extension):
		return ""

	var file_name := normalized_source.get_file()
	if is_valid(file_name):
		var existing_reference := _try_make_existing_chart_reference(chart, normalized_source)
		if not existing_reference.is_empty():
			return existing_reference

	var target_directory := chart.folder_path.path_join(CHART_DIRECTORY_NAME)
	var target_path := FileSystem.copy_file_unique(normalized_source, target_directory, fallback_name)
	return target_path.get_file() if not target_path.is_empty() else ""

static func _try_make_existing_chart_reference(chart: Chart, source_path: String) -> String:
	var target_directory := ProjectSettings.globalize_path(chart.folder_path.path_join(CHART_DIRECTORY_NAME)).simplify_path().replace("\\", "/")
	var normalized_source := source_path.simplify_path().replace("\\", "/")
	if normalized_source.get_base_dir().to_lower() != target_directory.to_lower():
		return ""
	var file_name := normalized_source.get_file()
	return file_name if is_valid(file_name) else ""
