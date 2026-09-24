extends RefCounted
class_name EditorHitsoundManager

signal changed()

const DEFAULT_HIT_SFX := preload("res://resources/audio/hitsounds/chop.wav")
const DEFAULT_MOVE_SFX := preload("res://resources/audio/hitsounds/chop.wav")

var chart: Chart = null
var selection: ChartEditorSelection = null

var _streams: Dictionary = {}

func setup(p_chart: Chart, p_selection: ChartEditorSelection) -> void:
	chart = p_chart
	selection = p_selection
	ensure_builtins()
	rebuild_cache()

func rebuild_cache() -> void:
	ensure_builtins()
	_streams.clear()
	var parsed_chart := CM.ensure_parsed_chart()
	for hitsound in parsed_chart.hitsounds:
		if hitsound == null or hitsound.stream == null:
			continue
		_streams[hitsound.id] = hitsound.stream

func ensure_builtins() -> void:
	var parsed_chart := CM.ensure_parsed_chart()
	var existing_ids: Dictionary = {}
	var existing_files: Dictionary = {}
	for hitsound in parsed_chart.hitsounds:
		if hitsound == null:
			continue
		existing_ids[hitsound.id] = true
		existing_files[hitsound.file_name] = true
	for builtin in HitSound.load_builtin_hitsounds():
		if builtin == null:
			continue
		if existing_ids.has(builtin.id) or existing_files.has(builtin.file_name):
			continue
		parsed_chart.hitsounds.append(builtin)

func get_all_hitsounds() -> Array[HitSound]:
	ensure_builtins()
	var parsed_chart := CM.ensure_parsed_chart()
	var result: Array[HitSound] = []
	for hitsound in parsed_chart.hitsounds:
		if hitsound != null:
			result.append(hitsound)
	result.sort_custom(func(a: HitSound, b: HitSound) -> bool: return a.id < b.id)
	return result

func get_custom_hitsounds() -> Array[HitSound]:
	var result: Array[HitSound] = []
	for hitsound in get_all_hitsounds():
		if not hitsound.is_builtin():
			result.append(hitsound)
	return result

func get_default_hitsound_id(slot: int) -> int:
	return chart.get_default_hitsound_id(slot) if chart != null else -1

func set_default_hitsound_id(slot: int, hitsound_id: int) -> void:
	if chart == null:
		return
	chart.set_default_hitsound_id(slot, hitsound_id)
	_notify_changed()

func set_selected_note_hitsound_id(hitsound_id: int) -> void:
	if selection == null or selection.selected_note == null:
		return
	selection.selected_note.hitsound = hitsound_id
	_notify_changed()

func add_custom_hitsound_from_file(source_path: String) -> void:
	if chart == null or source_path.is_empty():
		return
	if source_path.get_extension().to_lower() != "wav":
		return
	ensure_builtins()
	var target_path := FileSystem.copy_file_unique(source_path, chart.folder_path, "hitsound")
	if target_path.is_empty():
		return
	var hitsound := HitSound.new()
	hitsound.setup(chart, _next_id(), target_path.get_file())
	CM.ensure_parsed_chart().hitsounds.append(hitsound)
	_notify_changed()

func remove_custom_hitsound(hitsound_id: int) -> void:
	var parsed_chart := CM.ensure_parsed_chart()
	var target: HitSound = null
	for hitsound in parsed_chart.hitsounds:
		if hitsound != null and hitsound.id == hitsound_id:
			target = hitsound
			break
	if target == null or target.is_builtin():
		return
	parsed_chart.hitsounds.erase(target)
	if not target.file_path.is_empty() and FileAccess.file_exists(target.file_path):
		DirAccess.remove_absolute(target.file_path)
	for slot in range(Chart.DEFAULT_HITSOUND_SLOT_COUNT):
		if chart != null and chart.get_default_hitsound_id(slot) == hitsound_id:
			chart.set_default_hitsound_id(slot, -1)
	for rail in parsed_chart.rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note != null and int(note.hitsound) == hitsound_id:
				note.hitsound = -1
	_notify_changed()

func get_stream_for_note(note: Note) -> AudioStream:
	return HitsoundResolver.for_note(chart, _streams, note, DEFAULT_HIT_SFX, DEFAULT_MOVE_SFX)

func get_release_stream() -> AudioStream:
	return HitsoundResolver.long_note_release(chart, _streams, DEFAULT_HIT_SFX)

func _notify_changed() -> void:
	rebuild_cache()
	changed.emit()

func _next_id() -> int:
	var next_id := 0
	for hitsound in CM.ensure_parsed_chart().hitsounds:
		if hitsound != null:
			next_id = max(next_id, hitsound.id + 1)
	return next_id
