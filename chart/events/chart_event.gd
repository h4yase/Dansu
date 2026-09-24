extends RefCounted
class_name ChartEvent

var id: String = ""
var time: int = 0
var duration: int = 0

var end_time: int:
	get:
		return time + duration

func sort_frames() -> void:
	pass
