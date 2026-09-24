extends RefCounted
class_name SkinDocument


var context = SkinEditorContext.new()
var skin_data = PlayerSkinData.new()
var file_path := ""
var directory_path := ""
var sprite_directory_name := "sprite"
var sprite_directory_path := ""
var dirty := false

func load_from_file(target_path: String, open_mode: int) -> bool:
	file_path = target_path
	directory_path = target_path.get_base_dir()
	sprite_directory_name = _resolve_sprite_directory_name(open_mode, directory_path)
	sprite_directory_path = directory_path.path_join(sprite_directory_name)
	context.skin_file_path = file_path
	context.open_mode = open_mode
	dirty = false
	skin_data = PlayerSkinData.new()

	var folder_name := ""
	var json_name := target_path.get_file()
	var type := PlayerSkinData.TYPE.IN_SKIN_FOLDER

	match open_mode:
		SkinEditorContext.OpenMode.CUSTOM:
			type = PlayerSkinData.TYPE.IN_SKIN_FOLDER
			folder_name = directory_path.get_file()
		SkinEditorContext.OpenMode.CHART:
			type = PlayerSkinData.TYPE.IN_CHART
		_:
			type = PlayerSkinData.TYPE.IN_SKIN_FOLDER

	return skin_data.parse_objects(type, folder_name, json_name)

func create_empty(open_mode: int, target_directory_path: String) -> void:
	file_path = ""
	directory_path = target_directory_path
	sprite_directory_name = _resolve_sprite_directory_name(open_mode, directory_path, true)
	sprite_directory_path = directory_path.path_join(sprite_directory_name)
	context.skin_file_path = ""
	context.open_mode = open_mode
	dirty = false
	skin_data = PlayerSkinData.new()

	match open_mode:
		SkinEditorContext.OpenMode.CHART:
			skin_data.type = PlayerSkinData.TYPE.IN_CHART
		SkinEditorContext.OpenMode.CUSTOM:
			skin_data.type = PlayerSkinData.TYPE.IN_SKIN_FOLDER
			skin_data.folder_name = directory_path.get_file()
		_:
			skin_data.type = PlayerSkinData.TYPE.IN_SKIN_FOLDER
	skin_data.skin_name = "new skin"

func mark_dirty() -> void:
	dirty = true

func clear_dirty() -> void:
	dirty = false

func get_selected_animation():
	if context.selected_animation_index < 0:
		return null
	if context.selected_animation_index >= skin_data.animations.size():
		return null
	return skin_data.animations[context.selected_animation_index]

func get_sprite_file_names() -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(sprite_directory_path):
		return result

	var files := DirAccess.get_files_at(sprite_directory_path)
	files.sort()
	for file_name in files:
		var extension := file_name.get_extension().to_lower()
		if extension in ["png", "jpg", "jpeg", "webp", "bmp", "tga"]:
			result.append(file_name)
	return result

func get_next_animation_id() -> int:
	var max_id := 0
	for animation in skin_data.animations:
		if animation != null:
			max_id = max(max_id, animation.id)
	return max_id + 1

func _resolve_sprite_directory_name(open_mode: int, target_directory_path: String, prefer_new_layout: bool = false) -> String:
	if open_mode == SkinEditorContext.OpenMode.CHART:
		return "sprites"
	if prefer_new_layout:
		return "sprites"
	if DirAccess.dir_exists_absolute(target_directory_path.path_join("sprites")):
		return "sprites"
	return "sprite"
