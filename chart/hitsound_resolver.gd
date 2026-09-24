extends RefCounted
class_name HitsoundResolver

static func for_note(chart: Chart, streams: Dictionary, note: Note, hit_fallback: AudioStream, move_fallback: AudioStream) -> AudioStream:
	if note == null:
		return null
	var hitsound_id := int(note.hitsound)
	if hitsound_id < 0 and chart != null:
		hitsound_id = chart.get_default_hitsound_id(chart.get_default_hitsound_slot_for_note(note))
	if hitsound_id >= 0 and streams.has(hitsound_id):
		return streams[hitsound_id] as AudioStream
	return move_fallback if int(note.type) == int(Note.NoteType.MOVE) else hit_fallback

static func long_note_release(chart: Chart, streams: Dictionary, fallback: AudioStream) -> AudioStream:
	if chart != null:
		var hitsound_id := chart.get_default_hitsound_id(Chart.DEFAULT_HITSOUND_LONGNOTE_RELEASE)
		if hitsound_id >= 0 and streams.has(hitsound_id):
			return streams[hitsound_id] as AudioStream
	return fallback
