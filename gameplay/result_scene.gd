extends Control

const RESULT_TICK_STREAM := preload("res://resources/audio/buttons/switch8.ogg")
const RESULT_START_DELAY := 1.0
const FULL_RANK_SEGMENT_DURATION := 0.28
const FINAL_SEGMENT_DURATION := 0.95
const FINAL_SEGMENT_DURATION_MAX := 1.35
const TICK_PLAYER_COUNT := 4
const MAX_SCORE_DISPLAY := 101.0
var score = Score.new()

@export var make_fake_score : bool = false
@export var fake_score : float = 90.05

@export var rank : Label
@export var next_rank_score : Label
@export var current_rank_score : Label
@export var score_label : Label
@export var progress_bar: ProgressBar
@export var player_sprite: ResultPlayerSprite
@export var back_button: MenuBigButton
@export var rank_up_particles: CPUParticles2D
@export var just_plus_count_label: Label
@export var just_count_label: Label
@export var good_count_label: Label
@export var okay_count_label: Label
@export var nah_count_label: Label
@export var miss_count_label: Label
@export var combo_value_label: Label
@export var avg_value_label: Label
@export var difficulty_label: Label
@export var title_value_label: Label
@export var artist_value_label: Label
@export var cover_image_rect: TextureRect
@export var account_panel: AccountPanel
@export var sr_gain_label: Label

var _default_cover_texture: Texture2D

var _tick_players: Array[AudioStreamPlayer] = []
var _next_tick_player_index := 0
var _tick_cooldown := 0.0
var _target_score := 0.0
var _current_rank_index := 0
var _player_sprite_base_position := Vector2.ZERO
var _player_sprite_base_scale := Vector2.ONE
var _player_sprite_tween: Tween
var _sr_gain_tween: Tween
var _sr_gain_shown := false

func build_fake_score() -> void:
	score = Score.new()
	score.notes = 1
	score.max_score = 100.0
	score.score = clampf(fake_score, 0.0, MAX_SCORE_DISPLAY)
	score.high_combo = 1
	score.perfect_plus = 1

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_create_tick_players()
	_resolve_score()
	_setup_score_submission_ui()
	_setup_player_sprite()
	_setup_cover_loader()
	_populate_chart_metadata()
	_populate_result_details()

	await get_tree().process_frame
	_cache_animation_bases()
	_apply_rank_state(0)
	_update_live_score(0.0, 0)

	if back_button != null and back_button.button != null and not back_button.button.pressed.is_connected(_on_back_pressed):
		back_button.button.pressed.connect(_on_back_pressed)

	await get_tree().create_timer(RESULT_START_DELAY).timeout
	await _run_result_sequence()

func _setup_score_submission_ui() -> void:
	account_panel.visible = Auth.is_authenticated()
	Auth.state_changed.connect(_refresh_account_panel_visibility)
	Scores.submission_completed.connect(_on_score_submission_completed)
	sr_gain_label.hide()
	if not score.submission_response.is_empty():
		call_deferred("_show_sr_gain", score.submission_response)


func _refresh_account_panel_visibility() -> void:
	account_panel.visible = Auth.is_authenticated()


func _on_score_submission_completed(completed_score: Score, response: Dictionary) -> void:
	if completed_score != score or response.is_empty():
		return
	_show_sr_gain(response)


func _show_sr_gain(response: Dictionary) -> void:
	if _sr_gain_shown or not response.get("score") is Dictionary:
		return
	_sr_gain_shown = true
	var score_response: Dictionary = response.score
	var gained_sr := float(score_response.get("sr_awarded", 0.0))
	var sign_text := "+ " if gained_sr >= 0.0 else "- "
	sr_gain_label.text = sign_text + "%.2f SR" % absf(gained_sr)
	sr_gain_label.show()
	sr_gain_label.modulate.a = 1.0
	sr_gain_label.offset_transform_enabled = true
	sr_gain_label.offset_transform_position = Vector2.ZERO
	if _sr_gain_tween != null:
		_sr_gain_tween.kill()
	_sr_gain_tween = create_tween().set_parallel(true)
	_sr_gain_tween.tween_property(sr_gain_label, "offset_transform_position:y", 64.0, 2.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_sr_gain_tween.tween_property(sr_gain_label, "modulate:a", 0.0, 2.4).set_delay(0.35).set_trans(Tween.TRANS_SINE)
	_sr_gain_tween.chain().tween_callback(sr_gain_label.hide)

func _resolve_score() -> void:
	if make_fake_score:
		build_fake_score()
		return

	if Game.last_result_score != null:
		score = Game.last_result_score
		return

	build_fake_score()

func _populate_result_details() -> void:
	just_plus_count_label.text = str(score.perfect_plus)
	just_count_label.text = str(score.perfect)
	good_count_label.text = str(score.great)
	okay_count_label.text = str(score.ok)
	nah_count_label.text = str(score.bad)
	miss_count_label.text = str(score.miss)
	combo_value_label.text = "%d/%d" % [score.high_combo, max(score.notes, 1)]
	avg_value_label.text = str(score.avg_signed_timings)

func _populate_chart_metadata() -> void:
	var chart := CM.selected_chart
	if chart == null:
		difficulty_label.text = "-"
		title_value_label.text = "Unknown Title"
		artist_value_label.text = "Unknown Artist"
		if cover_image_rect != null:
			cover_image_rect.texture = _default_cover_texture
		return

	title_value_label.text = _coalesce_chart_text(chart.title, "Unknown Title")
	artist_value_label.text = _coalesce_chart_text(chart.artist, "Unknown Artist")
	difficulty_label.text = _build_difficulty_text(chart)
	_update_cover_image(chart)

func _build_difficulty_text(chart: Chart) -> String:
	if chart == null:
		return "-"

	var difficulty := _coalesce_chart_text(chart.difficulty, "Unknown Difficulty")
	if chart.rating > 0.0:
		return "%s (%.1f)" % [difficulty, chart.rating]
	return difficulty

func _coalesce_chart_text(value: String, fallback: String) -> String:
	var normalized := value.strip_edges()
	if normalized.is_empty() or normalized == "?":
		return fallback
	return normalized

func _setup_cover_loader() -> void:
	if cover_image_rect != null:
		_default_cover_texture = cover_image_rect.texture
	if CoverLoader != null:
		if not CoverLoader.cover_loaded.is_connected(_on_cover_loaded):
			CoverLoader.cover_loaded.connect(_on_cover_loaded)
		if not CoverLoader.cover_failed.is_connected(_on_cover_failed):
			CoverLoader.cover_failed.connect(_on_cover_failed)

func _update_cover_image(chart: Chart) -> void:
	if cover_image_rect == null:
		return
	if chart == null:
		cover_image_rect.texture = _default_cover_texture
		return
	if chart.cover_image != null:
		cover_image_rect.texture = chart.cover_image
		return
	cover_image_rect.texture = _default_cover_texture
	if not chart.file_cover_art.is_empty():
		CoverLoader.request_cover(chart)

func _on_cover_loaded(chart: Chart, texture: Texture2D) -> void:
	if chart == null or texture == null or chart != CM.selected_chart:
		return
	if cover_image_rect != null:
		cover_image_rect.texture = texture

func _on_cover_failed(chart: Chart) -> void:
	if chart == null or chart != CM.selected_chart:
		return
	if cover_image_rect != null:
		cover_image_rect.texture = _default_cover_texture

func _setup_player_sprite() -> void:
	var skin := PlayerSkinResolver.load_active()
	if skin == null:
		return

	player_sprite.skin = skin
	player_sprite.play_animation(skin.idle)
	if skin.idle != null and not skin.idle.frames.is_empty():
		player_sprite.texture = skin.idle.frames[0]
	
	player_sprite._apply_skin_scale()

func _cache_animation_bases() -> void:
	for label: Control in [rank, current_rank_score, next_rank_score, score_label]:
		label.offset_transform_enabled = true
	_refresh_label_pivots()
	rank.offset_transform_position = Vector2.ZERO
	rank.offset_transform_scale = Vector2.ONE
	current_rank_score.offset_transform_position = Vector2.ZERO
	current_rank_score.offset_transform_scale = Vector2.ONE
	next_rank_score.offset_transform_position = Vector2.ZERO
	next_rank_score.offset_transform_scale = Vector2.ONE
	_player_sprite_base_position = player_sprite.position
	_player_sprite_base_scale = player_sprite.scale

func _refresh_label_pivots() -> void:
	rank.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	current_rank_score.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	next_rank_score.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	score_label.offset_transform_pivot_ratio = Vector2(0.5, 0.5)

func _create_tick_players() -> void:
	if not _tick_players.is_empty():
		return

	for index in range(TICK_PLAYER_COUNT):
		var tick_player := AudioStreamPlayer.new()
		tick_player.name = "ResultTickPlayer%d" % index
		tick_player.stream = RESULT_TICK_STREAM
		tick_player.bus = "SFX"
		add_child(tick_player)
		_tick_players.append(tick_player)

func _run_result_sequence() -> void:
	_target_score = clampf(score.total_score, 0.0, MAX_SCORE_DISPLAY)
	var final_rank_index := ScoreRank.index_for_score(_target_score)
	var display_score := 0.0

	for rank_index in range(final_rank_index):
		var segment_start := ScoreRank.minimum(rank_index)
		var segment_end := ScoreRank.minimum(rank_index + 1)

		display_score = await _animate_score_segment(
			display_score,
			segment_end,
			FULL_RANK_SEGMENT_DURATION,
			false,
			segment_start,
			segment_end,
			rank_index
		)
		_play_player_dance()
		await _play_rank_transition(rank_index + 1)

	var final_rank_min := ScoreRank.minimum(final_rank_index)
	var final_ratio := 0.0
	if _target_score > final_rank_min:
		final_ratio = inverse_lerp(final_rank_min, ScoreRank.maximum(final_rank_index), _target_score)

	var final_duration := lerpf(FINAL_SEGMENT_DURATION, FINAL_SEGMENT_DURATION_MAX, final_ratio)
	await _animate_score_segment(
		display_score,
		_target_score,
		final_duration,
		true,
		final_rank_min,
		_target_score,
		final_rank_index
	)

	_apply_rank_state(final_rank_index)
	_update_live_score(_target_score)

func _animate_score_segment(
	start_score: float,
	end_score: float,
	duration: float,
	ease_out: bool,
	segment_start: float,
	segment_end: float,
	locked_rank_index: int = -1
) -> float:
	if is_equal_approx(start_score, end_score):
		_update_live_score(end_score, locked_rank_index)
		return end_score

	var elapsed := 0.0
	var current_score := start_score

	while elapsed < duration:
		var delta := get_process_delta_time()
		elapsed += delta

		var t := minf(elapsed / duration, 1.0)
		if ease_out:
			t = 1.0 - pow(1.0 - t, 3.0)

		current_score = lerpf(start_score, end_score, t)
		_update_live_score(current_score, locked_rank_index)
		_update_tick_sound(delta, current_score, segment_start, segment_end, ease_out)
		await get_tree().process_frame

	_update_live_score(end_score, locked_rank_index)
	return end_score

func _update_tick_sound(
	delta: float,
	current_score: float,
	segment_start: float,
	segment_end: float,
	ease_out: bool
) -> void:
	if _tick_players.is_empty():
		return

	_tick_cooldown -= delta
	if _tick_cooldown > 0.0:
		return

	var slow_ratio := 0.0
	if ease_out and segment_end > segment_start:
		slow_ratio = clampf(inverse_lerp(segment_start, segment_end, current_score), 0.0, 1.0)

	var total_ratio := 0.0
	if _target_score > 0.0:
		total_ratio = clampf(current_score / _target_score, 0.0, 1.0)

	_tick_cooldown = lerpf(0.032, 0.09, slow_ratio)

	var tick_player := _tick_players[_next_tick_player_index]
	_next_tick_player_index = (_next_tick_player_index + 1) % _tick_players.size()
	tick_player.pitch_scale = lerpf(0.85, 1.22, total_ratio)
	tick_player.play(0.1)

func _play_player_dance() -> void:
	if player_sprite == null or player_sprite.skin == null:
		return
	player_sprite.play_animation(player_sprite.get_hit_animation())
	_play_player_sprite_punch()

func _play_player_sprite_punch() -> void:
	if player_sprite == null:
		return
	if _player_sprite_tween != null:
		_player_sprite_tween.kill()

	player_sprite.position = _player_sprite_base_position
	player_sprite.scale = _player_sprite_base_scale

	_player_sprite_tween = create_tween()
	_player_sprite_tween.set_parallel(true)
	_player_sprite_tween.set_trans(Tween.TRANS_BACK)
	_player_sprite_tween.set_ease(Tween.EASE_OUT)
	_player_sprite_tween.tween_property(
		player_sprite,
		"position",
		_player_sprite_base_position + Vector2(0.0, -18.0),
		0.12
	)
	_player_sprite_tween.tween_property(
		player_sprite,
		"scale",
		Vector2(_player_sprite_base_scale.x * 0.94, _player_sprite_base_scale.y * 1.12),
		0.12
	)
	_player_sprite_tween.finished.connect(func() -> void:
		_player_sprite_tween = create_tween()
		_player_sprite_tween.set_parallel(true)
		_player_sprite_tween.set_trans(Tween.TRANS_BACK)
		_player_sprite_tween.set_ease(Tween.EASE_OUT)
		_player_sprite_tween.tween_property(player_sprite, "position", _player_sprite_base_position, 0.18)
		_player_sprite_tween.tween_property(player_sprite, "scale", _player_sprite_base_scale, 0.18)
	)

func _play_rank_transition(new_rank_index: int) -> void:
	_current_rank_index = new_rank_index

	if rank_up_particles != null:
		rank_up_particles.restart()
		rank_up_particles.emitting = true

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(rank, "offset_transform_position", Vector2(0.0, 28.0), 0.12)
	tween.tween_property(rank, "offset_transform_scale", Vector2.ONE * 0.82, 0.12)
	tween.tween_property(rank, "modulate:a", 0.0, 0.12)
	await tween.finished

	_apply_rank_state(new_rank_index)
	rank.offset_transform_position = Vector2(0.0, 20.0)
	rank.offset_transform_scale = Vector2.ONE * 1.16
	rank.modulate.a = 0.0

	var rank_tween := create_tween()
	rank_tween.set_parallel(true)
	rank_tween.set_trans(Tween.TRANS_BACK)
	rank_tween.set_ease(Tween.EASE_OUT)
	rank_tween.tween_property(rank, "offset_transform_position", Vector2.ZERO, 0.2)
	rank_tween.tween_property(rank, "offset_transform_scale", Vector2.ONE, 0.2)
	rank_tween.tween_property(rank, "modulate:a", 1.0, 0.18)

	_pulse_rank_score_labels()
	await rank_tween.finished

func _pulse_rank_score_labels() -> void:
	current_rank_score.offset_transform_position = Vector2.ZERO
	next_rank_score.offset_transform_position = Vector2.ZERO
	current_rank_score.offset_transform_scale = Vector2.ONE
	next_rank_score.offset_transform_scale = Vector2.ONE

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(current_rank_score, "offset_transform_position", Vector2(0.0, -10.0), 0.12)
	tween.tween_property(next_rank_score, "offset_transform_position", Vector2(0.0, -10.0), 0.12)
	tween.tween_property(current_rank_score, "offset_transform_scale", Vector2(1.0, 1.12), 0.12)
	tween.tween_property(next_rank_score, "offset_transform_scale", Vector2(1.0, 1.12), 0.12)

	tween.finished.connect(func() -> void:
		var settle_tween := create_tween()
		settle_tween.set_parallel(true)
		settle_tween.set_trans(Tween.TRANS_BACK)
		settle_tween.set_ease(Tween.EASE_OUT)
		settle_tween.tween_property(current_rank_score, "offset_transform_position", Vector2.ZERO, 0.16)
		settle_tween.tween_property(next_rank_score, "offset_transform_position", Vector2.ZERO, 0.16)
		settle_tween.tween_property(current_rank_score, "offset_transform_scale", Vector2.ONE, 0.16)
		settle_tween.tween_property(next_rank_score, "offset_transform_scale", Vector2.ONE, 0.16)
	)

func _apply_rank_state(rank_index: int) -> void:
	_current_rank_index = rank_index
	var current_rank_label := ScoreRank.label(rank_index)
	var current_rank_min := ScoreRank.minimum(rank_index)

	rank.text = current_rank_label
	current_rank_score.text = "%s\n%s" % [current_rank_label, _format_rank_score(current_rank_min)]

	if rank_index + 1 < ScoreRank.DATA.size():
		next_rank_score.text = "%s\n%s" % [
			ScoreRank.label(rank_index + 1),
			_format_rank_score(ScoreRank.minimum(rank_index + 1))
		]
	else:
		next_rank_score.text = "X\n%s" % _format_rank_score(MAX_SCORE_DISPLAY)

	_apply_rank_colors(rank_index)

func _update_live_score(display_score: float, locked_rank_index: int = -1) -> void:
	var display_rank_index := ScoreRank.index_for_score(display_score)
	if locked_rank_index >= 0:
		display_rank_index = locked_rank_index
	score_label.text = _format_score(display_score)

	if display_rank_index != _current_rank_index:
		_apply_rank_state(display_rank_index)

	var current_rank_min := ScoreRank.minimum(display_rank_index)
	var current_rank_max := ScoreRank.maximum(display_rank_index)
	if current_rank_max <= current_rank_min:
		progress_bar.value = 1.0
		return

	progress_bar.value = clampf(
		inverse_lerp(current_rank_min, current_rank_max, display_score),
		0.0,
		1.0
	)

func _apply_rank_colors(rank_index: int) -> void:
	var current_color := ScoreRank.color(rank_index)
	rank.add_theme_color_override("font_color", current_color)
	score_label.add_theme_color_override("font_color", current_color)
	current_rank_score.add_theme_color_override("font_color", current_color)

	if rank_index + 1 < ScoreRank.DATA.size():
		next_rank_score.add_theme_color_override(
			"font_color",
			ScoreRank.color(rank_index + 1)
		)
	else:
		next_rank_score.add_theme_color_override("font_color", current_color)

func _format_score(value: float) -> String:
	return "%.2f%%" % value

func _format_rank_score(value: float) -> String:
	return "%d%%" % int(round(value))

func _on_back_pressed() -> void:
	Transition.return_to_menu(0.6)
