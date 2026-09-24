extends RefCounted
class_name FileSystem

const res_skin_path: String = "res://resources/skins/"
const res_hitsounds_path: String = "res://resources/audio/hitsounds/"
const official_chart_path: String = "res://contents/chartsets"
const packaged_chartsets_manifest_path := "res://contents/chartsets.json"
const chart_package_extensions := ["dansu", "json", "png", "jpg", "jpeg", "webp", "wav", "ogg", "mp3"]
const keep_file_extensions := ["png", "jpg", "jpeg", "webp", "wav", "ogg", "mp3"]
const chartset_uuid_pattern := "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
const community_cache_path: String = "user://cache/community-charts"
const editor_chart_path: String = "user://editor/charts"
const skin_path: String = "user://skins"
const startup_import_dir_name := "import"

static func ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("FILE: failed to make folder : %s", path)


static func packaged_chartsets() -> Dictionary:
	if not FileAccess.file_exists(packaged_chartsets_manifest_path):
		push_error("[charts] packaged chartset manifest is missing: %s" % packaged_chartsets_manifest_path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(packaged_chartsets_manifest_path))
	if not parsed is Dictionary:
		push_error("[charts] packaged chartset manifest must be a JSON object")
		return {}
	var result := {}
	for uuid_value in parsed:
		var uuid := str(uuid_value).strip_edges().to_lower()
		var relative_path := str(parsed[uuid_value]).strip_edges().replace("\\", "/")
		if not _is_chartset_uuid(uuid) or not _is_safe_packaged_chartset_path(relative_path):
			push_warning("[charts] ignoring invalid packaged chartset entry: %s" % uuid_value)
			continue
		result[uuid] = relative_path
	return result


static func packaged_chartset_folders() -> PackedStringArray:
	var folders := PackedStringArray()
	for folder_name in packaged_chartsets().values():
		folders.append(str(folder_name))
	return folders


static func install_packaged_chartset(
	archive_path: String,
	chartset_uuid: String,
	preferred_folder_name: String,
	pack_id: String,
) -> ChartPackageInstaller.InstallResult:
	if not OS.has_feature("editor"):
		return ChartPackageInstaller.InstallResult.failure("Built-in chartsets can only be installed while running from the editor.")

	var uuid := chartset_uuid.strip_edges().to_lower()
	if not _is_chartset_uuid(uuid):
		return ChartPackageInstaller.InstallResult.failure("The chartset UUID is invalid.")

	var normalized_pack_id := pack_id.strip_edges().to_lower()
	if not is_valid_pack_id(normalized_pack_id):
		return ChartPackageInstaller.InstallResult.failure("The pack ID is invalid.")

	var archive_absolute := ProjectSettings.globalize_path(archive_path)
	if not FileAccess.file_exists(archive_absolute):
		return ChartPackageInstaller.InstallResult.failure("The server chart package is missing.")

	if not FileAccess.file_exists(packaged_chartsets_manifest_path):
		return ChartPackageInstaller.InstallResult.failure("The built-in chartset JSON is missing.")
	var raw_manifest = JSON.parse_string(FileAccess.get_file_as_string(packaged_chartsets_manifest_path))
	if not raw_manifest is Dictionary:
		return ChartPackageInstaller.InstallResult.failure("The built-in chartset JSON is invalid.")

	var manifest := packaged_chartsets()
	if manifest.size() != raw_manifest.size():
		return ChartPackageInstaller.InstallResult.failure("The built-in chartset JSON contains invalid entries.")

	var old_relative_path := str(manifest.get(uuid, ""))
	var relative_path := ""

	if not old_relative_path.is_empty() and old_relative_path.get_slice("/", 0).to_lower() == normalized_pack_id:
		relative_path = old_relative_path
	else:
		var preferred_name := preferred_folder_name.get_file().strip_edges()
		if preferred_name.is_empty() and not old_relative_path.is_empty():
			preferred_name = old_relative_path.get_file()
		var folder_name := _unique_packaged_folder_name(
			preferred_name,
			normalized_pack_id,
			manifest,
		)
		if folder_name.is_empty():
			return ChartPackageInstaller.InstallResult.failure("Could not choose a built-in chartset folder name.")
		relative_path = normalized_pack_id.path_join(folder_name).replace("\\", "/")

	var root_absolute := ProjectSettings.globalize_path(official_chart_path)
	ensure_dir(root_absolute)

	var target_absolute := root_absolute.path_join(relative_path)
	ensure_dir(target_absolute.get_base_dir())

	var staging_absolute := root_absolute.path_join(".%s.builtin-stage" % uuid)
	var backup_absolute := root_absolute.path_join(".%s.builtin-backup" % uuid)
	_remove_directory_tree(staging_absolute)
	_remove_directory_tree(backup_absolute)

	var extraction_error := _extract_packaged_chartset_archive(
		archive_absolute,
		staging_absolute,
		uuid,
	)
	if not extraction_error.is_empty():
		_remove_directory_tree(staging_absolute)
		return ChartPackageInstaller.InstallResult.failure(extraction_error)

	var had_target := DirAccess.dir_exists_absolute(target_absolute)
	if had_target and DirAccess.rename_absolute(target_absolute, backup_absolute) != OK:
		_remove_directory_tree(staging_absolute)
		return ChartPackageInstaller.InstallResult.failure("Could not replace the existing built-in chartset folder.")

	if DirAccess.rename_absolute(staging_absolute, target_absolute) != OK:
		if had_target:
			DirAccess.rename_absolute(backup_absolute, target_absolute)
		return ChartPackageInstaller.InstallResult.failure("Could not finish copying the built-in chartset folder.")

	manifest[uuid] = relative_path
	if not write_text_atomic(packaged_chartsets_manifest_path, JSON.stringify(manifest, "	") + "
"):
		_remove_directory_tree(target_absolute)
		if had_target:
			DirAccess.rename_absolute(backup_absolute, target_absolute)
		return ChartPackageInstaller.InstallResult.failure("Could not update the built-in chartset JSON.")

	_remove_directory_tree(backup_absolute)

	if not old_relative_path.is_empty() and old_relative_path != relative_path:
		var old_absolute := root_absolute.path_join(old_relative_path)
		if not _remove_directory_tree(old_absolute):
			push_warning("[charts] failed to remove previous packaged chartset folder: %s" % old_relative_path)

	return ChartPackageInstaller.InstallResult.completed(relative_path)


static func _unique_packaged_folder_name(
	preferred_name: String,
	pack_id: String,
	manifest: Dictionary,
) -> String:
	var base_name := preferred_name.strip_edges().validate_filename()
	if base_name.is_empty():
		base_name = "chartset"

	var used_folders := {}
	for value in manifest.values():
		var relative_path := str(value).replace("\\", "/")
		if relative_path.get_slice("/", 0).to_lower() == pack_id:
			used_folders[relative_path.get_file().to_lower()] = true

	var pack_root := official_chart_path.path_join(pack_id)
	var candidate := base_name
	var suffix := 2
	while (
		used_folders.has(candidate.to_lower())
		or DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(pack_root.path_join(candidate))
		)
	):
		candidate = "%s_%d" % [base_name, suffix]
		suffix += 1

	return candidate


static func is_valid_pack_id(value: String) -> bool:
	var pack_id := value.strip_edges().to_lower()
	if pack_id.is_empty() or pack_id in [".", ".."]:
		return false
	if "/" in pack_id or "\\" in pack_id or ":" in pack_id:
		return false
	return pack_id == pack_id.validate_filename()


static func _is_safe_packaged_chartset_path(value: String) -> bool:
	var normalized := value.strip_edges().replace("\\", "/")
	if normalized.is_empty() or normalized.begins_with("/") or ":" in normalized:
		return false

	var parts := normalized.split("/")
	if parts.size() < 2 or not is_valid_pack_id(parts[0]):
		return false

	for index in range(1, parts.size()):
		var part := str(parts[index])
		if part.is_empty() or part in [".", ".."] or part != part.validate_filename():
			return false

	return true


static func _is_chartset_uuid(value: String) -> bool:
	var expression := RegEx.new()
	return expression.compile(chartset_uuid_pattern) == OK and expression.search(value) != null


static func _extract_packaged_chartset_archive(archive_path: String, target_path: String, expected_uuid: String) -> String:
	if not _bounded_chartset_zip(archive_path):
		return "The server returned an invalid or oversized chart package."
	var zip := ZIPReader.new()
	if zip.open(archive_path) != OK:
		return "The server response is not a valid chart package."
	var names := zip.get_files()
	var seen := {}
	if names.is_empty() or names.size() > 5000:
		zip.close()
		return "The server chart package has an invalid file count."
	for path in names:
		if not _safe_chartset_archive_path(path) or seen.has(path.to_lower()):
			zip.close()
			return "The server chart package contains an unsafe or duplicate path."
		seen[path.to_lower()] = true
	if DirAccess.make_dir_recursive_absolute(target_path) != OK:
		zip.close()
		return "Could not create the built-in chart staging folder."

	var expanded_bytes := 0
	var chart_paths: Array[String] = []
	var error := ""
	for path in names:
		if path.ends_with("/"):
			continue
		var extension := path.get_extension().to_lower()
		if extension not in chart_package_extensions:
			error = "The server chart package contains an unsupported resource: %s" % path
			break
		var bytes := zip.read_file(path, true)
		expanded_bytes += bytes.size()
		if expanded_bytes > 100 * 1024 * 1024:
			error = "The expanded server chart package exceeds 100 MiB."
			break
		var output_path := target_path.path_join(path)
		if DirAccess.make_dir_recursive_absolute(output_path.get_base_dir()) != OK:
			error = "Could not create a built-in chart resource folder."
			break
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			error = "Could not write the server chart package into res://contents."
			break
		file.store_buffer(bytes)
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK:
			error = "Could not finish writing the server chart package."
			break
		if extension == "dansu":
			chart_paths.append(output_path)
		elif extension in keep_file_extensions and not _write_keep_file_import(output_path):
			error = "Could not mark a built-in resource as Keep File."
			break
	zip.close()
	if not error.is_empty():
		return error
	return _verify_server_chartset(target_path, chart_paths, expected_uuid)


static func _verify_server_chartset(target_path: String, chart_paths: Array[String], expected_uuid: String) -> String:
	if chart_paths.is_empty():
		return "The server chart package contains no charts."
	var manifest_path := target_path.path_join(".dansu-online.json")
	if not FileAccess.file_exists(manifest_path):
		return "The server chart package is missing its revision manifest."
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or str(manifest.get("chartset_uuid", "")).to_lower() != expected_uuid:
		return "The server chart package has invalid chartset metadata."
	var entries = manifest.get("charts")
	if not entries is Array or entries.size() != chart_paths.size():
		return "The server chart package has incomplete chart revision metadata."
	var entries_by_uuid := {}
	for entry in entries:
		if not entry is Dictionary:
			return "The server chart package has invalid chart revision metadata."
		var chart_uuid := str(entry.get("chart_uuid", "")).to_lower()
		if not _is_chartset_uuid(chart_uuid) or entries_by_uuid.has(chart_uuid):
			return "The server chart package has duplicate chart revision metadata."
		entries_by_uuid[chart_uuid] = entry
	for chart_path in chart_paths:
		var identity := _read_chart_identity(chart_path)
		if identity.get("chartset_uuid", "") != expected_uuid:
			return "A chart in the server package belongs to another chartset."
		var chart_uuid := str(identity.get("uuid", ""))
		var entry = entries_by_uuid.get(chart_uuid)
		if not entry is Dictionary:
			return "A chart in the server package is missing revision metadata."
		if int(identity.get("version", 0)) != int(entry.get("chart_revision", 0)):
			return "A chart revision does not match the server manifest."
		if FileAccess.get_sha256(chart_path).to_lower() != str(entry.get("checksum_sha256", "")).to_lower():
			return "A chart checksum does not match the server manifest."
	return ""


static func _read_chart_identity(path: String) -> Dictionary:
	var result := {}
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var line := str(raw_line).strip_edges()
		for key in ["uuid", "chartset_uuid", "version"]:
			var prefix: String = str(key) + ":"
			if line.begins_with(prefix):
				result[key] = line.trim_prefix(prefix).strip_edges().to_lower()
	return result


static func _safe_chartset_archive_path(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or "\\" in path or ":" in path:
		return false
	for part in path.trim_suffix("/").split("/"):
		if part in ["", ".", ".."] or part.ends_with(".") or part.ends_with(" ") or part.validate_filename() != part:
			return false
		var stem := part.get_slice(".", 0).to_upper()
		if stem in ["CON", "PRN", "AUX", "NUL"] or (stem.length() == 4 and stem.left(3) in ["COM", "LPT"] and stem.right(1).is_valid_int()):
			return false
	return true


static func _bounded_chartset_zip(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 22:
		return false
	var length := file.get_length()
	var tail_size := mini(length, 65557)
	file.seek(length - tail_size)
	var tail := file.get_buffer(tail_size)
	var end := -1
	for index in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(index) == 0x06054b50 and index + 22 + tail.decode_u16(index + 20) == tail.size():
			end = index
			break
	if end < 0 or tail.decode_u16(end + 4) != 0 or tail.decode_u16(end + 6) != 0:
		return false
	var count := tail.decode_u16(end + 10)
	var offset := tail.decode_u32(end + 16)
	if count == 0 or count > 5000 or offset >= length or tail.decode_u16(end + 8) != count:
		return false
	file.seek(offset)
	var total := 0
	for _index in range(count):
		var header := file.get_buffer(46)
		if header.size() != 46 or header.decode_u32(0) != 0x02014b50 or header.decode_u16(8) & 1:
			return false
		total += header.decode_u32(24)
		if total > 100 * 1024 * 1024:
			return false
		var next := file.get_position() + header.decode_u16(28) + header.decode_u16(30) + header.decode_u16(32)
		if next > length:
			return false
		file.seek(next)
	return true


static func _write_keep_file_import(resource_path: String) -> bool:
	var import_file := FileAccess.open(resource_path + ".import", FileAccess.WRITE)
	if import_file == null:
		return false
	import_file.store_string("[remap]\n\nimporter=\"keep\"\n")
	import_file.flush()
	import_file.close()
	return true


static func _remove_directory_tree(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	for child_directory in directory.get_directories():
		if not _remove_directory_tree(path.path_join(child_directory)):
			return false
	for file_name in directory.get_files():
		if DirAccess.remove_absolute(path.path_join(file_name)) != OK:
			return false
	return DirAccess.remove_absolute(path) == OK


static func unique_file_name(directory_path: String, preferred_name: String, fallback_name := "imported") -> String:
	var safe_name := preferred_name.validate_filename().strip_edges()
	var extension := safe_name.get_extension().to_lower()
	var base_name := safe_name.get_basename().strip_edges()
	if base_name.is_empty():
		base_name = fallback_name.validate_filename().strip_edges()
	if base_name.is_empty():
		base_name = "imported"
	var candidate := base_name if extension.is_empty() else "%s.%s" % [base_name, extension]
	var suffix := 2
	while FileAccess.file_exists(directory_path.path_join(candidate)):
		candidate = "%s_%d" % [base_name, suffix] if extension.is_empty() else "%s_%d.%s" % [base_name, suffix, extension]
		suffix += 1
	return candidate


static func copy_file_unique(source_path: String, target_directory: String, fallback_name := "imported") -> String:
	var normalized_source := source_path.simplify_path()
	if not FileAccess.file_exists(normalized_source):
		return ""
	ensure_dir(target_directory)
	var target_name := unique_file_name(target_directory, normalized_source.get_file(), fallback_name)
	var target_path := target_directory.path_join(target_name)
	var source := FileAccess.open(normalized_source, FileAccess.READ)
	if source == null:
		return ""
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		source.close()
		return ""
	target.store_buffer(source.get_buffer(source.get_length()))
	target.flush()
	target.close()
	source.close()
	return target_path


static func write_text_atomic(path: String, content: String) -> bool:
	var temporary_path := path + ".tmp"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	file.close()
	return replace_file(temporary_path, path)


static func replace_file(source_path: String, target_path: String) -> bool:
	if not FileAccess.file_exists(source_path):
		return false
	ensure_dir(target_path.get_base_dir())
	var absolute_source := ProjectSettings.globalize_path(source_path)
	var absolute_target := ProjectSettings.globalize_path(target_path)
	var backup_path := absolute_target + ".backup"
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	var had_target := FileAccess.file_exists(absolute_target)
	if had_target and DirAccess.rename_absolute(absolute_target, backup_path) != OK:
		return false
	if DirAccess.rename_absolute(absolute_source, absolute_target) != OK:
		if had_target:
			DirAccess.rename_absolute(backup_path, absolute_target)
		return false
	if had_target:
		DirAccess.remove_absolute(backup_path)
	return true


static func process_startup_imports() -> void:
	ChartTransfer.cleanup_all()
	var import_root := _get_startup_import_root()
	ensure_dir(import_root)
	ensure_dir(ProjectSettings.globalize_path(editor_chart_path))
	ensure_dir(ProjectSettings.globalize_path(skin_path))

	for folder_name in DirAccess.get_directories_at(import_root):
		var source_path := import_root.path_join(folder_name)
		var target_root := _resolve_import_target_root(source_path)
		if target_root == "":
			continue

		var target_path := _make_unique_directory_path(target_root, folder_name)
		if _move_directory(source_path, target_path):
			print("[import] moved %s -> %s" % [source_path, target_path])
		else:
			push_warning("[import] failed to move %s" % source_path)


static func get_image(full_path: String) -> Image:
	if not FileAccess.file_exists(full_path):
		push_warning("cover file not found: %s" % full_path)
		return null

	var bytes := FileAccess.get_file_as_bytes(full_path)
	if bytes.is_empty():
		push_warning("cover file read failed: %s" % full_path)
		return null

	var image := _load_image_from_bytes_loose(bytes, full_path.get_extension())
	if image == null:
		push_warning("cover load failed: %s" % full_path)
		return null
	return image


static func _load_image_from_bytes_loose(bytes: PackedByteArray, extension_hint: String = "") -> Image:
	var detected_format := _detect_image_format(bytes)
	if not detected_format.is_empty():
		return _try_load_image_format(bytes, detected_format)
	var normalized_hint := extension_hint.to_lower().replace("jpeg", "jpg")
	return _try_load_image_format(bytes, normalized_hint) if normalized_hint in ["png", "jpg", "webp", "bmp", "tga"] else null


static func _detect_image_format(bytes: PackedByteArray) -> String:
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4e and bytes[3] == 0x47:
		return "png"
	if bytes.size() >= 3 and bytes[0] == 0xff and bytes[1] == 0xd8 and bytes[2] == 0xff:
		return "jpg"
	if bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	if bytes.size() >= 2 and bytes[0] == 0x42 and bytes[1] == 0x4d:
		return "bmp"
	return ""


static func _try_load_image_format(bytes: PackedByteArray, format_name: String) -> Image:
	var image := Image.new()
	var err := FAILED

	match format_name:
		"png":
			err = image.load_png_from_buffer(bytes)
		"jpg":
			err = image.load_jpg_from_buffer(bytes)
		"webp":
			err = image.load_webp_from_buffer(bytes)
		"bmp":
			err = image.load_bmp_from_buffer(bytes)
		"tga":
			err = image.load_tga_from_buffer(bytes)
		_:
			return null

	if err == OK:
		return image

	return null


static func _get_startup_import_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join(startup_import_dir_name)
	return OS.get_executable_path().get_base_dir().path_join(startup_import_dir_name)


static func _resolve_import_target_root(source_path: String) -> String:
	if FileAccess.file_exists(source_path.path_join("skin.json")):
		return ProjectSettings.globalize_path(skin_path)

	for file_name in DirAccess.get_files_at(source_path):
		if file_name.ends_with(Config.FILE_EXTENSION):
			return ProjectSettings.globalize_path(editor_chart_path)

	return ""


static func _make_unique_directory_path(parent_path: String, preferred_name: String) -> String:
	var base_name := preferred_name.validate_filename()
	if base_name == "":
		base_name = "imported"

	var candidate := base_name
	var index := 2
	while DirAccess.dir_exists_absolute(parent_path.path_join(candidate)):
		candidate = "%s(%d)" % [base_name, index]
		index += 1
	return parent_path.path_join(candidate)


static func _move_directory(source_path: String, target_path: String) -> bool:
	ensure_dir(target_path.get_base_dir())

	var rename_error := DirAccess.rename_absolute(source_path, target_path)
	if rename_error == OK:
		return true

	if not DirAccess.dir_exists_absolute(source_path):
		return false

	ensure_dir(target_path)

	for child_directory_name in DirAccess.get_directories_at(source_path):
		var child_source_path := source_path.path_join(child_directory_name)
		var child_target_path := target_path.path_join(child_directory_name)
		if not _move_directory(child_source_path, child_target_path):
			return false

	for child_file_name in DirAccess.get_files_at(source_path):
		var child_source_file := source_path.path_join(child_file_name)
		var child_target_file := target_path.path_join(child_file_name)
		if not _move_file(child_source_file, child_target_file):
			return false

	var cleanup_error := DirAccess.remove_absolute(source_path)
	return cleanup_error == OK or not DirAccess.dir_exists_absolute(source_path)


static func _move_file(source_path: String, target_path: String) -> bool:
	var rename_error := DirAccess.rename_absolute(source_path, target_path)
	if rename_error == OK:
		return true

	if not FileAccess.file_exists(source_path):
		return false

	var bytes := FileAccess.get_file_as_bytes(source_path)
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_buffer(bytes)
	file.close()

	if DirAccess.remove_absolute(source_path) != OK:
		return false

	return true
