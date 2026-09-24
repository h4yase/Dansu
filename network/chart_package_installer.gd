extends RefCounted
class_name ChartPackageInstaller

class InstallResult extends RefCounted:
	var error: String = ""
	var folder: String = ""

	static func failure(message: String) -> InstallResult:
		var result := InstallResult.new()
		result.error = message
		return result

	static func completed(folder_name: String) -> InstallResult:
		var result := InstallResult.new()
		result.folder = folder_name
		return result


## Runs on a worker. Extract into a private staging directory, then atomically publish.
const MAX_EXPANDED_BYTES := 100 * 1024 * 1024
const MAX_FILES := 5000
const DOWNLOAD_FOLDER_MAX_LENGTH := 200
const REVISION_MANIFEST_NAME := ".dansu-online.json"
const CACHE_ROOT := FileSystem.community_cache_path
const MAX_CACHED_CHARTSETS := 200

class CachedFolder extends RefCounted:
	var name: String
	var last_used_at: int

	func _init(p_name: String, p_last_used_at: int) -> void:
		name = p_name
		last_used_at = p_last_used_at


static func safe_relative(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or "\\" in path or ":" in path:
		return false
	for part in path.trim_suffix("/").split("/"):
		if part in ["", ".", ".."] or part.ends_with(".") or part.ends_with(" "):
			return false
		if part.validate_filename() != part:
			return false
		var stem := part.get_slice(".", 0).to_upper()
		if stem in ["CON", "PRN", "AUX", "NUL"] or (stem.length() == 4 and stem.left(3) in ["COM", "LPT"] and stem.right(1).is_valid_int()):
			return false
	return true

static func download_folder_name(metadata: Dictionary) -> String:
	var chartset_id := int(metadata.get("id", 0))
	var title := ""
	var primary_chart = metadata.get("primary_chart")
	if primary_chart is Dictionary:
		title = str(primary_chart.get("title", ""))
	var charts = metadata.get("charts")
	if title.strip_edges().is_empty() and charts is Array:
		var primary_chart_id := int(metadata.get("primary_chart_id", -1))
		for chart in charts:
			if chart is Dictionary and int(chart.get("id", -2)) == primary_chart_id:
				title = str(chart.get("title", ""))
				break
		if title.strip_edges().is_empty() and not charts.is_empty() and charts[0] is Dictionary:
			title = str(charts[0].get("title", ""))
	var safe_title := title.strip_edges().validate_filename()
	while safe_title.ends_with(".") or safe_title.ends_with(" "):
		safe_title = safe_title.left(safe_title.length() - 1)
	if safe_title.is_empty():
		safe_title = "Untitled"
	var prefix := "[%d] " % chartset_id
	safe_title = safe_title.left(maxi(DOWNLOAD_FOLDER_MAX_LENGTH - prefix.length(), 1))
	while safe_title.ends_with(".") or safe_title.ends_with(" "):
		safe_title = safe_title.left(safe_title.length() - 1)
	return prefix + (safe_title if not safe_title.is_empty() else "Untitled")

static func read_revision_manifest(folder_path: String) -> Dictionary:
	var file := FileAccess.open(folder_path.path_join(REVISION_MANIFEST_NAME), FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func install(archive_path: String, metadata: Dictionary) -> InstallResult:
	var transfer_root := archive_path.get_base_dir()
	if not _bounded_zip(archive_path):
		ChartTransfer.cleanup(transfer_root)
		return InstallResult.failure("The ZIP is invalid or exceeds the 100 MiB extraction limit.")
	var zip := ZIPReader.new()
	if zip.open(archive_path) != OK:
		ChartTransfer.cleanup(transfer_root)
		return InstallResult.failure("The downloaded file is not a valid chart package.")
	var names := zip.get_files()
	var seen := {}
	if names.is_empty() or names.size() > MAX_FILES:
		zip.close()
		ChartTransfer.cleanup(transfer_root)
		return InstallResult.failure("The chart package has an invalid file count.")
	for path in names:
		if not safe_relative(path) or seen.has(path.to_lower()):
			zip.close()
			ChartTransfer.cleanup(transfer_root)
			return InstallResult.failure("The chart package contains an unsafe or duplicate path.")
		seen[path.to_lower()] = true
	var staging := transfer_root.path_join("staging")
	var backup_root := transfer_root.path_join("backup")
	var destination := CACHE_ROOT.path_join(download_folder_name(metadata))
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		zip.close()
		ChartTransfer.cleanup(transfer_root)
		return InstallResult.failure("Could not create the download staging folder.")
	var expanded := 0
	var error := ""
	for path in names:
		if path.ends_with("/"):
			continue
		var bytes := zip.read_file(path, true)
		expanded += bytes.size()
		if expanded > MAX_EXPANDED_BYTES:
			error = "The expanded package exceeds the size limit."
			break
		var target := staging.path_join(path)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
			error = "Could not create a chart resource folder."
			break
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			error = "Could not write the chart package. Check disk space."
			break
		file.store_buffer(bytes)
		file.flush()
		if file.get_error() != OK:
			error = "Could not finish writing the chart package. Check disk space."
		file.close()
		if not error.is_empty():
			break
	zip.close()
	if error.is_empty():
		error = _verify(staging, metadata)
	if error.is_empty():
		error = _write_revision_manifest(staging, metadata)
	var backups := {}
	if error.is_empty():
		var folders: Array[String] = []
		var chartset_prefix := "[%d] " % int(metadata.get("id", 0))
		for folder_name in DirAccess.get_directories_at(CACHE_ROOT):
			if folder_name.begins_with(chartset_prefix):
				folders.append(folder_name)
		for folder in folders:
			var original := CACHE_ROOT.path_join(folder)
			var backup := backup_root.path_join(str(folder))
			DirAccess.make_dir_recursive_absolute(backup.get_base_dir())
			if DirAccess.rename_absolute(original, backup) != OK:
				error = "Could not back up the existing chartset. Close any files and retry."
				break
			backups[original] = backup
	if error.is_empty():
		DirAccess.make_dir_recursive_absolute(CACHE_ROOT)
		if DirAccess.rename_absolute(staging, destination) != OK:
			error = "Could not move the installed charts into the library."
	if not error.is_empty():
		for original in backups:
			DirAccess.rename_absolute(backups[original], original)
		ChartTransfer.cleanup(transfer_root)
		return InstallResult.failure(error)
	ChartTransfer.cleanup(transfer_root)
	return InstallResult.completed(destination.get_file())

static func _write_revision_manifest(staging: String, metadata: Dictionary) -> String:
	var charts: Array = metadata.get("charts", [])
	var revisions: Array[Dictionary] = []
	for chart in charts:
		if not chart is Dictionary:
			continue
		revisions.append({
			"id": int(chart.get("id", 0)),
			"chart_uuid": str(chart.get("chart_uuid", "")),
			"chart_revision": int(chart.get("chart_revision", 0)),
			"checksum_sha256": str(chart.get("checksum_sha256", "")).to_lower(),
		})
	var snapshot := {
		"chartset_id": int(metadata.get("id", 0)),
		"chartset_uuid": str(metadata.get("chartset_uuid", "")),
		"charts": revisions,
		"last_used_at": int(Time.get_unix_time_from_system()),
	}
	var file := FileAccess.open(staging.path_join(REVISION_MANIFEST_NAME), FileAccess.WRITE)
	if file == null:
		return "Could not save the installed chart revision."
	file.store_string(JSON.stringify(snapshot))
	file.flush()
	var write_error := file.get_error()
	file.close()
	return "" if write_error == OK else "Could not save the installed chart revision."


static func prune_cache(keep_folder: String = "") -> void:
	var folders: Array[CachedFolder] = []
	for folder_name in DirAccess.get_directories_at(CACHE_ROOT):
		var manifest := read_revision_manifest(CACHE_ROOT.path_join(folder_name))
		folders.append(CachedFolder.new(folder_name, int(manifest.get("last_used_at", 0))))
	if folders.size() <= MAX_CACHED_CHARTSETS:
		return
	folders.sort_custom(func(a: CachedFolder, b: CachedFolder) -> bool:
		return int(a.last_used_at) < int(b.last_used_at)
	)
	var remove_count := folders.size() - MAX_CACHED_CHARTSETS
	for entry in folders:
		if remove_count <= 0:
			break
		if str(entry.name) == keep_folder:
			continue
		_remove_cache_tree(CACHE_ROOT.path_join(str(entry.name)))
		remove_count -= 1


static func _remove_cache_tree(path: String) -> void:
	var normalized := path.simplify_path()
	var prefix := CACHE_ROOT.simplify_path().trim_suffix("/") + "/"
	if not normalized.begins_with(prefix) or ".." in normalized:
		return
	for folder in DirAccess.get_directories_at(normalized):
		_remove_cache_tree(normalized.path_join(folder))
	for file in DirAccess.get_files_at(normalized):
		DirAccess.remove_absolute(normalized.path_join(file))
	DirAccess.remove_absolute(normalized)

static func _bounded_zip(path: String) -> bool:
	# Read declared sizes before ZIPReader can allocate an expanded entry.
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
	if count == 0 or count > MAX_FILES or offset >= length or tail.decode_u16(end + 8) != count:
		return false
	file.seek(offset)
	var total := 0
	for index in range(count):
		var header := file.get_buffer(46)
		if header.size() != 46 or header.decode_u32(0) != 0x02014b50 or header.decode_u16(8) & 1:
			return false
		total += header.decode_u32(24)
		if total > MAX_EXPANDED_BYTES:
			return false
		var next := file.get_position() + header.decode_u16(28) + header.decode_u16(30) + header.decode_u16(32)
		if next > length:
			return false
		file.seek(next)
	return true

static func _verify(staging: String, metadata: Dictionary) -> String:
	if not metadata.get("charts") is Array or metadata.charts.is_empty():
		return "No chart metadata was supplied."
	for chart in metadata.charts:
		var path := str(chart.get("relative_chart_path", ""))
		if not safe_relative(path) or path.get_extension().to_lower() != "dansu":
			return "The package contains an invalid chart path."
		var full_path := staging.path_join(path)
		if not FileAccess.file_exists(full_path) or FileAccess.get_sha256(full_path) != chart.get("checksum_sha256", ""):
			return "The package changed since this search. Refresh the list and retry."
		for key in ["relative_audio_path", "relative_cover_art_path", "relative_skin_path"]:
			var resource = chart.get(key)
			if resource != null and not str(resource).is_empty():
				if not safe_relative(str(resource)) or not FileAccess.file_exists(staging.path_join(resource)):
					return "A required chart resource is missing."
	return ""
