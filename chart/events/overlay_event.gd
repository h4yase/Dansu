extends ChartEvent
class_name OverlayEvent

var x: int = 0
var anchor: String = "center"
var frames: Array[OverlayEventFrame] = []

func _init() -> void:
	frames = []

func sort_frames() -> void:
	frames.sort_custom(func(a: OverlayEventFrame, b: OverlayEventFrame) -> bool: return a.time < b.time)
