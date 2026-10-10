extends Control
class_name SettingsScroll

signal wheel_scrolled(amount: float)
signal moved(offset: float)

const EDGE_SPACE := 32.0

var content: Control
var offset := 0.0
var target := 0.0
var _speed := 20.0
var _dragging_bar := false
var _bar_drag_offset := 0.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	content = Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)
	resized.connect(func(): scroll_to(target); queue_redraw())
	visibility_changed.connect(func(): _dragging_bar = false; set_process(is_visible_in_tree()))

func max_offset() -> float:
	return maxf(0.0, content.size.y - size.y)

func scroll_to(next_offset: float, fast: bool = false) -> void:
	target = clampf(next_offset, 0.0, max_offset())
	_speed = 32.0 if fast else 20.0
	set_process(true)

func scroll_wheel(amount: float) -> void:
	wheel_scrolled.emit(amount)
	scroll_to(target + amount * 90.0)

func reset() -> void:
	offset = 0.0
	target = 0.0
	content.position.y = 0.0
	moved.emit(offset)
	queue_redraw()

func _process(delta: float) -> void:
	offset = lerpf(offset, target, 1.0 - exp(-_speed * delta))
	if absf(offset - target) < 0.05:
		offset = target
	content.position.y = -offset
	moved.emit(offset)
	queue_redraw()
	if offset == target:
		set_process(false)

func _bar_rect() -> Rect2:
	var track_height := maxf(1.0, size.y - EDGE_SPACE * 2)
	var height := minf(track_height, maxf(40.0, track_height * size.y / maxf(content.size.y, 1.0)))
	var y := EDGE_SPACE + offset / maxf(max_offset(), 1.0) * (track_height - height)
	return Rect2(size.x - 7, y, 4, height)

func _draw() -> void:
	if max_offset() <= 0:
		return
	draw_line(Vector2(size.x - 5, EDGE_SPACE), Vector2(size.x - 5, size.y - EDGE_SPACE), SettingsPaint.TRACK, 2)
	SettingsPaint.box(self, _bar_rect(), SettingsPaint.ACCENT, Color.TRANSPARENT, 2)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.x > size.x - 20:
			_dragging_bar = true
			_bar_drag_offset = event.position.y - _bar_rect().position.y if _bar_rect().grow(8).has_point(event.position) else _bar_rect().size.y * 0.5
			_move_bar(event.position.y)
		elif not event.pressed:
			_dragging_bar = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging_bar:
		_move_bar(event.position.y)
		accept_event()

func _move_bar(y: float) -> void:
	scroll_to((y - EDGE_SPACE - _bar_drag_offset) / maxf(1.0, size.y - EDGE_SPACE * 2 - _bar_rect().size.y) * max_offset(), true)
