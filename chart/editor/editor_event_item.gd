extends RefCounted
class_name EditorEventItem

var event: ChartEvent
var frame: ChartEventFrame

func _init(p_event: ChartEvent, p_frame: ChartEventFrame = null) -> void:
	event = p_event
	frame = p_frame

func same_item(other: EditorEventItem) -> bool:
	return other != null and event == other.event and frame == other.frame
