extends Control
class_name FilterRangeSlider

signal changed

const HANDLE_SIZE := 36.0
const TRACK_WIDTH := 30.0
const TRACK_Y := 28.0
const HANDLE_FONT := preload("res://resources/fonts/bold/Next Bravo.ttf")

class HandleVisual:
	var step := 0.0
	var hover := 0.0
	var pulse := 0.0
	var held := 0.0

@export var finite_steps := 40
@export var time_range := false

var lower := 0
var upper := 41
var _dragging := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _upper_active := false
var _drag_offset := 0.0
var _lower_visual := HandleVisual.new()
var _upper_visual := HandleVisual.new()
var _hover_lower := false
var _hover_upper := false
var _keyboard_focus := false

func _ready() -> void:
	custom_minimum_size = Vector2(320, 76)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_values(lower, finite_steps + 1)
	resized.connect(queue_redraw)
	focus_entered.connect(func():
		_keyboard_focus = true
		set_process(true)
	)
	focus_exited.connect(func(): set_process(true))
	mouse_exited.connect(func():
		_hover_lower = false
		_hover_upper = false
		set_process(true)
	)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_end_drag()
			_hover_lower = false
			_hover_upper = false
		set_process(is_visible_in_tree())
	)

func _exit_tree() -> void:
	_end_drag()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_drag()

func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	Input.mouse_mode = _previous_mouse_mode
	set_process(true)

func set_values(minimum: int, maximum: int) -> void:
	lower = clampi(minimum, 0, finite_steps)
	upper = clampi(maximum, lower, finite_steps + 1)
	_lower_visual.step = lower
	_upper_visual.step = upper
	_lower_visual.pulse = 0.0
	_upper_visual.pulse = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	var moving := false
	var weight := 1.0 - exp(-24.0 * delta)
	for is_upper in [false, true]:
		var visual := _upper_visual if is_upper else _lower_visual
		var target := float(upper if is_upper else lower)
		var hovered := _hover_upper if is_upper else _hover_lower
		var active: bool = is_upper == _upper_active
		var hover_target := 1.0 if hovered or (has_focus() and _keyboard_focus and active) else 0.0
		var held_target := 1.0 if _dragging and active else 0.0
		visual.step = lerpf(visual.step, target, weight)
		visual.hover = lerpf(visual.hover, hover_target, weight)
		visual.held = lerpf(visual.held, held_target, weight)
		visual.pulse = move_toward(visual.pulse, 0.0, delta * 5.5)
		if absf(visual.step - target) + absf(visual.hover - hover_target) + absf(visual.held - held_target) + visual.pulse > 0.002:
			moving = true
		else:
			visual.step = target
			visual.hover = hover_target
			visual.held = held_target
	# Visual motion must preserve the same non-overlapping inner edges as the values.
	_lower_visual.step = minf(_lower_visual.step, _upper_visual.step)
	queue_redraw()
	set_process(moving)

func _step_x(value: float) -> float:
	return HANDLE_SIZE + 4.0 + value * _track_width() / (finite_steps + 1)

func _track_width() -> float:
	return maxf(1.0, size.x - 2.0 * (HANDLE_SIZE + 4.0))

func _handle_rect(is_upper: bool) -> Rect2:
	var x := _step_x(upper if is_upper else lower)
	# The inner edges point at the value, so equal bounds stay side by side.
	return Rect2(x if is_upper else x - HANDLE_SIZE, TRACK_Y - HANDLE_SIZE / 2.0, HANDLE_SIZE, HANDLE_SIZE)

func _caption(value: int) -> String:
	if value > finite_steps:
		return "INF"
	if time_range:
		return "%d:%02d" % [value / 2, (value % 2) * 30]
	return str(value)

func _draw() -> void:
	var start := Vector2(_step_x(0), TRACK_Y)
	var end := Vector2(_step_x(finite_steps + 1), TRACK_Y)
	var selected_start := Vector2(_step_x(_lower_visual.step), TRACK_Y)
	var selected_end := Vector2(_step_x(_upper_visual.step), TRACK_Y)
	var energy := maxf(_lower_visual.held + _lower_visual.pulse, _upper_visual.held + _upper_visual.pulse)
	draw_line(start, end, Color("383344"), TRACK_WIDTH)
	draw_line(selected_start, selected_end, Color(0.65, 0.53, 0.95, 0.1 * energy), TRACK_WIDTH + 6.0)
	draw_line(selected_start, selected_end, Color("a598ec").lerp(Color.WHITE, minf(0.35, energy * 0.2)), TRACK_WIDTH)
	for is_upper in [false, true]:
		_draw_handle(is_upper)

func _draw_handle(is_upper: bool) -> void:
	var value := upper if is_upper else lower
	var visual := _upper_visual if is_upper else _lower_visual
	var width := HANDLE_SIZE * (1.0 + visual.hover * 0.08 + visual.held * 0.08 + visual.pulse * 0.1)
	var height := HANDLE_SIZE * (1.0 + visual.hover * 0.08 + visual.held * 0.04 - visual.pulse * 0.08)
	var x := _step_x(visual.step)
	var y := TRACK_Y - height / 2.0 - visual.hover * 2.0 - visual.held * 3.0
	var rect := Rect2(x if is_upper else x - width, y, width, height)
	var color := Color("7760bb") if time_range or value > finite_steps else Rating.get_color_from_rating(visual.step, true)
	color = color.lightened(visual.hover * 0.1 + visual.pulse * 0.16)
	draw_rect(Rect2(rect.position + Vector2(0, 4), rect.size), Color(0, 0, 0, 0.3))
	draw_rect(rect, color)
	draw_rect(rect, Color.WHITE, false, 2.0)
	var caption := _caption(value)
	var font_size := 12 if time_range else 18
	var font := HANDLE_FONT if value <= finite_steps else get_theme_font("font", "Label")
	var text_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := rect.get_center().y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, Vector2(rect.get_center().x - text_width / 2, baseline), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			_keyboard_focus = false
			var on_lower := _handle_rect(false).has_point(event.position)
			var on_upper := _handle_rect(true).has_point(event.position)
			_upper_active = on_upper if on_lower or on_upper else absf(event.position.x - _step_x(upper)) < absf(event.position.x - _step_x(lower))
			_drag_offset = event.position.x - _step_x(upper if _upper_active else lower) if on_lower or on_upper else 0.0
			_previous_mouse_mode = Input.mouse_mode
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			_dragging = true
			_move_to_mouse(event.position.x)
		else:
			_end_drag()
			var visual := _upper_visual if _upper_active else _lower_visual
			visual.pulse = 0.65
		accept_event()
		set_process(true)
	elif event is InputEventMouseMotion:
		_hover_lower = _handle_rect(false).has_point(event.position)
		_hover_upper = _handle_rect(true).has_point(event.position)
		if _dragging:
			_move_to_mouse(event.position.x)
			accept_event()
		set_process(true)
	elif event is InputEventKey and event.pressed:
		_keyboard_focus = true
		var value := upper if _upper_active else lower
		match event.keycode:
			KEY_UP, KEY_DOWN, KEY_SPACE:
				_upper_active = not _upper_active
			KEY_LEFT:
				_set_active_value(value - 1)
			KEY_RIGHT:
				_set_active_value(value + 1)
			KEY_HOME:
				_set_active_value(0)
			KEY_END:
				_set_active_value(finite_steps + 1)
			_:
				return
		accept_event()
		set_process(true)

func _move_to_mouse(x: float) -> void:
	_set_active_value(roundi((x - _drag_offset - _step_x(0)) / _track_width() * (finite_steps + 1)))

func _set_active_value(value: int) -> void:
	var previous := upper if _upper_active else lower
	if _upper_active:
		upper = clampi(value, lower, finite_steps + 1)
	else:
		lower = clampi(value, 0, mini(upper, finite_steps))
	if previous != (upper if _upper_active else lower):
		var visual := _upper_visual if _upper_active else _lower_visual
		visual.pulse = 1.0
		changed.emit()
		set_process(true)
