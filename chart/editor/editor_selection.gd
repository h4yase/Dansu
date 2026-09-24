extends RefCounted
class_name ChartEditorSelection

signal changed()

var selected_rail: Rail = null
var selected_note: Note = null
var selected_notes: Dictionary = {}
var selected_points: Dictionary = {}
var selected_point_index := -1
var selected_event: ChartEvent = null
var selected_event_frame_index := -1
var selected_event_items: Array[EditorEventItem] = []

func clear() -> void:
	selected_event_items.clear()
	selected_points.clear()
	selected_notes.clear()
	if selected_rail == null and selected_note == null and selected_point_index == -1 \
			and selected_event == null and selected_event_frame_index == -1:
		return

	selected_rail = null
	selected_note = null
	selected_point_index = -1
	selected_event = null
	selected_event_frame_index = -1
	changed.emit()

func select_rail(rail: Rail) -> void:
	selected_event_items.clear()
	selected_points.clear()
	selected_notes.clear()
	selected_rail = rail
	selected_note = null
	selected_point_index = -1
	selected_event = null
	selected_event_frame_index = -1
	changed.emit()

func select_note(rail: Rail, note: Note) -> void:
	selected_event_items.clear()
	selected_points.clear()
	selected_notes.clear()
	selected_notes[note] = rail
	selected_rail = rail
	selected_note = note
	selected_point_index = -1
	selected_event = null
	selected_event_frame_index = -1
	changed.emit()

func select_point(rail: Rail, point_index: int, additive: bool = false) -> void:
	selected_event_items.clear()
	var point := rail.points[point_index]
	if not additive:
		selected_notes.clear()
		selected_points.clear()
	if additive and selected_points.has(point):
		selected_points.erase(point)
		selected_note = null
		selected_point_index = -1
		if not selected_points.is_empty():
			var last: RailPoint = selected_points.keys().back()
			selected_rail = selected_points[last]
			selected_point_index = selected_rail.points.find(last)
		else:
			selected_note = null if selected_notes.is_empty() else selected_notes.keys().back()
			selected_rail = null if selected_note == null else selected_notes[selected_note]
		changed.emit()
		return
	selected_points[point] = rail
	selected_rail = rail
	selected_note = null
	selected_point_index = point_index
	selected_event = null
	selected_event_frame_index = -1
	changed.emit()

func select_event(event: ChartEvent, frame_index: int = -1) -> void:
	selected_event_items.clear()
	if event != null:
		var frames: Array = event.frames if event is ThemeEvent or event is CameraEvent or event is OverlayEvent else []
		selected_event_items.append(EditorEventItem.new(event, frames[frame_index] if frame_index >= 0 and frame_index < frames.size() else null))
	selected_points.clear()
	selected_notes.clear()
	selected_rail = null
	selected_note = null
	selected_point_index = -1
	selected_event = event
	selected_event_frame_index = frame_index
	changed.emit()

func refresh() -> void:
	changed.emit()

func toggle_note(rail: Rail, note: Note) -> void:
	selected_event_items.clear()
	if selected_notes.has(note):
		selected_notes.erase(note)
	else:
		selected_notes[note] = rail
	if not has_point():
		selected_note = null if selected_notes.is_empty() else selected_notes.keys().back()
		selected_rail = null if selected_note == null else selected_notes[selected_note]
	selected_event = null
	selected_event_frame_index = -1
	changed.emit()

func has_point() -> bool:
	return selected_rail != null and selected_point_index >= 0 and selected_point_index < selected_rail.points.size()

func get_point() -> RailPoint:
	if not has_point():
		return null
	return selected_rail.points[selected_point_index]
