extends RefCounted
class_name DlcPackLoader

const DLC_DIRECTORY := "dlc"

static func mount_installed() -> int:
	var root := (
		ProjectSettings.globalize_path("res://").path_join(DLC_DIRECTORY)
		if OS.has_feature("editor")
		else OS.get_executable_path().get_base_dir().path_join(DLC_DIRECTORY)
	)
	if not DirAccess.dir_exists_absolute(root):
		return 0
	var mounted := 0
	for file_name in DirAccess.get_files_at(root):
		if file_name.get_extension().to_lower() != "pck":
			continue
		if ProjectSettings.load_resource_pack(root.path_join(file_name), false):
			mounted += 1
		else:
			push_warning("[dlc] failed to mount %s" % file_name)
	return mounted
