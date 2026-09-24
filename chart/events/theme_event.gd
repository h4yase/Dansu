extends ChartEvent
class_name ThemeEvent

var frames: Array[ThemeEventFrame] = []

func _init() -> void:
	frames = []

func sort_frames() -> void:
	frames.sort_custom(func(a: ThemeEventFrame, b: ThemeEventFrame) -> bool: return a.time < b.time)
