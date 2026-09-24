extends RefCounted
class_name SkinRefCleanup

static func clear_invalid_animation_refs_for_skin(
	chart_folder_path: String,
	skin_file_name: String,
	valid_ids: Array[int],
	current_chart = null
) -> void:
	var valid_lookup := {}
	for animation_id in valid_ids:
		valid_lookup[int(animation_id)] = true

	if current_chart != null and current_chart.file_skin == skin_file_name:
		_clear_invalid_refs_in_loaded_chart(valid_lookup)

	if not DirAccess.dir_exists_absolute(chart_folder_path):
		return

	for file_name in DirAccess.get_files_at(chart_folder_path):
		if not file_name.ends_with(Config.FILE_EXTENSION):
			continue
		var full_path := chart_folder_path.path_join(file_name)
		_rewrite_chart_animation_refs(full_path, skin_file_name, valid_lookup)

static func rename_skin_references(chart_folder_path: String, old_skin_name: String, new_skin_name: String) -> void:
	if old_skin_name == "" or new_skin_name == "" or old_skin_name == new_skin_name:
		return
	if not DirAccess.dir_exists_absolute(chart_folder_path):
		return

	for file_name in DirAccess.get_files_at(chart_folder_path):
		if not file_name.ends_with(Config.FILE_EXTENSION):
			continue

		var full_path := chart_folder_path.path_join(file_name)
		var lines := _read_lines(full_path)
		if lines.is_empty():
			continue

		var changed := false
		for index in range(lines.size()):
			if lines[index].begins_with("file_skin:"):
				var value := lines[index].trim_prefix("file_skin:").strip_edges()
				if value == old_skin_name:
					lines[index] = "file_skin: %s" % new_skin_name
					changed = true
				break

		if changed:
			_write_lines(full_path, lines)

static func _clear_invalid_refs_in_loaded_chart(valid_lookup: Dictionary) -> void:
	if CM.parsed_chart == null:
		return
	for rail in CM.parsed_chart.rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note == null:
				continue
			if int(note.animation) != 0 and not valid_lookup.has(int(note.animation)):
				note.animation = 0

static func _rewrite_chart_animation_refs(full_path: String, skin_file_name: String, valid_lookup: Dictionary) -> void:
	var lines := _read_lines(full_path)
	if lines.is_empty():
		return

	var referenced_skin := ""
	for line in lines:
		if line.begins_with("file_skin:"):
			referenced_skin = line.trim_prefix("file_skin:").strip_edges()
			break

	if referenced_skin != skin_file_name:
		return

	var changed := false
	for index in range(lines.size()):
		var line := lines[index].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("@") or line.begins_with("rail:") or line == "end":
			continue
		if line.begins_with("[") and line.ends_with("]"):
			continue

		var parts := line.split(",", false)
		if parts.size() < 3:
			continue

		var next_tokens: Array[String] = []
		var line_changed := false
		for token in parts:
			var trimmed := token.strip_edges()
			if trimmed.begins_with("a:"):
				var animation_id := int(trimmed.trim_prefix("a:"))
				if not valid_lookup.has(animation_id):
					line_changed = true
					continue
			next_tokens.append(trimmed)

		if line_changed:
			lines[index] = ",".join(next_tokens)
			changed = true

	if changed:
		_write_lines(full_path, lines)

static func _read_lines(full_path: String) -> PackedStringArray:
	if not FileAccess.file_exists(full_path):
		return PackedStringArray()
	var text := FileAccess.get_file_as_string(full_path)
	return text.split("\n")

static func _write_lines(full_path: String, lines: PackedStringArray) -> void:
	var file := FileAccess.open(full_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(lines))
	if lines.is_empty() or not String(lines[lines.size() - 1]).ends_with("\n"):
		file.store_string("\n")
	file.close()
