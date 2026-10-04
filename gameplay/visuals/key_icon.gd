extends Control
class_name GameplayKeyIcon

enum Shape { SQUARE, LEFT, RIGHT }

@export var shape := Shape.SQUARE

var tint := Color.WHITE:
	set(value):
		if tint == value:
			return
		tint = value
		queue_redraw()

var _pressed := false
var _points := PackedVector2Array()
var _outline := PackedVector2Array()
var _tween: Tween
var _press_amount := 0.0:
	set(value):
		_press_amount = value
		scale = Vector2.ONE * (1.0 - value * 0.10)
		rotation = -value * 0.10
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	var corners := PackedVector2Array()
	match shape:
		Shape.SQUARE:
			corners = PackedVector2Array([Vector2(8, 8), Vector2(56, 8), Vector2(56, 56), Vector2(8, 56)])
		Shape.LEFT:
			corners = PackedVector2Array([Vector2(7, 32), Vector2(55, 7), Vector2(55, 57)])
		Shape.RIGHT:
			corners = PackedVector2Array([Vector2(9, 7), Vector2(57, 32), Vector2(9, 57)])
	var radius := 9.0 if shape == Shape.SQUARE else 6.0
	for index in range(corners.size()):
		var corner := corners[index]
		var from := corner.move_toward(corners[(index + corners.size() - 1) % corners.size()], radius)
		var to := corner.move_toward(corners[(index + 1) % corners.size()], radius)
		for step in range(9):
			var progress := float(step) / 8.0
			_points.append(from.lerp(corner, progress).lerp(corner.lerp(to, progress), progress))
	_outline = _points.duplicate()
	_outline.append(_points[0])


func set_pressed(pressed: bool) -> void:
	if _pressed == pressed:
		return
	_pressed = pressed
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if pressed:
		# Keep a tap visible even when its press and release arrive in one frame.
		_press_amount = maxf(_press_amount, 0.35)
		_tween.tween_property(self, "_press_amount", 1.0, 0.07)
	else:
		_tween.tween_interval(0.035)
		_tween.tween_property(self, "_press_amount", 0.0, 0.14)


func reset() -> void:
	if _tween != null:
		_tween.kill()
	_pressed = false
	_press_amount = 0.0


func _draw() -> void:
	if _points.is_empty():
		return
	var fill := Color(tint.r, tint.g, tint.b, _press_amount * 0.26)
	var outline_color := Color(tint.r, tint.g, tint.b, 0.72 + _press_amount * 0.23)
	if _press_amount > 0.0:
		draw_colored_polygon(_points, fill)
	draw_polyline(_outline, outline_color, 2.5, true)
