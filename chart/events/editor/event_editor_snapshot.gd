extends EditorSnapshotValue
class_name EventEditorSnapshot

var events: Array[EditorSnapshot.EventData] = []
var event_index: int = -1
var frame_index: int = -1
var current_time: float = 0.0

func comparison_values() -> Array:
	return [array_values(events), event_index, frame_index, current_time]

func clear_editor_state() -> void:
	event_index = -1
	frame_index = -1
	current_time = 0.0
