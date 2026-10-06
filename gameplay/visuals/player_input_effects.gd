extends Node3D

const KEY_SHADER := preload("res://resources/shaders/player_key_beam.gdshader")
const WAVE_SHADER := preload("res://resources/shaders/player_move_wave.gdshader")
const KEY_DURATION := 0.26
const WAVE_DURATION := 0.28
const MAX_EFFECTS := 32

var player: Player
var tint := GameRail.DEFAULT_ACCENT_COLOR
var _effects: Array[InputEffect] = []


class InputEffect:
	var mesh: MeshInstance3D
	var material: ShaderMaterial
	var start_time: float
	var duration: float


func spawn_key_beam() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.2, 12.0)
	_add_effect(plane, KEY_SHADER, KEY_DURATION)


func spawn_move_wave(dir: Note.Dir) -> void:
	if dir == Note.Dir.NONE:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.4, 3.2)
	var effect := _add_effect(plane, WAVE_SHADER, WAVE_DURATION)
	var direction := -1.0 if dir == Note.Dir.LEFT else 1.0
	effect.material.set_shader_parameter("direction", direction)


func _add_effect(mesh: Mesh, shader: Shader, duration: float) -> InputEffect:
	if _effects.size() >= MAX_EFFECTS:
		_effects.pop_front().mesh.queue_free()
	var effect := InputEffect.new()
	effect.material = ShaderMaterial.new()
	effect.material.shader = shader
	effect.material.set_shader_parameter("tint", tint)
	effect.mesh = MeshInstance3D.new()
	effect.mesh.mesh = mesh
	effect.mesh.material_override = effect.material
	effect.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Project the player's feet onto the tilted playfield, without inheriting skin scale.
	var origin := to_local(player.global_position)
	origin.y = 0.035
	effect.mesh.position = origin
	effect.start_time = Game.current_time
	effect.duration = duration
	add_child(effect.mesh)
	_effects.append(effect)
	return effect


func _process(_delta: float) -> void:
	for index in range(_effects.size() - 1, -1, -1):
		var effect := _effects[index]
		var age := (Game.current_time - effect.start_time) * 0.001
		if age < 0.0 or age >= effect.duration:
			effect.mesh.queue_free()
			_effects.remove_at(index)
			continue
		var progress := age / effect.duration
		effect.material.set_shader_parameter("progress", progress)


func reset() -> void:
	for effect in _effects:
		effect.mesh.queue_free()
	_effects.clear()
