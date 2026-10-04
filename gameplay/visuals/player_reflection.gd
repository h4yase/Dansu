extends Sprite3D

const REFLECTION_SHADER := preload("res://resources/shaders/player_reflection.gdshader")

@export var source: Sprite3D

var _reflection_material: ShaderMaterial


func _ready() -> void:
	_reflection_material = ShaderMaterial.new()
	_reflection_material.shader = REFLECTION_SHADER
	_reflection_material.render_priority = 1
	material_override = _reflection_material


func _process(_delta: float) -> void:
	if source == null or source.texture == null:
		visible = false
		return
	visible = source.visible
	if texture != source.texture:
		texture = source.texture
		_reflection_material.set_shader_parameter("sprite_texture", texture)
	pixel_size = source.pixel_size
	offset = source.offset
	flip_h = source.flip_h
	flip_v = source.flip_v
	var mirror := Transform3D(
		Basis.from_scale(Vector3(1.0, -1.0, 1.0)), Vector3(0.0, -0.015, -0.01)
	)
	transform = mirror * source.transform
	_reflection_material.set_shader_parameter("tint", source.modulate)
