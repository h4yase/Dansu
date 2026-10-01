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
@export var point_list: VBoxContainer

const POINT_SCENE := preload("res://scenes/chart/editor/ui/inspector/point.tscn")
var _point_rows: Array[EditorPointItem] = []
var _listed_rail: Rail

var _syncing := false

func _ready() -> void:
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

	note_animation_option.disabled = true
	if note_animation_option.item_count == 0:
		note_animation_option.add_item(GameText.text(GameText.Key.EDITOR_DEFERRED_ANIMATION), 0)

func _refresh() -> void:
	if editor == null:
		return

	_syncing = true
	var selection: ChartEditorSelection = editor.selection
	var note: Note = selection.selected_note
	_refresh_note_hitsound_options()

	note_tab.visible = note != null
	rail_tab.visible = selection.selected_rail != null and selection.selected_notes.is_empty()

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

	_refresh_points()
	_syncing = false

func _refresh_points() -> void:
	var rail := editor.selection.selected_rail if rail_tab.visible else null
	var rebuild := rail != _listed_rail
	if rail != null:
		rebuild = rebuild or _point_rows.size() != rail.points.size()
		for row in _point_rows:
			if not rail.points.has(row.point):
				rebuild = true
	if rebuild:
		for row in _point_rows:
			row.editor = null
			point_list.remove_child(row)
			row.queue_free()
		_point_rows.clear()
		_listed_rail = rail
		if rail != null:
			for point: RailPoint in rail.points:
				var row: EditorPointItem = POINT_SCENE.instantiate()
				row.editor = editor
				row.rail = rail
				row.point = point
				point_list.add_child(row)
				_point_rows.append(row)
	if rail == null:
		return
	for index in range(rail.points.size()):
		for row in _point_rows:
			if row.point == rail.points[index]:
				point_list.move_child(row, index)
				row.sync(index)
				break

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
	elif int(editor.selection.selected_note.dir) == NOTE_DIR_NONE:
		editor.selection.selected_note.dir = Note.Dir.LEFT
	editor.refresh_views()
	editor.selection.refresh()

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

func _select_option_by_id(option_button: OptionButton, item_id: int) -> void:
	var index := option_button.get_item_index(item_id)
	if index >= 0:
		option_button.select(index)

func _refresh_note_hitsound_options() -> void:
	note_hitsound_option.clear()
	note_hitsound_option.add_item(GameText.text(GameText.Key.EDITOR_DEFAULT))
	note_hitsound_option.set_item_id(note_hitsound_option.item_count - 1, -1)
	for hitsound in editor.get_all_hitsounds():
		note_hitsound_option.add_item(hitsound.get_display_name(), hitsound.id)
