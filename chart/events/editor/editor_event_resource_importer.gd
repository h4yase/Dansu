extends RefCounted
class_name EditorEventResourceImporter

signal imported(event: ChartEvent, frame: ChartEventFrame, kind: String, reference: String)

const SPRITE_FILTERS: Array[String] = ["*.png,*.jpg,*.jpeg,*.webp,*.svg ; Image Files"]

var _dialog: FileDialog
var _chart: Chart
var _kind := ""
var _event: ChartEvent
var _frame: ChartEventFrame

func setup(dialog: FileDialog) -> void:
	_dialog = dialog
	if _dialog != null:
		_dialog.file_selected.connect(_on_file_selected)

func open(chart: Chart, kind: String, event: ChartEvent, frame: ChartEventFrame) -> void:
	if chart == null or _dialog == null or not can_import(kind):
		return
	_chart = chart
	_kind = kind
	_event = event
	_frame = frame
	var target_directory := chart.folder_path.path_join(EventResourceRef.CHART_DIRECTORY_NAME)
	FileSystem.ensure_dir(target_directory)
	_dialog.filters = PackedStringArray(SPRITE_FILTERS)
	_dialog.current_dir = ProjectSettings.globalize_path(target_directory)
	_dialog.popup_centered_ratio(0.7)

func _on_file_selected(path: String) -> void:
	var reference := EventResourceRef.import_sprite(_chart, path) if _kind == "sprite" else ""
	var event := _event
	var frame := _frame
	var kind := _kind
	_clear()
	if not reference.is_empty():
		imported.emit(event, frame, kind, reference)

func _clear() -> void:
	_chart = null
	_kind = ""
	_event = null
	_frame = null

static func can_import(kind: String) -> bool:
	return kind == "sprite"

static func references(chart: Chart, kind: String) -> Array[String]:
	var result: Array[String] = []
	var extensions = EventResourceRef.SPRITE_EXTENSIONS if kind == "sprite" else PackedStringArray(["json"])
	if chart != null:
		var chart_path := chart.folder_path.path_join(EventResourceRef.CHART_DIRECTORY_NAME)
		if DirAccess.dir_exists_absolute(chart_path):
			for file_name in DirAccess.get_files_at(chart_path):
				if file_name.get_extension().to_lower() in extensions and EventResourceRef.is_valid(file_name):
					result.append(file_name)
	var builtin_path := EventResourceRef.BUILTIN_SPRITE_BASE_PATH if kind == "sprite" else EventResourceRef.BUILTIN_SKIN_BASE_PATH
	if DirAccess.dir_exists_absolute(builtin_path):
		for file_name in DirAccess.get_files_at(builtin_path):
			if file_name.get_extension().to_lower() in extensions:
				result.append(EventResourceRef.BUILTIN_PREFIX + file_name)
	result.sort()
	return result

static func open_folder(chart: Chart) -> void:
	if chart == null:
		return
	var path := chart.folder_path.path_join(EventResourceRef.CHART_DIRECTORY_NAME)
	FileSystem.ensure_dir(path)
	OS.shell_open(ProjectSettings.globalize_path(path))
