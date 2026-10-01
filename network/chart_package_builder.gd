extends RefCounted
class_name ChartPackageBuilder

const MAX_BYTES := 100 * 1024 * 1024
const MAX_FILES := 5000
const EXTENSIONS := ["dansu", "json", "png", "jpg", "jpeg", "webp", "wav", "ogg", "mp3"]

class BuildResult extends RefCounted:
	var error: String = ""
	var path: String = ""
	var bytes: int = 0
	var files: int = 0

	static func failure(message: String) -> BuildResult:
		var result := BuildResult.new()
		result.error = message
		return result

	static func completed(archive: String, byte_count: int, file_count: int) -> BuildResult:
		var result := BuildResult.new()
		result.path = archive
		result.bytes = byte_count
		result.files = file_count
		return result

static func build(folder: String) -> BuildResult:
	var files: Array[String] = []
	var pending: Array[String] = [""]
	var total := 0
	var directories := 0
	while not pending.is_empty():
		directories += 1
		if directories > MAX_FILES:
			push_warning("The chartset contains too many folders.")
			return BuildResult.failure(GameText.text(GameText.Key.ERROR_UPLOAD_LIMIT))
		var relative: String = pending.pop_back()
		var directory := DirAccess.open(folder.path_join(relative))
		if directory == null:
			return BuildResult.failure(GameText.text(GameText.Key.ERROR_UPLOAD_SOURCE))
		for child in directory.get_directories():
			if not child.begins_with(".") and not directory.is_link(child):
				pending.append(relative.path_join(child))
		for name in directory.get_files():
			if name.begins_with(".") or name.get_extension().to_lower() not in EXTENSIONS or directory.is_link(name):
				continue
			var path := relative.path_join(name)
			if not ChartPackageInstaller.safe_relative(path):
				return BuildResult.failure(GameText.text(GameText.Key.ERROR_UPLOAD_FILENAME) % path)
			var file := FileAccess.open(folder.path_join(path), FileAccess.READ)
			if file == null:
				return BuildResult.failure(GameText.text(GameText.Key.ERROR_UPLOAD_FILE_READ) % path)
			total += file.get_length()
			files.append(path)
			if total > MAX_BYTES or files.size() > MAX_FILES:
				return BuildResult.failure(GameText.text(GameText.Key.ERROR_UPLOAD_LIMIT))
	if files.is_empty():
		return BuildResult.failure(GameText.text(GameText.Key.ERROR_UPLOAD_EMPTY))
	files.sort()
	var transfer_directory := ChartTransfer.create()
	if transfer_directory.is_empty():
		push_warning("Could not create the upload folder.")
		return BuildResult.failure(GameText.text(GameText.Key.ERROR_UPLOAD_START))
	var archive := transfer_directory.path_join("upload.zip")
	var zip := ZIPPacker.new()
	if zip.open(archive) != OK:
		ChartTransfer.cleanup(transfer_directory)
		push_warning("Could not create the upload package.")
		return BuildResult.failure(GameText.text(GameText.Key.ERROR_UPLOAD_START))
	var error := ""
	var written := 0
	for path in files:
		var file := FileAccess.open(folder.path_join(path), FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES:
			error = GameText.text(GameText.Key.ERROR_UPLOAD_RESOURCE_CHANGED)
			break
		written += file.get_length()
		if written > MAX_BYTES:
			push_warning("The resources exceed 100 MiB.")
			error = GameText.text(GameText.Key.ERROR_UPLOAD_LIMIT)
			break
		if zip.start_file(path) != OK or zip.write_file(file.get_buffer(file.get_length())) != OK or zip.close_file() != OK:
			push_warning("Could not write the upload package. Check disk space.")
			error = GameText.text(GameText.Key.ERROR_UPLOAD_START)
			break
	if zip.close() != OK:
		push_warning("Could not finish the upload package.")
		error = GameText.text(GameText.Key.ERROR_UPLOAD_START)
	if not error.is_empty():
		ChartTransfer.cleanup(transfer_directory)
		return BuildResult.failure(error)
	var packed := FileAccess.open(archive, FileAccess.READ)
	if packed == null or packed.get_length() > MAX_BYTES:
		packed = null
		ChartTransfer.cleanup(transfer_directory)
		push_warning("The ZIP exceeds the 100 MiB upload limit.")
		return BuildResult.failure(GameText.text(GameText.Key.ERROR_UPLOAD_LIMIT))
	return BuildResult.completed(archive, packed.get_length(), files.size())
