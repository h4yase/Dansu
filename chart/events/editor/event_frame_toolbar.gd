extends HBoxContainer
class_name EditorEventFrameToolbar

@export var selector: OptionButton
@export var add_button: Button
@export var duplicate_button: Button
@export var remove_button: Button

var _selection_callback: Callable
var _add_callback: Callable
var _duplicate_callback: Callable
var _remove_callback: Callable


func _ready() -> void:
	selector.item_selected.connect(_on_item_selected)
	add_button.pressed.connect(func() -> void: _add_callback.call())
	duplicate_button.pressed.connect(func() -> void: _duplicate_callback.call())
	remove_button.pressed.connect(func() -> void: _remove_callback.call())


func setup(
		frames: Array,
		selected_frame_index: int,
		selection_callback: Callable,
		add_callback: Callable,
		duplicate_callback: Callable,
		remove_callback: Callable
) -> void:
	_selection_callback = selection_callback
	_add_callback = add_callback
	_duplicate_callback = duplicate_callback
	_remove_callback = remove_callback
	selector.add_item("No frame selected", -1)
	for index in range(frames.size()):
		selector.add_item("%02d  +%d ms" % [index + 1, int(frames[index].time)], index)
	selector.select(selected_frame_index + 1)
	var has_selection := selected_frame_index >= 0 and selected_frame_index < frames.size()
	duplicate_button.disabled = not has_selection
	remove_button.disabled = not has_selection


func _on_item_selected(index: int) -> void:
	if _selection_callback.is_valid():
		_selection_callback.call(selector.get_item_id(index))
