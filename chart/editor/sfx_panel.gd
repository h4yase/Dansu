extends TabBar
class_name EditorSFXPanel

@export var editor: ChartEditor
@export var hit_option: OptionButton
@export var move_option: OptionButton
@export var trace_option: OptionButton
@export var spike_option: OptionButton
@export var release_option: OptionButton
@export var add_sfx_button: Button
@export var list_container: VBoxContainer
@export var hitsound_template: EditorHitSoundRow
@export var file_dialog: FileDialog

var _syncing := false
func _ready() -> void:
	_connect_signals()
	_refresh()

func _connect_signals() -> void:
	if editor != null:
		editor.hitsounds_changed.connect(_refresh)
	hit_option.item_selected.connect(_on_default_selected.bind(Chart.DEFAULT_HITSOUND_HIT, hit_option))
	move_option.item_selected.connect(_on_default_selected.bind(Chart.DEFAULT_HITSOUND_MOVE, move_option))
	trace_option.item_selected.connect(_on_default_selected.bind(Chart.DEFAULT_HITSOUND_TRACE, trace_option))
	spike_option.item_selected.connect(_on_default_selected.bind(Chart.DEFAULT_HITSOUND_SPIKE, spike_option))
	release_option.item_selected.connect(_on_default_selected.bind(Chart.DEFAULT_HITSOUND_LONGNOTE_RELEASE, release_option))
	add_sfx_button.pressed.connect(_open_file_dialog)
	if file_dialog != null:
		file_dialog.file_selected.connect(_on_file_selected)

func _refresh() -> void:
	if editor == null:
		return
	_syncing = true
	_populate_default_option(hit_option, Chart.DEFAULT_HITSOUND_HIT)
	_populate_default_option(move_option, Chart.DEFAULT_HITSOUND_MOVE)
	_populate_default_option(trace_option, Chart.DEFAULT_HITSOUND_TRACE)
	_populate_default_option(spike_option, Chart.DEFAULT_HITSOUND_SPIKE)
	_populate_default_option(release_option, Chart.DEFAULT_HITSOUND_LONGNOTE_RELEASE)
	_refresh_custom_hitsounds()
	_syncing = false

func _populate_default_option(option_button: OptionButton, slot: int) -> void:
	option_button.clear()
	option_button.add_item("None")
	option_button.set_item_id(option_button.item_count - 1, -1)
	for hitsound in editor.get_all_hitsounds():
		option_button.add_item(hitsound.get_display_name(), hitsound.id)
	var target_id := editor.get_default_hitsound_id(slot)
	var index := option_button.get_item_index(target_id)
	option_button.select(index if index >= 0 else 0)

func _refresh_custom_hitsounds() -> void:
	if hitsound_template != null:
		hitsound_template.visible = false
	for child in list_container.get_children():
		if child != hitsound_template and child is PanelContainer:
			child.queue_free()

	for hitsound in editor.get_custom_hitsounds():
		var row := hitsound_template.duplicate() as EditorHitSoundRow
		row.visible = true
		row.file_name_label.text = hitsound.get_display_name()
		row.remove_button.pressed.connect(_on_remove_hitsound_pressed.bind(hitsound.id))
		list_container.add_child(row)
		UIFocusUtils.disable_focus_recursive(row)

func _on_default_selected(index: int, slot: int, option_button: OptionButton) -> void:
	if _syncing or editor == null:
		return
	editor.set_default_hitsound_id(slot, option_button.get_item_id(index))

func _open_file_dialog() -> void:
	if file_dialog != null:
		file_dialog.popup_centered_ratio(0.6)

func _on_file_selected(path: String) -> void:
	if editor != null:
		editor.add_custom_hitsound_from_file(path)

func _on_remove_hitsound_pressed(hitsound_id: int) -> void:
	if editor != null:
		editor.remove_custom_hitsound(hitsound_id)
