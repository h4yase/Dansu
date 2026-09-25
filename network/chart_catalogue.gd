extends Node
class_name ChartCatalogue
## Owns cancellable catalogue/preview requests and one authenticated installation.
signal results_changed(chartsets: Array[ChartSet])
signal state_changed
signal message(text: String)
signal detail_cover_loaded(chart: Chart, texture: Texture2D)
signal detail_cover_failed(chart: Chart)
signal loved_state_changed(loved: bool, busy: bool)

var active := false
var loading := false
var loading_more := false
var downloading := false
var page := 1
var total_pages := 0
var total := 0
var status := ""
var filters: SongFilters = SongFilters.new(true)
var search_text := ""
var playlist_id := 0
var _list: HTTPRequest
var _audio: HTTPRequest
var _detail_cover: HTTPRequest
var _download: HTTPRequest
@export var preview_player: AudioStreamPlayer
@export var search_debounce: Timer
var _generation := 0
var _preview_generation := 0
var _detail_cover_generation := 0
var _preview_id := -1
var _preview_loop := MenuPreviewLoop.new()
var _cover_queue: Array[ChartSet] = []
var _cover_requests: Array[HTTPRequest] = []
var _archive_path := ""
var _download_metadata: Dictionary = {}
var _redirects := 0
var _installer_thread: Thread
var _automatic_update := false
var _pending_play := false
var _pending_autoplay := false
var _progress_time := 0.0
var _results: Array[ChartSet] = []
var _seen_chartsets: Dictionary = {}
var _cached_chartsets: Dictionary = {}
var _selected_loved := false
var _has_result_snapshot := false

func _ready() -> void:
	search_debounce.timeout.connect(refresh)
	CM.chart_selected.connect(_on_selected)
	Auth.state_changed.connect(_on_auth_changed)
	CM.playlists_changed.connect(_on_playlists_changed)
	CM.playlist_state_changed.connect(_on_playlist_state_changed)

func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if value:
		if _has_result_snapshot:
			results_changed.emit(_results)
			state_changed.emit()
			_cover_queue.append_array(_results)
			_pump_covers()
		else:
			refresh()
	else:
		if loading_more:
			page = maxi(page - 1, 1)
		loved_state_changed.emit(false, false)
		search_debounce.stop()
		_generation += 1
		_cancel(_list)
		_list = null
		_clear_covers()
		_cancel_detail_cover()
		stop_preview()
		loading = false
		loading_more = false

func set_search(value: String) -> void:
	search_text = value
	page = 1
	_has_result_snapshot = false
	# Invalidate immediately, including during the debounce interval.
	_generation += 1
	_cancel(_list)
	_list = null
	loading = true
	loading_more = false
	status = ""
	_clear_results()
	state_changed.emit()
	search_debounce.start()

func set_filters(value: SongFilters) -> void:
	filters = value.copy()
	page = 1
	refresh()


func set_playlist(id: int) -> void:
	playlist_id = id
	_has_result_snapshot = false
	refresh()

func load_next_page() -> void:
	if not active or loading or playlist_id != 0 or page >= total_pages:
		return
	page += 1
	_request_page(true)

func refresh() -> void:
	if not active:
		return
	search_debounce.stop()
	_generation += 1
	_cancel(_list)
	_list = null
	_clear_covers()
	loading = true
	loading_more = false
	_clear_results()
	page = 1
	_has_result_snapshot = false
	if filters.has_play_history() and not Auth.is_authenticated():
		_list_failed("Sign in to use the play history filter.")
		return
	if playlist_id != 0:
		_show_cached_playlist()
	else:
		_request_page(false)

func _show_cached_playlist() -> void:
	if CM.playlist_loader.loading:
		status = "Loading playlists…"
		state_changed.emit()
		return
	if not CM.playlist_loader.loaded:
		_list_failed(CM.playlist_loader.error)
		return
	var playlist: Playlist = null
	for entry in CM.playlists:
		if entry.id == playlist_id:
			playlist = entry
			break
	if playlist == null:
		_list_failed("Playlist not found.")
		return
	_results = playlist.filtered_chartsets(filters, search_text)
	total = _results.size()
	total_pages = 1
	loading = false
	loading_more = false
	_has_result_snapshot = true
	status = "No songs match these filters." if _results.is_empty() else "%d songs" % total
	results_changed.emit(_results)
	state_changed.emit()
	_cover_queue.append_array(_results)
	_pump_covers()


func _request_page(append: bool) -> void:
	loading = true
	loading_more = append
	status = ""
	state_changed.emit()
	var query := filters.to_query()
	query.merge({"q": search_text, "p": page, "limit": 20, "origin": "community"}, true)
	_list = _request_node(4 * 1024 * 1024)
	_list.request_completed.connect(_on_list.bind(_generation, append))
	var headers := Auth.authorization_headers() if filters.has_play_history() else PackedStringArray()
	if _list.request(_api_url("/chartset/?") + ServerURLs.query(query), headers) != OK:
		_list_failed("Could not start the search. Retry.")

func _on_list(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, append: bool) -> void:
	if not active or generation != _generation:
		return
	_cancel(_list)
	_list = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_list_failed(_http_error(result, code, "Search"))
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("items") is Array or not data.get("total_pages") is float or not data.get("total") is float:
		_list_failed("The server returned an invalid song list.")
		return
	var added: Array[ChartSet] = []
	for item in data.items:
		if not item is Dictionary:
			_list_failed("The server returned invalid song metadata.")
			return
		var mapped := OnlineChartMapper.from_metadata(item)
		if mapped == null:
			_list_failed("The server returned invalid song metadata.")
			return
		var key := _chartset_key(mapped)
		if _seen_chartsets.has(key):
			continue
		_seen_chartsets[key] = true
		_results.append(mapped)
		added.append(mapped)
	total = int(data.total)
	total_pages = int(data.total_pages)
	_has_result_snapshot = true
	loading = false
	loading_more = false
	var visible_total := maxi(total, _results.size())
	status = "No songs match these filters." if _results.is_empty() else "%d of %d songs" % [_results.size(), visible_total]
	results_changed.emit(_results)
	state_changed.emit()
	_cover_queue.append_array(added)
	_pump_covers()
	# Offset pagination can return a page made entirely of items already seen when
	# uploads move page boundaries. Skip such a page instead of stalling at the end.
	if append and added.is_empty() and page < total_pages:
		call_deferred("load_next_page")

func _list_failed(text: String) -> void:
	if loading_more:
		page = maxi(page - 1, 1)
	loading = false
	loading_more = false
	status = text
	state_changed.emit()

func _clear_results() -> void:
	_results.clear()
	_seen_chartsets.clear()
	var empty: Array[ChartSet] = []
	results_changed.emit(empty)


func show_chartset(metadata: Dictionary) -> void:
	var mapped := OnlineChartMapper.from_metadata(metadata)
	if mapped == null:
		Notification.notice("The playlist contains invalid chart metadata.", Notification.Type.WARNING)
		return
	search_debounce.stop()
	_generation += 1
	_cancel(_list)
	_list = null
	_clear_covers()
	_cancel_detail_cover()
	stop_preview()
	loading = false
	loading_more = false
	var key := _chartset_key(mapped)
	_results = [mapped]
	_seen_chartsets.clear()
	_seen_chartsets[key] = true
	total = 1
	total_pages = 1
	page = 1
	_has_result_snapshot = true
	status = "Playlist song"
	results_changed.emit(_results)
	CM.select_chartset(mapped)
	CM.select_chart(OnlineChartMapper.primary(mapped))
	state_changed.emit()

func _chartset_key(chartset: ChartSet) -> String:
	if not chartset.uuid.is_empty():
		return "uuid:" + chartset.uuid.to_lower()
	return "id:" + str(chartset.online_metadata.get("id", -1))

func _pump_covers() -> void:
	while active and not _cover_queue.is_empty() and _cover_requests.size() < 3:
		var chartset: ChartSet = _cover_queue.pop_front()
		var primary := OnlineChartMapper.primary(chartset)
		if primary != null and primary.cover_image != null:
			continue
		var url := _resource_url(str(chartset.online_metadata.get("preview_cover_url", "")))
		if url.is_empty():
			continue
		var request := _request_node(2 * 1024 * 1024)
		_cover_requests.append(request)
		request.request_completed.connect(_on_cover.bind(request, chartset, _generation))
		if request.request(url) != OK:
			_cover_requests.erase(request)
			_cancel(request)

func _on_cover(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray, request: HTTPRequest, chartset: ChartSet, generation: int) -> void:
	_cover_requests.erase(request)
	_cancel(request)
	if generation != _generation or not active:
		return
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var image := Image.new()
		if image.load_webp_from_buffer(bytes) == OK:
			var texture := ImageTexture.create_from_image(image)
			for chart in chartset.charts:
				chart.cover_image = texture
				CoverLoader.cover_loaded.emit(chart, texture)
	_pump_covers()

func _clear_covers() -> void:
	_cover_queue.clear()
	for request in _cover_requests:
		_cancel(request)
	_cover_requests.clear()

func _on_selected(chart: Chart) -> void:
	if not is_inside_tree():
		return
	if not active:
		return
	var should_auto_update := (
		chart != null
		and chart.chart_set != null
		and not chart.online_metadata.is_empty()
		and not downloading
		and Auth.is_authenticated()
		and revision_update_available(chart.chart_set)
	)
	state_changed.emit()
	if chart == null or chart.chart_set == null or chart.online_metadata.is_empty():
		loved_state_changed.emit(false, false)
		_cancel_detail_cover()
		stop_preview()
		return
	_check_loved(chart.chart_set)
	if should_auto_update and _begin_download(chart.chart_set, true):
		message.emit("A newer chart revision was found. Updating automatically…")
	_request_detail_cover(chart)
	var metadata := chart.chart_set.online_metadata
	var id := int(metadata.get("id", -1))
	if id == _preview_id and (preview_player.playing or _preview_loop.is_waiting() or is_instance_valid(_audio)):
		return
	stop_preview()
	_preview_id = id
	var url := _resource_url(str(metadata.get("preview_audio_url", "")))
	if url.is_empty():
		return
	_audio = _request_node(8 * 1024 * 1024)
	_audio.request_completed.connect(_on_audio.bind(_preview_generation))
	if _audio.request(url) != OK:
		stop_preview()
		message.emit("Could not start the audio preview.")

func _request_detail_cover(chart: Chart) -> void:
	_cancel_detail_cover()
	if chart.detail_cover_image != null:
		detail_cover_loaded.emit(chart, chart.detail_cover_image)
		return
	var url := _resource_url(str(chart.chart_set.online_metadata.get("cover_url", "")))
	if url.is_empty():
		return
	_detail_cover = _request_node(8 * 1024 * 1024)
	_detail_cover.request_completed.connect(
		_on_detail_cover.bind(chart, _detail_cover_generation)
	)
	if _detail_cover.request(url) != OK:
		_cancel_detail_cover()
		detail_cover_failed.emit(chart)

func _on_detail_cover(
	result: int,
	code: int,
	_headers: PackedStringArray,
	bytes: PackedByteArray,
	chart: Chart,
	generation: int
) -> void:
	if generation != _detail_cover_generation or not active:
		return
	_cancel(_detail_cover)
	_detail_cover = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		detail_cover_failed.emit(chart)
		return
	var image := Image.new()
	if image.load_webp_from_buffer(bytes) != OK:
		detail_cover_failed.emit(chart)
		return
	var texture := ImageTexture.create_from_image(image)
	for sibling in chart.chart_set.charts:
		sibling.detail_cover_image = texture
	detail_cover_loaded.emit(chart, texture)

func _cancel_detail_cover() -> void:
	_detail_cover_generation += 1
	_cancel(_detail_cover)
	_detail_cover = null

func _on_audio(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray, generation: int) -> void:
	if generation != _preview_generation or not active:
		return
	_cancel(_audio)
	_audio = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		message.emit(_http_error(result, code, "Preview"))
		return
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	if stream.get_length() <= 0:
		message.emit("The audio preview could not be decoded.")
		return
	preview_player.stream = stream
	preview_player.volume_db = -30
	preview_player.play()
	_preview_loop.arm(preview_player, true)

func stop_preview() -> void:
	_preview_loop.cancel()
	_preview_generation += 1
	_preview_id = -1
	_cancel(_audio)
	_audio = null
	if preview_player:
		preview_player.stop()

func local_chart(remote: Chart) -> Chart:
	if remote == null:
		return null
	var local_set := _cached_chartsets.get(remote.chart_set.uuid.to_lower()) as ChartSet
	if local_set == null:
		local_set = CommunityChartCache.load_chartset(remote.chart_set.online_metadata)
		if local_set != null:
			_cached_chartsets[local_set.uuid.to_lower()] = local_set
	if local_set == null:
		return null
	for local in local_set.charts:
		if local.uuid.to_lower() == remote.uuid.to_lower():
			return local
	return null

func is_installed(chartset: ChartSet) -> bool:
	if chartset == null or chartset.charts.is_empty():
		return false
	for chart in chartset.charts:
		if local_chart(chart) == null:
			return false
	return true

func revision_update_available(remote_chartset: ChartSet) -> bool:
	if remote_chartset == null or remote_chartset.uuid.is_empty() or remote_chartset.charts.is_empty():
		return false
	var local_chartset := _cached_chartsets.get(remote_chartset.uuid.to_lower()) as ChartSet
	if local_chartset == null:
		local_chartset = CommunityChartCache.load_chartset(remote_chartset.online_metadata)
		if local_chartset != null:
			_cached_chartsets[local_chartset.uuid.to_lower()] = local_chartset
	if local_chartset == null or local_chartset.charts.is_empty():
		return false
	var local_by_uuid := {}
	for local_chart in local_chartset.charts:
		local_by_uuid[local_chart.uuid.to_lower()] = local_chart
	var manifest := ChartPackageInstaller.read_revision_manifest(local_chartset.charts[0].folder_path)
	var recorded_by_uuid := {}
	if (
		str(manifest.get("chartset_uuid", "")).to_lower() == remote_chartset.uuid.to_lower()
		and manifest.get("charts") is Array
	):
		for entry in manifest.charts:
			if entry is Dictionary:
				recorded_by_uuid[str(entry.get("chart_uuid", "")).to_lower()] = entry
	if not recorded_by_uuid.is_empty() and recorded_by_uuid.size() != remote_chartset.charts.size():
		return true
	for remote_chart in remote_chartset.charts:
		var uuid := remote_chart.uuid.to_lower()
		var local_chart := local_by_uuid.get(uuid) as Chart
		if local_chart == null or not FileAccess.file_exists(local_chart.file_path):
			return true
		var remote_revision := int(remote_chart.online_metadata.get("chart_revision", 0))
		var recorded = recorded_by_uuid.get(uuid)
		var installed_revision := 0
		if recorded is Dictionary:
			installed_revision = int(recorded.get("chart_revision", 0))
		if remote_revision > 0 and installed_revision != remote_revision:
			return true
		var remote_checksum := str(remote_chart.online_metadata.get("checksum_sha256", "")).to_lower()
		if remote_checksum.length() == 64:
			var local_checksum := local_chart.filehash.to_lower()
			if local_checksum.length() != 64:
				local_checksum = FileAccess.get_sha256(local_chart.file_path).to_lower()
			if local_checksum != remote_checksum:
				return true
	return false

func activate_selection(autoplay: bool = false) -> void:
	if not active or (loading and not loading_more) or downloading or CM.selected_chart == null:
		return
	_pending_autoplay = autoplay
	if is_installed(CM.selected_chartset):
		_play_cached_selection()
		return
	if not Auth.is_authenticated():
		message.emit("Sign in with Steam, then press Download again.")
		Auth.login()
		return
	_begin_download(CM.selected_chartset)

func _begin_download(chartset: ChartSet, automatic_update: bool = false) -> bool:
	if chartset == null or chartset.online_metadata.is_empty() or downloading:
		return false
	_automatic_update = automatic_update
	_pending_play = not automatic_update
	_download_metadata = chartset.online_metadata.duplicate(true)
	var url := _resource_url(str(_download_metadata.get("download_url", "")))
	if not url.begins_with(_api_url("/chartsets/")):
		_automatic_update = false
		message.emit("The server returned an invalid download URL.")
		return false
	var transfer_directory := ChartTransfer.create()
	if transfer_directory.is_empty():
		_automatic_update = false
		message.emit("Could not create the download folder.")
		return false
	_archive_path = transfer_directory.path_join("download.part")
	downloading = true
	_redirects = 0
	_start_download(url, Auth.authorization_headers())
	state_changed.emit()
	return downloading

func _start_download(url: String, headers: PackedStringArray) -> void:
	_download = _request_node(100 * 1024 * 1024)
	_download.timeout = 180
	_download.download_file = _archive_path
	_download.request_completed.connect(_on_download)
	if _download.request(url, headers) != OK:
		_download_failed("Could not start the download.")

func _on_download(result: int, code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	_cancel(_download)
	_download = null
	# A future presigned redirect follows without the API bearer token.
	if result in [HTTPRequest.RESULT_SUCCESS, HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED] and code in [301, 302, 303, 307, 308] and _redirects < 3:
		var location := ""
		for header in headers:
			if header.to_lower().begins_with("location:"):
				location = header.substr(header.find(":") + 1).strip_edges()
		if location.begins_with("/"):
			location = ServerURLs.resolve(location)
		if location.begins_with("https://") and not "@" in location.get_slice("/", 2) and not "\\" in location:
			_redirects += 1
			_start_download(location, PackedStringArray())
			return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_download_failed(_http_error(result, code, "Download"))
		return
	_installer_thread = Thread.new()
	if _installer_thread.start(ChartPackageInstaller.install.bind(_archive_path, _download_metadata)) != OK:
		_installer_thread = null
		_download_failed("Could not start the chart installer.")
	state_changed.emit()

func _process(delta: float) -> void:
	if active:
		_preview_loop.update(delta)
	if _installer_thread != null and not _installer_thread.is_alive():
		var result: ChartPackageInstaller.InstallResult = _installer_thread.wait_to_finish()
		_installer_thread = null
		_remove_archive()
		if not result.error.is_empty():
			_download_failed(result.error)
		else:
			var installed := CommunityChartCache.load_chartset(_download_metadata)
			if installed == null:
				_download_failed("The installed chart could not be opened.")
			else:
				_cached_chartsets[installed.uuid.to_lower()] = installed
				ChartPackageInstaller.prune_cache(installed.folder_name)
				downloading = false
				message.emit("Chart updated. Ready to play." if _automatic_update else "Download complete.")
				if _pending_play:
					call_deferred("_play_cached_selection")
				_pending_play = false
				_automatic_update = false
				state_changed.emit()
	if downloading:
		_progress_time += delta
		if _progress_time >= 0.2:
			_progress_time = 0
			state_changed.emit()

func download_label() -> String:
	if _installer_thread != null:
		return "Installing…"
	if is_instance_valid(_download):
		var size := _download.get_body_size()
		if size > 0:
			return "%s %d%%" % ["Update" if _automatic_update else "Download", int(100.0 * _download.get_downloaded_bytes() / size)]
	return "Updating…" if _automatic_update else "Downloading…"

func _play_cached_selection() -> void:
	var remote := CM.selected_chart
	var local := local_chart(remote)
	if local == null:
		message.emit("The cached chart is unavailable. Download it again.")
		return
	# Menu previews belong to the remote chart; gameplay uses the cached chart.
	if remote.cover_image != null:
		local.cover_image = remote.cover_image
	if remote.detail_cover_image != null:
		local.detail_cover_image = remote.detail_cover_image
	stop_preview()
	CommunityChartCache.touch(local.chart_set)
	ChartPackageInstaller.prune_cache(local.chart_set.folder_name)
	CM.select_chartset(local.chart_set)
	CM.select_chart(local)
	var autoplay := _pending_autoplay
	_pending_autoplay = false
	Game.play_selected_chart(autoplay)

func _download_failed(text: String) -> void:
	_pending_autoplay = false
	_cancel(_download)
	_download = null
	downloading = false
	_automatic_update = false
	_pending_play = false
	_remove_archive()
	message.emit(text)
	state_changed.emit()

func _on_auth_changed() -> void:
	if not is_inside_tree():
		return
	var had_playlist := playlist_id != 0
	if not Auth.is_authenticated():
		playlist_id = 0
		_has_result_snapshot = false
	if active and (filters.has_play_history() or had_playlist):
		refresh()
	if active and CM.selected_chartset != null:
		_check_loved(CM.selected_chartset)
	state_changed.emit()


func _on_playlists_changed() -> void:
	_on_playlist_state_changed()
	if playlist_id != 0:
		_has_result_snapshot = false
		if active:
			refresh()


func _on_playlist_state_changed() -> void:
	if active and CM.selected_chartset != null:
		_check_loved(CM.selected_chartset)


func toggle_loved() -> void:
	if not active or not Auth.is_authenticated() or CM.selected_chartset == null:
		return
	for playlist in CM.playlists:
		if playlist.kind != "loved":
			continue
		if playlist.busy:
			return
		var chartset := CM.selected_chartset
		var added := playlist.contains(int(chartset.online_metadata.get("id", 0)))
		if not await playlist.set_chartset(chartset, not added):
			Notification.notice("Could not update Loved.", Notification.Type.WARNING)
		return


func _check_loved(chartset: ChartSet) -> void:
	_selected_loved = false
	if active and Auth.is_authenticated() and chartset != null:
		var chartset_id := int(chartset.online_metadata.get("id", 0))
		for playlist in CM.playlists:
			if playlist.kind == "loved":
				_selected_loved = playlist.contains(chartset_id)
				loved_state_changed.emit(_selected_loved, playlist.busy)
				return
	loved_state_changed.emit(false, not CM.playlist_loader.loaded)


func _remove_archive() -> void:
	if not _archive_path.is_empty():
		ChartTransfer.cleanup(_archive_path.get_base_dir())
		_archive_path = ""

func _request_node(limit: int) -> HTTPRequest:
	var node := HTTPRequest.new()
	node.timeout = 20
	node.max_redirects = 0
	node.body_size_limit = limit
	add_child(node)
	return node

func _api_url(path: String) -> String:
	return ServerURLs.api(path)

func _resource_url(path: String) -> String:
	return ServerURLs.resolve(path)

func _cancel(node: HTTPRequest) -> void:
	if is_instance_valid(node):
		node.cancel_request()
		node.queue_free()

func _http_error(result: int, code: int, action: String) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return action + " failed. Check your connection and retry."
	match code:
		401:
			Auth.logout()
			return "Session expired. Sign in with Steam and retry."
		403: return "This account cannot access this content."
		404: return action + " is unavailable on the server (404)."
		422: return "The server rejected these filters. Check the ranges."
		_: return "%s failed (HTTP %d). Retry." % [action, code]

func _exit_tree() -> void:
	_generation += 1
	_preview_generation += 1
	_cancel(_list)
	_cancel(_audio)
	_cancel_detail_cover()
	_cancel(_download)
	_clear_covers()
	if _installer_thread != null:
		_installer_thread.wait_to_finish()
	_remove_archive()
