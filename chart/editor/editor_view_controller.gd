extends Node
class_name EditorViewController

class NoteHit extends RefCounted:
	var note: Note
	var rail: Rail
	var tail: bool

	func _init(p_note: Note, p_rail: Rail, p_tail: bool = false) -> void:
		note = p_note
		rail = p_rail
		tail = p_tail

class PointHit extends RefCounted:
	var rail: Rail
	var point_index: int

	func _init(p_rail: Rail, p_index: int) -> void:
		rail = p_rail
		point_index = p_index


const POINT_HIT_RADIUS := 15.0
@export var editor: ChartEditor
@export var chart_root: Control
@export var chart_panel: Control
@export var note_pivot: Control
@export var bpm_lines: Control
@export var rail_layer: Control
@export var note_layer: Control

var rail_scene := preload("res://scenes/chart/editor/editor_rail.tscn")
var note_scene := preload("res://scenes/chart/editor/editor_note.tscn")

var rail_views: Dictionary = {}
var note_views: Dictionary = {}
var _sorted_note_views: Array[EditorNote] = []
var _note_end_times: Array[int] = []
var _visible_note_views: Array[EditorNote] = []
var _layout_dirty := true
var _last_panel_size := Vector2(-1.0, -1.0)
var _last_judge_y := INF
var _last_current_time := INF

var _hover_note: EditorNote
var _hover_rail: EditorRail
var _hover_mouse := Vector2(INF, INF)
var _hover_time := INF
var _hover_enabled := false

func _ready() -> void:
	editor.transport.note_crossed.connect(_on_note_crossed)

func _on_note_crossed(note: Note) -> void:
	var note_view := note_views.get(note) as EditorNote
	if note_view != null:
		note_view.play_pass()

func _process(_delta: float) -> void:
	if editor == null:
		return
	var can_hover: bool = editor._is_mouse_inside_chart() and not editor.edit_controller.gesture.active \
		and not (editor.event_controller != null and editor.event_controller.active)
	var mouse := editor.get_global_mouse_position()
	if mouse == _hover_mouse and _hover_time == Game.current_time and can_hover == _hover_enabled:
		return
	_hover_mouse = mouse
	_hover_time = Game.current_time
	_hover_enabled = can_hover
	if is_instance_valid(_hover_note):
		_hover_note.set_hovered(false)
	if is_instance_valid(_hover_rail):
		_hover_rail.set_hovered_point(-1)
	_hover_note = null
	_hover_rail = null
	var note_hit := find_note_at(mouse) if can_hover and not editor.note_passthrough else null
	var point_hit := find_point_at(mouse) if can_hover and (note_hit == null or not note_hit.tail) else null
	if point_hit != null:
		note_hit = null
	if note_hit != null:
		_hover_note = note_views.get(note_hit.note) as EditorNote
		_hover_note.set_hovered(true, note_hit.tail)
	if point_hit != null:
		_hover_rail = rail_views.get(point_hit.rail) as EditorRail
		_hover_rail.set_hovered_point(point_hit.point_index)

func prepare_layers() -> void:
	if rail_layer != null:
		rail_layer.z_index = 0
	if chart_panel == null:
		return
	if rail_layer != null:
		rail_layer.size = chart_panel.size
	if note_layer != null:
		note_layer.size = chart_panel.size

func configure_chart_input() -> void:
	for node in [chart_root, chart_panel, bpm_lines, note_pivot]:
		if node != null:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func mark_layout_dirty() -> void:
	_layout_dirty = true
	_hover_mouse = Vector2(INF, INF)

func refresh_views() -> void:
	if editor != null:
		editor.update_object_counts()
	_hover_mouse = Vector2(INF, INF)
	_mark_preview_dirty()
	clear_layers()
	rail_views.clear()
	note_views.clear()
	_sorted_note_views.clear()
	_note_end_times.clear()
	_visible_note_views.clear()
	_layout_dirty = true

	if editor == null or editor.transport == null or CM.parsed_chart == null:
		if editor != null and editor.transport != null:
			editor.transport.rebuild_playback_notes()
		sync_layouts()
		return

	for rail: Rail in CM.parsed_chart.rails:
		if rail == null:
			continue
		var rail_view: EditorRail = rail_scene.instantiate()
		rail_view.rail = rail
		rail_view.editor = editor
		rail_layer.add_child(rail_view)
		rail_view.set_point_handles_dimmed(false)
		rail_views[rail] = rail_view

		for note in rail.notes:
			if note == null:
				continue
			var note_view: EditorNote = note_scene.instantiate()
			note_view.note = note
			note_view.rail = rail
			note_view.editor = editor
			note_view.set_passthrough(editor.note_passthrough)
			note_view.hide()
			note_view.set_process(false)
			note_layer.add_child(note_view)
			note_views[note] = note_view

	editor.transport.rebuild_playback_notes()
	sync_layouts()


func refresh_note(note: Note) -> void:
	_mark_preview_dirty()
	if note == null:
		return
	if editor != null and editor.transport != null:
		editor.transport.rebuild_playback_notes()
	mark_layout_dirty()
	sync_layouts()
	var note_view := note_views.get(note) as EditorNote
	if note_view != null:
		note_view.queue_redraw()


func refresh_notes_for_rail(rail: Rail) -> void:
	_mark_preview_dirty()
	if rail == null:
		return
	for note: Note in rail.notes:
		var note_view := note_views.get(note) as EditorNote
		if note_view != null:
			note_view.queue_redraw()

func refresh_geometry(rails: Array[Rail]) -> void:
	for rail in rails:
		refresh_notes_for_rail(rail)
	mark_layout_dirty()
	sync_layouts()

func _mark_preview_dirty() -> void:
	if editor != null and editor.event_controller != null and editor.event_controller.game_view != null:
		editor.event_controller.game_view.chart_dirty = true

func clear_layers() -> void:
	if rail_layer != null:
		for child in rail_layer.get_children():
			child.queue_free()
	if note_layer != null:
		for child in note_layer.get_children():
			child.queue_free()

func sync_layouts() -> void:
	if editor == null or chart_panel == null or note_pivot == null:
		return

	var panel_size := chart_panel.size
	var judge_y := note_pivot.position.y - chart_panel.position.y
	var current_time := Game.current_time

	if not _layout_dirty \
	and _last_panel_size == panel_size \
	and is_equal_approx(_last_judge_y, judge_y) \
	and is_equal_approx(_last_current_time, current_time):
		return

	var refresh_selection := _layout_dirty
	if _layout_dirty:
		_rebuild_note_range()
	_layout_dirty = false
	_last_panel_size = panel_size
	_last_judge_y = judge_y
	_last_current_time = current_time

	if rail_layer != null and rail_layer.size != panel_size:
		rail_layer.size = panel_size
	if note_layer != null and note_layer.size != panel_size:
		note_layer.size = panel_size

	for rail_view in rail_views.values():
		rail_view.sync_layout(panel_size, judge_y, editor.get_pixels_per_ms(), current_time)
		if refresh_selection:
			rail_view.set_selection_state(editor.selection.selected_rail == rail_view.rail, editor.selection.selected_point_index)

	_sync_visible_notes(panel_size, judge_y, editor.get_pixels_per_ms(), current_time)

	editor._update_time_ui(false)

func _rebuild_note_range() -> void:
	_sorted_note_views.clear()
	_note_end_times.clear()
	for note_view: EditorNote in note_views.values():
		_sorted_note_views.append(note_view)
	_sorted_note_views.sort_custom(func(a: EditorNote, b: EditorNote) -> bool: return a.note.time < b.note.time)
	# Prefix end times retain long notes whose heads have already left the screen.
	var last_end := -9223372036854775807
	for note_view in _sorted_note_views:
		last_end = maxi(last_end, note_view.note.end_time)
		_note_end_times.append(last_end)

func _sync_visible_notes(panel_size: Vector2, judge_y: float, pixels_per_ms: float, current_time: float) -> void:
	var time_scale := maxf(pixels_per_ms, 0.001)
	var start_time := current_time - (panel_size.y - judge_y + 96.0) / time_scale
	var end_time := current_time + (judge_y + 96.0) / time_scale
	for index in range(_visible_note_views.size() - 1, -1, -1):
		var note_view := _visible_note_views[index]
		if note_view.note.end_time < start_time or note_view.note.time > end_time:
			note_view.sync_layout(panel_size, judge_y, pixels_per_ms, current_time)
			_visible_note_views.remove_at(index)

	var first := 0
	var last := _note_end_times.size()
	while first < last:
		var middle := first + ((last - first) >> 1)
		if _note_end_times[middle] < start_time:
			first = middle + 1
		else:
			last = middle
	for index in range(first, _sorted_note_views.size()):
		var note_view := _sorted_note_views[index]
		if note_view.note.time > end_time:
			break
		if note_view.note.end_time < start_time:
			continue
		if not note_view.visible:
			_visible_note_views.append(note_view)
		note_view.sync_layout(panel_size, judge_y, pixels_per_ms, current_time)
		note_view.set_selected(editor.selection.selected_notes.has(note_view.note))

func set_note_passthrough(enabled: bool) -> void:
	_hover_mouse = Vector2(INF, INF)
	for note_view in note_views.values():
		note_view.set_passthrough(enabled)
	for rail_view in rail_views.values():
		rail_view.set_point_handles_dimmed(not enabled)

func find_note_at(global_mouse_pos: Vector2) -> NoteHit:
	for note_view in _visible_note_views:
		if note_view.is_tail_hit(global_mouse_pos):
			return NoteHit.new(note_view.note, note_view.rail, true)
	for note_view in _visible_note_views:
		if note_view.is_head_hit(global_mouse_pos):
			return NoteHit.new(note_view.note, note_view.rail)
	return null

func find_rail_at(global_mouse_pos: Vector2) -> Rail:
	var closest_rail: Rail = null
	var closest_distance := INF
	for rail in rail_views.keys():
		var dist: float = rail_views[rail].distance_to_curve(global_mouse_pos)
		if dist < 14.0 and dist < closest_distance:
			closest_distance = dist
			closest_rail = rail
	return closest_rail

func find_point_at(global_mouse_pos: Vector2) -> PointHit:
	var closest_rail: Rail = null
	var closest_index := -1
	var closest_distance := INF
	for rail in rail_views.keys():
		var rail_view: EditorRail = rail_views[rail]
		var point_index := rail_view.get_point_hit_index(global_mouse_pos)
		if point_index == -1:
			continue
		var local := rail_view.get_global_transform_with_canvas().affine_inverse() * global_mouse_pos
		var dist := rail_view._point_to_panel(rail.points[point_index]).distance_to(local)
		if dist < closest_distance:
			closest_distance = dist
			closest_rail = rail
			closest_index = point_index
	if closest_rail == null:
		return null
	return PointHit.new(closest_rail, closest_index)

func drag_selected_point(global_mouse_pos: Vector2) -> void:
	if editor == null or chart_panel == null:
		return
	var point := editor.selection.get_point()
	if point == null:
		return
	var local := chart_panel.get_global_transform_with_canvas().affine_inverse() * global_mouse_pos
	var next_x = clamp(snapped(local.x / max(1.0, chart_panel.size.x), 0.05), 0.0, 1.0)
	var next_time := editor.timeline.snap_time(editor._local_y_to_time(local.y))
	next_time = EditorChartOps.constrain_rail_point_time(editor.selection.selected_rail, point, next_time)
	if is_equal_approx(point.x, next_x) and point.time == next_time:
		return
	if editor._point_drag_history_pending:
		editor._push_history_snapshot()
		editor._point_drag_history_pending = false
	point.x = next_x
	point.time = next_time
	editor.selection.selected_rail.sort_points()
	editor.selection.selected_point_index = editor.selection.selected_rail.points.find(point)
	refresh_notes_for_rail(editor.selection.selected_rail)
	mark_layout_dirty()
	sync_layouts()

func finalize_selected_point_drag(global_mouse_pos: Vector2) -> void:
	if editor == null or not editor.selection.has_point():
		return

	var source_rail := editor.selection.selected_rail
	var source_point_index := editor.selection.selected_point_index
	var target_hit := _find_merge_target_for_selected_point(global_mouse_pos, source_rail, source_point_index)
	if target_hit == null:
		return

	var target_rail := target_hit.rail as Rail
	var target_point_index := int(target_hit.point_index)
	if not EditorChartOps.can_merge_rails(source_rail, source_point_index, target_rail, target_point_index):
		Notification.notice(GameText.text(GameText.Key.ERROR_RAIL_MERGE_OVERLAP), Notification.Type.WARNING)
		return

	if editor._point_drag_history_pending:
		editor._push_history_snapshot()
		editor._point_drag_history_pending = false

	var merged_rail: Rail = EditorChartOps.merge_rails(source_rail, source_point_index, target_rail, target_point_index)
	if merged_rail == null:
		return

	editor.selection.select_rail(merged_rail)
	refresh_views()

func _find_merge_target_for_selected_point(global_mouse_pos: Vector2, source_rail: Rail, source_point_index: int) -> PointHit:
	if source_rail == null or source_rail.points.is_empty():
		return null

	var is_source_first := source_point_index == 0
	var is_source_last := source_point_index == source_rail.points.size() - 1
	if not is_source_first and not is_source_last:
		return null

	var closest_rail: Rail = null
	var closest_index := -1
	var closest_distance := INF
	for rail in rail_views.keys():
		if rail == null or rail == source_rail or rail.points.is_empty():
			continue

		var target_index = 0 if is_source_last else rail.points.size() - 1
		var rail_view := rail_views.get(rail) as EditorRail
		if rail_view == null:
			continue

		var local := rail_view.get_global_transform_with_canvas().affine_inverse() * global_mouse_pos
		var distance := rail_view._point_to_panel(rail.points[target_index]).distance_to(local)
		if distance > POINT_HIT_RADIUS or distance >= closest_distance:
			continue

		closest_distance = distance
		closest_rail = rail
		closest_index = target_index

	if closest_rail == null:
		return null
	return PointHit.new(closest_rail, closest_index)
