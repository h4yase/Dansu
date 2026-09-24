extends Node
class_name EditorViewController

class NoteHit extends RefCounted:
	var note: Note
	var rail: Rail

	func _init(p_note: Note, p_rail: Rail) -> void:
		note = p_note
		rail = p_rail

class PointHit extends RefCounted:
	var rail: Rail
	var point_index: int

	func _init(p_rail: Rail, p_index: int) -> void:
		rail = p_rail
		point_index = p_index


const POINT_HIT_RADIUS := 12.0
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
var _layout_dirty := true
var _last_panel_size := Vector2(-1.0, -1.0)
var _last_judge_y := INF
var _last_current_time := INF

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

func refresh_views() -> void:
	_mark_preview_dirty()
	clear_layers()
	rail_views.clear()
	note_views.clear()
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
		rail_view.set_selection_state(editor.selection.selected_rail == rail_view.rail, editor.selection.selected_point_index)

	for note in note_views.keys():
		var note_view: EditorNote = note_views[note]
		note_view.sync_layout(panel_size, judge_y, editor.get_pixels_per_ms(), current_time)
		note_view.set_selected(editor.selection.selected_notes.has(note))

	editor._update_time_ui(false)

func set_note_passthrough(enabled: bool) -> void:
	for note_view in note_views.values():
		note_view.set_passthrough(enabled)
	for rail_view in rail_views.values():
		rail_view.set_point_handles_dimmed(not enabled)

func find_note_at(global_mouse_pos: Vector2) -> NoteHit:
	for note in note_views.keys():
		var note_view: EditorNote = note_views[note]
		if note_view.is_head_hit(global_mouse_pos):
			return NoteHit.new(note, note_view.rail)
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
		Notification.notice("rails can only merge when their time ranges do not overlap", Notification.Type.WARNING)
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
