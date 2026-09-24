extends RefCounted
class_name ChartFileStore

static func save(parsed_chart: ParsedChart, previous_path := "") -> bool:
	if parsed_chart == null or parsed_chart.chart == null:
		return false
	var target_path := parsed_chart.chart.file_path
	FileSystem.ensure_dir(target_path.get_base_dir())
	var temporary_path := target_path + ".tmp"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	if not ChartWriter.new().write_chart(parsed_chart, temporary_path):
		return false
	if not FileSystem.replace_file(temporary_path, target_path):
		push_error("Failed to replace chart file: %s" % target_path)
		return false
	if not previous_path.is_empty() and previous_path != target_path and FileAccess.file_exists(previous_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(previous_path))
	return true
