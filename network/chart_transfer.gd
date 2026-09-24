extends RefCounted
class_name ChartTransfer

const ROOT := "user://cache/chart-transfers"


static func create() -> String:
	var directory := ROOT.path_join(Crypto.new().generate_random_bytes(8).hex_encode())
	return directory if DirAccess.make_dir_recursive_absolute(directory) == OK else ""


static func cleanup(directory: String) -> void:
	var normalized := directory.simplify_path()
	var prefix := ROOT.simplify_path().trim_suffix("/") + "/"
	if not normalized.begins_with(prefix) or ".." in normalized:
		return
	_remove_tree(normalized)
	DirAccess.remove_absolute(ROOT)


static func cleanup_all() -> void:
	_remove_tree(ROOT)


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
