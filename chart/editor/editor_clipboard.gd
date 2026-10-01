extends RefCounted

class RailEntry extends RefCounted:
	var rail: EditorSnapshot.RailData
	var start: int
	var finish: int
	var start_x: float
	var end_x: float

class Placement extends RefCounted:
	var rail: Rail
	var target: Rail
	var notes: Array[Note] = []
	var points: Array[RailPoint] = []

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

func get_paste_time(editor: ChartEditor) -> int:
	var time := int(round(Game.current_time))
	if editor._is_mouse_inside_chart():
		var local := editor.chart_panel.get_local_mouse_position()
		time = editor._local_y_to_time(local.y)
	return editor.timeline.snap_time(time)

func build_placements(editor: ChartEditor) -> Array[Placement]:
	if data.is_empty():
		return []
	var chart := CM.ensure_parsed_chart()
	var time := get_paste_time(editor)
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
	var placements: Array[Placement] = []
	for i in range(data.size()):
		var item := data[i]
		var start := int(item.start) + shift
		var finish := int(item.finish) + shift
		var placement := Placement.new()
		var target := Rail.new()
		var existing := selected != null and i < targets.size()
		if existing:
			placement.target = targets[i]
			target.id = placement.target.id
			target.notes = placement.target.notes.duplicate()
			for original: RailPoint in placement.target.points:
				var point := RailPoint.new()
				point.time = original.time
				point.x = original.x
				point.curve = original.curve
				target.points.append(point)
		placement.rail = target
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
			placement.points.append(placed)
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
					placement.notes.erase(old)
			target.notes.append(note)
			placement.notes.append(note)
			target.sort_notes()
		placements.append(placement)
	return placements

func paste(editor: ChartEditor) -> bool:
	var placements := build_placements(editor)
	if placements.is_empty():
		return false
	editor._push_history_snapshot()
	editor.selection.clear()
	for placement in placements:
		var target := placement.target
		if target == null:
			target = placement.rail
			target.id = EditorChartOps.next_rail_id()
			CM.parsed_chart.rails.append(target)
		else:
			target.points = placement.rail.points
			target.notes = placement.rail.notes
	# Pick a primary object before filling the selection: selecting one clears it.
	for placement in placements:
		if not placement.notes.is_empty():
			editor.selection.select_note(placement.target if placement.target != null else placement.rail, placement.notes[0])
			break
	if editor.selection.selected_note == null:
		for placement in placements:
			if not placement.points.is_empty():
				var target := placement.target if placement.target != null else placement.rail
				editor.selection.select_point(target, target.points.find(placement.points[0]))
				break
	for placement in placements:
		var target := placement.target if placement.target != null else placement.rail
		for note in placement.notes:
			editor.selection.selected_notes[note] = target
		for point in placement.points:
			editor.selection.selected_points[point] = target
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
