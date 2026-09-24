extends VBoxContainer
class_name EditorEventInspectorItem

@export var title_label: Label
@export var badge_label: Label
@export var separator: Control
@export var separator_label: Label
@export var field_row: HBoxContainer
@export var field_label: Label
@export var line_edit: LineEdit
@export var spin_box: SpinBox
@export var check_box: CheckBox
@export var color_picker: ColorPickerButton
@export var option_button: OptionButton
@export var import_button: Button
@export var action_button: Button


func setup_title(text_value: String) -> void:
	title_label.text = text_value
	title_label.visible = true


func setup_badge(text_value: String, color: Color) -> void:
	badge_label.text = text_value
	badge_label.add_theme_color_override("font_color", color)
	badge_label.visible = true


func setup_separator(text_value: String) -> void:
	separator_label.text = text_value
	separator.visible = true


func setup_line(label_text: String, value: String, callback: Callable) -> void:
	_show_field(label_text, line_edit)
	line_edit.text = value
	line_edit.text_submitted.connect(func(text: String) -> void: callback.call(text))
	line_edit.focus_exited.connect(func() -> void: callback.call(line_edit.text))


func setup_number(
		label_text: String,
		value: float,
		min_value: float,
		max_value: float,
		step: float,
		callback: Callable
) -> void:
	_show_field(label_text, spin_box)
	spin_box.min_value = min_value
	spin_box.max_value = max_value
	spin_box.step = step
	spin_box.value = value
	spin_box.value_changed.connect(func(next_value: float) -> void: callback.call(next_value))


func setup_check(label_text: String, value: bool, callback: Callable) -> void:
	_show_field(label_text, check_box)
	check_box.button_pressed = value
	check_box.toggled.connect(func(enabled: bool) -> void: callback.call(enabled))


func setup_color(label_text: String, value: Color, callback: Callable) -> void:
	_show_field(label_text, color_picker)
	color_picker.color = value
	color_picker.color_changed.connect(func(next_color: Color) -> void: callback.call(next_color))


func setup_option(
		label_text: String,
		items: Array[String],
		selected_index: int,
		callback: Callable,
		import_callback: Callable = Callable()
) -> void:
	_show_field(label_text, option_button)
	for item_text in items:
		option_button.add_item(item_text)
	option_button.select(clampi(selected_index, 0, maxi(0, items.size() - 1)))
	option_button.item_selected.connect(func(index: int) -> void: callback.call(index))
	if import_callback.is_valid():
		import_button.visible = true
		import_button.pressed.connect(func() -> void: import_callback.call())


func setup_button(text_value: String, callback: Callable, destructive: bool = false) -> void:
	action_button.text = text_value
	action_button.visible = true
	if destructive:
		action_button.add_theme_color_override("font_color", Color("ff8992"))
	action_button.pressed.connect(func() -> void: callback.call())


func _show_field(label_text: String, control: Control) -> void:
	field_label.text = label_text
	field_row.visible = true
	control.visible = true
