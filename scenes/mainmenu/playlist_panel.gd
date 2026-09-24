extends Control
class_name PlaylistPanel

signal visibility_set(blocked: bool)
signal chartset_chosen(metadata: Dictionary)
signal playlist_selected(id: int, title: String)
signal membership_changed

const OPEN_OFFSET := Vector2(-336.0, 14.0)
const OPEN_DURATION := 0.12
const CLOSE_DURATION := 0.08
const ITEM_HEIGHT := 48.0
const MAX_VISIBLE_ITEMS := 9
const COLOR_PANEL := Color(0.055, 0.052, 0.075, 0.965)
const COLOR_ITEM := Color(0.085, 0.078, 0.11, 0.0)
const COLOR_ITEM_ADDED := Color(0.439, 0.357, 0.871, 0.24)
const COLOR_ITEM_HOVER := Color(0.439, 0.357, 0.871, 0.30)
const COLOR_ITEM_PRESSED := Color(0.439, 0.357, 0.871, 0.50)
const COLOR_TEXT := Color(0.94, 0.93, 1.0, 1.0)
const COLOR_ADDED_TEXT := Color(1.0, 0.98, 0.72, 1.0)
const COLOR_MUTED := Color(0.68, 0.65, 0.82, 1.0)

@export var request: HTTPRequest
@export var panel: PanelContainer
@export var status_label: Label
@export var item_list: VBoxContainer
@export var scroll: ScrollContainer
@export var item_font: FontFile

var _playlists: Array[Dictionary] = []
var _current_chartset: Dictionary = {}
var _operation := ""
var _target_rect := Rect2()
var _tween: Tween = null
var _busy := false
var browsing := false
var selected_id := 0
var _items_appear: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 120
	z_as_relative = false
	visible = false
	modulate.a = 1.0
	if panel != null:
		panel.visible = false
		panel.offset_transform_enabled = true
	resized.connect(_position_panel)
	visibility_changed.connect(func(): visibility_set.emit(visible))
	_apply_styles()
	panel.resized.connect(_position_panel)


func open_browser(target_rect: Rect2, playlist_id: int) -> void:
	browsing = true
	selected_id = playlist_id
	open({}, target_rect)


func open(chartset_metadata: Dictionary = {}, target_rect: Rect2 = Rect2()) -> void:
	if not Auth.is_authenticated():
		Notification.notice("Sign in to use playlists.", Notification.Type.WARNING)
		return
	_current_chartset = chartset_metadata.duplicate(true)
	if _items_appear:
		_items_appear.kill()
	item_list.modulate.a = 1.0
	if not chartset_metadata.is_empty():
		browsing = false
	_target_rect = target_rect
	visible = true
	modulate.a = 1.0
	if panel != null:
		panel.visible = true
		panel.modulate.a = 1.0
		panel.offset_transform_scale = Vector2(0.96, 0.96)
	_position_panel()
	_play_open_animation()
	_playlists.clear()
	if browsing:
		_playlists.append({"id": 0, "name": "All Beatmaps"})
	_render_playlists()
	scroll.custom_minimum_size.y = ITEM_HEIGHT if browsing else 0.0
	panel.reset_size()
	_request_playlists()


func close() -> void:
	if not visible:
		return
	if request != null:
		request.cancel_request()
	_operation = ""
	_busy = false
	_play_close_animation()


func is_open() -> bool:
	return visible and (panel == null or panel.visible)


func _request_playlists() -> void:
	if browsing:
		_send("list", "/playlists")
		return
	if _current_chartset.is_empty() or _current_chartset_id() <= 0:
		_set_status("Select a community map first.")
		_show_playlists([])
		return
	if not _send("list", "/playlists?chartset_id=%d" % _current_chartset_id()):
		return


func _send(
	operation: String,
	path: String,
	method: HTTPClient.Method = HTTPClient.METHOD_GET,
	body: Dictionary = {}
) -> bool:
	if _busy or request == null:
		return false
	_operation = operation
	_busy = true
	var headers := Auth.authorization_headers()
	var content := ""
	if not body.is_empty():
		headers.append("Content-Type: application/json")
		content = JSON.stringify(body)
	var error := request.request(ServerURLs.api(path), headers, method, content)
	if error != OK:
		_operation = ""
		_busy = false
		_set_status("Could not start the request.")
		return false
	_update_item_disabled_state()
	_set_status("")
	return true


func _on_request_completed(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var operation := _operation
	_operation = ""
	_busy = false
	var data = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_set_status("Request failed.")
		_update_item_disabled_state()
		return
	var op_name := operation.get_slice(":", 0)
	var op_index := int(operation.get_slice(":", 1)) if operation.contains(":") else -1
	match op_name:
		"list":
			_show_playlists(data if data is Array else [])
			if _items_appear:
				_items_appear.kill()
			item_list.modulate.a = 0.0
			_items_appear = create_tween()
			_items_appear.tween_property(item_list, "modulate:a", 1.0, 0.18)
		"add":
			_update_playlist_membership(op_index, true)
			_set_status("")
			membership_changed.emit()
		"remove":
			_update_playlist_membership(op_index, false)
			_set_status("")
			membership_changed.emit()
	_update_item_disabled_state()


func _show_playlists(data: Array) -> void:
	_playlists.clear()
	for child in item_list.get_children():
		item_list.remove_child(child)
		child.queue_free()
	if browsing:
		_playlists.append({"id": 0, "name": "All Beatmaps"})

	for entry in data:
		if not entry is Dictionary:
			continue
		if int(entry.get("id", 0)) <= 0:
			continue
		var kind := str(entry.get("kind", ""))
		if kind == "recent" or (kind == "loved" and not browsing):
			continue
		_playlists.append(entry)

	if _playlists.is_empty():
		_set_status("No playlists yet.")
		return

	_set_status("")
	_render_playlists()

	var visible_items := mini(_playlists.size(), MAX_VISIBLE_ITEMS)
	scroll.custom_minimum_size.y = ITEM_HEIGHT * float(visible_items) + 4.0 * float(maxi(0, visible_items - 1))
	panel.reset_size()


func _render_playlists() -> void:
	for child in item_list.get_children():
		item_list.remove_child(child)
		child.queue_free()
	for index in range(_playlists.size()):
		item_list.add_child(_create_playlist_item(index, _playlists[index]))


func _create_playlist_item(index: int, playlist: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, ITEM_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var added := int(playlist.get("id", -1)) == selected_id if browsing else _playlist_contains_current(playlist)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, ITEM_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = str(playlist.get("name", "Playlist"))
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_constant_override("outline_size", 0)
	button.flat = false
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.theme = _build_item_theme(added)
	button.tooltip_text = button.text if browsing else ("Remove from this playlist" if added else "Add to this playlist")
	if browsing:
		button.pressed.connect(func():
			playlist_selected.emit(int(playlist.get("id", 0)), str(playlist.get("name", "Playlist")))
			close()
		)
	else:
		button.pressed.connect(_toggle_playlist.bind(index))
	if added:
		button.icon = preload("res://resources/icons/checkbox-checked.svg")
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.add_theme_constant_override("icon_max_width", 20)
	row.add_child(button)
	return row


func _playlist_contains_current(playlist: Dictionary) -> bool:
	return bool(playlist.get("contains_chartset", false))


func _toggle_playlist(index: int) -> void:
	if _busy or index < 0 or index >= _playlists.size():
		return
	var playlist_id := int(_playlists[index].get("id", 0))
	var chartset_id := _current_chartset_id()
	if playlist_id <= 0 or chartset_id <= 0:
		_set_status("This map cannot be updated.")
		return
	var added := _playlist_contains_current(_playlists[index])
	var method := HTTPClient.METHOD_DELETE if added else HTTPClient.METHOD_PUT
	var operation := ("remove:" if added else "add:") + str(index)
	if _send(operation, "/playlists/%d/chartsets/%d" % [playlist_id, chartset_id], method):
		_set_status("")


func _update_playlist_membership(index: int, added: bool) -> void:
	if index < 0 or index >= _playlists.size():
		return
	var playlist := _playlists[index].duplicate(true)
	var count := int(playlist.get("item_count", 0))
	var was_added := _playlist_contains_current(playlist)
	playlist["contains_chartset"] = added
	if added and not was_added:
		playlist["item_count"] = count + 1
	elif not added and was_added:
		playlist["item_count"] = maxi(0, count - 1)
	_playlists[index] = playlist
	_render_playlists()


func _current_chartset_id() -> int:
	return int(_current_chartset.get("id", _current_chartset.get("chartset_id", 0)))


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
		status_label.visible = not text.is_empty()
		panel.reset_size()


func _update_item_disabled_state() -> void:
	for row in item_list.get_children():
		for child in row.get_children():
			if child is Button:
				child.disabled = _busy


func _position_panel() -> void:
	if panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var target_position := _target_rect.position + Vector2(_target_rect.size.x, _target_rect.size.y) + OPEN_OFFSET
	if _target_rect == Rect2():
		target_position = Vector2(210.0, 62.0)
	elif browsing:
		target_position = Vector2(_target_rect.position.x, _target_rect.end.y + 8.0)
	var panel_size := panel.size
	if panel_size.x <= 1.0 or panel_size.y <= 1.0:
		panel_size = panel.custom_minimum_size
	target_position.x = clampf(target_position.x, 18.0, maxf(18.0, viewport_size.x - panel_size.x - 18.0))
	target_position.y = clampf(target_position.y, 18.0, maxf(18.0, viewport_size.y - panel_size.y - 120.0))
	panel.global_position = target_position


func _play_open_animation() -> void:
	if panel == null:
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(panel, "modulate:a", 1.0, OPEN_DURATION)
	_tween.tween_property(panel, "offset_transform_scale", Vector2.ONE, OPEN_DURATION)


func _play_close_animation() -> void:
	if panel == null:
		visible = false
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN)
	_tween.tween_property(panel, "modulate:a", 0.0, CLOSE_DURATION)
	_tween.tween_property(panel, "offset_transform_scale", Vector2(0.98, 0.98), CLOSE_DURATION)
	_tween.finished.connect(func() -> void:
		panel.visible = false
		visible = false
	)


func _apply_styles() -> void:
	if panel != null:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = COLOR_PANEL
		panel_style.set_border_width_all(0)
		panel_style.set_corner_radius_all(8)
		panel_style.shadow_color = Color(0, 0, 0, 0.24)
		panel_style.shadow_size = 8
		panel.add_theme_stylebox_override("panel", panel_style)
	if status_label != null:
		status_label.add_theme_color_override("font_color", COLOR_MUTED)


func _build_item_theme(added: bool = false) -> Theme:
	var theme := Theme.new()
	if item_font != null:
		theme.set_font("font", "Button", item_font)
	theme.set_font_size("font_size", "Button", 24)
	theme.set_color("font_color", "Button", COLOR_ADDED_TEXT if added else COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(COLOR_MUTED.r, COLOR_MUTED.g, COLOR_MUTED.b, 0.5))
	theme.set_stylebox("normal", "Button", _style(COLOR_ITEM_ADDED if added else COLOR_ITEM))
	theme.set_stylebox("hover", "Button", _style(COLOR_ITEM_HOVER))
	theme.set_stylebox("pressed", "Button", _style(COLOR_ITEM_PRESSED))
	theme.set_stylebox("hover_pressed", "Button", _style(COLOR_ITEM_PRESSED))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return theme


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.set_corner_radius_all(4)
	return style


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := get_global_mouse_position()
		if not panel.get_global_rect().has_point(mouse) and not _target_rect.has_point(mouse):
			close()
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if request != null:
		request.cancel_request()
