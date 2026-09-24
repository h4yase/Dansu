extends VBoxContainer
class_name SkinEditorSpriteItem

signal pressed(file_name: String)
signal drag_started(file_name: String)

@export var file_name_label: Label
@export var texture_rect: TextureRect

var file_name := ""
var _pressed := false
var _dragging := false

func setup(sprite_file_name: String, texture_value: Texture2D, is_selected: bool) -> void:
	file_name = sprite_file_name
	if file_name_label != null:
		file_name_label.text = sprite_file_name
	if texture_rect != null:
		texture_rect.texture = texture_value
	modulate = Color.WHITE if is_selected else Color(1.0, 1.0, 1.0, 0.78)
	scale = Vector2.ONE * (1.03 if is_selected else 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_dragging = false
		else:
			if _pressed and not _dragging:
				pressed.emit(file_name)
			_pressed = false
			_dragging = false
	elif event is InputEventMouseMotion and _pressed and not _dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_dragging = true
		drag_started.emit(file_name)
