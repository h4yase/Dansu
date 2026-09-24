extends RefCounted
class_name EventEditState

var items: Array[EditorEventItem] = []
var events: Dictionary[ChartEvent, Placement] = {}
var frames: Dictionary[ChartEventFrame, int] = {}

class Placement extends RefCounted:
	var time: int
	var duration: int
	var x: int

	func _init(event: ChartEvent = null) -> void:
		if event != null:
			time = event.time
			duration = event.duration
			x = event.x if event is OverlayEvent else 0

	func copy() -> Placement:
		var result := Placement.new()
		result.time = time
		result.duration = duration
		result.x = x
		return result
