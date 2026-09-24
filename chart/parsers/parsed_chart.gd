extends RefCounted
class_name ParsedChart

var chart: Chart = null
var rails :Array[Rail] = []
var hitsounds: Array[HitSound] = []
var events: Array[ChartEvent] = []

func _init(chart_value: Chart = null) -> void:
	chart = chart_value
	rails = []
	hitsounds = []
	events = []

func get_notes() -> Array[Note]:
	var result: Array[Note] = []
	for rail in rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note != null:
				result.append(note)
	return result

func get_play_time_ms() -> int:
	var end_time_ms := 0
	for note in get_notes():
		end_time_ms = maxi(end_time_ms, note.end_time)
	return end_time_ms

func sort_events() -> void:
	for event in events:
		if event != null:
			event.sort_frames()
	events.sort_custom(func(a: ChartEvent, b: ChartEvent) -> bool:
		if a == null:
			return false
		if b == null:
			return true
		return a.time < b.time
	)
