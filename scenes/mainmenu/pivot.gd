extends Control


func _ready() -> void:
	offset_transform_enabled = true


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var _size := get_viewport_rect().size
	if _size.x <= 0.0 or _size.y <= 0.0:
		return
	var normalized := mouse / _size
	offset_transform_position = normalized * -30.0
