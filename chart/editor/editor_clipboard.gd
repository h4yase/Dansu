extends RefCounted

class RailEntry extends RefCounted:
	var rail: EditorSnapshot.RailData
	var start: int
	var finish: int
	var start_x: float
	var end_x: float

var data: Array[RailEntry] = []
var first_time := 0

func copy(selection: ChartEditorSelection) -> bool:
	var owners: Array[Rail] = []
	for rail: Rail in selection.selected_notes.values():
		if not owners.has(rail):
			owners.append(rail)
	for rail: Rail in selection.selected_points.values():
		if not owners.has(rail):
			owners.append(rail)
	if selection.selected_rail != null and not owners.has(selection.selected_rail):
		owners.append(selection.selected_rail)
	if owners.is_empty():
		return false
	var whole_rail := selection.selected_notes.is_empty() and selection.selected_points.is_empty()
	var captured := EditorHistory._capture_rails(owners)
	var next_data: Array[RailEntry] = []
	var earliest := 2147483647
	for i in range(owners.size()):
		var rail := owners[i]
		var item: EditorSnapshot.RailData = captured[i]
		if not whole_rail:
			var notes: Array[EditorSnapshot.NoteData] = []
			for j in range(rail.notes.size()):
				if selection.selected_notes.has(rail.notes[j]):
					notes.append(item.notes[j])
			item.notes = notes
			var points: Array[EditorSnapshot.PointData] = []
			for j in range(rail.points.size()):
				if selection.selected_points.has(rail.points[j]):
					points.append(item.points[j])
			item.points = points
		if item.notes.is_empty() and item.points.is_empty():
			continue
		var start := 2147483647
		var finish := -2147483648
		for point: EditorSnapshot.PointData in item.points:
			start = mini(start, point.time)
			finish = maxi(finish, point.time)
		for note: EditorSnapshot.NoteData in item.notes:
			start = mini(start, note.time)
			finish = maxi(finish, note.time + maxi(note.length, 0))
		var entry := RailEntry.new()
		entry.rail = item
		entry.start = start
		entry.finish = finish
		entry.start_x = rail._get_rail_x_at_time(start)
		entry.end_x = rail._get_rail_x_at_time(finish)
		earliest = mini(earliest, start)
		next_data.append(entry)
	if next_data.is_empty():
		return false
	data = next_data
	first_time = earliest
	data.sort_custom(func(a: RailEntry, b: RailEntry) -> bool:
		return a.rail.id < b.rail.id if is_equal_approx(a.start_x, b.start_x) else a.start_x < b.start_x
	)
	return true

func paste(editor: ChartEditor) -> bool:
	if data.is_empty():
		return false
	var chart := CM.ensure_parsed_chart()
	var time := int(editor.timeline.snap_time(int(round(Game.current_time))))
	var shift := time - first_time
	var selected := editor.selection.selected_rail
	var targets: Array[Rail] = []
	if selected != null:
		for rail: Rail in chart.rails:
			if rail == selected or EditorChartOps.is_note_time_inside_rail(rail, time):
				targets.append(rail)
		targets.sort_custom(func(a: Rail, b: Rail) -> bool:
			var ax := a._get_rail_x_at_time(time)
			var bx := b._get_rail_x_at_time(time)
			return a.id < b.id if is_equal_approx(ax, bx) else ax < bx
		)
		# The explicitly selected rail anchors the leftmost copied source rail.
		var index := targets.find(selected)
		targets = targets.slice(index)
	var x_shift := 0.0 if selected == null else selected._get_rail_x_at_time(time) - float(data[0].start_x)
	editor._push_history_snapshot()
	var pasted_notes: Dictionary = {}
	var pasted_points: Dictionary[RailPoint, Rail] = {}
	for i in range(data.size()):
		var item := data[i]
		var start := int(item.start) + shift
		var finish := int(item.finish) + shift
		var target: Rail
		var existing := selected != null and i < targets.size()
		if existing:
			target = targets[i]
		else:
			target = Rail.new()
			target.id = EditorChartOps.next_rail_id()
			chart.rails.append(target)
		var start_x := target._get_rail_x_at_time(start) if existing else clampf(float(item.start_x) + x_shift, 0.0, 1.0)
		var end_x := target._get_rail_x_at_time(finish) if existing else clampf(float(item.end_x) + x_shift, 0.0, 1.0)
		if existing:
			_extend(target, start, finish)
		else:
			_put_point(target, start, start_x, 0.0)
			_put_point(target, maxi(start + 1, finish), end_x, 0.0)
		for point: EditorSnapshot.PointData in item.rail.points:
			var point_time := int(point.time) + shift
			var alpha := 0.0 if finish == start else float(point_time - start) / float(finish - start)
			var offset := lerpf(start_x - float(item.start_x), end_x - float(item.end_x), alpha) if existing else x_shift
			var placed := _put_point(target, point_time, clampf(float(point.x) + offset, 0.0, 1.0), point.curve)
			pasted_points[placed] = target
		for note_data: EditorSnapshot.NoteData in item.rail.notes:
			var note := Note.new()
			note.time = int(note_data.time) + shift
			note.type = int(note_data.type) as Note.NoteType
			note.dir = int(note_data.dir) as Note.Dir
			note.length = note_data.length
			note.animation = note_data.animation
			note.hitsound = note_data.hitsound
			for old: Note in target.notes.duplicate():
				if absi(old.time - note.time) <= 1:
					target.notes.erase(old)
					pasted_notes.erase(old)
			target.notes.append(note)
			pasted_notes[note] = target
			target.sort_notes()
	editor.selection.clear()
	if not pasted_notes.is_empty():
		var primary: Note = pasted_notes.keys()[0]
		editor.selection.select_note(pasted_notes[primary], primary)
		editor.selection.selected_notes = pasted_notes
	elif not pasted_points.is_empty():
		var primary: RailPoint = pasted_points.keys()[0]
		var rail: Rail = pasted_points[primary]
		editor.selection.select_point(rail, rail.points.find(primary))
	for point: RailPoint in pasted_points:
		editor.selection.selected_points[point] = pasted_points[point]
	editor.selection.refresh()
	editor.refresh_views()
	return true

func _extend(rail: Rail, start: int, finish: int) -> void:
	if start < rail.start_time:
		_put_point(rail, start, rail._get_rail_x_at_time(start), 0.0)
	if finish > rail.end_time:
		_put_point(rail, finish, rail._get_rail_x_at_time(finish), 0.0)

func _put_point(rail: Rail, time: int, x: float, curve: float) -> RailPoint:
	for point: RailPoint in rail.points:
		if point.time == time:
			point.x = x
			point.curve = curve
			return point
	var point := RailPoint.new()
	point.time = time
	point.x = x
	point.curve = curve
	rail.points.append(point)
	rail.sort_points()
	return point
