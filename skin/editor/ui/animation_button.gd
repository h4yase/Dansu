extends Button
class_name SkinEditorAnimationButton

signal selected(index: int)
signal name_changed(index: int, value: String)
signal remove_requested(index: int)

@export var animation_name: LineEdit
@export var first_frame_texture: TextureRect
@export var remove_button: Button

var index := -1

func _ready() -> void:
	toggle_mode = true
	pressed.connect(_on_pressed)
	if animation_name != null:
		animation_name.text_changed.connect(_on_name_changed)
	if remove_button != null:
		remove_button.pressed.connect(_on_remove_pressed)

func setup(animation, animation_index: int, is_selected: bool) -> void:
	index = animation_index
	button_pressed = is_selected
	if animation_name != null:
		animation_name.text = animation.name if animation != null else ""
	if first_frame_texture != null:
		first_frame_texture.texture = null
		if animation != null and not animation.frames.is_empty():
			first_frame_texture.texture = animation.frames[0]
	modulate = Color.WHITE if is_selected else Color(1.0, 1.0, 1.0, 0.72)

func _on_pressed() -> void:
	selected.emit(index)

func _on_name_changed(value: String) -> void:
	name_changed.emit(index, value)

func _on_remove_pressed() -> void:
	remove_requested.emit(index)
