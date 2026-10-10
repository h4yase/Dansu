extends Control
class_name SettingsButton

signal pressed

const BOOKMARK := preload("res://resources/textures/settings/bookmark.svg")

var caption := ""
var row_title := ""
var icon: Texture2D
var bookmark := false
var selected := false
var _hover := 0.0
var _press := 0.0
var _held := false
var _over := false

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): _over = true; set_process(true))
	mouse_exited.connect(func(): _over = false; set_process(true))
	focus_entered.connect(func(): set_process(true))
	focus_exited.connect(func(): _held = false; set_process(true))
	visibility_changed.connect(func():
		_held = false
		_over = false
		set_process(is_visible_in_tree())
	)
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	_hover = lerpf(_hover, 1.0 if _over or has_focus() else 0.0, 1.0 - exp(-16.0 * delta))
	_press = lerpf(_press, 1.0 if _held else 0.0, 1.0 - exp(-24.0 * delta))
	queue_redraw()
	if not _held and _hover < 0.001 and _press < 0.001:
		set_process(false)

func _draw() -> void:
	var shift := Vector2(_hover * 6.0 if bookmark else 0.0, -_hover * 2.0 + _press * 4.0)
	if not row_title.is_empty():
		SettingsPaint.text(self, row_title, Rect2(0, 0, size.x * 0.51, size.y), SettingsPaint.ROW_FONT_SIZE)
		var width := clampf(SettingsPaint.FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, SettingsPaint.ROW_FONT_SIZE).x + 36, 86, size.x * 0.46)
		var key_rect := Rect2(size.x * 0.77 - width * 0.5, 15 + shift.y, width, size.y - 30)
		var fill := SettingsPaint.INPUT.lerp(SettingsPaint.HOVER, _hover * 0.55 + _press * 0.25)
		var border := SettingsPaint.ACCENT if has_focus() else SettingsPaint.FIELD_BORDER.lerp(Color(SettingsPaint.ACCENT, 0.65), _hover)
		SettingsPaint.box(self, key_rect, fill, border, 6)
		draw_line(key_rect.position + Vector2(6, key_rect.size.y - 3), key_rect.end - Vector2(6, 3), Color(SettingsPaint.BORDER, 0.35), 1.0)
		SettingsPaint.text(self, caption, key_rect.grow(-10), SettingsPaint.ROW_FONT_SIZE, SettingsPaint.INK, true)
		return
	var rect := Rect2(shift + Vector2(2, 2), size - Vector2(4, 4))
	var color := SettingsPaint.SELECTED if selected else SettingsPaint.SURFACE
	color = color.lerp(SettingsPaint.HOVER, _hover * 0.5)
	if bookmark:
		draw_texture_rect(BOOKMARK, rect, false, Color.WHITE if selected else SettingsPaint.MUTED)
		if selected:
			draw_line(rect.position + Vector2(3, 12), rect.position + Vector2(3, rect.size.y - 12), SettingsPaint.ACCENT, 3.0)
	else:
		SettingsPaint.box(self, rect, color, SettingsPaint.ACCENT if has_focus() else SettingsPaint.BORDER)
	var text_rect := rect.grow(-14.0)
	if icon != null:
		var icon_rect := Rect2(rect.position + Vector2(16, (rect.size.y - 24) * 0.5), Vector2(24, 24))
		if caption.is_empty():
			icon_rect.position.x = rect.get_center().x - 12
		draw_texture_rect(icon, icon_rect, false, SettingsPaint.INK)
		text_rect.position.x += 34
		text_rect.size.x -= 34
	SettingsPaint.text(self, caption, text_rect, 17 if bookmark else 20, SettingsPaint.INK, not bookmark)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			_held = true
		elif _held:
			_held = false
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				pressed.emit()
		accept_event()
		set_process(true)
	elif event is InputEventKey and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if event.pressed and not event.echo:
			_held = true
		elif not event.pressed and _held:
			_held = false
			pressed.emit()
		accept_event()
		set_process(true)
