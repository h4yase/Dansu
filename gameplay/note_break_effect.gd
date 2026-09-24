extends Node3D
class_name GameplayNoteBreakEffect

@export var particles: GPUParticles3D
@export_range(1, 8, 1) var shard_columns := 2
@export_range(1, 8, 1) var shard_rows := 1
@export_range(0.0, 1.0, 0.01) var inertia_ratio := 0.09


func play(texture: Texture2D, tint: Color, flip_h: bool, pixel_size: float, note_speed: float) -> void:
	if particles == null or texture == null:
		queue_free()
		return

	var process_material := particles.process_material as ShaderMaterial
	var shard_mesh := particles.draw_pass_1 as QuadMesh
	var shard_material := shard_mesh.material as ShaderMaterial if shard_mesh != null else null
	if process_material == null or shard_mesh == null or shard_material == null:
		queue_free()
		return

	var grid_size := Vector2(shard_columns, shard_rows)
	var full_size := texture.get_size() * pixel_size
	particles.amount = shard_columns * shard_rows
	shard_mesh.size = full_size / grid_size

	process_material.set_shader_parameter("full_size", full_size)
	process_material.set_shader_parameter("shard_columns", shard_columns)
	process_material.set_shader_parameter("shard_rows", shard_rows)
	process_material.set_shader_parameter("forward_inertia", maxf(note_speed, 0.0) * inertia_ratio)
	shard_material.set_shader_parameter("shard_texture", texture)
	shard_material.set_shader_parameter("tint", tint)
	shard_material.set_shader_parameter("flip_h", flip_h)
	shard_material.set_shader_parameter("shard_columns", shard_columns)
	shard_material.set_shader_parameter("shard_rows", shard_rows)

	particles.restart()
	particles.emitting = true


func _on_particles_finished() -> void:
	queue_free()
