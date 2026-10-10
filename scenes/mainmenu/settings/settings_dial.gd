extends Control
class_name SettingsDial

signal value_changed(value: float)

var caption := ""
var large := false
var value := 1.0
var _shown_value := 1.0
var _hover := 0.0
var _pulse := 0.0
var _over := false
var _dragging := false
var _drag_value := 1.0

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	mouse_entered.connect(func(): _over = true; set_process(true))
	mouse_exited.connect(func(): _over = false; set_process(true))
	focus_entered.connect(func(): set_process(true))
	focus_exited.connect(func(): _dragging = false)
	visibility_changed.connect(func():
		_dragging = false
		_over = false
		set_process(is_visible_in_tree())
	)
	resized.connect(queue_redraw)

func set_value(next_value: float) -> void:
	value = clampf(next_value, 0.0, 1.0)
	_shown_value = value
	queue_redraw()

func _change_value(next_value: float) -> void:
	next_value = snappedf(clampf(next_value, 0.0, 1.0), 0.01)
	if is_equal_approx(value, next_value):
		return
	value = next_value
	_pulse = 1.0
	value_changed.emit(value)
	set_process(true)

func _process(delta: float) -> void:
	_shown_value = lerpf(_shown_value, value, 1.0 - exp(-22.0 * delta))
	_hover = lerpf(_hover, 1.0 if _over or has_focus() or _dragging else 0.0, 1.0 - exp(-14.0 * delta))
	_pulse = move_toward(_pulse, 0.0, delta * 4.0)
	queue_redraw()
	if not _dragging and _hover < 0.001 and _pulse == 0.0 and absf(_shown_value - value) < 0.001:
		set_process(false)

func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.45)
	var radius := minf(size.x * 0.4, size.y * 0.34) + _hover * 2.0 + sin(_pulse * PI) * 2.5
	var start := PI * 0.75
	var finish := start + PI * 1.5 * _shown_value
	draw_circle(center + Vector2(0, 5), radius - 8, Color(0.0, 0.0, 0.0, 0.18))
	draw_circle(center, radius - 10, SettingsPaint.SURFACE)
	draw_arc(center, radius + 7, start, PI * 2.25, 80, SettingsPaint.BORDER, 1.0, true)
	draw_arc(center, radius, start, PI * 2.25, 80, SettingsPaint.TRACK, 7.0, true)
	if _shown_value > 0.001:
		draw_arc(center, radius, start, finish, 80, Color(SettingsPaint.ACCENT, 0.12 + _hover * 0.07), 17.0, true)
		draw_arc(center, radius, start, finish, 80, SettingsPaint.ACCENT, 7.0, true)
	for tick in range(31):
		var angle := start + tick * PI * 1.5 / 30
		var point := center + Vector2.from_angle(angle) * (radius + 14)
		draw_circle(point, 1.2, SettingsPaint.MUTED if tick / 30.0 <= _shown_value else SettingsPaint.BORDER)
	var tip := center + Vector2.from_angle(finish) * radius
	draw_circle(tip, 6 + _hover, SettingsPaint.INK)
	SettingsPaint.text(self, caption, Rect2(center - Vector2(radius - 10, 29), Vector2((radius - 10) * 2, 30)), 20 if large else 16, SettingsPaint.MUTED, true, SettingsPaint.TITLE_FONT)
	SettingsPaint.text(self, "%d" % roundi(value * 100), Rect2(center - Vector2(radius - 4, -3), Vector2((radius - 4) * 2, 50)), 38 if large else 28, SettingsPaint.INK, true, SettingsPaint.TITLE_FONT)
	if has_focus():
		draw_arc(center, radius + 21, start, PI * 2.25, 80, SettingsPaint.ACCENT, 1.0, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			grab_focus()
			_drag_value = value
		accept_event()
		set_process(true)
	elif event is InputEventMouseMotion and _dragging:
		_drag_value = clampf(_drag_value - event.relative.y / 180.0 + event.relative.x / 420.0, 0.0, 1.0)
		_change_value(_drag_value)
		accept_event()
	elif event is InputEventKey and event.pressed:
		var amount := 0.05 if event.shift_pressed else 0.01
		match event.keycode:
			KEY_LEFT, KEY_DOWN: _change_value(value - amount)
			KEY_RIGHT, KEY_UP: _change_value(value + amount)
			KEY_HOME: _change_value(0.0)
			KEY_END: _change_value(1.0)
			_: return
		accept_event()
