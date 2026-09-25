extends Panel

const MAX_ROTATION_DEGREES := 3.0
const HOVER_SCALE := 1.015
const THUMB_PARALLAX := Vector2(10.0, 8.0)
const CONTENT_PARALLAX := Vector2(14.0, 10.0)
const SHADOW_BASE_OFFSET := Vector2(0.0, 8.0)
const SHADOW_MAX_OFFSET := Vector2(18.0, 12.0)
const SHADOW_HOVER_SIZE := 32.0
const SHADOW_REST_COLOR := Color(0, 0, 0, 0)
const SHADOW_HOVER_COLOR := Color(0, 0, 0, 0.32)
const VISUAL_LERP_SPEED := 12.0
const HOVER_LERP_SPEED := 10.0
const THUMB_VISIBLE_ALPHA := 0.8
const THUMB_CROSSFADE_DURATION := 0.24

@export_group("Node References")
@export var thumb: TextureRect
@export var previous_thumb: TextureRect
@export var cover_layer: Control
@export var content: Control
@export var shine_rect: ColorRect
@export var title_label: Label
@export var artist_label: Label
@export var desc_label: Label
@export var rank_label: Label
@export var full_combo_label: Label
@export var all_just_label: Label
@export var perfect_label: Label
@export var never_played_label: Label
@export var score_label: Label
@export var ranked_badge: Control

var score_ui_bound := true
var click_tween: Tween
var thumb_tween: Tween

var current_cover_chart: Chart = null
var hovered := false
var hover_strength := 0.0
var shine_uv := Vector2(0.5, 0.5)
var press_scale_multiplier := 1.0
var panel_style: StyleBoxFlat
var shine_material: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	resized.connect(_on_resized)
	CM.chart_selected.connect(_refresh)
	CoverLoader.cover_loaded.connect(_on_cover_loaded)
	CoverLoader.cover_failed.connect(_on_cover_failed)
	offset_transform_enabled = true
	cover_layer.offset_transform_enabled = true
	content.offset_transform_enabled = true

	_setup_stylebox()
	_setup_shine()
	_snap_to_rest_state()
	call_deferred("_on_resized")
	set_process(false)

	if CM.selected_chart != null:
		_refresh(CM.selected_chart)


func _process(delta: float) -> void:
	var target_uv := Vector2(0.5, 0.5)
	var normalized := Vector2.ZERO
	var target_hover_strength := 0.0
	var target_scale_value := 1.0

	if hovered and size.x > 0.0 and size.y > 0.0:
		var local_mouse := get_local_mouse_position()
		target_uv = Vector2(
			clampf(local_mouse.x / size.x, 0.0, 1.0),
			clampf(local_mouse.y / size.y, 0.0, 1.0)
		)
		normalized = (target_uv - Vector2(0.5, 0.5)) * 2.0
		target_hover_strength = 1.0
		target_scale_value = HOVER_SCALE

	var visual_weight := minf(delta * VISUAL_LERP_SPEED, 1.0)
	var hover_weight := minf(delta * HOVER_LERP_SPEED, 1.0)
	var target_scale := Vector2.ONE * (target_scale_value * press_scale_multiplier)
	var target_rotation := deg_to_rad(normalized.x * MAX_ROTATION_DEGREES)
	var target_thumb_offset := -Vector2(
		normalized.x * THUMB_PARALLAX.x,
		normalized.y * THUMB_PARALLAX.y
	)
	var target_content_offset := Vector2(
		normalized.x * CONTENT_PARALLAX.x,
		normalized.y * CONTENT_PARALLAX.y
	)
	var target_shadow_offset := SHADOW_BASE_OFFSET + Vector2(
		normalized.x * SHADOW_MAX_OFFSET.x,
		normalized.y * SHADOW_MAX_OFFSET.y
	)
	var target_shadow_color := SHADOW_HOVER_COLOR if hovered else SHADOW_REST_COLOR
	var target_shadow_size := SHADOW_HOVER_SIZE if hovered else 0.0

	offset_transform_scale = offset_transform_scale.lerp(target_scale, visual_weight)
	offset_transform_rotation = lerpf(offset_transform_rotation, target_rotation, visual_weight)
	cover_layer.offset_transform_position = cover_layer.offset_transform_position.lerp(target_thumb_offset, visual_weight)
	content.offset_transform_position = content.offset_transform_position.lerp(target_content_offset, visual_weight)
	shine_uv = shine_uv.lerp(target_uv, visual_weight)
	hover_strength = lerpf(hover_strength, target_hover_strength, hover_weight)

	if shine_material != null:
		shine_material.set_shader_parameter("cursor_uv", shine_uv)
		shine_material.set_shader_parameter("hover_strength", hover_strength)

	if panel_style != null:
		panel_style.shadow_offset = panel_style.shadow_offset.lerp(target_shadow_offset, visual_weight)
		panel_style.shadow_color = panel_style.shadow_color.lerp(target_shadow_color, hover_weight)
		panel_style.shadow_size = int(lerpf(panel_style.shadow_size, target_shadow_size, hover_weight))

	if not hovered and _is_visual_resting():
		_snap_to_rest_state()
		set_process(false)


func _refresh(chart: Chart) -> void:
	current_cover_chart = chart
	_refresh_best_play(chart)

	if chart == null:
		title_label.text = ""
		artist_label.text = ""
		desc_label.text = ""
		_crossfade_thumb(null)
		return

	title_label.text = chart.title
	artist_label.text = _build_artist_text(chart)
	desc_label.text = _build_desc_text(chart)
	ranked_badge.visible = (chart.chart_set.status == "ranked")

	if _is_builtin_chart(chart):
		if chart.cover_image != null:
			_crossfade_thumb(chart.cover_image)
		elif chart.file_cover_art.is_empty():
			_crossfade_thumb(null)
		else:
			CoverLoader.request_cover(chart)
	elif chart.detail_cover_image != null:
		_crossfade_thumb(chart.detail_cover_image)
	elif _expects_detail_cover(chart):
		# Keep the outgoing cover until the 1024px image is ready. Showing the
		# catalogue thumbnail first causes two rapid crossfades and a visible flash.
		pass
	elif chart.cover_image != null:
		_crossfade_thumb(chart.cover_image)
	elif chart.file_cover_art.is_empty():
		_crossfade_thumb(null)
	else:
		CoverLoader.request_cover(chart)


func refresh_selected_chart() -> void:
	_refresh(CM.selected_chart)


func _refresh_best_play(chart: Chart) -> void:
	if not score_ui_bound:
		_hide_score_ui()
		return

	var best_play: Score = Scores.get_best_play(chart) if chart != null else null
	var has_record := best_play != null

	rank_label.visible = has_record
	score_label.visible = has_record
	full_combo_label.visible = false
	all_just_label.visible = false
	perfect_label.visible = false
	# never_played_label.visible = chart != null and not has_record

	if not has_record:
		return

	rank_label.text = best_play.rank_str
	score_label.text = "%.2f%%" % best_play.total_score
	rank_label.add_theme_color_override("font_color", best_play.rank_color)
	score_label.add_theme_color_override("font_color", best_play.rank_color)

	if best_play.notes <= 0:
		return

	var is_full_combo := best_play.miss == 0 and best_play.high_combo >= best_play.notes
	full_combo_label.visible = is_full_combo


func set_score_ui_bound(bound: bool) -> void:
	score_ui_bound = bound
	if not is_node_ready():
		return
	_refresh_best_play(current_cover_chart)


func _hide_score_ui() -> void:
	for label: Label in [
		rank_label,
		full_combo_label,
		all_just_label,
		perfect_label,
		never_played_label,
		score_label,
	]:
		label.visible = false
		ranked_badge.visible = false


func _on_mouse_entered() -> void:
	hovered = true
	set_process(true)


func _on_mouse_exited() -> void:
	hovered = false
	set_process(true)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_click_animation()


func _on_resized() -> void:
	offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	if shine_rect != null:
		shine_rect.pivot_offset = shine_rect.size * 0.5


func _on_cover_loaded(chart: Chart, texture: Texture2D) -> void:
	if chart == null or texture == null:
		return
	if chart != current_cover_chart:
		return
	if _expects_detail_cover(chart):
		return
	var display_texture := texture
	if not _is_builtin_chart(chart) and chart.detail_cover_image != null:
		display_texture = chart.detail_cover_image
	_crossfade_thumb(display_texture)


func _on_cover_failed(chart: Chart) -> void:
	if chart != current_cover_chart:
		return
	if _expects_detail_cover(chart):
		return
	_crossfade_thumb(null)


func show_detail_cover(chart: Chart, texture: Texture2D) -> void:
	if chart == null or texture == null or chart != current_cover_chart:
		return
	if _is_builtin_chart(chart):
		return
	_crossfade_thumb(texture)


func show_detail_cover_failed(chart: Chart) -> void:
	if chart == null or chart != current_cover_chart:
		return
	if chart.cover_image != null:
		_crossfade_thumb(chart.cover_image)
	elif chart.file_cover_art.is_empty():
		_crossfade_thumb(null)
	else:
		CoverLoader.request_cover(chart)


func _expects_detail_cover(chart: Chart) -> bool:
	return (
		chart != null
		and not _is_builtin_chart(chart)
		and chart.detail_cover_image == null
		and chart.chart_set != null
		and not str(chart.chart_set.online_metadata.get("cover_url", "")).is_empty()
	)


func _is_builtin_chart(chart: Chart) -> bool:
	return (
		chart != null
		and not chart.file_name.is_empty()
		and chart.storage_root == FileSystem.official_chart_path
	)


func _setup_stylebox() -> void:
	var style := get("theme_override_styles/panel") as StyleBoxFlat
	if style == null:
		return

	panel_style = style.duplicate()
	panel_style.shadow_color = SHADOW_REST_COLOR
	panel_style.shadow_size = 0
	panel_style.shadow_offset = SHADOW_BASE_OFFSET
	add_theme_stylebox_override("panel", panel_style)


func _setup_shine() -> void:
	shine_material = shine_rect.material as ShaderMaterial
	if shine_material == null:
		return
	shine_material = shine_material.duplicate()
	shine_rect.material = shine_material
	shine_material.set_shader_parameter("cursor_uv", Vector2(0.5, 0.5))
	shine_material.set_shader_parameter("hover_strength", 0.0)


func _play_click_animation() -> void:
	if click_tween != null:
		click_tween.kill()

	click_tween = create_tween()
	click_tween.set_trans(Tween.TRANS_BACK)
	click_tween.set_ease(Tween.EASE_OUT)
	click_tween.tween_method(Callable(self, "_set_press_scale_multiplier"), press_scale_multiplier, 0.975, 0.06)
	click_tween.tween_method(Callable(self, "_set_press_scale_multiplier"), 0.975, 1.0, 0.16)


func _set_press_scale_multiplier(value: float) -> void:
	press_scale_multiplier = value
	set_process(true)


func _crossfade_thumb(texture: Texture2D) -> void:
	if thumb_tween != null:
		thumb_tween.kill()

	var outgoing_texture := thumb.texture
	var outgoing_alpha := thumb.modulate.a
	if previous_thumb.modulate.a > outgoing_alpha:
		outgoing_texture = previous_thumb.texture
		outgoing_alpha = previous_thumb.modulate.a

	if texture == outgoing_texture:
		previous_thumb.texture = null
		previous_thumb.modulate.a = 0.0
		thumb.texture = texture
		thumb.modulate.a = THUMB_VISIBLE_ALPHA if texture != null else 0.0
		thumb_tween = null
		return

	previous_thumb.texture = outgoing_texture
	previous_thumb.modulate.a = outgoing_alpha
	thumb.texture = texture
	thumb.modulate.a = 0.0

	if texture == null and outgoing_texture == null:
		thumb_tween = null
		return

	thumb_tween = create_tween()
	var active_tween := thumb_tween
	thumb_tween.set_parallel(true)
	thumb_tween.set_trans(Tween.TRANS_SINE)
	thumb_tween.set_ease(Tween.EASE_IN_OUT)
	thumb_tween.tween_property(previous_thumb, "modulate:a", 0.0, THUMB_CROSSFADE_DURATION)
	thumb_tween.tween_property(
		thumb,
		"modulate:a",
		THUMB_VISIBLE_ALPHA if texture != null else 0.0,
		THUMB_CROSSFADE_DURATION
	)
	thumb_tween.finished.connect(func() -> void:
		if thumb_tween != active_tween:
			return
		previous_thumb.texture = null
		previous_thumb.modulate.a = 0.0
		thumb_tween = null
	)


func _build_artist_text(chart: Chart) -> String:
	if chart == null:
		return ""
	return chart.artist


func _build_desc_text(chart: Chart) -> String:
	if chart == null:
		return ""

	var parts: Array[String] = []
	var timing_text := _build_timing_text(chart)
	var difficulty_text := _build_difficulty_text(chart)

	if not timing_text.is_empty():
		parts.append(timing_text)
	if not difficulty_text.is_empty():
		parts.append(difficulty_text)

	return "      ".join(parts)


func _build_timing_text(chart: Chart) -> String:
	if chart == null:
		return ""

	var length_text := _get_chart_length_text(chart)
	var bpm_text := _get_chart_bpm_text(chart)

	if length_text.is_empty() and bpm_text.is_empty():
		return ""
	if bpm_text.is_empty():
		return length_text
	if length_text.is_empty():
		return bpm_text
	return "%s (%s)" % [length_text, bpm_text]


func _get_chart_bpm_text(chart: Chart) -> String:
	if chart != null and not chart.online_metadata.is_empty():
		var low := float(chart.online_metadata.get("min_bpm", 0))
		var high := float(chart.online_metadata.get("max_bpm", 0))
		return "%s BPM" % _format_bpm(low) if is_equal_approx(low, high) else "%s–%s BPM" % [_format_bpm(low), _format_bpm(high)]
	if chart == null or chart.timings.is_empty():
		return ""

	var min_bpm := INF
	var max_bpm := -INF

	for timing in chart.timings:
		if timing == null or timing.bpm <= 0.0:
			continue
		min_bpm = minf(min_bpm, timing.bpm)
		max_bpm = maxf(max_bpm, timing.bpm)

	if min_bpm == INF or max_bpm == -INF:
		return ""
	if is_equal_approx(min_bpm, max_bpm):
		return "%s BPM" % _format_bpm(min_bpm)
	return "%s-%s BPM" % [_format_bpm(min_bpm), _format_bpm(max_bpm)]


func _format_bpm(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return ("%.1f" % value).rstrip("0").rstrip(".")


func _get_chart_length_text(chart: Chart) -> String:
	if chart == null or chart.play_time_ms <= 0:
		return ""
	return _format_duration(float(chart.play_time_ms) / 1000.0)


func _format_duration(length_sec: float) -> String:
	var total_seconds = max(0, int(round(length_sec)))
	var minutes = total_seconds / 60
	var seconds = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]


func _build_difficulty_text(chart: Chart) -> String:
	if chart == null:
		return ""

	var difficulty := chart.difficulty
	var creator := chart.creator
	var has_difficulty := not difficulty.is_empty() and difficulty != "?"
	var has_creator := not creator.is_empty() and creator != "?"

	if has_difficulty and has_creator:
		return "%s by %s" % [difficulty, creator]
	if has_difficulty:
		return difficulty
	if has_creator:
		return creator
	return ""


func _is_visual_resting() -> bool:
	if absf(offset_transform_rotation) > deg_to_rad(0.05):
		return false
	if offset_transform_scale.distance_to(Vector2.ONE) > 0.001:
		return false
	if cover_layer.offset_transform_position.length() > 0.2:
		return false
	if content.offset_transform_position.length() > 0.2:
		return false
	if hover_strength > 0.01:
		return false
	if absf(press_scale_multiplier - 1.0) > 0.001:
		return false
	return true


func _snap_to_rest_state() -> void:
	press_scale_multiplier = 1.0
	offset_transform_scale = Vector2.ONE
	offset_transform_rotation = 0.0
	cover_layer.offset_transform_position = Vector2.ZERO
	content.offset_transform_position = Vector2.ZERO
	shine_uv = Vector2(0.5, 0.5)
	hover_strength = 0.0

	if shine_material != null:
		shine_material.set_shader_parameter("cursor_uv", shine_uv)
		shine_material.set_shader_parameter("hover_strength", hover_strength)

	if panel_style != null:
		panel_style.shadow_offset = SHADOW_BASE_OFFSET
		panel_style.shadow_color = SHADOW_REST_COLOR
		panel_style.shadow_size = 0
