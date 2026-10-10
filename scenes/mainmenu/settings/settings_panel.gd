extends Control
class_name SettingsPanel

const BODY := preload("res://resources/textures/settings/panel.svg")
const GEAR := preload("res://resources/textures/settings/gear.svg")
const GEAR_OPACITY := 0.65
# Midpoint of panel.svg's rounded top corner.
const GEAR_CENTER := Vector2(632.75, 16.0)

var gear_angle := 0.0
var _wheel_speed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))

func spin_gear(amount: float) -> void:
	_wheel_speed = clampf(_wheel_speed + amount * 2.4, -9.0, 9.0)

func _process(delta: float) -> void:
	gear_angle += (0.09 + _wheel_speed) * delta
	_wheel_speed *= exp(-4.5 * delta)
	queue_redraw()

func _draw() -> void:
	draw_set_transform(GEAR_CENTER * size / BODY.get_size(), gear_angle)
	draw_texture_rect(GEAR, Rect2(-94, -94, 188, 188), false, Color(1.0, 1.0, 1.0, GEAR_OPACITY))
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(BODY, Rect2(Vector2.ZERO, size), false)
