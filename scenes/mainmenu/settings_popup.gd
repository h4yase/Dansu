extends Control
class_name SettingsPopup

const HIDDEN_SCALE := Vector2(0.38, 0.38)
const OPEN_OVERSHOOT_SCALE := Vector2(1.035, 1.035)
const OPEN_SETTLE_SCALE := Vector2(0.985, 0.985)
const OVERLAY_OPEN_DURATION := 0.08
const OVERLAY_CLOSE_DURATION := 0.12
const OPEN_BOUNCE_DURATION := 0.11
const OPEN_SETTLE_DURATION := 0.06
const OPEN_FINISH_DURATION := 0.04
const CLOSE_DURATION := 0.14
const INFINITE_FPS_TEXT := "Infinite"

@export_group("Node References")
@export var overlay: ColorRect
@export var panel: PanelContainer
@export var tab_container: TabContainer
@export var close_button: Button
@export var window_mode_option: OptionButton
@export var vsync_option: OptionButton
@export var max_fps_spin: SpinBox
@export var taa_check: CheckBox
@export var msaa_option: OptionButton
@export var master_slider: HSlider
@export var master_value: Label
@export var music_slider: HSlider
@export var music_value: Label
@export var sfx_slider: HSlider
@export var sfx_value: Label
@export var hit_effect_slider: HSlider
@export var hit_effect_value: Label
@export var offset_spin: SpinBox
@export var note_speed_slider: HSlider
@export var note_speed_value: Label
@export var action_left_button: Button
@export var action_right_button: Button
@export var action_hit1_button: Button
@export var action_hit2_button: Button
@export var ignore_chart_skin_check: CheckBox
@export var chart_load_threads_spin: SpinBox
@export var api_url_edit: LineEdit

var max_fps_line_edit: LineEdit

var _is_open := false
var _is_syncing := false
var _tween: Tween
var _pending_keybind_action := ""


func _ready() -> void:
	max_fps_line_edit = max_fps_spin.get_line_edit()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

	_setup_options()
	_connect_signals()
	_sync_from_config()

	overlay.modulate.a = 0.0
	panel.modulate.a = 1.0
	panel.offset_transform_enabled = true
	panel.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	panel.offset_transform_scale = HIDDEN_SCALE


func show_popup() -> void:
	if _is_open:
		return

	_is_open = true
	visible = true
	tab_container.current_tab = 0
	_sync_from_config()
	_play_tween(true)


func close_popup() -> void:
	if not _is_open:
		return

	_is_open = false
	_play_tween(false)


func is_open() -> bool:
	return _is_open


func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	if _pending_keybind_action == "":
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_pending_keybind_action = ""
			_refresh_keybind_labels()
		else:
			_apply_keybind(_pending_keybind_action, event.physical_keycode)
			_pending_keybind_action = ""
			_refresh_keybind_labels()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if _pending_keybind_action != "":
		return

	if event.is_action_pressed("ui_cancel"):
		close_popup()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not panel.get_global_rect().has_point(event.position):
			close_popup()
			get_viewport().set_input_as_handled()


func _setup_options() -> void:
	window_mode_option.clear()
	window_mode_option.add_item("Fullscreen", DisplayServer.WINDOW_MODE_FULLSCREEN)
	window_mode_option.add_item("Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
	window_mode_option.add_item("Exclusive", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	vsync_option.clear()
	vsync_option.add_item("Disabled", DisplayServer.VSYNC_DISABLED)
	vsync_option.add_item("Enabled", DisplayServer.VSYNC_ENABLED)
	vsync_option.add_item("Adaptive", DisplayServer.VSYNC_ADAPTIVE)
	vsync_option.add_item("Mailbox", DisplayServer.VSYNC_MAILBOX)

	msaa_option.clear()
	msaa_option.add_item("Off", Viewport.MSAA_DISABLED)
	msaa_option.add_item("2x", Viewport.MSAA_2X)
	msaa_option.add_item("4x", Viewport.MSAA_4X)
	msaa_option.add_item("8x", Viewport.MSAA_8X)

	max_fps_spin.min_value = 0.0
	max_fps_spin.max_value = 2000.0
	max_fps_spin.step = 1.0


func _connect_signals() -> void:
	close_button.pressed.connect(close_popup)

	window_mode_option.item_selected.connect(_on_window_mode_selected)
	vsync_option.item_selected.connect(_on_vsync_selected)
	max_fps_spin.value_changed.connect(_on_max_fps_changed)
	taa_check.toggled.connect(_on_taa_toggled)
	msaa_option.item_selected.connect(_on_msaa_selected)

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	hit_effect_slider.value_changed.connect(_on_hit_effect_changed)
	offset_spin.value_changed.connect(_on_offset_changed)

	note_speed_slider.value_changed.connect(_on_note_speed_changed)
	action_left_button.pressed.connect(_begin_keybind_capture.bind("action_left"))
	action_right_button.pressed.connect(_begin_keybind_capture.bind("action_right"))
	action_hit1_button.pressed.connect(_begin_keybind_capture.bind("action_hit1"))
	action_hit2_button.pressed.connect(_begin_keybind_capture.bind("action_hit2"))
	ignore_chart_skin_check.toggled.connect(_on_ignore_chart_skin_toggled)

	chart_load_threads_spin.value_changed.connect(_on_chart_threads_changed)
	api_url_edit.editable = false


func _sync_from_config() -> void:
	_is_syncing = true

	_select_option_by_id(window_mode_option, int(Config.window_mode))
	_select_option_by_id(vsync_option, int(Config.vsync_mode))
	_select_option_by_id(msaa_option, int(Config.msaa))

	max_fps_spin.value = Config.max_fps
	_refresh_max_fps_display()
	taa_check.button_pressed = Config.taa

	master_slider.value = Config.master_db
	music_slider.value = Config.music_db
	sfx_slider.value = Config.sfx_db
	hit_effect_slider.value = Config.hit_effect_db
	offset_spin.value = Config.offset

	note_speed_slider.value = Config.note_speed
	ignore_chart_skin_check.button_pressed = Config.ignore_chart_skin
	_refresh_keybind_labels()

	chart_load_threads_spin.value = Config.chart_load_threads
	api_url_edit.text = Config.SERVER_URL

	_refresh_value_labels()
	_is_syncing = false


func _play_tween(opening: bool) -> void:
	if _tween != null:
		_tween.kill()

	_tween = create_tween()

	if opening:
		overlay.modulate.a = 0.0
		panel.modulate.a = 1.0
		panel.offset_transform_scale = HIDDEN_SCALE
		_tween.set_parallel(true)
		_tween.tween_property(overlay, "modulate:a", 0.78, OVERLAY_OPEN_DURATION)
		_tween.tween_property(panel, "offset_transform_scale", OPEN_OVERSHOOT_SCALE, OPEN_BOUNCE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.chain().tween_property(panel, "offset_transform_scale", OPEN_SETTLE_SCALE, OPEN_SETTLE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.chain().tween_property(panel, "offset_transform_scale", Vector2.ONE, OPEN_FINISH_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_tween.set_parallel(true)
		_tween.tween_property(overlay, "modulate:a", 0.0, OVERLAY_CLOSE_DURATION)
		_tween.tween_property(panel, "offset_transform_scale", HIDDEN_SCALE, CLOSE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_tween.finished.connect(func() -> void:
			if not _is_open:
				visible = false
		)

func _select_option_by_id(option: OptionButton, target_id: int) -> void:
	for i in range(option.item_count):
		if option.get_item_id(i) == target_id:
			option.select(i)
			return
	if option.item_count > 0:
		option.select(0)


func _persist() -> void:
	Config.config.save(Config.FILE_PATH)


func _refresh_value_labels() -> void:
	master_value.text = _format_percent(master_slider.value)
	music_value.text = _format_percent(music_slider.value)
	sfx_value.text = _format_percent(sfx_slider.value)
	hit_effect_value.text = _format_percent(hit_effect_slider.value)
	note_speed_value.text = "%.0f" % note_speed_slider.value


func _refresh_keybind_labels() -> void:
	action_left_button.text = _get_keybind_button_text("action_left", Config.action_left)
	action_right_button.text = _get_keybind_button_text("action_right", Config.action_right)
	action_hit1_button.text = _get_keybind_button_text("action_hit1", Config.action_hit1)
	action_hit2_button.text = _get_keybind_button_text("action_hit2", Config.action_hit2)


func _get_keybind_button_text(action_name: String, keycode: Key) -> String:
	if _pending_keybind_action == action_name:
		return "Press key..."
	return OS.get_keycode_string(keycode)


func _begin_keybind_capture(action_name: String) -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is Control:
		focus_owner.release_focus()
	_pending_keybind_action = action_name
	_refresh_keybind_labels()


func _apply_keybind(action_name: String, keycode: Key) -> void:
	match action_name:
		"action_left":
			Config.action_left = keycode
		"action_right":
			Config.action_right = keycode
		"action_hit1":
			Config.action_hit1 = keycode
		"action_hit2":
			Config.action_hit2 = keycode
		_:
			return
	_persist()


func _format_percent(value: float) -> String:
	return "%d" % int(round(value * 100.0))


func _refresh_max_fps_display() -> void:
	if max_fps_line_edit == null:
		return
	if int(max_fps_spin.value) == 0:
		max_fps_line_edit.text = INFINITE_FPS_TEXT


func _on_window_mode_selected(index: int) -> void:
	if _is_syncing:
		return
	Config.window_mode = window_mode_option.get_item_id(index) as DisplayServer.WindowMode
	_persist()


func _on_vsync_selected(index: int) -> void:
	if _is_syncing:
		return
	Config.vsync_mode = vsync_option.get_item_id(index) as DisplayServer.VSyncMode
	_persist()


func _on_max_fps_changed(value: float) -> void:
	if _is_syncing:
		_refresh_max_fps_display()
		return

	Config.max_fps = int(value)
	var sanitized := Config.max_fps
	if int(max_fps_spin.value) != sanitized:
		_is_syncing = true
		max_fps_spin.value = sanitized
		_is_syncing = false
	_refresh_max_fps_display()
	_persist()


func _on_taa_toggled(enabled: bool) -> void:
	if _is_syncing:
		return
	Config.taa = enabled
	_persist()


func _on_msaa_selected(index: int) -> void:
	if _is_syncing:
		return
	Config.msaa = msaa_option.get_item_id(index) as Viewport.MSAA
	_persist()


func _on_master_changed(value: float) -> void:
	master_value.text = _format_percent(value)
	if _is_syncing:
		return
	Config.master_db = value
	_persist()


func _on_music_changed(value: float) -> void:
	music_value.text = _format_percent(value)
	if _is_syncing:
		return
	Config.music_db = value
	_persist()


func _on_sfx_changed(value: float) -> void:
	sfx_value.text = _format_percent(value)
	if _is_syncing:
		return
	Config.sfx_db = value
	_persist()


func _on_hit_effect_changed(value: float) -> void:
	hit_effect_value.text = _format_percent(value)
	if _is_syncing:
		return
	Config.hit_effect_db = value
	_persist()


func _on_offset_changed(value: float) -> void:
	if _is_syncing:
		return
	Config.offset = int(value)
	_persist()


func _on_note_speed_changed(value: float) -> void:
	note_speed_value.text = "%.0f" % value
	if _is_syncing:
		return
	Config.note_speed = value
	_persist()


func _on_ignore_chart_skin_toggled(enabled: bool) -> void:
	if _is_syncing:
		return
	Config.ignore_chart_skin = enabled
	_persist()


func _on_chart_threads_changed(value: float) -> void:
	if _is_syncing:
		return
	Config.chart_load_threads = int(value)
	_persist()
