extends Control
class_name ChartEditor

signal selection_changed()
signal hitsounds_changed()

const EVENT_EDITOR_SCENE_PATH := "res://scenes/chart/events/editor/event_editor_scene.tscn"
const GAMEPLAY_SCENE_PATH := "res://scenes/gameplay/gameplay.tscn"
const DEFAULT_PIXELS_PER_MS := 1.0
const MIN_PIXELS_PER_MS := 0.2
const MAX_PIXELS_PER_MS := 4.0
const TRANSPORT_UI_UPDATE_USEC := 33333
const EventWorkspace := preload("res://chart/editor/event_workspace.gd")
var event_controller: Node

@export var chart_root: Control
@export var chart_panel: Control
@export var note_pivot: Control
@export var bpm_lines: Control
@export var song_slider: HSlider
@export var current_time_label: Label
@export var back_button: Button
@export var playtest_button: Button
@export var save_button: Button
@export var delete_button: Button
@export var hit_button: Button
@export var trace_button: Button
@export var left_button: Button
@export var right_button: Button
@export var spike_button: Button
@export var title_line_edit: LineEdit
@export var artist_line_edit: LineEdit
@export var creator_line_edit: LineEdit
@export var difficulty_line_edit: LineEdit
@export var source_line_edit: LineEdit
@export var tags_line_edit: LineEdit
@export var beat_division_slider: HSlider
@export var beat_division_label: Label
@export var add_timing_button: Button
@export var timing_list_container: VBoxContainer
@export var timing_template: Node
@export var skin_file_label: Label
@export var skin_browser_button: Button
@export var open_skin_editor_button: Button
@export var open_event_editor_button: Button
@export var view_controller: EditorViewController
@export var inspector_controller: EditorInspectorController
@export var edit_controller: EditorEditController
@export var unsaved_exit_dialog: EditorUnsavedChangesDialog
@export var fps_label: Label

var timeline: EditorTimeline = null
var selection: ChartEditorSelection = ChartEditorSelection.new()
var chart: Chart = null
var previous_file_path := ""

var transport: EditorTransport = EditorTransport.new()
var hitsound_manager: EditorHitsoundManager = EditorHitsoundManager.new()

var point_dragging := false
var note_passthrough := false
var editor_pixels_per_ms := DEFAULT_PIXELS_PER_MS
var _syncing_song_slider := false
var _last_transport_ui_usec := 0

var _history := EditorHistoryStack.new()
var _is_restoring_history := false
var _point_drag_history_pending := false
var _saved_snapshot: EditorSnapshot
var _pending_exit_target := ""

func _ready() -> void:
	if not Game.reopen_editor_without_chart_reload:
		Game.current_time = 0.0
	chart = _ensure_chart()
	previous_file_path = chart.file_path
	selection.changed.connect(_on_selection_changed)

	transport.name = "EditorTransport"
	add_child(transport)
	transport.setup()

	hitsound_manager = EditorHitsoundManager.new()
	hitsound_manager.changed.connect(_on_hitsounds_changed)

	_connect_dialogs()
	_prepare_layers()
	_configure_chart_input()
	_load_chart_data()
	_connect_ui()
	event_controller = EventWorkspace.new()
	event_controller.editor = self
	add_child(event_controller)
	event_controller.setup()
	refresh_inspector()
	_update_slider_range()
	refresh_views()
	_update_save_button_state()
	_restore_or_mark_saved_state()
	UIFocusUtils.disable_focus_recursive(self)

func _process(_delta: float) -> void:
	fps_label.text = str(Engine.get_frames_per_second())
	transport.update()
	_update_time_ui(false)

	if point_dragging and selection.has_point() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drag_selected_point(get_global_mouse_position())
	elif point_dragging:
		point_dragging = false

	_sync_view_layouts()

func _input(event: InputEvent) -> void:
	if event_controller != null and event_controller.canvas != null and event_controller.canvas.gesture_active:
		if event is InputEventMouseMotion or event is InputEventMouseButton:
			event_controller.canvas.handle_mouse(event)
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			event_controller.canvas.cancel_drag()
		get_viewport().set_input_as_handled()
		return
	if edit_controller != null and edit_controller.gesture.active:
		if event is InputEventMouseMotion:
			edit_controller.gesture.motion(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			edit_controller.gesture.finish(event.position)
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			edit_controller.gesture.finish(get_global_mouse_position(), true)
		get_viewport().set_input_as_handled()
		return
	if event_controller != null and not _is_text_input_focused():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
			event_controller.toggle()
			get_viewport().set_input_as_handled()
			return
		if event_controller.active and (event is InputEventMouseButton or event is InputEventMouseMotion):
			event_controller.canvas.handle_mouse(event)
			return
		if event_controller.active and event is InputEventKey and event.pressed and not event.echo and event.keycode != KEY_ESCAPE:
			event_controller.handle_key(event)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if unsaved_exit_dialog != null and unsaved_exit_dialog.visible:
			return
		exit()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if point_dragging and view_controller != null:
			view_controller.finalize_selected_point_drag(get_global_mouse_position())
		point_dragging = false
		_point_drag_history_pending = false

	if event is InputEventMouseButton:
		if event.pressed \
				and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT) \
				and _is_text_input_focused() \
				and chart_panel.get_global_rect().has_point(event.position):
			UIFocusUtils.release_text_input_focus(get_viewport())
		if not _is_text_input_focused():
			if event_controller != null and event_controller.active:
				event_controller.canvas.handle_mouse(event)
			else:
				_handle_mouse_button(event)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if not _is_text_input_focused():
			_handle_key_input(event)

func refresh_views() -> void:
	if event_controller != null and event_controller.game_view != null:
		event_controller.game_view.chart_dirty = true
	if view_controller != null:
		view_controller.refresh_views()
	if bpm_lines != null:
		bpm_lines.queue_redraw()

func refresh_inspector() -> void:
	if inspector_controller == null:
		return
	inspector_controller.refresh_metadata_fields()
	inspector_controller.rebuild_timing_ui()
	inspector_controller.update_beat_division_ui()

# Init helpers

func _ensure_chart() -> Chart:
	if CM.selected_chart != null:
		return CM.selected_chart
	var fallback := Chart.new()
	fallback.build_uuid()
	fallback.storage_root = FileSystem.editor_chart_path
	fallback.title = ""
	fallback.artist = ""
	fallback.difficulty = ""
	fallback.chart_set = CM.selected_chartset
	if fallback.chart_set != null:
		fallback.folder_name = fallback.chart_set.folder_name
	return fallback

func _prepare_layers() -> void:
	if view_controller != null:
		view_controller.prepare_layers()

func _configure_chart_input() -> void:
	if view_controller != null:
		view_controller.configure_chart_input()

func _load_chart_data() -> void:
	if chart == null:
		return
	chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)
	var skip_reload := Game.reopen_editor_without_chart_reload
	Game.reopen_editor_without_chart_reload = false
	if CM.selected_chart != null and not skip_reload:
		EditorChartOps.load_selected_chart()

	transport.chart = chart
	transport.load_stream()
	timeline = EditorTimeline.new(chart, transport.stream_length_sec)
	transport.timeline = timeline
	transport.hitsound_manager = hitsound_manager
	hitsound_manager.setup(chart, selection)

	timeline.ensure_timings()

func _connect_ui() -> void:
	if song_slider != null:
		song_slider.value_changed.connect(_on_song_slider_value_changed)
	if back_button != null:
		back_button.pressed.connect(exit)
	if playtest_button != null:
		playtest_button.pressed.connect(_start_playtest)
	if save_button != null:
		save_button.pressed.connect(_save_chart)
	if edit_controller != null:
		if delete_button != null:
			delete_button.pressed.connect(edit_controller.delete_selected)
		if hit_button != null:
			hit_button.pressed.connect(edit_controller.create_hit_note)
		if trace_button != null:
			trace_button.pressed.connect(edit_controller.create_trace_note)
		if left_button != null:
			left_button.pressed.connect(edit_controller.create_left_note)
		if right_button != null:
			right_button.pressed.connect(edit_controller.create_right_note)
		if spike_button != null:
			spike_button.pressed.connect(edit_controller.create_spike_note)
	if inspector_controller != null:
		if title_line_edit != null:
			title_line_edit.text_changed.connect(inspector_controller.on_title_changed)
		if artist_line_edit != null:
			artist_line_edit.text_changed.connect(inspector_controller.on_artist_changed)
		if creator_line_edit != null:
			creator_line_edit.text_changed.connect(inspector_controller.on_creator_changed)
		if difficulty_line_edit != null:
			difficulty_line_edit.text_changed.connect(inspector_controller.on_difficulty_changed)
		if source_line_edit != null:
			source_line_edit.text_changed.connect(inspector_controller.on_source_changed)
		if tags_line_edit != null:
			tags_line_edit.text_changed.connect(inspector_controller.on_tags_changed)
		if beat_division_slider != null:
			beat_division_slider.value_changed.connect(inspector_controller.on_beat_division_slider_changed)
		if add_timing_button != null:
			add_timing_button.pressed.connect(inspector_controller.add_timing)
		if skin_browser_button != null:
			skin_browser_button.pressed.connect(inspector_controller.open_skin_browser)
	if open_skin_editor_button != null:
		open_skin_editor_button.pressed.connect(_open_skin_editor)
	if open_event_editor_button != null:
		open_event_editor_button.pressed.connect(_open_event_editor)

func _connect_dialogs() -> void:
	if inspector_controller != null:
		inspector_controller.connect_dialogs()
	if unsaved_exit_dialog != null:
		unsaved_exit_dialog.save_requested.connect(_on_unsaved_exit_save_requested)
		unsaved_exit_dialog.discard_requested.connect(_on_unsaved_exit_discard_requested)

# — View —

func _sync_view_layouts() -> void:
	if view_controller != null:
		view_controller.sync_layouts()

# Input

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if edit_controller != null:
		edit_controller.handle_mouse_button(event)


func exit() -> void:
	_request_exit("menu")

func _handle_key_input(event: InputEventKey) -> void:
	if edit_controller != null:
		edit_controller.handle_key_input(event)

# Chart editing

func _set_current_time(value: float) -> void:
	if edit_controller != null:
		edit_controller.set_current_time(value)

# Hit testing 

func _find_note_at(global_mouse_pos: Vector2) -> EditorViewController.NoteHit:
	return view_controller.find_note_at(global_mouse_pos) if view_controller != null else null

func _find_rail_at(global_mouse_pos: Vector2) -> Rail:
	return view_controller.find_rail_at(global_mouse_pos) if view_controller != null else null

func _find_point_at(global_mouse_pos: Vector2) -> EditorViewController.PointHit:
	return view_controller.find_point_at(global_mouse_pos) if view_controller != null else null

func _drag_selected_point(global_mouse_pos: Vector2) -> void:
	if view_controller != null:
		view_controller.drag_selected_point(global_mouse_pos)

# Save

func _save_chart() -> bool:
	if chart == null or not EditorChartOps.can_save(chart):
		return false
	if not EditorChartOps.save_chart(chart, previous_file_path):
		return false
	previous_file_path = chart.file_path
	_update_save_button_state()
	mark_saved_state()
	return true

func _open_skin_editor() -> void:
	if chart == null:
		return
	if _has_unsaved_changes():
		_request_exit("skin")
		return
	_open_skin_editor_now()

func _open_skin_editor_now() -> void:
	CM.selected_chart = chart
	SkinEditorRouter.open_chart_skin_editor(chart)

func open_new_chart_skin_editor() -> void:
	if chart == null:
		return
	if _has_unsaved_changes():
		_request_exit("new_skin")
		return
	_open_new_chart_skin_editor_now()

func _open_new_chart_skin_editor_now() -> void:
	CM.selected_chart = chart
	SkinEditorRouter.open_new_chart_skin_editor(chart)

func _open_event_editor() -> void:
	if event_controller != null:
		event_controller.toggle()


func _start_playtest() -> void:
	if chart == null or CM.parsed_chart == null:
		Notification.notice("no chart available for playtest", Notification.Type.WARNING)
		return
	if chart.get_stream() == null:
		Notification.notice("audio file is required for playtest", Notification.Type.WARNING)
		return

	if transport.playing:
		transport.pause()
	CM.selected_chart = chart
	CM.parsed_chart.chart = chart
	EditorChartOps.sort_chart_objects()
	Game.begin_editor_playtest(Game.current_time, _saved_snapshot)
	Transition.transition_to(GAMEPLAY_SCENE_PATH, 0.45)

# UI state

func _update_slider_range() -> void:
	if song_slider == null:
		return
	song_slider.min_value = timeline.get_min_time()
	song_slider.max_value = timeline.get_max_time()
	song_slider.step = 1.0
	_update_time_ui(true)

func _update_save_button_state() -> void:
	if save_button != null:
		save_button.disabled = not EditorChartOps.can_save(chart)

func _update_time_ui(force: bool) -> void:
	var now_usec := Time.get_ticks_usec()
	if not force and now_usec - _last_transport_ui_usec < TRANSPORT_UI_UPDATE_USEC:
		return
	_last_transport_ui_usec = now_usec
	_set_song_slider_value(Game.current_time)
	if current_time_label != null:
		var label_text := timeline.format_time_label(Game.current_time)
		if current_time_label.text != label_text:
			current_time_label.text = label_text

func _set_song_slider_value(value: float) -> void:
	if song_slider == null or is_equal_approx(song_slider.value, value):
		return
	_syncing_song_slider = true
	song_slider.value = value
	_syncing_song_slider = false

# UI event handlers

func _on_selection_changed() -> void:
	selection_changed.emit()
	if view_controller != null:
		view_controller.mark_layout_dirty()
	_sync_view_layouts()

func _on_hitsounds_changed() -> void:
	hitsounds_changed.emit()
	selection_changed.emit()

func _on_song_slider_value_changed(value: float) -> void:
	if not _syncing_song_slider:
		_set_current_time(value)

# History

func push_history_snapshot() -> void:
	_push_history_snapshot()

func _push_history_snapshot() -> void:
	if _is_restoring_history:
		return
	_history.push(EditorHistory.capture(self))

func _undo_history() -> void:
	var snapshot := _history.undo(EditorHistory.capture(self)) as EditorSnapshot
	if snapshot != null:
		_restore_history_snapshot(snapshot)

func _redo_history() -> void:
	var snapshot := _history.redo(EditorHistory.capture(self)) as EditorSnapshot
	if snapshot != null:
		_restore_history_snapshot(snapshot)

func _restore_history_snapshot(snapshot: EditorSnapshot) -> void:
	if transport.playing:
		transport.pause()
	_is_restoring_history = true
	EditorHistory.restore(self, snapshot)
	if event_controller != null:
		event_controller.on_history_restored()
	_is_restoring_history = false

# Unsaved changes

func mark_saved_state() -> void:
	_saved_snapshot = _capture_saved_state()


func _restore_or_mark_saved_state() -> void:
	var playtest_saved_snapshot := Game.take_editor_playtest_saved_snapshot()
	if playtest_saved_snapshot == null:
		mark_saved_state()
	else:
		_saved_snapshot = playtest_saved_snapshot

func _has_unsaved_changes() -> bool:
	if _saved_snapshot == null:
		return false
	return not EditorHistory.same_snapshot(_saved_snapshot, _capture_saved_state())

func _capture_saved_state() -> EditorSnapshot:
	var snapshot := EditorHistory.capture(self)
	snapshot.clear_editor_state()
	return snapshot

func _request_exit(target: String) -> void:
	if _has_unsaved_changes():
		_show_unsaved_exit_dialog(target)
		return
	_transition_to_pending_target(target)

func _show_unsaved_exit_dialog(target: String) -> void:
	_pending_exit_target = target
	if unsaved_exit_dialog == null:
		_transition_to_pending_target(target)
		return
	unsaved_exit_dialog.open(EditorChartOps.can_save(chart))

func _on_unsaved_exit_save_requested() -> void:
	if _save_chart():
		_transition_to_pending_target(_pending_exit_target)

func _on_unsaved_exit_discard_requested() -> void:
	_transition_to_pending_target(_pending_exit_target)

func _transition_to_pending_target(target: String) -> void:
	match target:
		"new_skin":
			_open_new_chart_skin_editor_now()
		"skin":
			_open_skin_editor_now()
		_:
			if chart != null:
				CM.select_chartset(chart.chart_set)
				CM.select_chart(chart)
			Transition.return_to_menu(1)

# Hitsound public API

func get_all_hitsounds() -> Array[HitSound]:
	return hitsound_manager.get_all_hitsounds()

func get_custom_hitsounds() -> Array[HitSound]:
	return hitsound_manager.get_custom_hitsounds()

func get_default_hitsound_id(slot: int) -> int:
	return hitsound_manager.get_default_hitsound_id(slot)

func set_default_hitsound_id(slot: int, hitsound_id: int) -> void:
	if hitsound_manager.get_default_hitsound_id(slot) == hitsound_id:
		return
	_push_history_snapshot()
	hitsound_manager.set_default_hitsound_id(slot, hitsound_id)

func set_selected_note_hitsound_id(hitsound_id: int) -> void:
	if selection.selected_note == null or int(selection.selected_note.hitsound) == hitsound_id:
		return
	_push_history_snapshot()
	hitsound_manager.set_selected_note_hitsound_id(hitsound_id)

func add_custom_hitsound_from_file(source_path: String) -> void:
	_push_history_snapshot()
	hitsound_manager.add_custom_hitsound_from_file(source_path)

func remove_custom_hitsound(hitsound_id: int) -> void:
	_push_history_snapshot()
	hitsound_manager.remove_custom_hitsound(hitsound_id)

# Utilities

func get_pixels_per_ms() -> float:
	return editor_pixels_per_ms

func get_judge_y() -> float:
	return note_pivot.position.y - chart_panel.position.y

func _get_supported_beat_divisions() -> Array[int]:
	return [1, 2, 3, 4, 6, 8, 12, 16]

func _is_mouse_inside_chart() -> bool:
	return chart_panel != null and chart_panel.get_global_rect().has_point(get_global_mouse_position())

func _is_text_input_focused() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit

func _local_y_to_time(local_y: float) -> int:
	var judge_y := note_pivot.position.y - chart_panel.position.y
	return int(round(Game.current_time - ((local_y - judge_y) / editor_pixels_per_ms)))

func _snap_point_x(value: float) -> float:
	return clamp(snapped(value, 0.1), 0.0, 1.0)

func set_note_passthrough_enabled(enabled: bool) -> void:
	if note_passthrough == enabled:
		return
	note_passthrough = enabled
	if view_controller != null:
		view_controller.set_note_passthrough(note_passthrough)

func toggle_note_passthrough() -> void:
	var rail_edit_mode := not note_passthrough
	set_note_passthrough_enabled(rail_edit_mode)
	if rail_edit_mode and selection.selected_note != null:
		selection.select_rail(selection.selected_rail)
	elif not rail_edit_mode and selection.has_point():
		selection.select_rail(selection.selected_rail)

func adjust_editor_zoom(is_positive: bool) -> void:
	var zoom_factor := 1.15 if is_positive else (1.0 / 1.15)
	var next_scale := clampf(editor_pixels_per_ms * zoom_factor, MIN_PIXELS_PER_MS, MAX_PIXELS_PER_MS)
	if is_equal_approx(editor_pixels_per_ms, next_scale):
		return
	editor_pixels_per_ms = next_scale
	if view_controller != null:
		view_controller.mark_layout_dirty()
		view_controller.sync_layouts()
	if bpm_lines != null:
		bpm_lines.queue_redraw()
