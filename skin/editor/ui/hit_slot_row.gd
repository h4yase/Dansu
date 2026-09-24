extends HBoxContainer
class_name SkinHitSlotRow

signal option_selected(index: int)
signal remove_requested

@export var label: Label
@export var option_button: OptionButton
@export var remove_button: Button


func _ready() -> void:
	option_button.item_selected.connect(func(index: int) -> void: option_selected.emit(index))
	remove_button.pressed.connect(func() -> void: remove_requested.emit())


func setup(label_text: String) -> void:
	label.text = label_text
