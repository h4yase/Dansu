extends Control
class_name SettingsNumber

signal value_changed(value: float)

var caption := ""
var hint := ""
var min_value := 0.0
var max_value := 100.0
var step := 1.0
var unit := ""
var zero_text := ""
var minimum_positive := 0.0
var value := 0.0
var _editing := false
var _edit_text := ""
var _select_all := false
var _caret := 0
var _hover := 0.0
var _pulse := 0.0
var _over := false

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): _over = true; set_process(true))
	mouse_exited.connect(func(): _over = false; set_process(true))
	focus_entered.connect(func(): set_process(true))
	focus_exited.connect(commit_edit)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			commit_edit()
			_over = false
		set_process(is_visible_in_tree())
	)
	resized.connect(queue_redraw)

func set_value(next_value: float) -> void:
	value = _sanitize(next_value)
	queue_redraw()

func _sanitize(next_value: float) -> float:
	next_value = snappedf(clampf(next_value, min_value, max_value), step)
	if next_value > 0.0 and next_value < minimum_positive:
		return minimum_positive
	return next_value

func _change_value(next_value: float) -> void:
	var previous := value
	set_value(next_value)
	if not is_equal_approx(previous, value):
		_pulse = 1.0
		value_changed.emit(value)
	set_process(true)

func display_text() -> String:
	if not zero_text.is_empty():
		if _editing and _edit_text.is_valid_float() and float(_edit_text) == 0.0:
			return zero_text
		if not _editing and value == 0.0:
			return zero_text
	if _editing:
		return _edit_text
	return _format(value) + (" " + unit if not unit.is_empty() else "")

func _format(number: float) -> String:
	return str(roundi(number)) if step >= 1.0 else str(snappedf(number, step))

func commit_edit() -> void:
	if not _editing:
		return
	_editing = false
	if _edit_text.is_valid_float() and is_finite(float(_edit_text)):
		_change_value(float(_edit_text))
	_select_all = false
	queue_redraw()

func _begin_edit() -> void:
	grab_focus()
	_editing = true
	_edit_text = _format(value)
	_caret = _edit_text.length()
	_select_all = true
	set_process(true)

func _process(delta: float) -> void:
	_hover = lerpf(_hover, 1.0 if _over or has_focus() else 0.0, 1.0 - exp(-16.0 * delta))
	_pulse = move_toward(_pulse, 0.0, delta * 5.0)
	queue_redraw()
	if not _editing and _hover < 0.001 and _pulse == 0.0:
		set_process(false)

func _field_rect() -> Rect2:
	return Rect2(size.x * 0.54, 15, size.x * 0.46 - 88, size.y - 30)

func _draw() -> void:
	if hint.is_empty():
		SettingsPaint.text(self, caption, Rect2(0, 0, size.x * 0.50, size.y), SettingsPaint.ROW_FONT_SIZE)
	else:
		SettingsPaint.text(self, caption, Rect2(0, 10, size.x * 0.50, 32), SettingsPaint.ROW_FONT_SIZE)
		SettingsPaint.text(self, hint, Rect2(0, 42, size.x * 0.50, 22), 13, Color(SettingsPaint.MUTED, 0.6))
	var rect := _field_rect()
	rect.position.y -= _hover
	var border := SettingsPaint.ACCENT if has_focus() else SettingsPaint.FIELD_BORDER.lerp(Color(SettingsPaint.ACCENT, 0.65), _hover)
	SettingsPaint.box(self, Rect2(rect.position, rect.size + Vector2(88, 0)), SettingsPaint.INPUT.lerp(SettingsPaint.HOVER, _hover * 0.55 + _pulse * 0.2), border, 6)
	if _editing and _select_all:
		SettingsPaint.box(self, rect.grow(-6), Color(SettingsPaint.ACCENT, 0.22), Color.TRANSPARENT, 4)
	SettingsPaint.text(self, display_text(), rect.grow(-8), SettingsPaint.ROW_FONT_SIZE, SettingsPaint.INK, true)
	if _editing and not _select_all and fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.55:
		var text_width := SettingsPaint.FONT.get_string_size(display_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, SettingsPaint.ROW_FONT_SIZE).x
		var before_width := SettingsPaint.FONT.get_string_size(_edit_text.left(_caret), HORIZONTAL_ALIGNMENT_LEFT, -1, SettingsPaint.ROW_FONT_SIZE).x
		var x := rect.get_center().x - text_width * 0.5 + before_width
		draw_line(Vector2(x, rect.position.y + 12), Vector2(x, rect.end.y - 12), SettingsPaint.ACCENT, 2.0)
	var step_color := Color(SettingsPaint.MUTED, 0.6).lerp(SettingsPaint.ACCENT, _hover)
	for direction in [-1, 1]:
		var x := size.x - (88 if direction < 0 else 44)
		draw_line(Vector2(x, rect.position.y + 10), Vector2(x, rect.end.y - 10), SettingsPaint.FIELD_BORDER, 1.0)
		var center := Vector2(x + 22, rect.get_center().y)
		draw_line(center - Vector2(5, 0), center + Vector2(5, 0), step_color, 2.0, true)
		if direction > 0:
			draw_line(center - Vector2(0, 5), center + Vector2(0, 5), step_color, 2.0, true)

func _insert(text: String) -> void:
	for character in text:
		if not character in "0123456789.-":
			return
	if _select_all:
		_edit_text = ""
		_caret = 0
		_select_all = false
	if _edit_text.length() + text.length() <= 12:
		_edit_text = _edit_text.left(_caret) + text + _edit_text.substr(_caret)
		_caret += text.length()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.x >= size.x - 88:
			commit_edit()
			grab_focus()
			var direction := -1.0 if event.position.x < size.x - 44 else 1.0
			var next_value := value + direction * step
			if minimum_positive > 0 and value == minimum_positive and direction < 0:
				next_value = 0.0
			_change_value(next_value)
		else:
			_begin_edit()
		accept_event()
	elif event is InputEventKey and event.pressed:
		if not _editing:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				_begin_edit()
				accept_event()
				return
			if event.unicode >= 48 and event.unicode <= 57:
				_begin_edit()
			else:
				return
		if event.ctrl_pressed or event.meta_pressed:
			match event.keycode:
				KEY_A: _select_all = true
				KEY_C: DisplayServer.clipboard_set(_edit_text)
				KEY_V: _insert(DisplayServer.clipboard_get().strip_edges())
				_: return
		else:
			match event.keycode:
				KEY_ENTER, KEY_KP_ENTER: commit_edit()
				KEY_ESCAPE:
					_editing = false
					queue_redraw()
				KEY_BACKSPACE, KEY_DELETE:
					if _select_all:
						_edit_text = ""
						_caret = 0
					elif event.keycode == KEY_BACKSPACE and _caret > 0:
						_edit_text = _edit_text.erase(_caret - 1, 1)
						_caret -= 1
					elif event.keycode == KEY_DELETE:
						_edit_text = _edit_text.erase(_caret, 1)
					_select_all = false
				KEY_LEFT: _caret = maxi(0, _caret - 1); _select_all = false
				KEY_RIGHT: _caret = mini(_edit_text.length(), _caret + 1); _select_all = false
				KEY_HOME: _caret = 0; _select_all = false
				KEY_END: _caret = _edit_text.length(); _select_all = false
				KEY_TAB: commit_edit(); return
				_:
					if event.unicode > 0:
						_insert(String.chr(event.unicode))
		accept_event()
		set_process(true)
