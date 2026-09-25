extends Node
class_name ChartPublisher

signal state_changed
signal published
signal message(text: String)

var selection: ChartSet
var remote: Dictionary = {}
var busy := false
var checking := false
var lookup_error := ""
var _request: HTTPRequest
var _generation := 0
@export var dialog: ConfirmationDialog
var _thread: Thread
var _package := ChartPackageBuilder.BuildResult.new()
var _target: ChartSet
var _submitter := -1
var _upload: HTTPRequest
const DEFAULT_BUILTIN_PACK_ID := "dansu"

@export var pack_id_input: LineEdit

var _builtin_button: Button
var _publish_as_builtin := false
var _publish_pack_id := DEFAULT_BUILTIN_PACK_ID

func _ready() -> void:
	dialog.confirmed.connect(_submit.bind(false))
	dialog.custom_action.connect(_on_custom_action)
	dialog.canceled.connect(_cancel_preparation)
	Auth.state_changed.connect(_on_auth_changed)
	_builtin_button = dialog.add_button("Upload + add as built-in", true, "builtin")
	_builtin_button.visible = false
	if is_instance_valid(pack_id_input):
		pack_id_input.placeholder_text = DEFAULT_BUILTIN_PACK_ID
		pack_id_input.text_changed.connect(_on_pack_id_changed)

func set_selection(chartset: ChartSet) -> void:
	if busy or selection == chartset:
		return
	selection = chartset
	if is_instance_valid(pack_id_input):
		pack_id_input.text = (
			chartset.pack_id
			if chartset != null and not chartset.pack_id.is_empty()
			else DEFAULT_BUILTIN_PACK_ID
		)
	remote.clear()
	lookup_error = ""
	_lookup()

func _lookup() -> void:
	_generation += 1
	_cancel_request()
	checking = false
	if not is_inside_tree():
		return
	if selection == null or selection.uuid.is_empty() or not selection.online_metadata.is_empty():
		state_changed.emit()
		return
	checking = true
	_request = HTTPRequest.new()
	_request.max_redirects = 0
	_request.timeout = 20
	_request.body_size_limit = 2 * 1024 * 1024
	add_child(_request)
	_request.request_completed.connect(_on_lookup.bind(_generation))
	if _request.request(_api_url("/chartsets/by-uuid/") + selection.uuid.uri_encode()) != OK:
		checking = false
		lookup_error = "Could not check the published version. Retry."
	state_changed.emit()

func _on_lookup(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray, generation: int) -> void:
	if generation != _generation:
		return
	_cancel_request()
	checking = false
	remote.clear()
	lookup_error = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		lookup_error = "Could not reach the server. Retry."
	elif code == 200:
		var data = JSON.parse_string(bytes.get_string_from_utf8())
		if data is Dictionary and data.get("chartset_uuid") == selection.uuid and data.has("status") and data.has("owner_id"):
			remote = data
		else:
			lookup_error = "The server returned invalid chartset metadata."
	elif code == 404:
		var data = JSON.parse_string(bytes.get_string_from_utf8())
		if not data is Dictionary or data.get("detail") != "Chartset not found":
			lookup_error = "Chart publishing support is not deployed on the server yet."
	else:
		lookup_error = "Could not check the published version (HTTP %d)." % code
	_update_dialog()
	state_changed.emit()

func restriction(as_builtin: bool = false) -> String:
	if not Auth.is_authenticated():
		return "Sign in with Steam to publish chartsets."
	if not remote.is_empty():
		if remote.owner_id != Auth.user.get("id"):
			return "Only the original uploader can update this chartset."
		if not as_builtin and (remote.get("origin") == "official" or remote.status in ["approved", "ranked"]):
			return "Approved and ranked chartsets cannot be updated."
	return ""

func button_text() -> String:
	if busy:
		return "Uploading…" if _upload != null else "Preparing…"
	if checking:
		return "Checking…"
	return "Update" if not remote.is_empty() else "Upload"

func show_publish(theme_value: Theme) -> void:
	if busy or selection == null:
		return
	if not Auth.is_authenticated():
		message.emit(restriction())
		Auth.login()
		return
	_target = selection
	_submitter = int(Auth.user.get("id", -1))
	_publish_as_builtin = false
	busy = true
	_package = ChartPackageBuilder.BuildResult.new()
	dialog.theme = theme_value
	dialog.get_cancel_button().disabled = false
	dialog.popup_centered(Vector2i(720, 440))
	_lookup()
	_thread = Thread.new()
	if _thread.start(ChartPackageBuilder.build.bind(_target.charts[0].folder_path)) != OK:
		_thread = null
		_package = ChartPackageBuilder.BuildResult.failure("Could not start the package builder.")
	_update_dialog()
	state_changed.emit()

func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		_package = _thread.wait_to_finish()
		_thread = null
		if not dialog.visible:
			_remove_package()
			busy = false
		_update_dialog()
		state_changed.emit()

func _update_dialog() -> void:
	if _target == null:
		return
	var text := "%s\n%d difficulties\n\n" % [_target.charts[0].title, _target.charts.size()]
	var builtin_available := can_publish_builtin() and restriction(true).is_empty()
	if _upload != null:
		text += "Uploading and validating the package…"
	elif checking or _thread != null:
		text += "Checking the published version and preparing files…"
	elif not lookup_error.is_empty():
		text += lookup_error
	elif not _package.error.is_empty():
		text += _package.error
	elif not restriction().is_empty() and not builtin_available:
		text += restriction()
	else:
		text += "%d files · %.2f MiB\n\n" % [int(_package.files), float(_package.bytes) / 1048576.0]
		if not restriction().is_empty():
			text += "The regular update is locked. The built-in action will replace it as an official ranked chartset."
		else:
			text += "Publish this chartset to the online catalogue?" if remote.is_empty() else "Replace your published chartset with this package?\nDifficulties absent from this package are removed from the server."
		text += "\n\nIncludes charts, audio, images and skin files from this folder."
	dialog.dialog_text = text
	dialog.get_ok_button().text = "Upload" if remote.is_empty() else "Update"
	var common_disabled := checking or _thread != null or _upload != null or not lookup_error.is_empty() or not _package.error.is_empty() or _package.path.is_empty()
	dialog.get_ok_button().disabled = common_disabled or not restriction().is_empty()
	if is_instance_valid(_builtin_button):
		var pack_id_valid := FileSystem.is_valid_pack_id(_get_pack_id())
		_builtin_button.visible = can_publish_builtin()
		_builtin_button.text = "Upload + add as built-in" if remote.is_empty() else "Update built-in map"
		_builtin_button.disabled = common_disabled or not restriction(true).is_empty() or not pack_id_valid

func can_publish_builtin() -> bool:
	return OS.has_feature("editor") and Auth.is_admin()

func _get_pack_id() -> String:
	if is_instance_valid(pack_id_input):
		var value := pack_id_input.text.strip_edges().to_lower()
		if not value.is_empty():
			return value
	if _target != null and not _target.pack_id.is_empty():
		return _target.pack_id.to_lower()
	return DEFAULT_BUILTIN_PACK_ID


func _on_pack_id_changed(_value: String) -> void:
	_update_dialog()
	state_changed.emit()


func _on_custom_action(action: StringName) -> void:
	if action == &"builtin" and can_publish_builtin():
		_submit(true)

func _submit(as_builtin: bool = false) -> void:
	var submit_button := _builtin_button if as_builtin else dialog.get_ok_button()
	if not is_instance_valid(submit_button) or submit_button.disabled or _submitter != int(Auth.user.get("id", -1)):
		return
	if as_builtin and (not can_publish_builtin() or not restriction(true).is_empty()):
		return

	if as_builtin:
		_publish_pack_id = _get_pack_id()
		if not FileSystem.is_valid_pack_id(_publish_pack_id):
			Notification.notice("Invalid pack ID.", Notification.Type.WARNING)
			return
	else:
		_publish_pack_id = DEFAULT_BUILTIN_PACK_ID

	_publish_as_builtin = as_builtin
	var file := FileAccess.open(_package.path, FileAccess.READ)
	if file == null:
		_package.error = "The prepared package is missing. Close and retry."
		_update_dialog()
		return
	var boundary := "Dansu" + Crypto.new().generate_random_bytes(16).hex_encode()
	var body := PackedByteArray()
	if _publish_as_builtin:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"publish_as_official\"\r\n\r\ntrue\r\n" % boundary).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"chartset_zip\"; filename=\"chartset.zip\"\r\nContent-Type: application/zip\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(file.get_buffer(file.get_length()))
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var headers := Auth.authorization_headers()
	headers.append("Content-Type: multipart/form-data; boundary=" + boundary)
	_upload = HTTPRequest.new()
	_upload.timeout = 180
	_upload.max_redirects = 0
	_upload.body_size_limit = 100 * 1024 * 1024 if _publish_as_builtin else 2 * 1024 * 1024
	add_child(_upload)
	_upload.request_completed.connect(_on_uploaded)
	if _upload.request_raw(_api_url("/chartsets/uploads"), headers, HTTPClient.METHOD_POST, body) != OK:
		_on_uploaded(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	_update_dialog()
	state_changed.emit()

func _on_uploaded(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	if is_instance_valid(_upload):
		_upload.queue_free()
	_upload = null
	var data = null if _publish_as_builtin or bytes.is_empty() else JSON.parse_string(bytes.get_string_from_utf8())
	var upload_succeeded: bool = result == HTTPRequest.RESULT_SUCCESS and code == 201 and (
		_publish_as_builtin or (data is Dictionary and data.get("chartset_uuid") == _target.uuid)
	)
	if upload_succeeded:
		var builtin_result := ChartPackageInstaller.InstallResult.new()
		if _publish_as_builtin:
			var package_file := FileAccess.open(_package.path, FileAccess.WRITE)
			if package_file == null:
				builtin_result = ChartPackageInstaller.InstallResult.failure("Could not save the server chart package.")
			else:
				package_file.store_buffer(bytes)
				package_file.flush()
				var write_error := package_file.get_error()
				package_file.close()
				if write_error != OK:
					builtin_result = ChartPackageInstaller.InstallResult.failure("Could not finish saving the server chart package.")
				else:
					builtin_result = FileSystem.install_packaged_chartset(
						_package.path,
						_target.uuid,
						_target.folder_name.get_file(),
						_publish_pack_id,
					)
		dialog.hide()
		busy = false
		_remove_package()
		if not builtin_result.error.is_empty():
			Notification.notice("Published to the server, but built-in installation failed: " + str(builtin_result.error), Notification.Type.WARNING)
		else:
			Notification.notice("Chartset published and added as a built-in map." if _publish_as_builtin else "Chartset published successfully.", Notification.Type.NOTICE)
		if _publish_as_builtin and builtin_result.error.is_empty():
			CM.rescan_library()
		_publish_as_builtin = false
		_publish_pack_id = DEFAULT_BUILTIN_PACK_ID
		_lookup()
		published.emit()
	else:
		var error := "Upload failed. Check your connection and retry."
		if result == HTTPRequest.RESULT_SUCCESS:
			error = "Upload failed (HTTP %d)." % code
			if data == null and not bytes.is_empty():
				data = JSON.parse_string(bytes.get_string_from_utf8())
			if data is Dictionary and data.get("detail") is String:
				error = data.detail
		if code == 401:
			Auth.logout()
		_package.error = error
		_update_dialog()
		Notification.notice(error, Notification.Type.WARNING)
	state_changed.emit()

func _cancel_preparation() -> void:
	if _upload != null:
		# Closing the review does not claim that an in-flight server publish was cancelled.
		return
	if _thread == null:
		_remove_package()
		busy = false
	state_changed.emit()

func _on_auth_changed() -> void:
	if not is_inside_tree():
		return
	_update_dialog()
	state_changed.emit()

func _remove_package() -> void:
	if not _package.path.is_empty():
		ChartTransfer.cleanup(str(_package.path).get_base_dir())
	_package = ChartPackageBuilder.BuildResult.new()

func _cancel_request() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null

func _api_url(path: String) -> String:
	return ServerURLs.api(path)

func _exit_tree() -> void:
	_generation += 1
	_cancel_request()
	if is_instance_valid(_upload):
		_upload.cancel_request()
	if _thread != null:
		_package = _thread.wait_to_finish()
		_thread = null
	_remove_package()
