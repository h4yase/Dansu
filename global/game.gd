extends Node

enum GameStage { Loading, Main, Play, Edit, Browse }
enum MainMenuState { Home, SongSelect }

var stage = GameStage.Loading
var main_menu_state := MainMenuState.Home
var current_time := 0.0
var last_result_score: Score = null
var replay_playback: Replay = null
var autoplay_requested := false
var skin_editor_request = null
var reopen_editor_without_chart_reload := false
var editor_playtest_active := false
var editor_playtest_start_time_ms := 0.0
var editor_playtest_saved_snapshot: EditorSnapshot

func _init() -> void:
	Input.set_custom_mouse_cursor(
	preload("res://resources/textures/cursor/cursor_circle.svg"),
	Input.CURSOR_ARROW,
	Vector2(12, 12)
	)
	Input.set_custom_mouse_cursor(
		preload("res://resources/textures/cursor/cursor_circle_hover.svg"),
		Input.CURSOR_POINTING_HAND,
		Vector2(12, 12)
	)
	Input.set_custom_mouse_cursor(
		preload("res://resources/textures/cursor/cursor_circle_input.svg"),
		Input.CURSOR_IBEAM,
		Vector2(12, 12)
	)

func play_selected_chart(autoplay: bool = false) -> void:
	cancel_editor_playtest()
	replay_playback = null
	autoplay_requested = autoplay
	if CM.parse_selected_chart():
		if not autoplay:
			Scores.record_play_start(CM.selected_chart)
		Transition.transition_to("res://scenes/gameplay/gameplay.tscn",1.0)
	else:
		autoplay_requested = false


func play_replay(replay: Replay) -> bool:
	cancel_editor_playtest()
	if replay == null or replay.chart == null:
		return false
	CM.selected_chart = replay.chart
	if not CM.parse_selected_chart():
		return false
	if replay.chart_uuid.to_lower() != CM.selected_chart.uuid.to_lower() \
			or replay.hash.to_lower() != CM.selected_chart.filehash.to_lower():
		return false
	replay_playback = replay
	autoplay_requested = false
	Transition.transition_to("res://scenes/gameplay/gameplay.tscn", 1.0)
	return true


func begin_editor_playtest(start_time_ms: float, saved_snapshot: EditorSnapshot) -> void:
	editor_playtest_active = true
	editor_playtest_start_time_ms = start_time_ms
	# Captured snapshots are immutable after publication to history or saved state.
	editor_playtest_saved_snapshot = saved_snapshot


func finish_editor_playtest() -> void:
	current_time = editor_playtest_start_time_ms
	editor_playtest_active = false
	reopen_editor_without_chart_reload = true


func cancel_editor_playtest() -> void:
	editor_playtest_active = false
	editor_playtest_start_time_ms = 0.0
	editor_playtest_saved_snapshot = null


func take_editor_playtest_saved_snapshot() -> EditorSnapshot:
	var snapshot := editor_playtest_saved_snapshot
	editor_playtest_saved_snapshot = null
	return snapshot
