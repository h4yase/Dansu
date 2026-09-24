extends Control
class_name EventEditor

const MAP_EDITOR_SCENE_PATH := "res://scenes/chart/editor/editor_scene.tscn"
const GAMEPLAY_ENTRY_LEAD_IN_MS := 3000
const EVENT_EDITOR_PRE_ENTRY_PADDING_MS := 100
const EVENT_EDITOR_POST_SONG_PADDING_MS := 3000

@export var chart_root: Control
@export var event_controller: EditorEventController
@export var back_button: Button
@export var save_button: Button
@export var play_button: Button
@export var time_label: Label
@export var status_label: Label
@export var preview: Control
@export var exit_dialog: EditorUnsavedChangesDialog

var chart: Chart = null
var timeline: EditorTimeline = null
var selection := ChartEditorSelection.new()
var transport := EditorTransport.new()

var _history := EditorHistoryStack.new()
var _restoring := false
var _saved_snapshot: EventEditorSnapshot

func _ready() -> void:
	chart = CM.selected_chart
	if chart == null:
		Transition.return_to_menu(0.2)
		return
	_ensure_parsed_chart()
	_setup_transport()
	_connect_ui()
	if event_controller != null:
		event_controller.setup()
	_connect_exit_dialog()
	mark_saved_state()
	_update_toolbar()
	UIFocusUtils.disable_focus_recursive(self)

func _process(_delta: float) -> void:
	transport.update()
	_update_toolbar()
	if preview != null:
		preview.queue_redraw()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.ctrl_pressed and event.keycode == KEY_Z:
		_undo_history()
		return
	if event.ctrl_pressed and event.keycode == KEY_Y:
		_redo_history()
		return
	if event.ctrl_pressed and event.keycode == KEY_C:
		if event_controller != null:
			event_controller.copy_selected_frames()
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and event.keycode == KEY_V:
		if event_controller != null:
			event_controller.paste_copied_frames()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_SPACE: transport.toggle()
		KEY_DELETE:
			if event_controller != null:
				event_controller.delete_selection()
		KEY_ESCAPE: _return_to_chart()

func _ensure_parsed_chart() -> void:
	if CM.parsed_chart != null and CM.parsed_chart.chart == chart:
		return
	var result := Parser.new().parse_object(chart)
	CM.parsed_chart = result.parsed_chart if result.success else ParsedChart.new(chart)

func _setup_transport() -> void:
	transport = EditorTransport.new()
	transport.name = "EventEditorTransport"
	add_child(transport)
	transport.setup()
	transport.chart = chart
	transport.load_stream()
	timeline = EditorTimeline.new(
		chart,
		transport.stream_length_sec,
		-(GAMEPLAY_ENTRY_LEAD_IN_MS + EVENT_EDITOR_PRE_ENTRY_PADDING_MS),
		EVENT_EDITOR_POST_SONG_PADDING_MS
	)
	timeline.ensure_timings()
	transport.timeline = timeline

func _connect_ui() -> void:
	if back_button != null:
		back_button.pressed.connect(_return_to_chart)
	if save_button != null:
		save_button.pressed.connect(_save_chart)
	if play_button != null:
		play_button.pressed.connect(transport.toggle)

func _set_current_time(value: float) -> void:
	if timeline == null:
		return
	Game.current_time = timeline.clamp_time(value)
	if transport.playing:
		transport.seek()
	_update_toolbar()

func _push_history_snapshot() -> void:
	if _restoring or CM.parsed_chart == null:
		return
	_history.push(_capture_snapshot())

func _capture_snapshot() -> EventEditorSnapshot:
	var event_index := -1
	if selection.selected_event != null:
		event_index = CM.parsed_chart.events.find(selection.selected_event)
	var snapshot := EventEditorSnapshot.new()
	snapshot.events = EditorHistory.capture_events_data(CM.parsed_chart.events)
	snapshot.event_index = event_index
	snapshot.frame_index = selection.selected_event_frame_index
	snapshot.current_time = Game.current_time
	return snapshot

func _undo_history() -> void:
	var snapshot := _history.undo(_capture_snapshot()) as EventEditorSnapshot
	if snapshot != null:
		_restore_snapshot(snapshot)

func _redo_history() -> void:
	var snapshot := _history.redo(_capture_snapshot()) as EventEditorSnapshot
	if snapshot != null:
		_restore_snapshot(snapshot)

func _restore_snapshot(snapshot: EventEditorSnapshot) -> void:
	if transport.playing:
		transport.pause()
	_restoring = true
	CM.parsed_chart.events = EditorHistory.restore_events_data(snapshot.events)
	CM.parsed_chart.sort_events()
	var event_index := int(snapshot.event_index)
	if event_index >= 0 and event_index < CM.parsed_chart.events.size():
		selection.select_event(CM.parsed_chart.events[event_index], int(snapshot.frame_index))
	else:
		selection.clear()
	Game.current_time = timeline.clamp_time(float(snapshot.current_time))
	_restoring = false
	if event_controller != null:
		event_controller.on_history_restored()

func _save_chart() -> bool:
	if CM.parsed_chart == null:
		return false
	CM.parsed_chart.chart = chart
	var success := EditorChartOps.save_chart(chart, chart.file_path)
	if status_label != null:
		status_label.text = "Chart saved" if success else "Save failed"
		status_label.add_theme_color_override("font_color", Color("75d5a4") if success else Color("ff7c86"))
	if success:
		mark_saved_state()
	return success

func _return_to_chart() -> void:
	if _has_unsaved_changes():
		if exit_dialog != null:
			exit_dialog.open()
		else:
			_return_to_chart_now()
		return
	_return_to_chart_now()

func _return_to_chart_now() -> void:
	if transport.playing:
		transport.pause()
	Game.reopen_editor_without_chart_reload = true
	Transition.transition_to(MAP_EDITOR_SCENE_PATH, 0.45)

func mark_saved_state() -> void:
	_saved_snapshot = _capture_saved_state()

func _has_unsaved_changes() -> bool:
	return _saved_snapshot != null and not EditorHistory.same_snapshot(_saved_snapshot, _capture_saved_state())

func _capture_saved_state() -> EventEditorSnapshot:
	var snapshot := _capture_snapshot()
	snapshot.clear_editor_state()
	return snapshot

func _connect_exit_dialog() -> void:
	if exit_dialog == null:
		return
	exit_dialog.save_requested.connect(_on_exit_save_requested)
	exit_dialog.discard_requested.connect(_return_to_chart_now)

func _on_exit_save_requested() -> void:
	if _save_chart():
		_return_to_chart_now()

func _update_toolbar() -> void:
	if play_button != null:
		play_button.text = "Pause" if transport.playing else "Play"
	if time_label != null and timeline != null:
		time_label.text = timeline.format_time_label(Game.current_time)
