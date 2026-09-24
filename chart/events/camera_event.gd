extends ChartEvent
class_name CameraEvent

var frames: Array[CameraEventFrame] = []

func _init() -> void:
	frames = []

func sort_frames() -> void:
	frames.sort_custom(func(a: CameraEventFrame, b: CameraEventFrame) -> bool: return a.time < b.time)
