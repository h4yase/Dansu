@tool
extends Control
class_name MenuBigButton

signal activated()

const TEXT_SIDE_SPACE := 70.0

@export var bg_color : Color = Color("705bde")

@export var button_text := "PLAY":
	set(value):
		button_text = value
		_update_button()

@export var icon_texture :Texture:
	set(value):
		icon_texture = value
		if icon != null:
			icon.texture = value

@export var hover_scale := 1.1
@export var hover_rotation := -2.0
@export var hover_offset := Vector2(-8, 0)

@export var hover_time := 0.15

@export_group("Node References")
@export var pivot: Control
@export var background: ColorRect
@export var button: Button
@export var icon: Sprite2D
@export var hover_player: AudioStreamPlayer
@export var click_player: AudioStreamPlayer

var tween: Tween
var _interaction_enabled := true

func _ready() -> void:
	await get_tree().process_frame
	
	background.color = bg_color
	icon.texture = icon_texture
	pivot.offset_transform_enabled = true
	background.offset_transform_enabled = true
	background.offset_transform_pivot_ratio = Vector2(0.0, 0.5)

	background.scale = Vector2.ONE
	background.offset_transform_scale = Vector2.ZERO
	background.modulate.a = 0.0
	button.theme_changed.connect(_update_background_size)
	button.resized.connect(_update_background_size)
	_update_button()

	if not Engine.is_editor_hint():
		button.mouse_entered.connect(_hover_enter)
		button.mouse_exited.connect(_hover_exit)
		button.pressed.connect(_pressed)
		_apply_interaction_state()


func set_interaction_enabled(enabled: bool) -> void:
	var was_enabled := _interaction_enabled
	_interaction_enabled = enabled
	if not is_node_ready():
		return

	_apply_interaction_state()
	if not enabled:
		button.release_focus()
		_play_hover(false)
	elif not was_enabled and _is_mouse_over_button():
		_hover_enter()


func _apply_interaction_state() -> void:
	button.disabled = false
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_ALL if _interaction_enabled else Control.FOCUS_NONE


func _is_mouse_over_button() -> bool:
	if not button.is_visible_in_tree():
		return false
	return Rect2(Vector2.ZERO, button.size).has_point(button.get_local_mouse_position())


func _update_button() -> void:
	if not is_node_ready():
		return

	button.text = button_text
	button.clip_text = false
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_update_background_size()


func _update_background_size() -> void:
	if not is_node_ready():
		return
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var text_width := font.get_string_size(button_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	background.size = Vector2(text_width + TEXT_SIDE_SPACE, button.get_combined_minimum_size().y + 10.0)


func _hover_enter() -> void:
	if not _interaction_enabled:
		return
	hover_player.play()
	_play_hover(true)

func _hover_exit() -> void:
	_play_hover(false)


func _pressed() -> void:
	click_player.play(0.1)
	if not _interaction_enabled:
		return

	if tween:
		tween.kill()

	tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	pivot.offset_transform_scale = Vector2.ONE * 0.96

	tween.tween_property(
		pivot,
		"offset_transform_scale",
		Vector2.ONE * hover_scale,
		0.12
	)
	activated.emit()


func _play_hover(state: bool) -> void:
	if tween:
		tween.kill()

	tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	if state:
		tween.parallel().tween_property(
			pivot,
			"offset_transform_scale",
			Vector2.ONE * hover_scale,
			hover_time
		)

		tween.parallel().tween_property(
			pivot,
			"offset_transform_position",
			hover_offset,
			hover_time
		)

		tween.parallel().tween_property(
			pivot,
			"offset_transform_rotation",
			deg_to_rad(hover_rotation),
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"offset_transform_scale:x",
			1.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"offset_transform_scale:y",
			1.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"modulate:a",
			0.8,
			hover_time
		)

	else:
		tween.parallel().tween_property(
			pivot,
			"offset_transform_scale",
			Vector2.ONE,
			hover_time
		)

		tween.parallel().tween_property(
			pivot,
			"offset_transform_position",
			Vector2.ZERO,
			hover_time
		)

		tween.parallel().tween_property(
			pivot,
			"offset_transform_rotation",
			0.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"offset_transform_scale:x",
			0.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"offset_transform_scale:y",
			0.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"modulate:a",
			0.0,
			hover_time
		)
