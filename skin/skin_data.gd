extends RefCounted
class_name PlayerSkinData

enum TYPE { BUILT_IN, IN_CHART, IN_SKIN_FOLDER }

var skin_name: String = "none"
var scale: float = 1.0

var type : TYPE
var folder_name: String = ""
var json_name: String = ""

var texture_cache = {}

var animations: Array[PlayerAnimation] = []

# player_animation

var idle: PlayerAnimation = null
var left: PlayerAnimation = null
var right: PlayerAnimation = null
var jump: PlayerAnimation = null
var land: PlayerAnimation = null
var hits: Array[PlayerAnimation] = []
var repeat_idle := false
var resource_directory := ""

func get_folder_path() -> String:
	if not resource_directory.is_empty():
		return resource_directory
	match type:
		TYPE.BUILT_IN:
			return "res://contents/skin".path_join(folder_name)
		TYPE.IN_CHART:
			if CM.selected_chart == null:
				return ""
			return CM.selected_chart.skin_directory_path
		TYPE.IN_SKIN_FOLDER:
			return "user://skins".path_join(folder_name)
	return ""

func parse_objects(_type:TYPE,_folder_name:String,_json_name:String) -> bool:
	type = _type
	folder_name = _folder_name
	json_name = _json_name
	animations.clear()
	hits.clear()
	idle = null
	left = null
	right = null
	jump = null
	land = null
	repeat_idle = false
	texture_cache.clear()
	var folder_path = get_folder_path()

	var file = FileAccess.open(folder_path.path_join(json_name), FileAccess.READ)
	if not file:
		push_warning("FILE : %s is missing" , folder_path.path_join(folder_name))
		return false
	var json = JSON.parse_string(file.get_as_text())
	if typeof(json) != TYPE_DICTIONARY:
		return false

	skin_name = json.get("name","new skin")
	scale = float(json.get("scale", 1.0))
	if "animations" in json:
		for animation in json["animations"]:
			var _frames = animation.get("frames", [])
			var textures: Array[Texture2D] = []
			var frame_file_names: Array[String] = []
			for _frame in _frames:
				var frame_file_name := str(_frame)
				frame_file_names.append(frame_file_name)
				var _texture = load_texture(frame_file_name)
				if _texture:
					textures.append(_texture)
			var new_animation = PlayerAnimation.new()
			new_animation.id = animation.get("id", -1)
			new_animation.frames = textures
			new_animation.frames_file_name = frame_file_names
			new_animation.name = animation.get("name", "new animation")
			new_animation.fps = float(animation.get("fps", 10.0))
			new_animation.effect = animation.get("effect","none")
			new_animation.return_idle = bool(animation.get("return_idle",true))
			animations.append(new_animation)
	if "player" in json:
		if "hits" in json["player"]:
			for id in json["player"]["hits"]:
				hits.append(get_animation_via_id(int(id)))
		idle = get_animation_via_id(int(json["player"].get("idle",-1)))
		jump = get_animation_via_id(int(json["player"].get("jump",-1)))
		land = get_animation_via_id(int(json["player"].get("land",-1)))
		left = get_animation_via_id(int(json["player"].get("left",-1)))
		right = get_animation_via_id(int(json["player"].get("right",-1)))
		repeat_idle = bool(json["player"].get("repeat_idle", true))
	
	if not idle and not animations.is_empty():
		idle = animations[0]
	
	return idle != null

func get_animation_via_id(id:int) -> PlayerAnimation:
	if id <= 0:
		return null
	for animation in animations:
		if animation.id == id:
			return animation
	return null

func load_texture(file_name: String) -> Texture2D:
	if texture_cache.has(file_name):
		return texture_cache[file_name]
	var base_dir = get_folder_path()
	var _texture: Texture2D = null
	var texture_paths := [
		base_dir.path_join("sprites").path_join(file_name),
		base_dir.path_join("sprite").path_join(file_name),
	]

	for texture_path in texture_paths:
		if texture_path.begins_with("res://"):
			_texture = load(texture_path)
		elif FileAccess.file_exists(texture_path):
			var image = Image.new()
			if image.load(texture_path) == OK:
				_texture = ImageTexture.create_from_image(image)
			else:
				_texture = load("res://contents/skins/danshe/sprites/idle.png")
		if _texture != null:
			break

	if _texture:
		texture_cache[file_name] = _texture

	return _texture
