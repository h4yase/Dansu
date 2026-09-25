extends Node
class_name ScoreManager

signal submission_started(score: Score)
signal submission_completed(score: Score, response: Dictionary)
signal submission_failed(score: Score, message: String)

const MAX_SUBMISSION_ATTEMPTS := 2
const RETRY_DELAY_SECONDS := 1.0

class Submission extends RefCounted:
	var chart: Chart
	var score: Score
	var attempt: int = 0

	func _init(p_chart: Chart, p_score: Score) -> void:
		chart = p_chart
		score = p_score

var scores: Array[Score] = []
var _submission_queue: Array[Submission] = []
var _active_submission: Submission
var _request: HTTPRequest
var _play_start_requests: Array[HTTPRequest] = []


func record_play(chart: Chart, score: Score) -> int:
	if chart == null or score == null:
		return -1
	if score.submission_id.is_empty():
		score.submission_id = ChartIdentity.generate_uuid()
	if score.replay != null and not score.submission_id.is_empty():
		var saved_replay_path := score.replay.save(score.submission_id)
		if saved_replay_path.is_empty():
			Notification.notice("Failed to save replay.", Notification.Type.WARNING)
	var play_id := 0
	if DB.connection != null:
		play_id = int(DB.connection.record_play(chart, score))
		if play_id <= 0:
			Notification.notice("failed to record play: %s" % DB.connection.get_last_error_message(),
				Notification.Type.ERROR)
			return -1

	scores.append(score)
	score.object_hash = chart.filehash
	score.chart_db_id = chart.db_id
	score.played_at = int(Time.get_unix_time_from_system())
	chart.last_played_at = int(Time.get_unix_time_from_system())
	chart.best_score = maxf(chart.best_score, score.total_score)
	chart.play_count += 1
	chart.current_version_play_count += 1
	submit_play(chart, score)
	return play_id


func record_play_start(chart: Chart) -> void:
	if chart == null or not Auth.is_authenticated():
		return
	var chart_id := int(chart.online_metadata.get("id", 0))
	var revision := int(chart.online_metadata.get("chart_revision", 0))
	if chart_id > 0 and revision > 0:
		_post_play_start(chart_id, revision, chart.chart_set)
		return
	if chart.uuid.is_empty() or chart.chart_set == null or chart.chart_set.uuid.is_empty():
		return
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.body_size_limit = 4 * 1024 * 1024
	add_child(request)
	_play_start_requests.append(request)
	request.request_completed.connect(_on_play_metadata_resolved.bind(request, chart))
	if request.request(
		_api_url("/chartsets/by-uuid/" + chart.chart_set.uuid.uri_encode()),
		Auth.authorization_headers()
	) != OK:
		_dispose_play_start_request(request)


func _post_play_start(chart_id: int, revision: int, chartset: ChartSet) -> void:
	if chart_id <= 0 or revision <= 0:
		return
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.body_size_limit = 64 * 1024
	add_child(request)
	_play_start_requests.append(request)
	var recent: Playlist = null
	for playlist in CM.playlists:
		if playlist.kind == "recent":
			recent = playlist
			break
	request.request_completed.connect(_on_play_start_recorded.bind(request, chartset, recent))
	var headers := Auth.authorization_headers()
	headers.append("Content-Type: application/json")
	if request.request(
		_api_url("/plays/" + str(chart_id)),
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify({
			"session_id": ChartIdentity.generate_uuid(),
			"chart_revision": revision,
		})
	) != OK:
		_dispose_play_start_request(request)


func _on_play_metadata_resolved(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	request: HTTPRequest,
	chart: Chart
) -> void:
	_dispose_play_start_request(request)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("charts") is Array:
		return
	for entry in data.charts:
		if entry is Dictionary and str(entry.get("chart_uuid", "")).to_lower() == chart.uuid.to_lower():
			chart.online_metadata = entry.duplicate(true)
			chart.chart_set.online_metadata = data.duplicate(true)
			_post_play_start(int(entry.get("id", 0)), int(entry.get("chart_revision", 0)), chart.chart_set)
			return


func _on_play_start_recorded(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	request: HTTPRequest,
	chartset: ChartSet,
	recent: Playlist
) -> void:
	_dispose_play_start_request(request)
	if result != HTTPRequest.RESULT_SUCCESS or code != 201:
		return
	if recent == null or not CM.playlists.has(recent) or not Auth.is_authenticated():
		return
	if chartset == null or chartset.online_metadata.get("origin") != "community":
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	var chartset_id := int(chartset.online_metadata.get("id", 0))
	if not data is Dictionary or int(data.get("chartset_id", 0)) != chartset_id:
		return
	var online_chartset := OnlineChartMapper.from_metadata(chartset.online_metadata)
	if online_chartset == null:
		return
	recent.record_recent(online_chartset)
	for playlist in CM.playlists:
		if playlist.contains(chartset_id) and not playlist.played_chartset_ids.has(chartset_id):
			playlist.played_chartset_ids.append(chartset_id)
	CM.playlists_changed.emit()


func _dispose_play_start_request(request: HTTPRequest) -> void:
	_play_start_requests.erase(request)
	if is_instance_valid(request):
		request.cancel_request()
		request.queue_free()


func submit_play(chart: Chart, score: Score) -> bool:
	if chart == null or score == null or not Auth.is_authenticated():
		return false
	if chart.chart_set == null or chart.uuid.is_empty() or chart.chart_set.uuid.is_empty():
		return false
	if chart.filehash.length() != 64:
		return false
	if score.replay == null:
		return false
	if score.submitted:
		return true
	if score.submission_id.is_empty():
		score.submission_id = ChartIdentity.generate_uuid()
	if score.submission_id.is_empty():
		return false
	for queued in _submission_queue:
		if queued.score == score:
			return true
	if _active_submission != null and _active_submission.score == score:
		return true
	score.submission_error = ""
	_submission_queue.append(Submission.new(chart, score))
	_pump_submissions()
	return true


func build_submission_payload(
	chart: Chart,
	score: Score,
	metadata: Dictionary,
	submission_id: String
) -> Dictionary:
	if chart == null or score == null or submission_id.is_empty():
		return {}
	var judgement_count := (
		score.perfect_plus + score.perfect + score.great
		+ score.ok + score.bad + score.miss
	)
	if score.notes <= 0 or score.max_score <= 0.0 or judgement_count != score.notes:
		return {}
	if score.high_combo < 0 or score.high_combo > score.notes:
		return {}
	var chart_id := int(metadata.get("id", -1))
	var revision := int(metadata.get("chart_revision", 0))
	var checksum := str(metadata.get("checksum_sha256", "")).to_lower()
	var replay_checksum := score.replay.sha256() if score.replay != null else ""
	if chart_id <= 0 or revision <= 0 or checksum.length() != 64:
		return {}
	if checksum != chart.filehash.to_lower():
		return {}
	if replay_checksum.length() != 64:
		return {}
	return {
		"submission_id": submission_id,
		"chart_id": chart_id,
		"chart_checksum_sha256": checksum,
		"chart_revision": revision,
		"scoring_version": score.scoring_version,
		"total_score": _decimal(score.total_score),
		"raw_score": _decimal(score.score),
		"max_score": _decimal(score.max_score),
		"note_count": score.notes,
		"max_combo": score.high_combo,
		"perfect_plus_count": score.perfect_plus,
		"perfect_count": score.perfect,
		"great_count": score.great,
		"ok_count": score.ok,
		"bad_count": score.bad,
		"miss_count": score.miss,
		"average_signed_timing_ms": _decimal(score.avg_signed_timings),
		"unstable_rate": _decimal(score.unstable_rate),
		"mods": [],
		"replay_sha256": replay_checksum,
	}


func _pump_submissions() -> void:
	if _active_submission != null or _submission_queue.is_empty():
		return
	_active_submission = _submission_queue.pop_front()
	var score: Score = _active_submission.score
	submission_started.emit(score)
	_begin_active_submission()


func _begin_active_submission() -> void:
	if _active_submission == null:
		return
	if not Auth.is_authenticated():
		_fail_active("Score was saved locally because the session is offline.")
		return
	var chart: Chart = _active_submission.chart
	var metadata := _matching_metadata(chart, chart.online_metadata)
	if not metadata.is_empty():
		_post_active(metadata)
		return
	_request = _new_request()
	_request.request_completed.connect(_on_chartset_resolved)
	var url := _api_url("/chartsets/by-uuid/" + chart.chart_set.uuid.uri_encode())
	if _request.request(url, PackedStringArray(["Accept: application/json"])) != OK:
		_retry_or_fail("Could not resolve the online chart version.")


func _on_chartset_resolved(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_dispose_request()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_retry_or_fail("Could not resolve the online chart version.", result, code)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("charts") is Array:
		_fail_active("The server returned invalid chart metadata.")
		return
	var chart: Chart = _active_submission.chart
	var metadata: Dictionary = {}
	for entry in data.charts:
		if entry is Dictionary and str(entry.get("chart_uuid", "")).to_lower() == chart.uuid.to_lower():
			metadata = _matching_metadata(chart, entry)
			break
	if metadata.is_empty():
		_fail_active("This score belongs to a different chart revision. Update the chart and retry.")
		return
	chart.online_metadata = metadata.duplicate(true)
	chart.chart_set.online_metadata = data.duplicate(true)
	_post_active(metadata)


func _post_active(metadata: Dictionary) -> void:
	var chart: Chart = _active_submission.chart
	var score: Score = _active_submission.score
	var payload := build_submission_payload(chart, score, metadata, score.submission_id)
	if payload.is_empty():
		_fail_active("The completed score does not match the chart metadata.")
		return
	_request = _new_request()
	_request.request_completed.connect(_on_score_submitted)
	var headers := Auth.authorization_headers()
	var boundary := "----DansuReplay" + score.submission_id.replace("-", "")
	headers.append("Content-Type: multipart/form-data; boundary=" + boundary)
	headers.append("Accept: application/json")
	if _request.request_raw(
		_api_url("/scores"),
		headers,
		HTTPClient.METHOD_POST,
		_build_multipart_submission(payload, score.replay.to_bytes(), boundary, score.submission_id)
	) != OK:
		_retry_or_fail("Could not start the score submission.")


func _on_score_submitted(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_dispose_request()
	var score: Score = _active_submission.score
	if result == HTTPRequest.RESULT_SUCCESS and code == 409:
		score.submitted = true
		score.submission_error = ""
		submission_completed.emit(score, {})
		_finish_active()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 201:
		var message := _response_error(body, "Score submission failed (HTTP %d)." % code)
		_retry_or_fail(message, result, code)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("score") is Dictionary:
		_fail_active("The server returned an invalid score response.")
		return
	score.submitted = true
	score.submission_error = ""
	score.submission_response = data.duplicate(true)
	if Auth.has_method("apply_score_submission"):
		Auth.apply_score_submission(data)
	submission_completed.emit(score, data)
	_finish_active()


func _matching_metadata(chart: Chart, value) -> Dictionary:
	if not value is Dictionary:
		return {}
	if int(value.get("id", -1)) <= 0 or int(value.get("chart_revision", 0)) <= 0:
		return {}
	var checksum := str(value.get("checksum_sha256", "")).to_lower()
	if checksum.length() != 64 or checksum != chart.filehash.to_lower():
		return {}
	return value


func _retry_or_fail(
	message: String,
	result: int = HTTPRequest.RESULT_SUCCESS,
	code: int = 0
) -> void:
	_dispose_request()
	var transient := result != HTTPRequest.RESULT_SUCCESS or code == 0 or code == 408 or code == 429 or code >= 500
	var attempt := int(_active_submission.attempt) + 1
	_active_submission.attempt = attempt
	if transient and attempt < MAX_SUBMISSION_ATTEMPTS and is_inside_tree():
		get_tree().create_timer(RETRY_DELAY_SECONDS).timeout.connect(_begin_active_submission)
		return
	_fail_active(message)


func _fail_active(message: String) -> void:
	if _active_submission == null:
		return
	var score: Score = _active_submission.score
	score.submission_error = message
	Notification.notice("Score submission failed: " + message, Notification.Type.WARNING)
	submission_failed.emit(score, message)
	_finish_active()


func _finish_active() -> void:
	_dispose_request()
	_active_submission = null
	call_deferred("_pump_submissions")


func _new_request() -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	request.max_redirects = 0
	request.body_size_limit = 1024 * 1024
	add_child(request)
	return request


func _dispose_request() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null


func _response_error(body: PackedByteArray, fallback: String) -> String:
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		return fallback
	var data = parser.data
	if data is Dictionary and data.get("detail") is String:
		return str(data.detail)
	return fallback


func _decimal(value: float) -> String:
	return "%.4f" % value


func _build_multipart_submission(
	payload: Dictionary,
	replay_bytes: PackedByteArray,
	boundary: String,
	submission_id: String
) -> PackedByteArray:
	var body := PackedByteArray()
	body.append_array((
		"--%s\r\nContent-Disposition: form-data; name=\"payload\"\r\n" % boundary
		+ "Content-Type: application/json\r\n\r\n"
		+ JSON.stringify(payload)
		+ "\r\n--%s\r\n" % boundary
		+ "Content-Disposition: form-data; name=\"replay\"; filename=\"%s.replay\"\r\n" % submission_id
		+ "Content-Type: application/octet-stream\r\n\r\n"
	).to_utf8_buffer())
	body.append_array(replay_bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return body


func _api_url(path: String) -> String:
	return ServerURLs.api(path)


func _exit_tree() -> void:
	_dispose_request()
	for request in _play_start_requests.duplicate():
		_dispose_play_start_request(request)


func get_best_play(chart: Chart) -> Score:
	if chart == null or DB.connection == null:
		return null
	var query_chart := Chart.new()
	query_chart.db_id = chart.db_id
	query_chart.uuid = chart.uuid
	query_chart.filehash = chart.filehash
	if query_chart.filehash.is_empty():
		query_chart.filehash = str(chart.online_metadata.get("checksum_sha256", "")).to_lower()
	return DB.connection.get_best_play(query_chart, _create_score)


func get_chart_plays(chart: Chart, limit: int = 50, offset: int = 0) -> Array:
	if chart == null or DB.connection == null:
		return []
	return DB.connection.get_chart_plays(chart, _create_score, limit, offset)


func get_recent_plays(limit: int = 50, offset: int = 0) -> Array:
	if DB.connection == null:
		return []
	return DB.connection.get_recent_plays(_create_score, limit, offset)


func _create_score(_db_id: int) -> Score:
	return Score.new()
