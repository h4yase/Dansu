extends ChartEventFrame
class_name OverlayEventFrame

const ANCHOR_PRESETS: Array[String] = [
	"top_left", "top_center", "top_right",
	"center_left", "center", "center_right",
	"bottom_left", "bottom_center", "bottom_right",
]

var position: Vector2 = Vector2.ZERO
var anchor: String = "center"
var scale: Vector2 = Vector2.ONE
var rotation: float = 0.0
var sprite: String = ""
var opacity: float = 1.0
var has_opacity: bool = false

func clone() -> ChartEventFrame:
	var result := OverlayEventFrame.new()
	result.time = time
	result.ease = ease
	result.position = position
	result.anchor = anchor
	result.scale = scale
	result.rotation = rotation
	result.sprite = sprite
	result.opacity = opacity
	result.has_opacity = has_opacity
	return result

static func is_valid_anchor(value: String) -> bool:
	return ANCHOR_PRESETS.has(value)

static func anchor_to_vector(value: String) -> Vector2:
	match value:
		"top_left": return Vector2(0.0, 0.0)
		"top_center": return Vector2(0.5, 0.0)
		"top_right": return Vector2(1.0, 0.0)
		"center_left": return Vector2(0.0, 0.5)
		"center_right": return Vector2(1.0, 0.5)
		"bottom_left": return Vector2(0.0, 1.0)
		"bottom_center": return Vector2(0.5, 1.0)
		"bottom_right": return Vector2(1.0, 1.0)
		_: return Vector2(0.5, 0.5)

static func vector_to_anchor(value: Vector2) -> String:
	var column := clampi(int(round(value.x * 2.0)), 0, 2)
	var row := clampi(int(round(value.y * 2.0)), 0, 2)
	return ANCHOR_PRESETS[row * 3 + column]
