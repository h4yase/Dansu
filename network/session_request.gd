extends HTTPRequest
class_name SessionRequest
## Keeps each request's data and retries one rejected API token after shared renewal.

signal response_received(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)

var _url := ""
var _headers := PackedStringArray()
var _method := HTTPClient.METHOD_GET
var _body := PackedByteArray()
var _token := ""
var _session_version := 0
var _send_id := 0
var _retried := false


func _init() -> void:
	request_completed.connect(_on_response)


func send(url: String, headers: PackedStringArray = PackedStringArray(), method: HTTPClient.Method = HTTPClient.METHOD_GET, body: String = "") -> Error:
	return send_raw(url, headers, method, body.to_utf8_buffer())


func send_raw(url: String, headers: PackedStringArray, method: HTTPClient.Method, body: PackedByteArray) -> Error:
	stop()
	_url = url
	_headers = headers.duplicate()
	_method = method
	_body = body
	_retried = false
	_session_version = Auth.session_version
	_token = ""
	for header in _headers:
		if header.begins_with("Authorization: Bearer "):
			_token = header.trim_prefix("Authorization: Bearer ")
	if not _token.is_empty() and not (url == ServerURLs.api() or url.begins_with(ServerURLs.api() + "/")):
		_body = PackedByteArray()
		return ERR_INVALID_PARAMETER
	if not _token.is_empty():
		max_redirects = 0
		# Defer so callers can connect or await completion before renewal fails.
		_send_when_ready.call_deferred(_send_id)
		return OK
	return request_raw(_url, _headers, _method, _body)


func stop() -> void:
	_send_id += 1
	cancel_request()
	_body = PackedByteArray()


func _send_when_ready(send_id: int) -> void:
	if send_id != _send_id or is_queued_for_deletion():
		return
	if _session_version != Auth.session_version:
		_complete(RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		return
	var ready := await Auth.ensure_session()
	if send_id != _send_id or is_queued_for_deletion():
		return
	if not ready or _session_version != Auth.session_version:
		_complete(RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		return
	_send_with_current_token()


func _send_with_current_token() -> void:
	for index in range(_headers.size()):
		if _headers[index].begins_with("Authorization: Bearer "):
			_headers[index] = Auth.authorization_headers()[0]
			_token = _headers[index].trim_prefix("Authorization: Bearer ")
	var error := request_raw(_url, _headers, _method, _body)
	if error != OK:
		_complete(RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _on_response(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _token.is_empty() and _session_version != Auth.session_version:
		_complete(RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		return
	if result == RESULT_SUCCESS and code == 401 and not _token.is_empty() and not _retried:
		_retried = true
		var send_id := _send_id
		var renewed := await Auth.ensure_session(_token)
		if send_id != _send_id or is_queued_for_deletion():
			return
		if renewed and _session_version == Auth.session_version:
			_send_with_current_token()
			return
	_complete(result, code, headers, body)


func _complete(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_body = PackedByteArray()
	response_received.emit(result, code, headers, body)


func _exit_tree() -> void:
	stop()
