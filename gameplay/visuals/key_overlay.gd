extends Control
class_name GameplayKeyOverlay

var _keys: Array[GameplayKeyIcon] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys.assign([$Hit1, $Hit2, $Left, $Right])


func apply_inputs(inputs: Array[ReplayInput], color: Color) -> void:
	for key in _keys:
		key.tint = color
	for input in inputs:
		# Replay input types are signed key numbers: down is positive, up is negative.
		var index := absi(input.type) - 1
		if index >= 0 and index < _keys.size():
			_keys[index].set_pressed(input.type > 0)


func reset() -> void:
	for key in _keys:
		key.reset()
