extends Control
class_name SongFilterPopup

## Shared modal for local song selection and the online catalogue.
signal applied(filters: SongFilters)
signal visibility_set(blocked: bool)

var _online := false
var _open := false
var _saved: SongFilters
@export_group("Node References")
@export var _sort: OptionButton
@export var ranked_button: Button
@export var approved_button: Button
@export var unranked_button: Button
@export var _played: OptionButton
@export var _reverse: CheckBox
@export var _nsfl: CheckBox
@export var _error: Label
@export var _panel: PanelContainer
@export var _overlay: ColorRect
@export var length_range: FilterRangeSlider
@export var rating_range: FilterRangeSlider
@export var max_size: LineEdit
@export var rank_status_row: Control
@export var content_row: Control
@export var max_download_row: Control
@export var reset_button: Button
@export var bottom_close_button: Button
var _server_rows: Array[Control]
var _tween: Tween
var _previous_focus: Control

func _ready() -> void:
	_server_rows = [rank_status_row, content_row, max_download_row]
	_overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_apply()
	)
	reset_button.pressed.connect(func(): _sync(SongFilters.new(_online)))
	bottom_close_button.pressed.connect(_apply)

func show_popup(online: bool, values: SongFilters, authenticated: bool = false) -> void:
	_online = online
	_saved = values.copy()
	_sort.clear()
	if online:
		_add_sort_option(GameText.Key.FILTER_SORT_NEWEST, "newest")
		_add_sort_option(GameText.Key.FILTER_SORT_LENGTH, "length")
		_add_sort_option(GameText.Key.FILTER_SORT_FARMING, "farming")
		_add_sort_option(GameText.Key.FILTER_SORT_POPULARITY, "popularity")
	else:
		_add_sort_option(GameText.Key.FILTER_SORT_TITLE, "title")
		_add_sort_option(GameText.Key.FILTER_SORT_ARTIST, "artist")
		_add_sort_option(GameText.Key.FILTER_SORT_DIFFICULTY, "rating")
		_add_sort_option(GameText.Key.PLAYLIST_RECENT, "recent")
		_add_sort_option(GameText.Key.FILTER_SORT_LENGTH, "length")
	for row in _server_rows:
		row.visible = online
	_played.disabled = online and not authenticated
	_sync(_saved)
	_previous_focus = get_viewport().gui_get_focus_owner()
	_open = true
	show()
	visibility_set.emit(true)
	_animate(true)
	_sort.grab_focus()

func _add_sort_option(caption: GameText.Key, value: String) -> void:
	_sort.add_item(GameText.text(caption))
	_sort.set_item_metadata(_sort.item_count - 1, value)

func _sync(values: SongFilters) -> void:
	for i in range(_sort.item_count):
		if _sort.get_item_metadata(i) == values.sort:
			_sort.select(i)
	_reverse.button_pressed = values.reverse
	_nsfl.button_pressed = values.nsfl
	ranked_button.set_pressed_no_signal(values.status == "ranked")
	approved_button.set_pressed_no_signal(values.status == "approved")
	unranked_button.set_pressed_no_signal(values.status == "unranked")
	_played.select(values.played)
	length_range.set_values(maxi(0, values.min_length_ms / 30000), length_range.finite_steps + 1 if values.max_length_ms < 0 else ceili(values.max_length_ms / 30000.0))
	rating_range.set_values(maxi(0, floori(values.min_rating)), rating_range.finite_steps + 1 if values.max_rating < 0 else floori(values.max_rating))
	max_size.text = _format_bound(values.max_size_bytes, 1048576.0)
	_error.text = ""

func _format_bound(value: float, divisor: float = 1.0) -> String:
	return str(value / divisor) if value >= 0 else ""

func _read_bound(field: LineEdit, multiplier: float = 1.0) -> float:
	var text_value := field.text.strip_edges()
	return -1.0 if text_value.is_empty() else float(text_value) * multiplier

func _apply() -> void:
	if not _open:
		return
	var size_text := max_size.text.strip_edges()
	if _online and not size_text.is_empty() and (not size_text.is_valid_float() or not is_finite(float(size_text)) or float(size_text) < 0):
		_error.text = GameText.text(GameText.Key.HINT_FILTER_NUMBER)
		return
	var values := SongFilters.new(_online)
	values.sort = _sort.get_selected_metadata()
	values.reverse = _reverse.button_pressed
	values.nsfl = _online and _nsfl.button_pressed
	values.min_rating = rating_range.lower if rating_range.lower > 0 else -1.0
	values.max_rating = rating_range.upper if rating_range.upper <= rating_range.finite_steps else -1.0
	values.min_length_ms = length_range.lower * 30000 if length_range.lower > 0 else -1
	values.max_length_ms = length_range.upper * 30000 if length_range.upper <= length_range.finite_steps else -1
	if _online:
		values.max_size_bytes = int(_read_bound(max_size, 1048576.0))
		if ranked_button.button_pressed:
			values.status = "ranked"
		elif approved_button.button_pressed:
			values.status = "approved"
		elif unranked_button.button_pressed:
			values.status = "unranked"
	if not _played.disabled:
		values.played = _played.selected as SongFilters.PlayHistory
	applied.emit(values)
	close_popup()

func is_open() -> bool:
	return visible

func close_popup() -> void:
	if not _open:
		return
	_open = false
	_animate(false)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_apply()
		get_viewport().set_input_as_handled()

func _animate(opening: bool) -> void:
	if _tween:
		_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_tween = create_tween().set_parallel(true)
	if opening:
		_panel.scale = Vector2.ONE * 0.9
		modulate.a = 0
		_tween.tween_property(self, "modulate:a", 1.0, 0.12)
		_tween.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, 0.14)
		_tween.tween_property(_panel, "scale", Vector2.ONE * 0.94, 0.14)
		_tween.finished.connect(func():
			hide()
			visibility_set.emit(false)
			if is_instance_valid(_previous_focus):
				_previous_focus.grab_focus()
		)
