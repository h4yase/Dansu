extends Node
class_name ChartManager

signal progress_changed(ratio: float)
signal loading_finished()
signal database_sync_finished(success: bool)
signal chart_update(chart_set)
signal editor_chart_update(chart_set)
signal chart_selected(chart: Chart)
signal chartset_selected(chart_set: ChartSet)

const SONG_PATH := FileSystem.official_chart_path

var selected_chart: Chart = null
var selected_chartset: ChartSet = null
var chartsets: Array[ChartSet] = []
var editor_chartsets: Array[ChartSet] = []
var parsed_chart: ParsedChart = null

var chartsets_by_db_id: Dictionary = {}
var charts_by_db_id: Dictionary = {}
var chartsets_by_uuid: Dictionary = {}
var charts_by_uuid: Dictionary = {}

var _database = null
var _scanner := ChartLibraryScanner.new()


func _exit_tree() -> void:
	_scanner.stop()


func parse_selected_chart() -> bool:
	if selected_chart == null:
		Notification.notice("no chart selected", Notification.Type.WARNING)
		return false
	if not validate_chart_file(selected_chart):
		Notification.notice("chart file is missing", Notification.Type.WARNING)
		parsed_chart = null
		return false

	selected_chart.filehash = FileAccess.get_sha256(selected_chart.file_path)
	var result := Parser.new().parse_object(selected_chart)
	if not result.success:
		selected_chart.availability = Chart.Availability.INVALID
		parsed_chart = null
		return false

	selected_chart.availability = Chart.Availability.AVAILABLE
	parsed_chart = result.parsed_chart
	return true


func ensure_parsed_chart() -> ParsedChart:
	if parsed_chart == null or parsed_chart.chart != selected_chart:
		parsed_chart = ParsedChart.new(selected_chart)
	return parsed_chart


func select_chart(chart: Chart) -> void:
	if selected_chart != chart:
		parsed_chart = null
	selected_chart = chart
	if chart != null and chart.online_metadata.is_empty():
		validate_chart_file(chart)
	chart_selected.emit(chart)


func select_chartset(chartset: ChartSet) -> void:
	selected_chartset = chartset
	chartset_selected.emit(chartset)


func validate_chart_file(chart: Chart) -> bool:
	if chart == null:
		return false

	var previous := chart.availability
	var exists := FileAccess.file_exists(chart.file_path)
	chart.availability = Chart.Availability.AVAILABLE if exists else Chart.Availability.MISSING

	if _database != null and chart.db_id > 0:
		if not exists or previous == Chart.Availability.MISSING:
			if not _database.set_chart_present(chart.db_id, exists):
				push_warning("[database] failed to update chart presence: %s" % _database.get_last_error_message())
	return exists


func make_unique_chartset_folder_name(preferred_name: String = "new_chartset") -> String:
	var base_name := preferred_name.strip_edges().validate_filename()
	if base_name.is_empty():
		base_name = "new_chartset"

	var candidate := base_name
	var suffix := 2
	while _chartset_folder_exists(candidate):
		candidate = "%s_%d" % [base_name, suffix]
		suffix += 1
	return candidate


func register_saved_chart(chart: Chart) -> bool:
	if chart == null or chart.chart_set == null:
		return false

	if not _index_saved_chart(chart, true):
		return false
	if not chartsets.has(chart.chart_set):
		chartsets.append(chart.chart_set)
	if not chart.chart_set.charts.has(chart):
		chart.chart_set.charts.append(chart)

	select_chartset(chart.chart_set)
	select_chart(chart)
	_emit_update()
	return true


func register_saved_editor_chart(chart: Chart) -> bool:
	if chart == null or chart.chart_set == null:
		return false
	if not FileAccess.file_exists(chart.file_path):
		return false

	chart.storage_root = FileSystem.editor_chart_path
	chart.db_id = -1
	chart.chart_set.db_id = -1
	chart.availability = Chart.Availability.AVAILABLE
	chart.file_modified_time = int(FileAccess.get_modified_time(chart.file_path))
	chart.file_size = _get_file_size(chart.file_path)
	chart.filehash = FileAccess.get_sha256(chart.file_path)

	if not editor_chartsets.has(chart.chart_set):
		editor_chartsets.append(chart.chart_set)
	if not chart.chart_set.charts.has(chart):
		chart.chart_set.charts.append(chart)

	select_chartset(chart.chart_set)
	select_chart(chart)
	editor_chart_update.emit(editor_chartsets)
	return true


func reload_editor_library() -> void:
	FileSystem.ensure_dir(FileSystem.editor_chart_path)
	editor_chartsets.clear()
	var parser := Parser.new()

	var folder_names := DirAccess.get_directories_at(FileSystem.editor_chart_path)
	folder_names.sort()
	for folder_name in folder_names:
		var folder_path := FileSystem.editor_chart_path.path_join(folder_name)
		var file_names := DirAccess.get_files_at(folder_path)
		file_names.sort()

		var chart_set := ChartSet.new()
		chart_set.folder_name = folder_name
		for file_name in file_names:
			if not file_name.ends_with(Config.FILE_EXTENSION):
				continue

			var parsed_set := ChartSet.new()
			parsed_set.folder_name = folder_name
			var chart := Chart.new()
			chart.storage_root = FileSystem.editor_chart_path
			chart.folder_name = folder_name
			chart.file_name = file_name
			chart.chart_set = parsed_set
			if not Parser.parse_meta(chart):
				push_warning("[editor charts] invalid chart metadata: %s" % chart.file_path)
				continue

			if chart_set.uuid.is_empty():
				chart_set.uuid = parsed_set.uuid
			elif not parsed_set.uuid.is_empty() and parsed_set.uuid != chart_set.uuid:
				push_warning("[editor charts] conflicting chartset UUID: %s" % chart.file_path)
				continue

			chart.chart_set = chart_set
			chart.db_id = -1
			chart.availability = Chart.Availability.AVAILABLE
			var parse_result := parser.parse_object(chart)
			if parse_result.success and parse_result.parsed_chart != null:
				chart.rating = Rating.calculate_rating(parse_result.parsed_chart)
				chart.rating_calculated = true
			else:
				push_warning("[editor charts] failed to calculate rating: %s" % chart.file_path)
			chart.file_modified_time = int(FileAccess.get_modified_time(chart.file_path))
			chart.file_size = _get_file_size(chart.file_path)
			chart_set.charts.append(chart)

		if chart_set.charts.is_empty():
			continue
		if chart_set.uuid.is_empty():
			chart_set.build_uuid()
		editor_chartsets.append(chart_set)

	editor_chart_update.emit(editor_chartsets)


class RatingRecalculation extends RefCounted:
	var total: int = 0
	var updated: int = 0
	var failed: int = 0

func recalculate_all_ratings() -> RatingRecalculation:
	var result := RatingRecalculation.new()
	var parser := Parser.new()

	for chart_set: ChartSet in chartsets:
		if chart_set == null:
			continue
		for chart: Chart in chart_set.charts:
			if chart == null:
				continue
			result.total += 1

			var parse_result := parser.parse_object(chart)
			if not parse_result.success or parse_result.parsed_chart == null:
				result.failed += 1
				continue

			var parsed: ParsedChart = parse_result.parsed_chart
			chart.rating = Rating.calculate_rating(parsed)
			chart.rating_calculated = true
			chart.build_search_string()
			if not _index_saved_chart(chart):
				result.failed += 1
				continue
			result.updated += 1

	if result.updated > 0:
		_emit_update()

	return result


func _load(_is_reload: bool) -> void:
	var mounted_dlcs := DlcPackLoader.mount_installed()
	if mounted_dlcs > 0:
		print("[dlc] mounted %d content packs" % mounted_dlcs)
	reload_editor_library()
	_database = DB.get("connection") if DB != null else null
	if _database == null:
		push_error("[database] DansuDB is unavailable")
		call_deferred("_emit_loading_failure")
		return
	if not _database.prepare_rating_cache(Rating.CACHE_VERSION):
		push_error("[database] failed to prepare rating cache: %s" % _database.get_last_error_message())
		call_deferred("_emit_loading_failure")
		return

	_refresh_library_from_database(false)
	_emit_initial_ready()
	_start_background_sync()


func _refresh_library_from_database(filesystem_validated: bool) -> bool:
	if _database == null:
		return false

	var previous_chart_id := selected_chart.db_id if selected_chart != null else -1
	var previous_set_id := selected_chartset.db_id if selected_chartset != null else -1
	var loaded_chartsets: Array = _database.load_chart_library(
		_get_or_create_chartset,
		_get_or_create_chart,
		_create_timing,
		true,
		filesystem_validated
	)
	if _database.get_last_error_code() != 0:
		push_error("[database] failed to load chart library: %s" % _database.get_last_error_message())
		return false

	var next_chartsets: Array[ChartSet] = []
	var active_set_ids: Dictionary = {}
	var active_chart_ids: Dictionary = {}
	chartsets_by_uuid.clear()
	charts_by_uuid.clear()
	for chartset_value in loaded_chartsets:
		var chart_set := chartset_value as ChartSet
		if chart_set == null:
			continue
		active_set_ids[chart_set.db_id] = true
		chartsets_by_uuid[chart_set.uuid] = chart_set
		next_chartsets.append(chart_set)
		for chart in chart_set.charts:
			active_chart_ids[chart.db_id] = true
			charts_by_uuid[chart.uuid] = chart

	chartsets = next_chartsets
	selected_chartset = chartsets_by_db_id.get(previous_set_id) if active_set_ids.has(previous_set_id) else null
	selected_chart = charts_by_db_id.get(previous_chart_id) if active_chart_ids.has(previous_chart_id) else null
	if selected_chart == null:
		parsed_chart = null
	return true


func _get_or_create_chartset(db_id: int) -> ChartSet:
	var chart_set := chartsets_by_db_id.get(db_id) as ChartSet
	if chart_set == null:
		chart_set = ChartSet.new()
		chartsets_by_db_id[db_id] = chart_set
	return chart_set


func _get_or_create_chart(db_id: int) -> Chart:
	var chart := charts_by_db_id.get(db_id) as Chart
	if chart == null:
		chart = Chart.new()
		charts_by_db_id[db_id] = chart
	return chart


func _create_timing() -> Timing:
	return Timing.new()


func rescan_library() -> void:
	if _database != null:
		_start_background_sync()
	else:
		database_sync_finished.emit(false)


func _start_background_sync() -> void:
	if not _scanner.progress_changed.is_connected(_emit_progress):
		_scanner.progress_changed.connect(_emit_progress)
	if not _scanner.finished.is_connected(_on_scan_finished):
		_scanner.finished.connect(_on_scan_finished)
	_scanner.setup(self, _database)
	_scanner.start()


func _on_scan_finished(success: bool) -> void:
	if success:
		_refresh_library_from_database(true)
		_emit_update()
	database_sync_finished.emit(success)


func _index_saved_chart(chart: Chart, force_rating: bool = false) -> bool:
	if _database == null or chart == null or chart.chart_set == null:
		return false
	if not FileAccess.file_exists(chart.file_path):
		return false

	var chart_set := chart.chart_set
	if chart_set.uuid.is_empty():
		chart_set.build_uuid()
	var set_id := int(_database.upsert_chart_set(chart_set))
	if set_id <= 0:
		push_error("[database] failed to save chart set: %s" % _database.get_last_error_message())
		return false

	var previous_id := chart.db_id
	chart_set.db_id = set_id
	if not _calculate_chart_rating(chart, force_rating):
		push_error("[rating] failed to calculate chart rating: %s" % chart.file_path)
		return false
	chart.file_modified_time = int(FileAccess.get_modified_time(chart.file_path))
	chart.file_size = _get_file_size(chart.file_path)
	chart.filehash = FileAccess.get_sha256(chart.file_path)
	var chart_id := int(_database.upsert_chart(chart))
	if chart_id <= 0:
		push_error("[database] failed to save chart: %s" % _database.get_last_error_message())
		return false

	if previous_id > 0 and previous_id != chart_id:
		_database.set_chart_present(previous_id, false)
	chart.db_id = chart_id
	chart.availability = Chart.Availability.AVAILABLE
	chartsets_by_db_id[set_id] = chart_set
	charts_by_db_id[chart_id] = chart
	chartsets_by_uuid[chart_set.uuid] = chart_set
	charts_by_uuid[chart.uuid] = chart
	return true


func _calculate_chart_rating(chart: Chart, force: bool = false) -> bool:
	if chart == null:
		return false
	if chart.rating_calculated and not force:
		return true

	var rating_source: ParsedChart = null
	if parsed_chart != null and parsed_chart.chart == chart:
		rating_source = parsed_chart
	else:
		var parse_result := Parser.new().parse_object(chart)
		if not parse_result.success or parse_result.parsed_chart == null:
			return false
		rating_source = parse_result.parsed_chart

	chart.rating = Rating.calculate_rating(rating_source)
	chart.rating_calculated = true
	return true


func _get_file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	return file.get_length()


func _emit_progress(ratio: float) -> void:
	progress_changed.emit(ratio)


func _emit_initial_ready() -> void:
	loading_finished.emit()
	if not chartsets.is_empty():
		if selected_chartset == null:
			selected_chartset = chartsets[0]


func _emit_loading_failure() -> void:
	_emit_initial_ready()
	database_sync_finished.emit(false)


func _emit_update() -> void:
	chart_update.emit(chartsets)


func _chartset_folder_exists(folder_name: String) -> bool:
	var normalized := folder_name.strip_edges()
	if normalized.is_empty():
		return true

	for chartset in chartsets:
		if chartset != null and chartset.folder_name == normalized:
			return true

	var absolute_path := ProjectSettings.globalize_path(FileSystem.official_chart_path.path_join(normalized))
	return DirAccess.dir_exists_absolute(absolute_path)


func make_unique_editor_chartset_folder_name(preferred_name: String = "new_chartset") -> String:
	var base_name := preferred_name.strip_edges().validate_filename()
	if base_name.is_empty():
		base_name = "new_chartset"

	var candidate := base_name
	var suffix := 2
	while _editor_chartset_folder_exists(candidate):
		candidate = "%s_%d" % [base_name, suffix]
		suffix += 1
	return candidate


func _editor_chartset_folder_exists(folder_name: String) -> bool:
	var normalized := folder_name.strip_edges()
	if normalized.is_empty():
		return true

	for chartset in editor_chartsets:
		if chartset != null and chartset.folder_name == normalized:
			return true

	var absolute_path := ProjectSettings.globalize_path(FileSystem.editor_chart_path.path_join(normalized))
	return DirAccess.dir_exists_absolute(absolute_path)
