extends Button
class_name LovedButton

const OUTLINE := preload("res://resources/icons/loved-outline.svg")
const FILLED := preload("res://resources/icons/loved-filled.svg")

var _heart: TextureRect
var _motion: Tween
var _hovered := false
var _loved := false


func _ready() -> void:
	text = ""
	icon = null
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color.TRANSPARENT
	focus_style.border_color = Color("705bde")
	focus_style.set_border_width_all(2)
	focus_style.set_corner_radius_all(18)
	add_theme_stylebox_override("focus", focus_style)
	_heart = TextureRect.new()
	_heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_heart)
	_heart.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_update_pivot)
	mouse_entered.connect(func() -> void:
		_hovered = true
		_rest()
	)
	mouse_exited.connect(func() -> void:
		_hovered = false
		_rest()
	)
	focus_entered.connect(_rest)
	focus_exited.connect(_rest)
	button_down.connect(_press_down)
	button_up.connect(_rest)
	pressed.connect(_click)
	_update_pivot()
	set_loved_state(_loved, disabled)


func set_loved_state(loved: bool, unavailable: bool) -> void:
	_loved = loved
	disabled = unavailable
	tooltip_text = "Remove from Loved" if loved else "Add to Loved"
	if _heart != null:
		_heart.texture = FILLED if loved else OUTLINE
		_heart.modulate.a = 0.65 if unavailable else 1.0


func _update_pivot() -> void:
	_heart.pivot_offset = size * 0.5


func _animate(target_scale: float, angle: float, duration: float) -> void:
	if _motion:
		_motion.kill()
	_motion = create_tween().set_parallel(true)
	_motion.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion.tween_property(_heart, "scale", Vector2.ONE * target_scale, duration)
	_motion.tween_property(_heart, "rotation", deg_to_rad(angle), duration)


func _rest() -> void:
	var active := not disabled and (_hovered or has_focus())
	_animate(1.12 if active else 1.0, -6.0 if active else 0.0, 0.16)


func _press_down() -> void:
	if not disabled:
		_animate(0.86, 4.0, 0.07)


func _click() -> void:
	_heart.scale = Vector2.ONE * 1.22
	_rest()
	for index in range(8):
		var particle := TextureRect.new()
		particle.texture = FILLED
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		particle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		particle.size = Vector2.ONE * (9.0 + (index % 3) * 2.0)
		particle.pivot_offset = particle.size * 0.5
		var direction := Vector2.UP.rotated(TAU * index / 8.0)
		particle.position = size * 0.5 - particle.size * 0.5 + direction * 12.0
		add_child(particle)
		var burst := particle.create_tween().set_parallel(true)
		burst.tween_property(particle, "position", particle.position + direction * 34.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		burst.tween_property(particle, "rotation", direction.x * 0.7, 0.36)
		burst.tween_property(particle, "scale", Vector2.ONE * 0.25, 0.36)
		burst.tween_property(particle, "modulate:a", 0.0, 0.26).set_delay(0.1)
		burst.finished.connect(particle.queue_free)
