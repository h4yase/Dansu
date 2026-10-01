extends Node
class_name SteamAuthManager

## Steam Web API ticket -> Dansu JWT. Credentials are held in memory only.

signal state_changed
signal refresh_finished(success: bool)

enum State {
	OFFLINE,
	REQUESTING_TICKET,
	SIGNING_IN,
	USERNAME_REQUIRED,
	SETTING_USERNAME,
	SIGNED_IN,
	ERROR,
}

const LOGIN_TTL_SECONDS := 15.0
const REFRESH_BEFORE_SECONDS := 300.0
const REFRESH_RETRY_SECONDS := 30.0
const USER_GROUP_ADMIN := 1 << 1

var state := State.OFFLINE
var status_message := "Offline"
var user: Dictionary = {}
var session_version := 0

var _steam: Object
var _steam_initialized := false
var _ticket_handle := 0
var _ticket_deadline_msec := 0
var _access_token := ""
var _expires_at_msec := 0
var _session_api_url := ""
var _request: HTTPRequest
var _attempt := 0
var _username_required := false
var _refreshing := false
var _login_step := State.OFFLINE
var _received_token := false
var _refresh_at_msec := 0
var _retry_at_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _steam_initialized:
		_steam.call("run_callbacks")
	if state != State.OFFLINE and _session_api_url != _api_url():
		logout()
		_set_state(State.OFFLINE, GameText.text(GameText.Key.ERROR_SERVER_CHANGED))
		return
	var now := Time.get_ticks_msec()
	if _login_step in [State.REQUESTING_TICKET, State.SIGNING_IN] and now >= _ticket_deadline_msec:
		if not _received_token:
			push_warning("Steam sign-in timed out. Please retry.")
			_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))
		else:
			_finish_login()
	if state == State.SIGNED_IN and not _refreshing and now >= maxi(_refresh_at_msec, _retry_at_msec):
		_start_refresh()
	if state in [State.USERNAME_REQUIRED, State.SETTING_USERNAME] and now >= _expires_at_msec:
		logout()
		_set_state(State.OFFLINE, GameText.text(GameText.Key.ERROR_SESSION_EXPIRED))


func login() -> void:
	if _refreshing or is_busy() or is_authenticated() or is_username_setup_pending():
		return
	_clear_session()
	_session_api_url = _api_url()
	if not _valid_api_url(_session_api_url):
		_fail(GameText.text(GameText.Key.ERROR_SERVER_URL))
		return
	if not _initialize_steam():
		return
	_request_ticket()


func _request_ticket() -> void:
	_received_token = false
	if not bool(_steam.call("loggedOn")):
		_fail(GameText.text(GameText.Key.HINT_SIGN_IN_STEAM))
		return
	_attempt += 1
	_ticket_deadline_msec = Time.get_ticks_msec() + int(LOGIN_TTL_SECONDS * 1000)
	_set_login_step(State.REQUESTING_TICKET, "Requesting Steam ticket…")
	var identity := str(ProjectSettings.get_setting("steam/web_api_identity", "dansuapi"))
	_ticket_handle = int(_steam.call("getAuthTicketForWebApi", identity))
	if _ticket_handle == 0:
		push_warning("Steam could not issue an authentication ticket.")
		_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))


func logout() -> void:
	_attempt += 1
	_dispose_request()
	_cancel_ticket()
	_clear_session()
	_set_state(State.OFFLINE, "Offline")
	_end_refresh(false)


func is_busy() -> bool:
	return state in [State.REQUESTING_TICKET, State.SIGNING_IN, State.SETTING_USERNAME]


func is_username_setup_pending() -> bool:
	return state in [State.USERNAME_REQUIRED, State.SETTING_USERNAME]


func is_username_setup_submitting() -> bool:
	return state == State.SETTING_USERNAME


# The signed-in UI survives renewal; ensure_session checks token validity before requests.
func is_authenticated() -> bool:
	return (
		state == State.SIGNED_IN and not _access_token.is_empty()
		and _session_api_url == _api_url()
	)


func is_admin() -> bool:
	return is_authenticated() and (int(user.get("groups", 0)) & USER_GROUP_ADMIN) != 0


func authorization_headers() -> PackedStringArray:
	if _access_token.is_empty() or _session_api_url != _api_url():
		return PackedStringArray()
	return PackedStringArray(["Authorization: Bearer " + _access_token])


# Requests share one renewal; an old 401 must not renew an already replaced token.
func ensure_session(rejected_token: String = "") -> bool:
	if not is_authenticated():
		return false
	if _has_valid_session() and rejected_token != _access_token:
		return true
	var version := session_version
	if not _refreshing:
		if Time.get_ticks_msec() < _retry_at_msec:
			return false
		_start_refresh()
	if not _refreshing:
		return false
	var success: bool = await refresh_finished
	return success and _has_valid_session() and is_authenticated() and session_version == version


func _start_refresh() -> void:
	if _refreshing or state != State.SIGNED_IN:
		return
	_refreshing = true
	_request_ticket()


func _set_login_step(step: State, message: String) -> void:
	_login_step = step
	if not _refreshing:
		_set_state(step, message)


func _end_refresh(success: bool) -> void:
	_login_step = State.OFFLINE
	if not _refreshing:
		return
	_refreshing = false
	refresh_finished.emit(success)


func submit_username(value: String) -> void:
	if state != State.USERNAME_REQUIRED or not _has_valid_session():
		return
	var username := value.strip_edges()
	_request = HTTPRequest.new()
	_request.timeout = LOGIN_TTL_SECONDS
	_request.max_redirects = 0
	_request.body_size_limit = 64 * 1024
	add_child(_request)
	_request.request_completed.connect(_on_username_response.bind(_attempt))
	_set_state(State.SETTING_USERNAME, "Saving username…")
	var error := _request.request(
		_api_url() + "/auth/username",
		PackedStringArray([
			"Content-Type: application/json",
			"Accept: application/json",
			"Authorization: Bearer " + _access_token,
		]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"username": username})
	)
	if error != OK:
		_username_setup_failed(GameText.text(GameText.Key.ERROR_USERNAME_SAVE))


func apply_score_submission(response: Dictionary) -> void:
	if not is_authenticated() or not response.has("sr_total"):
		return
	var stats = user.get("stats", {})
	if not stats is Dictionary:
		stats = {}
	else:
		stats = stats.duplicate(true)
	stats["sr_total"] = float(response.sr_total)
	user["stats"] = stats
	state_changed.emit()


func _initialize_steam() -> bool:
	if _steam_initialized:
		return true
	if not Engine.has_singleton("Steam"):
		push_warning("GodotSteam could not load. Check the Steam extension and DLLs.")
		_fail(GameText.text(GameText.Key.ERROR_STEAM_UNAVAILABLE))
		return false
	_steam = Engine.get_singleton("Steam")
	var app_id := int(ProjectSettings.get_setting("steam/app_id", 0))
	var result: Dictionary = _steam.call("steamInitEx", app_id, false)
	if int(result.get("status", -1)) != 0:
		push_warning("Steam initialization failed.")
		_fail(GameText.text(GameText.Key.ERROR_STEAM_UNAVAILABLE))
		return false
	_steam_initialized = true
	_steam.connect("get_ticket_for_web_api", _on_web_api_ticket)
	return true


func _on_web_api_ticket(handle: int, result: int, ticket_size: int, buffer: PackedByteArray) -> void:
	if _login_step != State.REQUESTING_TICKET or handle != _ticket_handle:
		return
	if result != 1 or ticket_size <= 0 or ticket_size > buffer.size() or ticket_size > 2560:
		push_warning("Steam rejected the request. Please retry.")
		_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))
		return
	_request = HTTPRequest.new()
	_request.timeout = maxf(_remaining_login_seconds(), 0.001)
	_request.max_redirects = 0
	_request.body_size_limit = 64 * 1024
	add_child(_request)
	_request.request_completed.connect(_on_token_response.bind(_attempt))
	_set_login_step(State.SIGNING_IN, "Signing in…")
	var error := _request.request(
		_session_api_url + "/auth/steam/token",
		PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"ticket": buffer.slice(0, ticket_size).hex_encode()})
	)
	if error != OK:
		push_warning("Could not start the sign-in request. Please retry.")
		_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))


func _on_token_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, attempt: int) -> void:
	if attempt != _attempt or _login_step != State.SIGNING_IN:
		return
	_dispose_request()
	_cancel_ticket()
	if _session_api_url != _api_url():
		_fail(GameText.text(GameText.Key.ERROR_SERVER_CHANGED))
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(GameText.text(GameText.Key.ERROR_SERVER_CONNECTION))
		return
	if code != 200:
		match code:
			401:
				push_warning("Steam ticket expired or was rejected. Please retry.")
				_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))
			403:
				logout()
				_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FORBIDDEN))
			502, 503: _fail(GameText.text(GameText.Key.ERROR_STEAM_SERVER))
			_:
				push_warning("Sign-in failed (HTTP %d). Please retry." % code)
				_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		push_warning("Invalid sign-in response from the server.")
		_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))
		return
	var token = data.get("access_token")
	var lifetime = data.get("expires_in")
	var profile = data.get("user")
	var username_required = data.get("username_required")
	if (
		not token is String or token.is_empty() or data.get("token_type") != "bearer"
		or not (lifetime is float or lifetime is int) or float(lifetime) <= 0
		or not profile is Dictionary or not profile.get("steam_persona_name") is String
		or not (profile.get("id") is float or profile.get("id") is int)
		or not username_required is bool
	):
		push_warning("Invalid sign-in response from the server.")
		_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))
		return
	if _refreshing and int(profile.id) != int(user.get("id", -1)):
		logout()
		_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))
		return
	_received_token = true
	_access_token = token
	_expires_at_msec = Time.get_ticks_msec() + int(float(lifetime) * 1000)
	_refresh_at_msec = _expires_at_msec - int(minf(REFRESH_BEFORE_SECONDS, float(lifetime) * 0.5) * 1000)
	_retry_at_msec = 0
	if _refreshing:
		user.merge(profile, true)
	else:
		user = profile.duplicate(true)
	_username_required = username_required
	_request_user_profile(attempt)


func _request_user_profile(attempt: int) -> void:
	if _remaining_login_seconds() <= 0.0:
		_finish_login()
		return
	_request = HTTPRequest.new()
	_request.timeout = maxf(_remaining_login_seconds(), 0.001)
	_request.max_redirects = 0
	_request.body_size_limit = 256 * 1024
	add_child(_request)
	_request.request_completed.connect(_on_profile_response.bind(attempt))
	_set_login_step(State.SIGNING_IN, "Loading player profile…")
	var error := _request.request(
		_api_url() + "/users/" + str(int(user.get("id", -1))),
		PackedStringArray(["Accept: application/json", "Authorization: Bearer " + _access_token])
	)
	if error != OK:
		_finish_login()


func _on_profile_response(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	attempt: int
) -> void:
	if attempt != _attempt or _login_step != State.SIGNING_IN:
		return
	_dispose_request()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var profile = JSON.parse_string(body.get_string_from_utf8())
		if profile is Dictionary and int(profile.get("id", -1)) == int(user.get("id", -2)):
			user.merge(profile, true)
	_finish_login()


func _finish_login() -> void:
	_dispose_request()
	_cancel_ticket()
	if _access_token.is_empty() or user.is_empty():
		push_warning("Sign-in did not return a usable session.")
		_fail(GameText.text(GameText.Key.ERROR_SIGN_IN_FAILED))
		return
	if _username_required:
		_set_state(State.USERNAME_REQUIRED, GameText.text(GameText.Key.HINT_USERNAME_SETUP))
	else:
		var message := "Signed in as " + str(user["username"])
		if _refreshing:
			# A token replacement must not reload the catalogue or reset selection.
			status_message = message
		else:
			_set_state(State.SIGNED_IN, message)
	_end_refresh(true)


func _on_username_response(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	attempt: int
) -> void:
	if attempt != _attempt or state != State.SETTING_USERNAME:
		return
	_dispose_request()
	if result != HTTPRequest.RESULT_SUCCESS:
		_username_setup_failed(GameText.text(GameText.Key.ERROR_SERVER_CONNECTION))
		return
	if code != 200:
		var fallback := GameText.text(GameText.Key.ERROR_USERNAME_SAVE)
		if code == 409:
			fallback = GameText.text(GameText.Key.ERROR_USERNAME_TAKEN)
		elif code == 422:
			fallback = GameText.text(GameText.Key.HINT_USERNAME_RULES)
		_username_setup_failed(_response_detail(body, fallback))
		return
	var profile = JSON.parse_string(body.get_string_from_utf8())
	if not profile is Dictionary or not profile.get("username") is String:
		push_warning("Invalid username response from the server.")
		_username_setup_failed(GameText.text(GameText.Key.ERROR_USERNAME_SAVE))
		return
	user.merge(profile, true)
	_username_required = false
	_finish_login()


func _username_setup_failed(message: String) -> void:
	_dispose_request()
	_set_state(State.USERNAME_REQUIRED, message)


func _response_detail(body: PackedByteArray, fallback: String) -> String:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("detail") is String:
		var detail := str(data.get("detail")).strip_edges()
		if not detail.is_empty():
			push_warning("Username setup: %s" % detail)
	return fallback


func _remaining_login_seconds() -> float:
	return maxf(float(_ticket_deadline_msec - Time.get_ticks_msec()) / 1000.0, 0.0)


func _api_url() -> String:
	return ServerURLs.api()


func _valid_api_url(url: String) -> bool:
	return url.begins_with("https://") or (
		url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")
		or url.begins_with("http://127.0.0.1/") or url.begins_with("http://localhost/")
	)


func _cancel_ticket() -> void:
	if _ticket_handle != 0 and _steam_initialized:
		_steam.call("cancelAuthTicket", _ticket_handle)
	_ticket_handle = 0


func _dispose_request() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null


func _clear_session() -> void:
	session_version += 1
	_received_token = false
	_login_step = State.OFFLINE
	_refresh_at_msec = 0
	_retry_at_msec = 0
	_access_token = ""
	_expires_at_msec = 0
	_username_required = false
	user = {}


func _has_valid_session() -> bool:
	return (
		not _access_token.is_empty()
		and Time.get_ticks_msec() < _expires_at_msec
		and _session_api_url == _api_url()
	)


func _set_state(value: State, message: String) -> void:
	state = value
	status_message = message
	state_changed.emit()


func _fail(message: String) -> void:
	_dispose_request()
	_cancel_ticket()
	if _refreshing:
		_retry_at_msec = Time.get_ticks_msec() + int(REFRESH_RETRY_SECONDS * 1000)
		push_warning("Session renewal failed; will retry in 30 seconds.")
		_end_refresh(false)
		return
	_clear_session()
	_set_state(State.ERROR, message)


func _exit_tree() -> void:
	_dispose_request()
	_cancel_ticket()
