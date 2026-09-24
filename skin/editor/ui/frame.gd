extends TextureRect
class_name SkinEditorFrameItem

signal selected(index: int)
signal drag_started(index: int)
signal hovered(index: int)
signal released(index: int)

@export var frame_index_label: Label

var index := -1
var _pressed := false
var _dragging := false

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)

func setup(texture_value: Texture2D, frame_index: int, is_selected: bool, is_drop_target: bool = false, drop_after: bool = false) -> void:
	texture = texture_value
	index = frame_index
	if frame_index_label != null:
		frame_index_label.text = str(frame_index + 1)
		if is_drop_target:
			frame_index_label.text = "%d+" % (frame_index + 1) if drop_after else "+%d" % (frame_index + 1)
	if is_drop_target:
		modulate = Color(0.65, 1.0, 0.72, 1.0)
		scale = Vector2.ONE * 1.08
	else:
		modulate = Color.WHITE if is_selected else Color(1.0, 1.0, 1.0, 0.65)
		scale = Vector2.ONE * (1.06 if is_selected else 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_dragging = false
			selected.emit(index)
		else:
			released.emit(index)
			_pressed = false
			_dragging = false
	elif event is InputEventMouseMotion and _pressed and not _dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_dragging = true
		drag_started.emit(index)

func _on_mouse_entered() -> void:
	hovered.emit(index)
