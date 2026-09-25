extends Node3D

const GAMEPLAY_SCENE_PATH := "res://scenes/gameplay/gameplay.tscn"
const RESULT_SCENE_PATH := "res://scenes/mainmenu/result_scene.tscn"
const CHART_EDITOR_SCENE_PATH := "res://scenes/chart/editor/editor_scene.tscn"
const JUDGE_POPUP_SCENE := preload("res://scenes/gameplay/judge_popup.tscn")
const COMBOBRAKE_SOUND := preload("res://resources/audio/combobreak2.wav")
const RESULT_DELAY_AFTER_PLAY_END_MS := 2000.0
const LEAD_IN_MS := 3000.0
const COMBO_POP_SCALE := Vector2(0.96, 1.12)
const COMBO_POP_DURATION_IN := 0.08
const COMBO_POP_DURATION_OUT := 0.14
const JUDGE_POPUP_OFFSET := Vector3(0.0, 2.5, -0.1)

@export var editor_preview := false
@export var autoplay_enabled := false
@export var player: Player
@export var rail_container: Node3D
@export var songplayer: AudioStreamPlayer
@export var dim: ColorRect
@export var pause_menu: VBoxContainer
@export var gameplay_camera: Camera3D
@export var hud_root: Control
@export var combo_container: VBoxContainer
@export var combo_label: Label
@export var score_hud: GameplayScoreHUD
@export var world_environment: WorldEnvironment
@export var stage_visualizer: GameplayStageVisualizer

@onready var song_progress: ProgressBar = $Control/ProgressBar

var paused := false
var is_replay_mode := false

var _clock := GameClock.new()
var _input := GameInput.new()
var _replay_recorder := ReplayRecorder.new()
var _rule := GameRule.new()
var _spawner := ObjectSpawner.new()
var _audio := GameplayAudio.new()
var _visuals := GameplayVisuals.new()

var _replay_playback: Replay
var _play_time_ms := 0.0
var _hud_skipped_notes := 0
var _result_started := false
var _preview_time := -INF
var _combo_tween: Tween
var _pause_tween: Tween

func _enter_tree() -> void:
	if not editor_preview:
		DisplayServer.window_set_vsync_mode(Config.vsync_mode)
		return
	var environment_node := get_node("WorldEnvironment") as WorldEnvironment
	environment_node.environment = environment_node.environment.duplicate(true)
	var ground := get_node("PlayArea/Ground") as MeshInstance3D
	ground.mesh = ground.mesh.duplicate(true)

func _ready() -> void:
	_visuals.setup(player, gameplay_camera, hud_root, world_environment, stage_visualizer)
	_spawner.setup(CM.parsed_chart, rail_container)
	if editor_preview:
		set_process(false)
		_visuals.hide_gameplay_hud_for_preview()
		get_node("Label").hide()
		return

	_setup_hud()
	_audio.setup(self, songplayer, CM.parsed_chart, _clock)
	_rule.note_judged.connect(_on_note_judged)
	_rule.spike_dodged.connect(_on_spike_dodged)
	_rule.combo_changed.connect(_on_combo_changed)
	_rule.standing_rail_changed.connect(_spawner.set_standing_rail)
	_rule.failed.connect(_fail)
	reset()

func _exit_tree() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if not editor_preview:
		_input.stop()

func reset() -> void:
	set_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	paused = false
	_result_started = false
	song_progress.value = 0.0

	_replay_playback = Game.replay_playback
	Game.replay_playback = null
	autoplay_enabled = (autoplay_enabled or Game.autoplay_requested) and _replay_playback == null
	Game.autoplay_requested = false
	is_replay_mode = _replay_playback != null
	_update_replay_hud()

	var playback_start := maxf(0.0, Game.editor_playtest_start_time_ms) if Game.editor_playtest_active else 0.0
	_clock.setup(playback_start, LEAD_IN_MS)
	_input.setup(_clock, _replay_playback, autoplay_enabled)

	_spawner.build()
	_spawner.reset_runtime()
	_rule.setup(player, _spawner.rail_states, _spawner.note_states, _spawner.touch_states, _spawner.long_states)

	var start_time := _input.current_time()
	_rule.reset(start_time, autoplay_enabled, int(playback_start))
	if Game.editor_playtest_active and playback_start > 0.0:
		_rule.skip_before(int(playback_start))

	_replay_recorder.setup(
		CM.selected_chart,
		not Game.editor_playtest_active and not autoplay_enabled and _replay_playback == null
	)
	if _replay_playback != null:
		_rule.score.replay = _replay_playback
	elif _replay_recorder.enabled:
		_rule.score.replay = _replay_recorder.replay

	_play_time_ms = float(CM.parsed_chart.get_play_time_ms())
	_audio.reset(_play_time_ms)
	_audio.play_song()

	_hud_skipped_notes = _rule.processed_count()
	if score_hud != null:
		score_hud.reset(_rule.note_count() - _hud_skipped_notes)

	Game.current_time = start_time
	_rule.process(start_time, [], true)
	_spawner.spawn(start_time, _rule.standing_rail)
	_visuals.collect_events()
	_visuals.apply(Game.current_time)
	_spawner.set_rail_color(_visuals.rail_color)
	_reset_combo_hud()
	_update_score_hud()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel") and (_audio.is_song_playing or paused):
		pause()

	if paused:
		_input.discard()
		return

	_update_game(delta)

func _update_game(delta: float) -> void:
	var frame := _input.poll(_rule.last_simulated_time)
	if frame.failed:
		_fail(frame.error)
		return

	Game.current_time = frame.time
	_replay_recorder.record(frame.inputs)

	_spawner.spawn(frame.time, _rule.standing_rail)
	_rule.process(frame.simulation_target, frame.inputs, frame.exclusive)
	if _rule.failed_state:
		return

	_audio.update(int(Game.current_time), delta)
	_visuals.apply(Game.current_time)
	_spawner.set_rail_color(_visuals.rail_color)
	_update_score_hud()
	_check_result()

func pause() -> void:
	if _rule.failed_state:
		return
	if not paused:
		_update_game(0.0)
		if _rule.failed_state:
			return

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	paused = not paused
	if _pause_tween != null:
		_pause_tween.kill()

	if paused:
		_clock.pause(_input.reference_usec())
		pause_menu.visible = true
		_audio.pause()
		_pause_tween = create_tween().set_parallel()
		_pause_tween.tween_property(dim, "self_modulate", Color.WHITE, 0.5)
		_pause_tween.tween_property(pause_menu, "offset_transform_position", Vector2.ZERO, 0.25).set_trans(Tween.TRANS_SINE)
		return

	_input.discard()
	_clock.resume(_input.reference_usec())
	_audio.resume()
	_pause_tween = create_tween().set_parallel()
	_pause_tween.tween_property(dim, "self_modulate", Color(1.0, 1.0, 1.0, 0.0), 0.5)
	_pause_tween.tween_property(pause_menu, "offset_transform_position", Vector2(0, 1080), 0.25).set_trans(Tween.TRANS_SINE)
	_pause_tween.tween_property(pause_menu, "visible", false, 0.25)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func exit() -> void:
	if _result_started:
		return
	if Game.editor_playtest_active:
		_result_started = true
		_return_to_chart_editor()
		return
	if not Transition.try_return_to_menu(1.0):
		return
	_result_started = true
	set_process(false)
	_audio.stop()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func retry() -> void:
	if _result_started:
		return
	if not Transition.try_transition_to(GAMEPLAY_SCENE_PATH, 0.45):
		return
	_result_started = true
	set_process(false)
	_audio.stop()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _replay_playback != null:
		Game.replay_playback = _replay_playback
	Game.autoplay_requested = autoplay_enabled

func update_editor_preview(rebuild: bool, events_changed: bool) -> void:
	if not editor_preview or CM.parsed_chart == null:
		return
	var time := Game.current_time

	if rebuild:
		GameRail.clear_mesh_cache()
		GameplayLongNoteVisual.clear_mesh_cache()

	if rebuild or time < _preview_time or absf(time - _preview_time) > 1000.0:
		_spawner.build()
		_spawner.prepare_preview(time)

	if rebuild or events_changed:
		_visuals.collect_events()

	_preview_time = time
	var standing_rail := _spawner.active_rail_at(int(time))
	player.standing_rail = standing_rail
	if standing_rail != null:
		player.position.x = GameplayPlayfield.normalized_x_to_world(
			standing_rail._get_rail_x_at_time(int(time))
		)

	_visuals.apply(time)
	_spawner.set_rail_color(_visuals.rail_color)
	_spawner.spawn(int(time), standing_rail)
	_spawner.set_preview_visibility(time, standing_rail)
	_visuals.update_camera_position()

func _on_note_judged(
	state: GameplayNoteState,
	judgement: int,
	_gap: float,
	is_release: bool
) -> void:
	if is_release:
		_spawner.finish_long_note(state, judgement)
	else:
		_spawner.consume_note(state, judgement)

	if judgement != Score.NONE:
		_spawn_judge_popup(judgement)
		if judgement == Score.MISS:
			$Player/VFXAnimationPlayer.play("miss")
	if judgement == Score.MISS or judgement == Score.NONE:
		return

	player.spawn_hit_stars()
	if not is_release and state.note.type != Note.NoteType.MOVE:
		player.play_hit_animation(state.note)
	if is_release:
		_audio.play_long_release_sfx()
	else:
		_audio.play_note_sfx(state.note)

func _on_spike_dodged(state: GameplayNoteState) -> void:
	_spawner.consume_note(state, Score.NONE)

func _on_combo_changed(value: int, pop: bool) -> void:
	combo_label.text = str(value)
	combo_container.visible = true
	if pop:
		_play_combo_pop()

func _check_result() -> void:
	if _result_started or Game.current_time < _play_time_ms + RESULT_DELAY_AFTER_PLAY_END_MS:
		return
	if Game.editor_playtest_active:
		_result_started = true
		_return_to_chart_editor()
		return
	if not Transition.try_transition_to(RESULT_SCENE_PATH, 1.0):
		return
	_result_started = true
	if _replay_playback == null and not autoplay_enabled:
		Scores.record_play(CM.selected_chart, _rule.score)
	Game.last_result_score = _rule.score

func _return_to_chart_editor() -> void:
	set_process(false)
	_audio.stop()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Game.finish_editor_playtest()
	Transition.transition_to(CHART_EDITOR_SCENE_PATH, 0.45)

func _fail(message: String) -> void:
	push_error(message)
	set_process(false)
	_audio.freeze()

func _update_score_hud() -> void:
	song_progress.value = clampf(float(Game.current_time) / _play_time_ms, 0.0, 1.0) if _play_time_ms > 0.0 else 0.0
	if score_hud != null:
		score_hud.refresh(_rule.score, _rule.processed_count() - _hud_skipped_notes)

func _setup_hud() -> void:
	song_progress.min_value = 0.0
	song_progress.max_value = 1.0
	song_progress.step = 0.0
	combo_container.visible = true
	combo_container.modulate.a = 1.0
	combo_container.offset_transform_enabled = true
	combo_container.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	combo_container.offset_transform_scale = Vector2.ONE

func _reset_combo_hud() -> void:
	if _combo_tween != null:
		_combo_tween.kill()
	combo_container.visible = true
	combo_container.modulate.a = 1.0
	combo_container.offset_transform_scale = Vector2.ONE
	_on_combo_changed(_rule.combo, false)

func _play_combo_pop() -> void:
	if _combo_tween != null:
		_combo_tween.kill()
	combo_container.offset_transform_scale = Vector2.ONE
	_combo_tween = create_tween()
	_combo_tween.set_trans(Tween.TRANS_BACK)
	_combo_tween.set_ease(Tween.EASE_OUT)
	_combo_tween.tween_property(combo_container, "offset_transform_scale", COMBO_POP_SCALE, COMBO_POP_DURATION_IN)
	_combo_tween.tween_property(combo_container, "offset_transform_scale", Vector2.ONE, COMBO_POP_DURATION_OUT)

func _spawn_judge_popup(judgement: int) -> void:
	if judgement == Score.NONE or player == null:
		return
	var popup := JUDGE_POPUP_SCENE.instantiate()
	if popup == null:
		return
	popup.judgement = judgement
	add_child(popup)
	popup.global_position = player.global_position + JUDGE_POPUP_OFFSET

func _update_replay_hud() -> void:
	$Control/ReplayVignette.visible = is_replay_mode or autoplay_enabled
	$Control/ReplayLabel.visible = is_replay_mode or autoplay_enabled
	$Control/ReplayLabel.text = "WATCHING AUTOPLAY" if autoplay_enabled else "WATCHING REPLAY"
	$Control/PauseMenu/Retry.visible = not is_replay_mode

func _on_resume_activated() -> void:
	if paused:
		pause()

func _on_retry_activated() -> void:
	retry()

func _on_quit_activated() -> void:
	exit()
