extends PanelContainer
class_name AccountPanel

const AVATAR_BODY_LIMIT := 4 * 1024 * 1024
const AVATAR_TIMEOUT_SECONDS := 15.0

@export_group("Node References")
@export var avatar: TextureRect
@export var avatar_placeholder: Label
@export var name_label: Label
@export var rating_label: Label
@export var rank_label: Label
@export var avatar_request: HTTPRequest

var _avatar_url := ""


func _ready() -> void:
	Auth.state_changed.connect(_refresh)
	avatar_request.request_completed.connect(_on_avatar_loaded)
	_refresh()


func _refresh() -> void:
	if Auth.is_authenticated():
		var profile: Dictionary = Auth.user
		var stats = profile.get("stats", {})
		name_label.text = str(profile.get("username", profile.get("steam_persona_name", "PLAYER")))
		var sr = float(stats.get("sr_total", 0.0)) if stats is Dictionary else 0.00
		rating_label.text = "%.2f SR" %sr
		rating_label.self_modulate = Rating.get_color_from_rating(sr / 20)
		var rank_value = profile.get("rank")
		rank_label.text = "#%d" % int(rank_value) if rank_value is int or rank_value is float else "not placed"
		_request_avatar(profile.avatar_url)
	elif Auth.is_busy():
		name_label.text = "SIGNING IN"
		rating_label.text = "--"
		rank_label.text = "--"
		_clear_avatar()
	else:
		name_label.text = "OFFLINE"
		rating_label.text = "--"
		rank_label.text = "--"
		_clear_avatar()


func _request_avatar(url: String) -> void:
	if url == _avatar_url and (avatar.texture != null or avatar_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED):
		return
	avatar_request.cancel_request()
	_avatar_url = url
	avatar.texture = null
	avatar_placeholder.show()
	if not _valid_avatar_url(url):
		return
	avatar_request.timeout = AVATAR_TIMEOUT_SECONDS
	avatar_request.body_size_limit = AVATAR_BODY_LIMIT
	if avatar_request.request(url) != OK:
		_avatar_url = ""


func _on_avatar_loaded(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		return
	var image := Image.new()
	var error := image.load_jpg_from_buffer(body)
	if error != OK:
		error = image.load_png_from_buffer(body)
	if error != OK:
		error = image.load_webp_from_buffer(body)
	if error != OK:
		return
	avatar.texture = ImageTexture.create_from_image(image)
	avatar_placeholder.hide()


func _clear_avatar() -> void:
	avatar_request.cancel_request()
	_avatar_url = ""
	avatar.texture = null
	avatar_placeholder.show()


func _valid_avatar_url(url: String) -> bool:
	return url.begins_with("https://") or url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")
