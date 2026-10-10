extends Control
class_name SettingsChoice

signal item_selected(index: int)

var caption := ""
var items := PackedStringArray()
var item_ids := PackedInt32Array()
var selected := 0
var toggle := false
var _hover := 0.0
var _pulse := 0.0
var _over := false
var _switch := 0.0

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): _over = true; set_process(true))
	mouse_exited.connect(func(): _over = false; set_process(true))
	focus_entered.connect(func(): set_process(true))
	focus_exited.connect(func(): set_process(true))
	visibility_changed.connect(func(): _over = false; set_process(is_visible_in_tree()))
	resized.connect(queue_redraw)

func select_id(id: int) -> void:
	var index := item_ids.find(id)
	select(index if index >= 0 else 0)

func select(index: int) -> void:
	selected = clampi(index, 0, maxi(0, items.size() - 1))
	_switch = float(selected)
	queue_redraw()

func _change(direction: int) -> void:
	if items.is_empty():
		return
	selected = posmod(selected + direction, items.size())
	_pulse = 1.0
	item_selected.emit(selected)
	set_process(true)

func _process(delta: float) -> void:
	_hover = lerpf(_hover, 1.0 if _over or has_focus() else 0.0, 1.0 - exp(-16.0 * delta))
	_switch = lerpf(_switch, float(selected), 1.0 - exp(-22.0 * delta))
	_pulse = move_toward(_pulse, 0.0, delta * 5.0)
	queue_redraw()
	if _hover < 0.001 and _pulse == 0.0 and absf(_switch - selected) < 0.001:
		set_process(false)

func _draw() -> void:
	SettingsPaint.text(self, caption, Rect2(0, 0, size.x * 0.51, size.y), SettingsPaint.ROW_FONT_SIZE)
	var rect := Rect2(size.x * 0.54, 15 - _hover, size.x * 0.46, size.y - 30)
	if items.is_empty():
		return
	if toggle:
		var track := Rect2(rect.end - Vector2(52, rect.size.y * 0.5 + 12), Vector2(44, 24))
		var border := SettingsPaint.ACCENT if has_focus() else SettingsPaint.FIELD_BORDER
		SettingsPaint.box(self, track, SettingsPaint.TRACK.lerp(SettingsPaint.ACCENT, _switch), border, 12)
		draw_circle(track.position + Vector2(lerpf(12, 32, _switch), 12), 8, SettingsPaint.INK)
		SettingsPaint.text(self, items[selected], Rect2(rect.position, rect.size - Vector2(68, 0)), SettingsPaint.ROW_FONT_SIZE, SettingsPaint.INK if selected > 0 else SettingsPaint.MUTED, true)
	else:
		var border := SettingsPaint.ACCENT if has_focus() else SettingsPaint.FIELD_BORDER.lerp(Color(SettingsPaint.ACCENT, 0.65), _hover)
		SettingsPaint.box(self, rect, SettingsPaint.INPUT.lerp(SettingsPaint.HOVER, _hover * 0.55 + _pulse * 0.2), border, 6)
		SettingsPaint.text(self, items[selected], Rect2(rect.position + Vector2(30, -sin(_pulse * PI) * 2), rect.size - Vector2(60, 0)), SettingsPaint.ROW_FONT_SIZE, SettingsPaint.INK, true)
		var arrow_color := Color(SettingsPaint.MUTED, 0.55).lerp(SettingsPaint.ACCENT, _hover)
		for direction in [-1, 1]:
			var center := Vector2(rect.position.x + 16 if direction < 0 else rect.end.x - 16, rect.get_center().y)
			draw_polyline(PackedVector2Array([center - Vector2(direction * 3, 5), center + Vector2(direction * 3, 0), center - Vector2(direction * 3, -5)]), arrow_color, 2.0, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		_change(-1 if not toggle and event.position.x >= size.x * 0.54 and event.position.x < size.x * 0.54 + 30 else 1)
		accept_event()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: _change(-1)
			KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _change(1)
			_: return
		accept_event()
