extends Window
class_name EditorUnsavedChangesDialog

signal save_requested
signal discard_requested

@export_multiline var message := "Save changes before leaving?"
@export var save_button_text := "Save and leave"
@export var discard_button_text := "Leave without saving"
@export var message_label: Label
@export var save_button: Button
@export var discard_button: Button
@export var cancel_button: Button


func _ready() -> void:
	message_label.text = message
	save_button.text = save_button_text
	discard_button.text = discard_button_text
	save_button.pressed.connect(_on_save_pressed)
	discard_button.pressed.connect(_on_discard_pressed)
	cancel_button.pressed.connect(hide)
	close_requested.connect(hide)


func open(save_enabled: bool = true) -> void:
	save_button.disabled = not save_enabled
	popup_centered()


func _on_save_pressed() -> void:
	hide()
	save_requested.emit()


func _on_discard_pressed() -> void:
	hide()
	discard_requested.emit()
