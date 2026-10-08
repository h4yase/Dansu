extends TextureRect

const OUTLINE_SHADER := preload("res://resources/shaders/editor_note_outline.gdshader")

var hovered := false
var selected := false:
	set(value):
		if selected == value:
			return
		selected = value
		if _outline_material != null:
			_outline_material.set_shader_parameter("selected", selected)
var _hover_scale := 1.0
var _outline_material: ShaderMaterial

func _ready() -> void:
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("draw_size", size)
	_outline_material.set_shader_parameter("selected", selected)
	material = _outline_material

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_hover_scale = move_toward(_hover_scale, 1.25 if hovered else 1.0, delta * 2.0)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * _hover_scale
