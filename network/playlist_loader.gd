extends Node
class_name PlaylistLoader

var loading := false
var loaded := false
var error := ""
var _started := false
var _request: HTTPRequest
var _pending: Array[Playlist] = []
var _index := -1
var _page := 1
var _played_only := false


func _ready() -> void:
	Auth.state_changed.connect(_on_auth_changed)
	_on_auth_changed()


func _on_auth_changed() -> void:
	if not Auth.is_authenticated():
		if is_instance_valid(_request):
			_request.cancel_request()
			_request.queue_free()
		_request = null
		_pending.clear()
		CM.playlists.clear()
		loading = false
		loaded = false
		_started = false
		error = ""
		CM.playlists_changed.emit()
		return
	if _started:
		return
	_started = true
	loading = true
	_index = -1
	_request = HTTPRequest.new()
	_request.timeout = 20
	_request.max_redirects = 0
	_request.body_size_limit = 16 * 1024 * 1024
	add_child(_request)
	_request.request_completed.connect(_on_response)
	_send("/playlists")
	CM.playlists_changed.emit()


func _send(path: String) -> void:
	if _request.request(ServerURLs.api(path), Auth.authorization_headers()) != OK:
		_fail()


func _request_page() -> void:
	if _pending[_index].kind == "recent":
		_send("/plays/recent?limit=%d" % Playlist.RECENT_LIMIT)
		return
	# Keep the server's farming order and personal play history in the startup snapshot.
	var path := "/chartset/?playlist_id=%d&p=%d&limit=100&origin=community&nsfl=true&sort=farming" % [_pending[_index].id, _page]
	if _played_only:
		path += "&played=true"
	_send(path)


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if _index == -1:
		if not data is Array:
			_fail()
			return
		for entry in data:
			if not entry is Dictionary or int(entry.get("id", 0)) <= 0:
				_fail()
				return
			var playlist := Playlist.new()
			playlist.id = int(entry.id)
			playlist.name = str(entry.get("name", "Playlist"))
			playlist.kind = str(entry.get("kind", ""))
			_pending.append(playlist)
		var recent := Playlist.new()
		recent.id = Playlist.RECENT_ID
		recent.name = "Recent"
		recent.kind = "recent"
		_pending.append(recent)
		_index = 0
		_page = 1
		_played_only = false
	elif _pending[_index].kind == "recent":
		if not _load_recent(data):
			_fail()
			return
		_index += 1
	else:
		if not data is Dictionary or not data.get("items") is Array or not data.has("total_pages"):
			_fail()
			return
		var playlist := _pending[_index]
		for entry in data.items:
			if not entry is Dictionary:
				_fail()
				return
			if _played_only:
				playlist.played_chartset_ids.append(int(entry.get("id", 0)))
			else:
				var chartset := OnlineChartMapper.from_metadata(entry)
				if chartset == null:
					_fail()
					return
				if not playlist.contains(int(entry.get("id", 0))):
					playlist.chartsets.append(chartset)
		if _page < int(data.total_pages):
			_page += 1
		else:
			_page = 1
			if not _played_only and not playlist.chartsets.is_empty():
				_played_only = true
			else:
				_played_only = false
				_index += 1
	if _index < _pending.size():
		_request_page()
		return
	CM.playlists.assign(_pending)
	_pending.clear()
	loading = false
	loaded = true
	_request.queue_free()
	_request = null
	CM.playlists_changed.emit()


func _load_recent(data: Variant) -> bool:
	if not data is Array:
		return false
	var recent := _pending[_index]
	for entry in data:
		if not entry is Dictionary or not entry.get("chartset") is Dictionary:
			return false
		if entry.chartset.get("origin") != "community":
			continue
		var chartset := OnlineChartMapper.from_metadata(entry.chartset)
		if chartset == null:
			return false
		var chartset_id := int(chartset.online_metadata.get("id", 0))
		if not recent.contains(chartset_id):
			recent.chartsets.append(chartset)
			recent.played_chartset_ids.append(chartset_id)
	return true


func _fail() -> void:
	loading = false
	error = "Could not load playlists. Restart the game to sync again."
	_pending.clear()
	_request.queue_free()
	_request = null
	CM.playlists_changed.emit()
