extends RefCounted
class_name GameplayVisuals

const SKY_BASE_COLOR_PARAM := "base_color"
const SKY_DETAIL_COLOR_PARAM := "detail_color"

var rail_color := GameRail.DEFAULT_ACCENT_COLOR

var _player: Player
var _camera: Camera3D
var _hud_root: Control
var _world: WorldEnvironment
var _stage: GameplayStageVisualizer
var _base_player_skin: PlayerSkinData
var _active_skin_path := ""

var _skin_paths: Array[String] = []
var _skin_values: Array[PlayerSkinData] = []
var _camera_events: Array[CameraEvent] = []
var _overlay_events: Array[OverlayEvent] = []
var _theme_events: Array[ThemeEvent] = []
var _sky_material: ShaderMaterial
var _default_sky_base := Color(0.075, 0.078, 0.09, 1.0)
var _default_sky_detail := Color(0.19, 0.19, 0.22, 1.0)
var _overlay_root: Control
var _overlay_nodes: Array[TextureRect] = []
var _overlay_paths: Array[String] = []
var _overlay_textures: Array[Texture2D] = []

func setup(
	player: Player,
	camera: Camera3D,
	hud_root: Control,
	world: WorldEnvironment,
	stage: GameplayStageVisualizer
) -> void:
	_player = player
	_camera = camera
	_hud_root = hud_root
	_world = world
	_stage = stage
	_base_player_skin = player.sprite.skin if player != null and player.sprite != null else null
	_cache_theme_defaults()
	_ensure_overlay_root()
	collect_events()

func collect_events() -> void:
	_camera_events.clear()
	_overlay_events.clear()
	_theme_events.clear()
	if CM.parsed_chart == null:
		return
	for event in CM.parsed_chart.events:
		if event is CameraEvent:
			_camera_events.append(event)
		elif event is OverlayEvent:
			_overlay_events.append(event)
		elif event is ThemeEvent:
			_theme_events.append(event)

func hide_gameplay_hud_for_preview() -> void:
	if _hud_root == null:
		return
	for child in _hud_root.get_children():
		if child != _overlay_root and child is CanvasItem:
			child.hide()

func apply(time_ms: float) -> void:
	_apply_skin(time_ms)
	_apply_theme(time_ms)
	_apply_camera(time_ms)
	_apply_overlays(time_ms)

func update_camera_position() -> void:
	if _camera == null or _player == null:
		return
	_camera.position.x = _camera._base_position.x + _camera.target_position.x + (_player.position.x if _camera.follow_character else 0.0)
	_camera.position.y = _camera._base_position.y + _camera.target_position.y
	_camera.fov = _camera._base_fov / maxf(_camera.target_zoom, 0.01)

func _cache_theme_defaults() -> void:
	if _world == null or _world.environment == null:
		return
	var sky := _world.environment.sky
	if sky == null:
		return
	_sky_material = sky.sky_material as ShaderMaterial
	if _sky_material == null:
		return
	if _sky_material.get_shader_parameter(SKY_BASE_COLOR_PARAM) is Color:
		_default_sky_base = _sky_material.get_shader_parameter(SKY_BASE_COLOR_PARAM)
	if _sky_material.get_shader_parameter(SKY_DETAIL_COLOR_PARAM) is Color:
		_default_sky_detail = _sky_material.get_shader_parameter(SKY_DETAIL_COLOR_PARAM)

func _ensure_overlay_root() -> void:
	if _hud_root == null or _overlay_root != null:
		return
	_overlay_root = Control.new()
	_overlay_root.name = "OverlayRuntime"
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.clip_contents = false
	_hud_root.add_child(_overlay_root)
	_hud_root.move_child(_overlay_root, 0)

func _apply_skin(time_ms: float) -> void:
	if _player == null or _player.sprite == null or Config.ignore_chart_skin:
		return
	var active: SkinEvent
	for event in CM.parsed_chart.events:
		if event is SkinEvent and event.time <= time_ms and (active == null or event.time >= active.time):
			active = event

	var path := EventResourceRef.resolve_skin(CM.selected_chart, active.skin_json) if active != null else ""
	if path == _active_skin_path:
		return
	_active_skin_path = path

	var skin := _base_player_skin
	if not path.is_empty():
		var index := _skin_paths.find(path)
		if index < 0:
			var candidate := PlayerSkinData.new()
			candidate.resource_directory = path.get_base_dir()
			var parsed := FileAccess.file_exists(path) and candidate.parse_objects(PlayerSkinData.TYPE.IN_CHART, "", path.get_file())
			_skin_paths.append(path)
			_skin_values.append(candidate if parsed else null)
			index = _skin_paths.size() - 1
		if _skin_values[index] != null:
			skin = _skin_values[index]

	if skin != null:
		var holding := _player.sprite.hold_last_frame
		_player.sprite.skin = skin
		_player.sprite._setup()
		_player.sprite.hold_last_frame = holding

func _apply_theme(time_ms: float) -> void:
	var base_color := _default_sky_base
	var detail_color := _default_sky_detail
	var next_rail_color := GameRail.DEFAULT_ACCENT_COLOR
	var active := _find_theme_event(time_ms)
	if active != null and not active.frames.is_empty():
		var pair := ChartEventEvaluator.frame_pair_indices(active.frames, time_ms - active.time)
		var previous: ThemeEventFrame = active.frames[pair.x]
		var next: ThemeEventFrame = active.frames[pair.y]
		var alpha := ChartEventEvaluator.frame_alpha(previous, next, time_ms - active.time)
		base_color = previous.bg_color.lerp(next.bg_color, alpha)
		detail_color = previous.bg_color_2.lerp(next.bg_color_2, alpha)
		next_rail_color = previous.rail_color.lerp(next.rail_color, alpha)

	rail_color = Color(next_rail_color.r, next_rail_color.g, next_rail_color.b, 1.0)
	if _sky_material != null:
		_sky_material.set_shader_parameter(SKY_BASE_COLOR_PARAM, base_color)
		_sky_material.set_shader_parameter(SKY_DETAIL_COLOR_PARAM, detail_color)
	if _stage != null:
		_stage.set_theme_colors(base_color, detail_color, rail_color)

func _find_theme_event(time_ms: float) -> ThemeEvent:
	var active: ThemeEvent
	for event in _theme_events:
		if event.frames.is_empty() or time_ms < event.time + event.frames[0].time:
			continue
		if active == null or event.time >= active.time:
			active = event
	return active

func _apply_camera(time_ms: float) -> void:
	if _camera == null:
		return
	var active := _find_camera_event(time_ms)
	if active == null or active.frames.is_empty():
		_camera.follow_character = true
		_camera.target_position = Vector2.ZERO
		_camera.target_zoom = 1.0
		return
	var pair := ChartEventEvaluator.frame_pair_indices(active.frames, time_ms - active.time)
	var previous: CameraEventFrame = active.frames[pair.x]
	var next: CameraEventFrame = active.frames[pair.y]
	var alpha := ChartEventEvaluator.frame_alpha(previous, next, time_ms - active.time)
	_camera.follow_character = previous.follow_character
	_camera.target_position = previous.position.lerp(next.position, alpha)
	_camera.target_zoom = lerpf(previous.zoom, next.zoom, alpha)

func _find_camera_event(time_ms: float) -> CameraEvent:
	var active: CameraEvent
	for event in _camera_events:
		if event.frames.is_empty() or time_ms < event.time + event.frames[0].time:
			continue
		if active == null or event.time >= active.time:
			active = event
	return active

func _apply_overlays(time_ms: float) -> void:
	if _overlay_root == null:
		return
	var active_overlays := _active_overlays(time_ms)
	_ensure_overlay_nodes(active_overlays.size())
	var visible_count := 0
	for overlay in active_overlays:
		var state := ChartEventEvaluator.evaluate_overlay(overlay, time_ms - overlay.time)
		if state == null:
			continue
		var texture := _load_overlay_texture(state.sprite)
		if texture == null:
			continue

		var node := _overlay_nodes[visible_count]
		visible_count += 1
		var anchor := OverlayEventFrame.anchor_to_vector(overlay.anchor)
		node.texture = texture
		node.size = texture.get_size()
		node.anchor_left = anchor.x
		node.anchor_top = anchor.y
		node.anchor_right = anchor.x
		node.anchor_bottom = anchor.y
		node.offset_left = -node.size.x * 0.5
		node.offset_top = -node.size.y * 0.5
		node.offset_right = node.size.x * 0.5
		node.offset_bottom = node.size.y * 0.5
		node.offset_transform_position = state.position
		node.offset_transform_scale = state.scale
		node.offset_transform_rotation = deg_to_rad(state.rotation)
		node.modulate = Color(1.0, 1.0, 1.0, clampf(state.opacity, 0.0, 1.0))
		node.visible = true
		node.z_index = visible_count

	for index in range(visible_count, _overlay_nodes.size()):
		_overlay_nodes[index].visible = false

func _active_overlays(time_ms: float) -> Array[OverlayEvent]:
	var result: Array[OverlayEvent] = []
	for event in _overlay_events:
		if time_ms >= event.time and time_ms <= event.end_time:
			result.append(event)
	result.sort_custom(func(a: OverlayEvent, b: OverlayEvent) -> bool:
		if a.x == b.x:
			return a.time < b.time
		return a.x < b.x
	)
	return result

func _ensure_overlay_nodes(count: int) -> void:
	while _overlay_nodes.size() < count:
		var node := TextureRect.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP
		node.offset_transform_enabled = true
		node.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
		node.visible = false
		_overlay_root.add_child(node)
		_overlay_nodes.append(node)

func _load_overlay_texture(reference: String) -> Texture2D:
	var chart := CM.selected_chart
	if chart == null or reference.is_empty() or not EventResourceRef.is_valid(reference):
		return null
	var path := EventResourceRef.resolve_sprite(chart, reference)
	var cache_index := _overlay_paths.find(path)
	if cache_index >= 0:
		return _overlay_textures[cache_index]

	var texture: Texture2D
	if path.begins_with("res://"):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_overlay_paths.append(path)
	_overlay_textures.append(texture)
	return texture
