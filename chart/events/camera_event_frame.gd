extends ChartEventFrame
class_name CameraEventFrame

var follow_character: bool = false
var position: Vector2 = Vector2.ZERO
var zoom: float = 1.0

func clone() -> ChartEventFrame:
	var result := CameraEventFrame.new()
	result.time = time
	result.ease = ease
	result.follow_character = follow_character
	result.position = position
	result.zoom = zoom
	return result
