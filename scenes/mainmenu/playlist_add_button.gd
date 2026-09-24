extends Button

var _motion: Tween
var _hovered := false


func _ready() -> void:
	tooltip_text = "Add to playlist"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	resized.connect(func(): pivot_offset = size * 0.5)
	pivot_offset = size * 0.5
	mouse_entered.connect(func():
		_hovered = true
		_rest()
	)
	mouse_exited.connect(func():
		_hovered = false
		_rest()
	)
	focus_entered.connect(_rest)
	focus_exited.connect(_rest)
	button_down.connect(func(): _animate(0.86, 0.07))
	button_up.connect(_rest)
	visibility_changed.connect(func():
		if _motion:
			_motion.kill()
		_hovered = false
		scale = Vector2.ONE
	)


func _rest() -> void:
	_animate(1.12 if not disabled and (_hovered or has_focus()) else 1.0, 0.16)


func _animate(target: float, duration: float) -> void:
	if _motion:
		_motion.kill()
	_motion = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion.tween_property(self, "scale", Vector2.ONE * target, duration)
