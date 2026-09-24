extends Node

const MAIN_MENU_SCENE_PATH := "res://scenes/mainmenu/mainmenu.tscn"

var main_menu: Node
var cached_main_menu: Node
var _transition_layer: CanvasLayer
var _transition_rect: ColorRect
var _transition_material: ShaderMaterial

var _is_transitioning := false


func _ready() -> void:
	_setup_transition_layer()


func try_transition_to(scene_path: String, duration: float = 1.0) -> bool:
	if _is_transitioning:
		return false
	transition_to(scene_path, duration)
	return true


func try_return_to_menu(duration: float = 2.0) -> bool:
	if _is_transitioning:
		return false
	return_to_menu(duration)
	return true


func transition_to(scene_path: String, duration: float = 1.0) -> void:
	if scene_path == MAIN_MENU_SCENE_PATH:
		await return_to_menu(duration)
		return

	if _is_transitioning:
		return

	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Scene transition failed to load: %s" % scene_path)
		return

	await _play_transition_in(duration)

	var next_scene := packed_scene.instantiate()
	_replace_current_scene(next_scene)

	await get_tree().process_frame
	await _play_transition_out(duration)


func return_to_menu(duration: float = 2.0) -> void:
	if _is_transitioning:
		return 

	await _play_transition_in(duration)

	var menu_scene := cached_main_menu
	if menu_scene == null:
		var packed_scene := load(MAIN_MENU_SCENE_PATH) as PackedScene
		if packed_scene == null:
			push_error("Main menu scene failed to load: %s" % MAIN_MENU_SCENE_PATH)
			_finish_transition_immediately()
			return
		menu_scene = packed_scene.instantiate()
	else:
		_unfreeze_menu(menu_scene)

	_replace_current_scene(menu_scene)

	await get_tree().process_frame
	await _play_transition_out(duration)


func _play_transition_in(duration: float) -> void:
	_is_transitioning = true

	if _transition_layer == null:
		_setup_transition_layer()

	_transition_rect.visible = true
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_material.set_shader_parameter("progress", 0.0)

	var tween_in := create_tween()
	tween_in.tween_property(
		_transition_material,
		"shader_parameter/progress",
		1.0,
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween_in.finished


func _play_transition_out(duration: float) -> void:
	_transition_material.set_shader_parameter("progress", 1.0)

	var tween_out := create_tween()
	tween_out.tween_property(
		_transition_material,
		"shader_parameter/progress",
		0.0,
		duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween_out.finished

	_transition_rect.visible = false
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false


func _finish_transition_immediately() -> void:
	if _transition_rect != null:
		_transition_rect.visible = false
		_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false


func _replace_current_scene(next_scene: Node) -> void:
	var tree := get_tree()
	var root := tree.root
	var current_scene := tree.current_scene

	if current_scene != null:
		if _is_main_menu_scene(current_scene):
			_cache_main_menu(current_scene)
		else:
			root.remove_child(current_scene)
			current_scene.queue_free()
			if tree.current_scene == current_scene:
				tree.current_scene = null

	root.add_child(next_scene)
	tree.current_scene = next_scene

	if _is_main_menu_scene(next_scene):
		main_menu = next_scene


func _cache_main_menu(scene: Node) -> void:
	if scene == null:
		return

	if cached_main_menu != null and cached_main_menu != scene:
		cached_main_menu.queue_free()

	cached_main_menu = scene
	main_menu = scene
	_freeze_menu(scene)

	var tree := get_tree()
	var root := tree.root
	if scene.get_parent() == root:
		root.remove_child(scene)
	if tree.current_scene == scene:
		tree.current_scene = null


func _freeze_menu(menu: Node) -> void:
	menu.hide()
	menu.process_mode = Node.PROCESS_MODE_DISABLED
	_set_menu_audio_paused(menu, true)


func _unfreeze_menu(menu: Node) -> void:
	menu.process_mode = Node.PROCESS_MODE_INHERIT
	menu.show()
	_set_menu_audio_paused(menu, false)


func _set_menu_audio_paused(menu: Node, paused: bool) -> void:
	if not menu is DansuMainMenu:
		return

	var main_menu := menu as DansuMainMenu

	if main_menu.audio_1 != null:
		main_menu.audio_1.stream_paused = paused
	if main_menu.audio_2 != null:
		main_menu.audio_2.stream_paused = paused


func _is_main_menu_scene(scene: Node) -> bool:
	return scene != null and scene.scene_file_path == MAIN_MENU_SCENE_PATH


func _setup_transition_layer() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "TransitionLayer"
	_transition_layer.layer = 9999
	add_child(_transition_layer)

	_transition_rect = ColorRect.new()
	_transition_rect.name = "TransitionRect"
	_transition_rect.visible = false
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	_transition_layer.add_child(_transition_rect)

	_transition_material = ShaderMaterial.new()
	_transition_material.shader = load("res://resources/shaders/transition.gdshader") as Shader
	_transition_rect.material = _transition_material
