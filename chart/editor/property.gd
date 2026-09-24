extends TabBar

const NOTE_TYPE_MOVE := 2
const NOTE_DIR_NONE := -1

@export var editor: ChartEditor
@export var note_tab: Control
@export var rail_tab: Control
@export var note_time_lineedit: LineEdit
@export var note_type_option: OptionButton
@export var note_length_lineedit: LineEdit
@export var note_animation_option: OptionButton
@export var note_hitsound_option: OptionButton
@export var note_dir_option: OptionButton
@export var point_position_slider: HSlider
@export var point_curve_slider: HSlider
@export var point_time_lineedit: LineEdit

var _syncing := false

func _ready() -> void:
	point_position_slider.min_value = 0.0
	point_position_slider.max_value = 1.0
	point_position_slider.step = 0.1
	_connect_signals()
	_refresh()

func _connect_signals() -> void:
	if editor != null:
		editor.selection_changed.connect(_refresh)
		editor.hitsounds_changed.connect(_refresh)

	note_time_lineedit.text_submitted.connect(_commit_note_time)
	note_time_lineedit.focus_exited.connect(_commit_current_note_time)
	note_length_lineedit.text_submitted.connect(_commit_note_length)
	note_length_lineedit.focus_exited.connect(_commit_current_note_length)
	note_type_option.item_selected.connect(_on_note_type_selected)
	note_hitsound_option.item_selected.connect(_on_note_hitsound_selected)
	note_dir_option.item_selected.connect(_on_note_dir_selected)
	point_position_slider.value_changed.connect(_on_point_position_changed)
	point_curve_slider.value_changed.connect(_on_point_curve_changed)
	point_time_lineedit.text_submitted.connect(_commit_point_time)
	point_time_lineedit.focus_exited.connect(_commit_current_point_time)

	note_animation_option.disabled = true
	if note_animation_option.item_count == 0:
		note_animation_option.add_item("Deferred", 0)

func _refresh() -> void:
	if editor == null:
		return

	_syncing = true
	var selection: ChartEditorSelection = editor.selection
	var note: Note = selection.selected_note
	var point: RailPoint = selection.get_point()
	_refresh_note_hitsound_options()

	note_tab.visible = note != null
	rail_tab.visible = selection.selected_rail != null

	if note != null:
		note_time_lineedit.text = str(note.time)
		note_length_lineedit.text = str(note.length)
		_select_option_by_id(note_type_option, int(note.type))
		_select_option_by_id(note_dir_option, int(note.dir))
		_select_option_by_id(note_hitsound_option, int(note.hitsound))
		note_dir_option.disabled = int(note.type) != NOTE_TYPE_MOVE
	else:
		note_time_lineedit.text = ""
		note_length_lineedit.text = ""
		note_dir_option.disabled = true

	if point != null:
		point_position_slider.value = point.x
		point_curve_slider.value = point.curve
		point_time_lineedit.text = str(point.time)
	elif selection.selected_rail != null and selection.selected_rail.points.size() > 0:
		var first_point: RailPoint = selection.selected_rail.points[0]
		point_position_slider.value = first_point.x
		point_curve_slider.value = first_point.curve
		point_time_lineedit.text = str(first_point.time)
	else:
		point_position_slider.value = 0.0
		point_curve_slider.value = 0.0
		point_time_lineedit.text = ""

	_syncing = false

func _commit_note_time(value: String) -> void:
	if _syncing or editor == null or editor.selection.selected_note == null:
		return

	if value.is_valid_int():
		var note: Note = editor.selection.selected_note
		var rail: Rail = editor.selection.selected_rail
		var next_time := EditorChartOps.clamp_note_time_to_rail(rail, note, value.to_int())
		if note.time == next_time:
			note_time_lineedit.text = str(note.time)
			return
		editor.push_history_snapshot()
		note.time = next_time
		rail.sort_notes()
		editor.selection.select_note(rail, note)
		editor.refresh_views()

func _commit_current_note_time() -> void:
	_commit_note_time(note_time_lineedit.text)

func _commit_note_length(value: String) -> void:
	if _syncing or editor == null or editor.selection.selected_note == null:
		return

	if value.is_valid_int():
		var note: Note = editor.selection.selected_note
		var next_length := EditorChartOps.clamp_note_length_to_rail(
			editor.selection.selected_rail,
			note,
			value.to_int()
		)
		if note.length == next_length:
			note_length_lineedit.text = str(note.length)
			return
		editor.push_history_snapshot()
		note.length = next_length
		editor.refresh_views()

func _commit_current_note_length() -> void:
	_commit_note_length(note_length_lineedit.text)

func _on_note_type_selected(index: int) -> void:
	if _syncing or editor == null or editor.selection.selected_note == null:
		return

	var new_type := int(note_type_option.get_item_id(index))
	if int(editor.selection.selected_note.type) == new_type:
		return
	editor.push_history_snapshot()
	editor.selection.selected_note.type = new_type as Note.NoteType
	if int(editor.selection.selected_note.type) != NOTE_TYPE_MOVE:
		editor.selection.selected_note.dir = NOTE_DIR_NONE as Note.Dir
	editor.refresh_views()

func _on_note_dir_selected(index: int) -> void:
	if _syncing or editor == null or editor.selection.selected_note == null:
		return

	var new_dir := int(note_dir_option.get_item_id(index))
	if int(editor.selection.selected_note.dir) == new_dir:
		return
	editor.push_history_snapshot()
	editor.selection.selected_note.dir = new_dir as Note.Dir
	editor.refresh_views()

func _on_note_hitsound_selected(index: int) -> void:
	if _syncing or editor == null or editor.selection.selected_note == null:
		return
	editor.set_selected_note_hitsound_id(note_hitsound_option.get_item_id(index))

func _on_point_position_changed(value: float) -> void:
	if _syncing or editor == null or not editor.selection.has_point():
		return

	if is_equal_approx(editor.selection.get_point().x, value):
		return
	editor.push_history_snapshot()
	editor.selection.get_point().x = value
	editor.refresh_views()

func _on_point_curve_changed(value: float) -> void:
	if _syncing or editor == null or not editor.selection.has_point():
		return

	if is_equal_approx(editor.selection.get_point().curve, value):
		return
	editor.push_history_snapshot()
	editor.selection.get_point().curve = value
	editor.refresh_views()

func _commit_point_time(value: String) -> void:
	if _syncing or editor == null or not editor.selection.has_point():
		return

	if value.is_valid_int():
		var point: RailPoint = editor.selection.get_point()
		var next_time := EditorChartOps.constrain_rail_point_time(
			editor.selection.selected_rail,
			point,
			value.to_int()
		)
		if point.time == next_time:
			point_time_lineedit.text = str(point.time)
			return
		editor.push_history_snapshot()
		point.time = next_time
		editor.selection.selected_rail.sort_points()
		editor.selection.selected_point_index = editor.selection.selected_rail.points.find(point)
		editor.refresh_views()

func _commit_current_point_time() -> void:
	_commit_point_time(point_time_lineedit.text)

func _select_option_by_id(option_button: OptionButton, item_id: int) -> void:
	var index := option_button.get_item_index(item_id)
	if index >= 0:
		option_button.select(index)

func _refresh_note_hitsound_options() -> void:
	note_hitsound_option.clear()
	note_hitsound_option.add_item("Default")
	note_hitsound_option.set_item_id(note_hitsound_option.item_count - 1, -1)
	for hitsound in editor.get_all_hitsounds():
		note_hitsound_option.add_item(hitsound.get_display_name(), hitsound.id)
