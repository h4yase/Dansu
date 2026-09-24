extends VBoxContainer
class_name InlineLeaderboard

const PAGE_SIZE := 20
@export var above_panel: Control
@onready var _scroll: ScrollContainer = $Scroll
@onready var _entries: VBoxContainer = $Scroll/Entries

var _chart: Chart
var _request: HTTPRequest
var _generation := 0
var _page := 0
var _total_pages := 0
var _chart_id := -1
var _maximum_combo := 0
var _debounce: Timer
var _replay_request: HTTPRequest
var _replay_generation := 0
var _replay_row: InlineLeaderboardRow


func _ready() -> void:
	if above_panel != null:
		above_panel.item_rect_changed.connect(_follow_panel)
		_follow_panel()
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.18
	add_child(_debounce)
	_debounce.timeout.connect(_load_selected)
	CM.chart_selected.connect(_select_chart)
	Scores.submission_completed.connect(_on_submission_completed)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll)
	visibility_changed.connect(_on_visibility_changed)
	_select_chart(CM.selected_chart)


func _follow_panel() -> void:
	anchor_left = above_panel.anchor_left
	anchor_right = above_panel.anchor_right
	anchor_top = above_panel.anchor_bottom
	anchor_bottom = 1.0
	offset_left = above_panel.offset_left
	offset_right = above_panel.offset_right
	offset_top = above_panel.offset_bottom + 20.0
	offset_bottom = 0.0


func refresh_selected_chart() -> void:
	_select_chart(CM.selected_chart, true)


func _on_submission_completed(score: Score, response: Dictionary) -> void:
	if not is_inside_tree() or not is_visible_in_tree() or _chart == null:
		return
	var submitted_chart_id := int(response.get("score", {}).get("chart_id", -1))
	var selected_chart_id := int(_chart.online_metadata.get("id", _chart_id))
	var matches_id := selected_chart_id > 0 and submitted_chart_id == selected_chart_id
	var matches_uuid := score.replay != null and not _chart.uuid.is_empty() and score.replay.chart_uuid.to_lower() == _chart.uuid.to_lower()
	if matches_id or matches_uuid:
		refresh_selected_chart()


func _select_chart(chart: Chart, force_refresh: bool = false) -> void:
	if not force_refresh and chart != null and chart == _chart and _page > 0:
		return
	_cancel_replay()
	_cancel_request()
	_debounce.stop()
	_chart = chart
	_page = 0
	_total_pages = 0
	_chart_id = -1
	_scroll.scroll_vertical = 0
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	if chart != null and is_visible_in_tree():
		_debounce.start()


func _on_visibility_changed() -> void:
	if is_node_ready() and is_visible_in_tree() and _chart != null and _page == 0 and _request == null:
		_debounce.start()


func _load_selected() -> void:
	if _chart == null or not is_visible_in_tree():
		return
	_chart_id = int(_chart.online_metadata.get("id", -1))
	_maximum_combo = int(_chart.online_metadata.get("max_combo", 0))
	if _chart_id > 0:
		_load_page()
	elif _chart.chart_set != null and not _chart.chart_set.uuid.is_empty():
		_request_json("/chartsets/by-uuid/" + _chart.chart_set.uuid.uri_encode(), _on_resolved)


func _load_page() -> void:
	_request_json("/leaderboards/charts/%d?page=%d&limit=%d" % [_chart_id, _page + 1, PAGE_SIZE], _on_page)


func _request_json(path: String, callback: Callable) -> void:
	_cancel_request()
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	_request.max_redirects = 0
	_request.body_size_limit = 2 * 1024 * 1024
	add_child(_request)
	_request.request_completed.connect(_on_response.bind(callback, _generation))
	var headers := Auth.authorization_headers()
	headers.append("Accept: application/json")
	if _request.request(ServerURLs.api(path), headers) != OK:
		_cancel_request()
		Notification.notice("Could not load leaderboard.", Notification.Type.WARNING)


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, callback: Callable, generation: int) -> void:
	if generation != _generation:
		return
	_cancel_request()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if code != 404:
			Notification.notice("Could not load leaderboard.", Notification.Type.WARNING)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		Notification.notice("Could not read leaderboard.", Notification.Type.WARNING)
		return
	callback.call(data)


func _on_resolved(data: Dictionary) -> void:
	for item in data.get("charts", []):
		if item is Dictionary and str(item.get("chart_uuid", "")).to_lower() == _chart.uuid.to_lower():
			_chart_id = int(item.get("id", -1))
			_maximum_combo = int(item.get("max_combo", 0))
			if _chart_id > 0:
				_load_page()
				return


func _on_page(data: Dictionary) -> void:
	if not data.get("items") is Array or int(data.get("chart_id", -1)) != _chart_id:
		Notification.notice("Could not read leaderboard.", Notification.Type.WARNING)
		return
	_page = int(data.get("page", _page + 1))
	_total_pages = int(data.get("total_pages", _page))
	var index := 0
	for item in data.items:
		if not item is Dictionary:
			continue
		var row := InlineLeaderboardRow.new()
		_entries.add_child(row)
		row.set_entry(item, _maximum_combo)
		row.action_pressed.connect(_on_row_action.bind(row))
		row.play_appear(minf(index * 0.035, 0.35))
		index += 1


func _on_scroll(value: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	if _request == null and _page > 0 and _page < _total_pages and value + bar.page >= bar.max_value - 120:
		_load_page()


func _cancel_request() -> void:
	_generation += 1
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null


func _exit_tree() -> void:
	_cancel_request()
	_cancel_replay()


func _on_row_action(action: String, item: Dictionary, row: InlineLeaderboardRow) -> void:
	if action == "more":
		row.toggle_details(_chart_id)
	elif action == "replay":
		_download_replay(item, row)


func _download_replay(item: Dictionary, row: InlineLeaderboardRow) -> void:
	if is_instance_valid(_replay_request) or _chart == null or not bool(item.get("replay_available", false)):
		return
	var score_id := int(item.get("score_id", -1))
	if _chart_id <= 0 or score_id <= 0:
		return
	var local := _resolve_replay_chart()
	if local == null:
		Notification.notice("Download or update this chart before watching the replay.", Notification.Type.WARNING)
		return
	if _chart.cover_image != null:
		local.cover_image = _chart.cover_image
	if _chart.detail_cover_image != null:
		local.detail_cover_image = _chart.detail_cover_image
	_cancel_replay()
	_replay_row = row
	row.set_replay_loading(true)
	_replay_request = HTTPRequest.new()
	_replay_request.timeout = 30.0
	_replay_request.max_redirects = 0
	_replay_request.body_size_limit = 4 * 1024 * 1024
	add_child(_replay_request)
	_replay_request.request_completed.connect(_on_replay_loaded.bind(local, _replay_generation))
	var url := ServerURLs.api("/leaderboards/charts/%d/scores/%d/replay" % [_chart_id, score_id])
	if _replay_request.request(url, Auth.authorization_headers()) != OK:
		_cancel_replay()
		Notification.notice("Could not download replay. Try again.", Notification.Type.WARNING)


func _resolve_replay_chart() -> Chart:
	if not _chart.file_name.is_empty() and FileAccess.file_exists(_chart.file_path):
		return _chart
	var local := CM.charts_by_uuid.get(_chart.uuid) as Chart
	if local != null and FileAccess.file_exists(local.file_path):
		return local
	if _chart.chart_set != null:
		var cached := CommunityChartCache.load_chartset(_chart.chart_set.online_metadata)
		if cached != null:
			for chart in cached.charts:
				if chart.uuid.to_lower() == _chart.uuid.to_lower():
					return chart
	return null


func _on_replay_loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, chart: Chart, generation: int) -> void:
	if generation != _replay_generation:
		return
	_cancel_replay()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if code == 404:
			Notification.notice("Replay is no longer available.",
			Notification.Type.WARNING)
		else:
			Notification.notice("Could not download replay. Try again.",
			Notification.Type.WARNING)
		return
	chart.filehash = FileAccess.get_sha256(chart.file_path)
	var replay := Replay.from_bytes(body, chart)
	if replay == null:
		Notification.notice("Replay does not match the installed chart version.",
		Notification.Type.WARNING)
		return
	if not Game.play_replay(replay):
		Notification.notice("Could not play replay. Check the installed chart version.",
		Notification.Type.WARNING)
		return


func _cancel_replay() -> void:
	_replay_generation += 1
	if is_instance_valid(_replay_request):
		_replay_request.cancel_request()
		_replay_request.queue_free()
	_replay_request = null
	if is_instance_valid(_replay_row):
		_replay_row.set_replay_loading(false)
	_replay_row = null
