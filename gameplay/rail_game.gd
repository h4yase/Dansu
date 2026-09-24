extends Node3D
class_name GameRail

const CLIP_SHADER := preload("res://resources/shaders/rail_clip.gdshader")
const DEFAULT_WIDTH := 0.1
const DEFAULT_OUTLINE_SIZE := 0.1
const CAP_SEGMENTS := 10
const SAMPLE_INTERVAL_MS := 16.0
const SHADOW_EXTRA_SIZE := 0.025
const DEFAULT_FILL_COLOR := Color(0.135, 0.132, 0.205, 1.0)
const DEFAULT_OUTLINE_COLOR := Color(0.455, 0.420, 0.690, 1.0)
const DEFAULT_ACCENT_COLOR := Color(0.575, 0.520, 0.860, 1.0)
const DEFAULT_SHADOW_COLOR := Color(0.025, 0.025, 0.04, 1.0)
const IDLE_BRIGHTNESS := 0.38
const STANDING_BRIGHTNESS := 1.0

class RailMeshCacheEntry:
	extends RefCounted

	var rail: Rail
	var rail_width := 0.0
	var rail_outline_size := 0.0
	var mesh: ArrayMesh = null

static var _mesh_cache: Array[RailMeshCacheEntry] = []

static func clear_mesh_cache() -> void:
	_mesh_cache.clear()

var rail: Rail

@export var note_container: Node3D
@export var width: float = DEFAULT_WIDTH
@export var mesh_instance: MeshInstance3D

var outline_size := DEFAULT_OUTLINE_SIZE
var _material: ShaderMaterial = null
var _theme_color := DEFAULT_ACCENT_COLOR

var is_standing := false:
	set(value):
		is_standing = value
		_update_brightness()


static func prebake_for_rails(rails: Array[Rail], rail_width: float = DEFAULT_WIDTH, rail_outline_size: float = DEFAULT_OUTLINE_SIZE) -> void:
	for _rail in rails:
		prebake_for_rail(_rail, rail_width, rail_outline_size)


static func prebake_for_rail(_rail: Rail, rail_width: float = DEFAULT_WIDTH, rail_outline_size: float = DEFAULT_OUTLINE_SIZE) -> void:
	if _rail == null or _rail.points.size() < 2:
		return

	var existing_entry := _find_cached_mesh_entry(_rail, rail_width, rail_outline_size)
	if existing_entry != null:
		return

	var path := _sample_curve_points_for_rail(_rail)
	var new_entry := RailMeshCacheEntry.new()
	new_entry.rail = _rail
	new_entry.rail_width = rail_width
	new_entry.rail_outline_size = rail_outline_size
	new_entry.mesh = build_ribbon_mesh(path, _get_visual_width(rail_width, rail_outline_size))
	_mesh_cache.append(new_entry)


func _ready() -> void:
	if rail != null and not rail.points.is_empty():
		position.z = GameplayPlayfield.rail_origin_z(rail.start_time, Game.current_time)

	_apply_prebaked_mesh()
	_apply_material()


func _process(_delta: float) -> void:
	if rail == null or rail.points.is_empty():
		return
	position.z = GameplayPlayfield.rail_origin_z(rail.start_time, Game.current_time)
	_update_material_position()


func _apply_prebaked_mesh() -> void:
	if rail == null:
		mesh_instance.mesh = null
		return

	prebake_for_rail(rail, width, outline_size)
	var cached_entry := _find_cached_mesh_entry(rail, width, outline_size)
	mesh_instance.mesh = cached_entry.mesh if cached_entry != null else null


func _apply_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = CLIP_SHADER
	_material.set_shader_parameter("min_visible_z", 0.0)

	var visual_width := _get_visual_width(width, outline_size)
	_material.set_shader_parameter("fill_width_ratio", width / visual_width)
	_material.set_shader_parameter("outline_width_ratio", (width + outline_size * 2.0) / visual_width)

	mesh_instance.material_override = _material
	_update_brightness()
	_update_material_position()
	_update_theme_color()


func set_theme_color(color: Color) -> void:
	_theme_color = Color(color.r, color.g, color.b, 1.0)
	_update_theme_color()


func _update_theme_color() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("fill_color", _theme_color.darkened(0.75))
	_material.set_shader_parameter("outline_color", _theme_color.darkened(0.20))
	var shadow_color := _theme_color.darkened(0.955)
	_material.set_shader_parameter("shadow_color", shadow_color)
	_material.set_shader_parameter("accent_color", _theme_color)


func _update_brightness() -> void:
	if _material != null:
		_material.set_shader_parameter("brightness", STANDING_BRIGHTNESS if is_standing else IDLE_BRIGHTNESS)


func _update_material_position() -> void:
	if _material != null:
		_material.set_shader_parameter("rail_origin_z", position.z)


static func _get_visual_width(rail_width: float, rail_outline_size: float) -> float:
	return rail_width + ((rail_outline_size + SHADOW_EXTRA_SIZE) * 2.0)


static func _sample_curve_points_for_rail(_rail: Rail) -> Array[Vector3]:
	var result: Array[Vector3] = []

	if _rail == null or _rail.points.size() < 2:
		return result

	for i in range(_rail.points.size() - 1):
		var a: RailPoint = _rail.points[i]
		var b: RailPoint = _rail.points[i + 1]

		var t0 := int(a.time)
		var t1 := int(b.time)
		var duration_ms = max(1, t1 - t0)
		var steps = max(4, int(ceil(duration_ms / SAMPLE_INTERVAL_MS)))

		for j in range(steps):
			var alpha := float(j) / float(steps)
			var curved_alpha := _rail._apply_curve(alpha, float(a.curve))
			var x := GameplayPlayfield.normalized_x_to_world(lerp(float(a.x), float(b.x), curved_alpha))
			var sampled_time := int(round(lerp(float(t0), float(t1), alpha)))
			var z := GameplayPlayfield.local_z_from_start(_rail.start_time, sampled_time)
			result.append(Vector3(x, 0.0, z))

	var last := _rail.points[_rail.points.size() - 1]
	result.append(
		Vector3(
			GameplayPlayfield.normalized_x_to_world(float(last.x)),
			0.0,
			GameplayPlayfield.local_z_from_start(_rail.start_time, int(last.time))
		)
	)
	return result


static func _find_cached_mesh_entry(_rail: Rail, rail_width: float, rail_outline_size: float) -> RailMeshCacheEntry:
	for entry in _mesh_cache:
		if entry == null:
			continue
		if entry.rail != _rail:
			continue
		if not is_equal_approx(entry.rail_width, rail_width):
			continue
		if not is_equal_approx(entry.rail_outline_size, rail_outline_size):
			continue
		return entry
	return null


static func build_ribbon_mesh(
	path: Array[Vector3],
	rail_width: float,
	round_start: bool = true,
	round_end: bool = true
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if path.size() < 2:
		return st.commit()

	var half_width := rail_width * 0.5
	var left_points: Array[Vector3] = []
	var right_points: Array[Vector3] = []

	for i in range(path.size()):
		var offset := _get_join_offset(path, i, half_width)
		left_points.append(path[i] - offset)
		right_points.append(path[i] + offset)

	for i in range(path.size() - 1):
		var a := left_points[i]
		var b := right_points[i]
		var c := left_points[i + 1]
		var d := right_points[i + 1]

		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(0, 1)); st.add_vertex(c)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b)

		st.set_uv(Vector2(1, 0)); st.add_vertex(b)
		st.set_uv(Vector2(0, 1)); st.add_vertex(c)
		st.set_uv(Vector2(1, 1)); st.add_vertex(d)

	if round_start:
		var start_dir := (path[1] - path[0]).normalized()
		_append_cap(st, path[0], start_dir, half_width, true)
	if round_end:
		var end_dir := (path[path.size() - 1] - path[path.size() - 2]).normalized()
		_append_cap(st, path[path.size() - 1], end_dir, half_width, false)

	return st.commit()


static func build_open_ribbon_mesh(path: Array[Vector3], ribbon_width: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if path.size() < 2 or ribbon_width <= 0.0:
		return mesh

	var point_count := path.size()
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(point_count * 2)
	uvs.resize(point_count * 2)
	indices.resize((point_count - 1) * 6)

	var half_width := ribbon_width * 0.5
	for point_index in range(point_count):
		var offset := _get_join_offset(path, point_index, half_width)
		var vertex_index := point_index * 2
		var path_alpha := float(point_index) / float(point_count - 1)
		vertices[vertex_index] = path[point_index] - offset
		vertices[vertex_index + 1] = path[point_index] + offset
		uvs[vertex_index] = Vector2(0.0, path_alpha)
		uvs[vertex_index + 1] = Vector2(1.0, path_alpha)

	for segment_index in range(point_count - 1):
		var vertex_index := segment_index * 2
		var next_vertex_index := vertex_index + 2
		var index_offset := segment_index * 6
		indices[index_offset] = vertex_index
		indices[index_offset + 1] = next_vertex_index
		indices[index_offset + 2] = vertex_index + 1
		indices[index_offset + 3] = vertex_index + 1
		indices[index_offset + 4] = next_vertex_index
		indices[index_offset + 5] = next_vertex_index + 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_cap(st: SurfaceTool, center: Vector3, forward: Vector3, radius: float, is_start: bool) -> void:
	if forward.is_zero_approx():
		return

	forward = forward.normalized()
	var side := Vector3.UP.cross(forward).normalized()
	if side.is_zero_approx():
		side = Vector3.RIGHT

	var prev_point := _get_cap_point(center, side, forward, radius, 0.0, is_start)
	for index in range(1, CAP_SEGMENTS + 1):
		var angle := PI * float(index) / float(CAP_SEGMENTS)
		var next_point := _get_cap_point(center, side, forward, radius, angle, is_start)

		st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(center)
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(prev_point)
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(next_point)

		prev_point = next_point


static func _get_cap_point(center: Vector3, side: Vector3, forward: Vector3, radius: float, angle: float, is_start: bool) -> Vector3:
	var offset := Vector3.ZERO
	if is_start:
		offset = (side * cos(angle) - forward * sin(angle)) * radius
	else:
		offset = (-side * cos(angle) + forward * sin(angle)) * radius
	return center + offset


static func _get_join_offset(path: Array[Vector3], index: int, half_width: float) -> Vector3:
	var current := path[index]
	var prev := path[max(index - 1, 0)]
	var nxt := path[min(index + 1, path.size() - 1)]

	var prev_dir := (current - prev).normalized()
	var next_dir := (nxt - current).normalized()
	if prev_dir.is_zero_approx():
		prev_dir = next_dir
	if next_dir.is_zero_approx():
		next_dir = prev_dir
	if prev_dir.is_zero_approx() and next_dir.is_zero_approx():
		return Vector3.RIGHT * half_width

	var prev_side := Vector3.UP.cross(prev_dir).normalized()
	var next_side := Vector3.UP.cross(next_dir).normalized()
	if prev_side.dot(next_side) < 0.0:
		next_side = -next_side

	var miter := (prev_side + next_side).normalized()
	if miter.is_zero_approx():
		return next_side * half_width

	var miter_scale := half_width / maxf(absf(miter.dot(next_side)), 0.35)
	miter_scale = minf(miter_scale, half_width * 2.0)
	return miter * miter_scale
