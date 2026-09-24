extends Node3D
class_name GameplayLongNoteVisual

@export_group("Node References")
@export var body: MeshInstance3D
@export var tail_cap: Sprite3D

const BODY_SHADER := preload("res://resources/shaders/long_note.gdshader")
const SAMPLE_INTERVAL_MS := 16.0
const BODY_WIDTH_RATIO := 0.5
const BODY_SURFACE_Y := 0.012
const CAP_SURFACE_Y := 0.014
const HIT_BODY_COLOR := Color("929cf1")
const HIT_EDGE_COLOR := Color("6061df")
const MOVE_BODY_COLOR := Color("f15b6b")
const MOVE_EDGE_COLOR := Color("b83f4d")
const FAILED_BRIGHTNESS := 0.3
const BODY_RENDER_PRIORITY := 1

class MeshCacheEntry:
	extends RefCounted

	var rail: Rail = null
	var body_width := 0.0
	var note_speed := 0.0
	var owner_basis := Basis.IDENTITY
	var mesh: ArrayMesh = null

static var _mesh_cache: Dictionary = {}
static var _material_templates: Dictionary = {}

var _note: Note = null
var _rail: Rail = null
var _head_owner: Node3D = null
var _material: ShaderMaterial = null
var _cap_color := Color.WHITE


func _ready() -> void:
	visible = false
	set_process(false)


func configure(note: Note, rail: Rail, head_owner: Node3D, head_sprite: Sprite3D) -> void:
	_set_source(note, rail, head_owner)

	if not _is_supported_long_note() or head_sprite == null or head_sprite.texture == null:
		visible = false
		set_process(false)
		return

	var body_width := _get_head_world_width_in_owner_space(head_sprite)
	var cached_mesh := _get_cached_mesh(body_width)
	if cached_mesh == null:
		cached_mesh = _build_and_cache_mesh(body_width)
	if cached_mesh == null:
		visible = false
		set_process(false)
		return

	body.mesh = cached_mesh
	_setup_material()
	_setup_tail_cap(body_width, _get_tail_position())
	visible = true
	set_process(true)
	_update_clip_position()


func prebake(note: Note, rail: Rail, head_owner: Node3D, head_sprite: Sprite3D) -> void:
	_set_source(note, rail, head_owner)
	if not _is_supported_long_note() or head_sprite == null or head_sprite.texture == null:
		return
	_get_material_template(_note.type)
	var body_width := _get_head_world_width_in_owner_space(head_sprite)
	if _get_cached_mesh(body_width) == null:
		_build_and_cache_mesh(body_width)


static func clear_mesh_cache() -> void:
	_mesh_cache.clear()


func set_holding(value: bool) -> void:
	if _material != null:
		_material.set_shader_parameter("holding", 1.0 if value else 0.0)


func get_tail_cap() -> Sprite3D:
	return tail_cap


func set_failed() -> void:
	set_holding(false)
	var colors := _get_visual_colors(_note.type)
	var body_color: Color = colors[0]
	var edge_color: Color = colors[1]
	body_color = Color(body_color.r * FAILED_BRIGHTNESS, body_color.g * FAILED_BRIGHTNESS, body_color.b * FAILED_BRIGHTNESS, body_color.a)
	edge_color = Color(edge_color.r * FAILED_BRIGHTNESS, edge_color.g * FAILED_BRIGHTNESS, edge_color.b * FAILED_BRIGHTNESS, edge_color.a)
	_cap_color = body_color
	if _material != null:
		_material.set_shader_parameter("body_color", body_color)
		_material.set_shader_parameter("edge_color", edge_color)
	if tail_cap != null:
		tail_cap.modulate = _cap_color
	_update_clip_position()


func _process(_delta: float) -> void:
	_update_clip_position()


func _is_supported_long_note() -> bool:
	return (
		_note != null
		and _rail != null
		and _head_owner != null
		and _note.length > 0
		and (_note.type == Note.NoteType.HIT or _note.type == Note.NoteType.MOVE)
	)


func _set_source(note: Note, rail: Rail, head_owner: Node3D) -> void:
	_note = note
	_rail = rail
	_head_owner = head_owner


func _get_head_world_width_in_owner_space(head_sprite: Sprite3D) -> float:
	var texture_width := head_sprite.texture.get_size().x
	var sprite_scale_x := absf(head_sprite.transform.basis.get_scale().x)
	return texture_width * head_sprite.pixel_size * sprite_scale_x * BODY_WIDTH_RATIO


func _get_cached_mesh(body_width: float) -> ArrayMesh:
	var entry: MeshCacheEntry = _mesh_cache.get(_note)
	if entry == null:
		return null
	if entry.rail != _rail:
		return null
	if not is_equal_approx(entry.body_width, body_width):
		return null
	if not is_equal_approx(entry.note_speed, Config.note_speed):
		return null
	if not entry.owner_basis.is_equal_approx(_head_owner.transform.basis):
		return null
	return entry.mesh


func _build_and_cache_mesh(body_width: float) -> ArrayMesh:
	if body_width <= 0.0:
		return null
	var path := _sample_note_path()
	if path.size() < 2:
		return null

	var entry := MeshCacheEntry.new()
	entry.rail = _rail
	entry.body_width = body_width
	entry.note_speed = Config.note_speed
	entry.owner_basis = _head_owner.transform.basis
	entry.mesh = GameRail.build_open_ribbon_mesh(path, body_width)
	_mesh_cache[_note] = entry
	return entry.mesh


func _sample_note_path() -> Array[Vector3]:
	var path: Array[Vector3] = []
	var duration_ms := maxi(_note.length, 1)
	var steps := maxi(4, int(ceil(float(duration_ms) / SAMPLE_INTERVAL_MS)))

	for index in range(steps + 1):
		var alpha := float(index) / float(steps)
		var time_ms := int(round(lerp(float(_note.time), float(_note.end_time), alpha)))
		var parent_point := Vector3(
			GameplayPlayfield.normalized_x_to_world(_rail._get_rail_x_at_time(time_ms)),
			BODY_SURFACE_Y,
			GameplayPlayfield.local_z_from_start(_rail.start_time, time_ms)
		)
		path.append(_head_owner.transform.affine_inverse() * parent_point)

	return path


func _get_tail_position() -> Vector3:
	var parent_point := Vector3(
		GameplayPlayfield.normalized_x_to_world(_rail._get_rail_x_at_time(_note.end_time)),
		BODY_SURFACE_Y,
		GameplayPlayfield.local_z_from_start(_rail.start_time, _note.end_time)
	)
	return _head_owner.transform.affine_inverse() * parent_point


func _setup_material() -> void:
	var colors := _get_visual_colors(_note.type)
	var body_color: Color = colors[0]
	_cap_color = body_color
	_material = _get_material_template(_note.type).duplicate() as ShaderMaterial
	_material.render_priority = BODY_RENDER_PRIORITY
	_material.set_shader_parameter("spawn_fade_distance", GameplayPlayfield.get_spawn_fade_distance())
	var owner_transform := _head_owner.transform
	_material.set_shader_parameter("owner_z_axis", Vector3(
		owner_transform.basis.x.z, owner_transform.basis.y.z, owner_transform.basis.z.z
	))
	_material.set_shader_parameter("holding", 0.0)
	body.material_override = _material


static func _get_material_template(note_type: Note.NoteType) -> ShaderMaterial:
	var cached := _material_templates.get(note_type) as ShaderMaterial
	if cached != null:
		return cached

	var colors := _get_visual_colors(note_type)
	var material := ShaderMaterial.new()
	material.shader = BODY_SHADER
	material.render_priority = BODY_RENDER_PRIORITY
	material.set_shader_parameter("body_color", colors[0])
	material.set_shader_parameter("edge_color", colors[1])
	material.set_shader_parameter("holding", 0.0)
	_material_templates[note_type] = material
	return material


static func _get_visual_colors(note_type: Note.NoteType) -> Array[Color]:
	if note_type == Note.NoteType.MOVE:
		return [MOVE_BODY_COLOR, MOVE_EDGE_COLOR]
	return [HIT_BODY_COLOR, HIT_EDGE_COLOR]


func _setup_tail_cap(body_width: float, endpoint: Vector3) -> void:
	if tail_cap == null or tail_cap.texture == null:
		return

	tail_cap.pixel_size = body_width / maxf(tail_cap.texture.get_size().x, 1.0)
	var parent_endpoint := _head_owner.transform * endpoint
	parent_endpoint.y = CAP_SURFACE_Y
	tail_cap.position = _head_owner.transform.affine_inverse() * parent_endpoint
	tail_cap.modulate = _cap_color


func _update_clip_position() -> void:
	if _material == null or _head_owner == null or _rail == null:
		return

	var current_time_z := -(
		(Game.current_time - float(_rail.start_time)) * Config.note_speed / 1000.0
	)
	var parent_point := Vector3(_head_owner.position.x, BODY_SURFACE_Y, current_time_z)
	var local_point := _head_owner.transform.affine_inverse() * parent_point
	_material.set_shader_parameter("clip_local_z", local_point.z)
	_material.set_shader_parameter("playfield_origin_z",
		GameplayPlayfield.rail_origin_z(_rail.start_time, Game.current_time) + _head_owner.position.z)
	if tail_cap != null:
		var alpha := GameplayPlayfield.get_spawn_fade_alpha(_note.end_time, Game.current_time)
		tail_cap.modulate = Color(_cap_color.r, _cap_color.g, _cap_color.b, _cap_color.a * alpha)
