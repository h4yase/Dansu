extends EditorSnapshotValue
class_name EditorSnapshot

var chart: ChartData = null
var timings: Array[TimingData] = []
var hitsounds: Array[HitSoundData] = []
var rails: Array[RailData] = []
var events: Array[EventData] = []
var selection: SelectionData = null
var current_time: float = 0.0
var beat_division: int = 4

func comparison_values() -> Array:
	return [chart.comparison_values() if chart != null else null,
		array_values(timings), array_values(hitsounds), array_values(rails), array_values(events),
		selection.comparison_values() if selection != null else null, current_time, beat_division]

func clear_editor_state() -> void:
	selection = null
	current_time = 0.0
	beat_division = 4

class ChartData extends EditorSnapshotValue:
	var version: int = 1
	var uuid: String = ""
	var folder_name: String = ""
	var file_name: String = ""
	var title: String = ""
	var artist: String = ""
	var creator: String = ""
	var source: String = ""
	var tags: String = ""
	var difficulty: String = ""
	var rating: float = 0.0
	var preview_time: float = 0.0
	var file_audio: String = ""
	var file_cover_art: String = ""
	var file_skin: String = ""
	var default_hitsounds: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1])

	func comparison_values() -> Array:
		return [
			version, uuid, folder_name, file_name, title, artist, creator, source, tags, difficulty,
			rating, preview_time, file_audio, file_cover_art, file_skin, default_hitsounds,
		]

class TimingData extends EditorSnapshotValue:
	var time: int = 0
	var bpm: float = 120.0

	func _init(p_time: int = 0, p_bpm: float = 120.0) -> void:
		time = p_time
		bpm = p_bpm

	func comparison_values() -> Array:
		return [time, bpm]

class HitSoundData extends EditorSnapshotValue:
	var id: int = -1
	var file_name: String = ""

	func _init(p_id: int = -1, p_file_name: String = "") -> void:
		id = p_id
		file_name = p_file_name

	func comparison_values() -> Array:
		return [id, file_name]

class PointData extends EditorSnapshotValue:
	var x: float = 0.5
	var curve: float = 0.0
	var time: int = 0

	func _init(p_x: float = 0.5, p_curve: float = 0.0, p_time: int = 0) -> void:
		x = p_x
		curve = p_curve
		time = p_time

	func comparison_values() -> Array:
		return [x, curve, time]

class NoteData extends EditorSnapshotValue:
	var time: int = 0
	var type: Note.NoteType = Note.NoteType.HIT
	var dir: Note.Dir = Note.Dir.NONE
	var length: int = 0
	var animation: int = 0
	var hitsound: int = -1

	func _init(
		p_time: int = 0,
		p_type: Note.NoteType = Note.NoteType.HIT,
		p_dir: Note.Dir = Note.Dir.NONE,
		p_length: int = 0,
		p_animation: int = 0,
		p_hitsound: int = -1
	) -> void:
		time = p_time
		type = p_type
		dir = p_dir
		length = p_length
		animation = p_animation
		hitsound = p_hitsound

	func comparison_values() -> Array:
		return [time, type, dir, length, animation, hitsound]

class RailData extends EditorSnapshotValue:
	var id: int = -1
	var points: Array[PointData] = []
	var notes: Array[NoteData] = []

	func comparison_values() -> Array:
		return [id, array_values(points), array_values(notes)]

class FrameData extends EditorSnapshotValue:
	var time: int = 0
	@warning_ignore("shadowed_global_identifier")
	var ease: String = ""
	var follow_character: bool = false
	var position: Vector2 = Vector2.ZERO
	var zoom: float = 1.0
	var scale: Vector2 = Vector2.ONE
	var rotation: float = 0.0
	var sprite: String = ""
	var opacity: float = 1.0
	var has_opacity: bool = false
	var bg_color: Color = Color.BLACK
	var bg_color_2: Color = Color.BLACK
	var rail_color: Color = Color.WHITE

	func comparison_values() -> Array:
		return [
			time, ease, follow_character, position, zoom, scale, rotation, sprite, opacity,
			has_opacity, bg_color, bg_color_2, rail_color,
		]

class EventData extends EditorSnapshotValue:
	enum Kind {CAMERA, OVERLAY, THEME, SKIN}

	var id: String = ""
	var time: int = 0
	var duration: int = 0
	var frames: Array[FrameData] = []
	var type: Kind = Kind.CAMERA
	var x: int = 0
	var anchor: String = "center"
	var skin_json: String = ""

	func comparison_values() -> Array:
		return [id, time, duration, array_values(frames), type, x, anchor, skin_json]

class SelectionData extends EditorSnapshotValue:
	enum Kind {CLEAR, RAIL, NOTE, POINT, EVENT}

	var kind: Kind = Kind.CLEAR
	var rail_id: int = -1
	var point_index: int = -1
	var note_index: int = -1
	var event_index: int = -1
	var event_id: String = ""
	var event_time: int = 0
	var frame_index: int = -1
	var items: Array[EventIndex] = []
	var notes: Array[NoteIndex] = []
	var points: Array[PointIndex] = []

	func comparison_values() -> Array:
		return [
			kind, rail_id, point_index, note_index, event_index, event_id, event_time, frame_index,
			array_values(items), array_values(notes), array_values(points),
		]

class EventIndex extends EditorSnapshotValue:
	var event_index: int
	var frame_index: int

	func _init(p_event_index: int, p_frame_index: int) -> void:
		event_index = p_event_index
		frame_index = p_frame_index

	func comparison_values() -> Array:
		return [event_index, frame_index]

class NoteIndex extends EditorSnapshotValue:
	var rail_id: int
	var note_index: int

	func _init(p_rail_id: int, p_note_index: int) -> void:
		rail_id = p_rail_id
		note_index = p_note_index

	func comparison_values() -> Array:
		return [rail_id, note_index]

class PointIndex extends EditorSnapshotValue:
	var rail_id: int
	var point_index: int

	func _init(p_rail_id: int, p_point_index: int) -> void:
		rail_id = p_rail_id
		point_index = p_point_index

	func comparison_values() -> Array:
		return [rail_id, point_index]
