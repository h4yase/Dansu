extends TextureRect

var hovered := false
var _hover_scale := 1.0

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_hover_scale = move_toward(_hover_scale, 1.25 if hovered else 1.0, delta * 2.0)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * _hover_scale
