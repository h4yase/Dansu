extends RefCounted
class_name ChartLibraryScanner

signal progress_changed(ratio: float)
signal finished(success: bool)

const SONG_PATH := FileSystem.official_chart_path

var _library
var _database
var _threads: Array[Thread] = []
var _folders_to_load: PackedStringArray = []
var _charts_by_path: Dictionary = {}
var _scan_generation := -1
var _scan_total_count := 0
var _scan_completed_count := 0
var _active_worker_count := 0
var _stop := false
var _scan_failed := false
var _finish_queued := false
var _mutex := Mutex.new()
var _allowed_chart_paths: Dictionary = {}
var _chartsets_by_folder: Dictionary = {}
var _packaged_uuid_by_folder: Dictionary = {}

func setup(library, database) -> void:
	_library = library
	_database = database

func start() -> void:
	stop()
	if _library == null or _database == null:
		finished.emit(false)
		return
	var packaged_chartsets := FileSystem.packaged_chartsets()
	_packaged_uuid_by_folder.clear()
	var folders := PackedStringArray()
	for uuid_value in packaged_chartsets:
		var folder_name := str(packaged_chartsets[uuid_value])
		if _packaged_uuid_by_folder.has(folder_name):
			push_error("[charts] duplicate packaged chartset folder in manifest: %s" % folder_name)
			continue
		_packaged_uuid_by_folder[folder_name] = str(uuid_value)
		folders.append(folder_name)
	folders.sort()
	_folders_to_load = _prepare_sources(folders)
	_charts_by_path.clear()
	for chart_set in _library.chartsets:
		for chart in chart_set.charts:
			_charts_by_path[_path_key(chart.folder_name, chart.file_name)] = chart

	_scan_generation = int(_database.begin_chart_scan())
	if _scan_generation <= 0:
		push_error("[database] failed to begin chart scan: %s" % _database.get_last_error_message())
		finished.emit(false)
		return

	_scan_total_count = _folders_to_load.size()
	_scan_completed_count = 0
	_scan_failed = false
	_finish_queued = false
	_stop = false
	_threads.clear()
	if _folders_to_load.is_empty():
		call_deferred("_finish")
		return

	_active_worker_count = clampi(Config.chart_load_threads, 1, _folders_to_load.size())
	for _index in range(_active_worker_count):
		var thread := Thread.new()
		_threads.append(thread)
		thread.start(Callable(self, "_worker"))

func stop() -> void:
	_stop = true
	for thread in _threads:
		if thread.is_started():
			thread.wait_to_finish()
	_threads.clear()
	_active_worker_count = 0

func _worker() -> void:
	while true:
		var folder := ""
		_mutex.lock()
		if not _stop and not _folders_to_load.is_empty():
			folder = _folders_to_load[0]
			_folders_to_load.remove_at(0)
		_mutex.unlock()
		if folder.is_empty():
			break
		_scan_folder(folder)
		_mutex.lock()
		_scan_completed_count += 1
		var progress := float(_scan_completed_count) / float(maxi(_scan_total_count, 1))
		_mutex.unlock()
		call_deferred("_emit_progress", progress)

	_mutex.lock()
	_active_worker_count -= 1
	var should_finish := _active_worker_count == 0 and not _stop and not _finish_queued
	if should_finish:
		_finish_queued = true
	_mutex.unlock()
	if should_finish:
		call_deferred("_finish")

func _scan_folder(folder: String) -> void:
	var chart_set := _chartsets_by_folder.get(folder) as ChartSet
	if chart_set == null:
		_mark_failed("failed to resolve chart set UUID '%s'" % folder)
		return
	var set_id := int(_database.upsert_chart_set(chart_set, _scan_generation))
	if set_id <= 0:
		_mark_failed("failed to index chart set '%s'" % folder)
		return
	chart_set.db_id = set_id

	for file_name in _chart_files(folder):
		if _stop:
			return
		if not _allowed_chart_paths.has(_path_key(folder, file_name)):
			continue
		var path := SONG_PATH.path_join(folder).path_join(file_name)
		var modified_time := int(FileAccess.get_modified_time(path))
		var file_size := _file_size(path)
		var cached := _charts_by_path.get(_path_key(folder, file_name)) as Chart
		if cached != null and cached.rating_calculated and cached.file_modified_time == modified_time and cached.file_size == file_size:
			if not _database.touch_chart(cached.db_id, modified_time, file_size, _scan_generation):
				_mark_failed("failed to touch cached chart '%s'" % path)
			continue

		var chart := Chart.new()
		chart.chart_set = chart_set
		chart.folder_name = folder
		chart.file_name = file_name
		if not Parser.parse_meta(chart):
			push_warning("[charts] invalid chart metadata: %s" % path)
			continue
		if not _calculate_rating(chart):
			push_warning("[charts] failed to calculate rating: %s" % path)
			continue
		chart.file_modified_time = modified_time
		chart.file_size = file_size
		chart.filehash = FileAccess.get_sha256(path)
		if int(_database.upsert_chart(chart, _scan_generation)) <= 0:
			_mark_failed("failed to index chart '%s'" % path)
			return

func _finish() -> void:
	for thread in _threads:
		if thread.is_started():
			thread.wait_to_finish()
	_threads.clear()
	var success := not _scan_failed and not _stop
	if success:
		success = bool(_database.finish_chart_scan(_scan_generation))
		if not success:
			push_error("[database] failed to finish chart scan: %s" % _database.get_last_error_message())
	_emit_progress(1.0)
	finished.emit(success)

func _mark_failed(context: String) -> void:
	_mutex.lock()
	_scan_failed = true
	_mutex.unlock()
	push_error("[database] %s: %s" % [context, _database.get_last_error_message()])

func _calculate_rating(chart: Chart) -> bool:
	if chart.rating_calculated:
		return true
	var result := Parser.new().parse_object(chart)
	if not result.success or result.parsed_chart == null:
		return false
	chart.rating = Rating.calculate_rating(result.parsed_chart)
	chart.rating_calculated = true
	return true

func _prepare_sources(folders: PackedStringArray) -> PackedStringArray:
	_allowed_chart_paths.clear()
	_chartsets_by_folder.clear()
	var sets_by_uuid: Dictionary = {}
	for folder in folders:
		var chart_files := _chart_files(folder)
		if chart_files.is_empty():
			continue
		var discovered_uuids: Dictionary = {}
		for file_name in chart_files:
			var candidate_set := ChartSet.new()
			candidate_set.folder_name = folder
			var candidate_chart := Chart.new()
			candidate_chart.chart_set = candidate_set
			candidate_chart.folder_name = folder
			candidate_chart.file_name = file_name
			if not Parser.parse_meta(candidate_chart):
				continue
			if not candidate_set.uuid.is_empty():
				discovered_uuids[candidate_set.uuid] = true
		if discovered_uuids.size() != 1:
			push_error("[charts] conflicting chartset_uuid values in folder: %s" % folder)
			continue
		var discovered_uuid := str(discovered_uuids.keys()[0]).to_lower()
		var expected_uuid := str(_packaged_uuid_by_folder.get(folder, "")).to_lower()
		if discovered_uuid != expected_uuid:
			push_error("[charts] packaged chartset UUID does not match manifest: %s" % folder)
			continue

		var chart_set := ChartSet.new()
		chart_set.folder_name = folder
		chart_set.uuid = discovered_uuid
		_chartsets_by_folder[folder] = chart_set
		if not sets_by_uuid.has(chart_set.uuid):
			sets_by_uuid[chart_set.uuid] = []
		sets_by_uuid[chart_set.uuid].append(folder)

	var winning_folders: PackedStringArray = []
	for uuid_value in sets_by_uuid:
		var candidates: Array = sets_by_uuid[uuid_value]
		var registered := _library.chartsets_by_uuid.get(uuid_value) as ChartSet
		var registered_folder := registered.folder_name if registered != null else ""
		var winner := _choose_newest_path(candidates, registered_folder, true)
		winning_folders.append(winner)

	winning_folders.sort()
	var charts_by_uuid_for_scan: Dictionary = {}
	for folder in winning_folders:
		for file_name in _chart_files(folder):
			var chart := Chart.new()
			chart.chart_set = _chartsets_by_folder[folder]
			chart.folder_name = folder
			chart.file_name = file_name
			if not Parser.parse_meta(chart) or chart.uuid.is_empty():
				push_warning("[charts] invalid or missing chart UUID: %s" % chart.file_path)
				continue
			if not charts_by_uuid_for_scan.has(chart.uuid):
				charts_by_uuid_for_scan[chart.uuid] = []
			charts_by_uuid_for_scan[chart.uuid].append(chart.file_path)
	for uuid_value in charts_by_uuid_for_scan:
		var candidates: Array = charts_by_uuid_for_scan[uuid_value]
		var registered := _library.charts_by_uuid.get(uuid_value) as Chart
		var registered_path := registered.file_path if registered != null else ""
		var winner := _choose_newest_path(candidates, registered_path, false)
		_allowed_chart_paths[_path_key_from_path(winner)] = true
	return winning_folders

func _choose_newest_path(candidates: Array, registered_path: String, is_directory: bool) -> String:
	var pool := candidates.duplicate()
	if not registered_path.is_empty() and candidates.size() > 1:
		var new_candidates := candidates.filter(func(path): return str(path) != registered_path)
		if not new_candidates.is_empty():
			pool = new_candidates
	pool.sort_custom(func(a, b):
		var modified_a := _chartset_modified_time(str(a)) if is_directory else int(FileAccess.get_modified_time(str(a)))
		var modified_b := _chartset_modified_time(str(b)) if is_directory else int(FileAccess.get_modified_time(str(b)))
		return str(a).naturalnocasecmp_to(str(b)) < 0 if modified_a == modified_b else modified_a > modified_b
	)
	return str(pool[0])

func _chartset_modified_time(folder_name: String) -> int:
	var newest := 0
	for file_name in _chart_files(folder_name):
		newest = maxi(newest, int(FileAccess.get_modified_time(SONG_PATH.path_join(folder_name).path_join(file_name))))
	return newest

func _chart_files(folder: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(SONG_PATH.path_join(folder))
	if directory == null:
		return result
	for file_name in directory.get_files():
		if file_name.ends_with(Config.FILE_EXTENSION):
			result.append(file_name)
	return result

func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return -1 if file == null else file.get_length()

func _path_key(folder_name: String, file_name: String) -> String:
	return folder_name.path_join(file_name).replace("\\", "/").to_lower()

func _path_key_from_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	var root_prefix := SONG_PATH.replace("\\", "/").trim_suffix("/") + "/"
	return normalized.trim_prefix(root_prefix).to_lower() if normalized.begins_with(root_prefix) else normalized.to_lower()

func _emit_progress(ratio: float) -> void:
	progress_changed.emit(ratio)
