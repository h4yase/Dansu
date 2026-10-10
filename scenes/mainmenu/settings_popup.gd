extends Control
class_name SettingsPopup

const PANEL_WIDTH := 650.0
const PANEL_TOP := 87.0
const HIDDEN_X := -850.0
const AUDIO_ICON := preload("res://resources/textures/settings/audio.svg")
const GRAPHICS_ICON := preload("res://resources/textures/settings/graphics.svg")
const GAMEPLAY_ICON := preload("res://resources/textures/settings/gameplay.svg")
const KEYS_ICON := preload("res://resources/textures/settings/keybinds.svg")
const SYSTEM_ICON := preload("res://resources/textures/settings/system.svg")

var panel: SettingsPanel
var scroll: SettingsScroll
var master_dial: SettingsDial
var music_dial: SettingsDial
var sfx_dial: SettingsDial
var offset_field: SettingsNumber
var output_latency_field: SettingsNumber
var max_fps_field: SettingsNumber
var note_speed_field: SettingsNumber
var judgment_line_field: SettingsNumber
var player_size_field: SettingsNumber
var play_area_tilt_field: SettingsNumber
var chart_threads_field: SettingsNumber
var window_mode_choice: SettingsChoice
var vsync_choice: SettingsChoice
var msaa_choice: SettingsChoice
var taa_choice: SettingsChoice
var ignore_skin_choice: SettingsChoice
var language_choice: SettingsChoice
var left_key: SettingsButton
var right_key: SettingsButton
var hit1_key: SettingsButton
var hit2_key: SettingsButton
var _sections: Array[SettingsSection] = []
var _bookmarks: Array[SettingsButton] = []
var _is_open := false
var _tween: Tween
var _pending_keybind_action := ""
var _language_before_focus := ""
var _previous_focus: Control
var _overlay_alpha := 0.0:
	set(value):
		_overlay_alpha = value
		queue_redraw()

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 50
	panel = SettingsPanel.new()
	panel.name = "Panel"
	add_child(panel)
	scroll = SettingsScroll.new()
	scroll.name = "Options"
	panel.add_child(scroll)
	scroll.wheel_scrolled.connect(panel.spin_gear)
	scroll.moved.connect(_update_bookmarks)
	_build_options()
	resized.connect(_layout)
	_layout()
	panel.position.x = HIDDEN_X * panel.scale.x
	_sync_from_config()

func _build_options() -> void:
	var audio := _add_section(GameText.Key.SETTINGS_AUDIO, AUDIO_ICON)
	master_dial = _make_dial(GameText.Key.SETTINGS_MASTER_VOLUME, &"master_db", true)
	music_dial = _make_dial(GameText.Key.SETTINGS_MUSIC_VOLUME, &"music_db")
	sfx_dial = _make_dial(GameText.Key.SETTINGS_SFX_VOLUME, &"sfx_db")
	audio.add_dials(master_dial, music_dial, sfx_dial)
	offset_field = _add_number(audio, GameText.Key.SETTINGS_AUDIO_OFFSET, &"offset", -250, 250, 1, "ms")
	output_latency_field = _add_number(audio, GameText.Key.SETTINGS_OUTPUT_LATENCY, &"output_latency", AppConfig.MIN_OUTPUT_LATENCY, AppConfig.MAX_OUTPUT_LATENCY, 1, "ms")
	output_latency_field.hint = GameText.text(GameText.Key.SETTINGS_APPLY_AFTER_RESTART)

	var graphics := _add_section(GameText.Key.SETTINGS_GRAPHICS, GRAPHICS_ICON)
	window_mode_choice = _add_choice(graphics, GameText.text(GameText.Key.SETTINGS_WINDOW_MODE),
		[GameText.text(GameText.Key.SETTINGS_FULLSCREEN), GameText.text(GameText.Key.SETTINGS_WINDOWED), GameText.text(GameText.Key.SETTINGS_EXCLUSIVE_FULLSCREEN)],
		[DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])
	window_mode_choice.item_selected.connect(func(index: int):
		Config.window_mode = window_mode_choice.item_ids[index]
		_persist()
	)
	vsync_choice = _add_choice(graphics, GameText.text(GameText.Key.SETTINGS_VSYNC),
		[GameText.text(GameText.Key.SETTINGS_DISABLED), GameText.text(GameText.Key.SETTINGS_ENABLED), GameText.text(GameText.Key.SETTINGS_VSYNC_ADAPTIVE), GameText.text(GameText.Key.SETTINGS_VSYNC_MAILBOX)],
		[DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_MAILBOX])
	vsync_choice.item_selected.connect(func(index: int):
		Config.vsync_mode = vsync_choice.item_ids[index]
		_persist()
	)
	max_fps_field = _add_number(graphics, GameText.Key.SETTINGS_MAX_FPS, &"max_fps", 0, 2000)
	max_fps_field.minimum_positive = AppConfig.MIN_MAX_FPS
	max_fps_field.zero_text = GameText.text(GameText.Key.SETTINGS_FPS_UNLIMITED)
	taa_choice = _add_toggle(graphics, GameText.Key.SETTINGS_TEMPORAL_AA, &"taa")
	msaa_choice = _add_choice(graphics, "MSAA",
		[GameText.text(GameText.Key.SETTINGS_AA_OFF), "2x", "4x", "8x"],
		[Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X])
	msaa_choice.item_selected.connect(func(index: int):
		Config.msaa = msaa_choice.item_ids[index]
		_persist()
	)

	var gameplay := _add_section(GameText.Key.SETTINGS_GAMEPLAY, GAMEPLAY_ICON)
	note_speed_field = _add_number(gameplay, GameText.Key.SETTINGS_NOTE_SPEED, &"note_speed", 10, 120)
	judgment_line_field = _add_number(gameplay, GameText.Key.SETTINGS_JUDGMENT_LINE_POSITION, &"judgment_line_position", -50, 50)
	player_size_field = _add_number(gameplay, GameText.Key.SETTINGS_PLAYER_SIZE, &"player_size", 0.5, 2.0, 0.05)
	play_area_tilt_field = _add_number(gameplay, GameText.Key.SETTINGS_PLAY_AREA_TILT, &"play_area_tilt", 0, 90, 1, "°")
	ignore_skin_choice = _add_toggle(gameplay, GameText.Key.SETTINGS_IGNORE_CHART_SKIN, &"ignore_chart_skin")

	var keys := _add_section(GameText.Key.SETTINGS_KEYBINDS, KEYS_ICON)
	left_key = _add_key(keys, GameText.Key.SETTINGS_MOVE_LEFT, "action_left")
	right_key = _add_key(keys, GameText.Key.SETTINGS_MOVE_RIGHT, "action_right")
	hit1_key = _add_key(keys, GameText.Key.SETTINGS_NOTE_HIT_1, "action_hit1")
	hit2_key = _add_key(keys, GameText.Key.SETTINGS_NOTE_HIT_2, "action_hit2")

	var system := _add_section(GameText.Key.SETTINGS_SYSTEM, SYSTEM_ICON)
	language_choice = _add_choice(system, GameText.text(GameText.Key.SETTINGS_LANGUAGE), [], [])
	for locale in Localization.available_locales:
		language_choice.items.append(TranslationServer.get_locale_name(locale))
	language_choice.focus_entered.connect(func():
		_language_before_focus = Config.language
	)
	language_choice.focus_exited.connect(func():
		if Config.language != _language_before_focus:
			Notification.notice(GameText.text(GameText.Key.HINT_LANGUAGE_RESTART))
	)
	language_choice.item_selected.connect(func(index: int):
		Config.language = Localization.available_locales[index]
		_persist()
	)
	chart_threads_field = _add_number(system, GameText.Key.SETTINGS_CHART_LOAD_THREADS, &"chart_load_threads", 1, 32)

func _add_section(caption: GameText.Key, icon: Texture2D) -> SettingsSection:
	var section := SettingsSection.new()
	section.caption = GameText.text(caption)
	section.icon = icon
	_sections.append(section)
	scroll.content.add_child(section)
	var bookmark := SettingsButton.new()
	bookmark.caption = section.caption
	bookmark.icon = icon
	bookmark.bookmark = true
	bookmark.pressed.connect(_jump_to_section.bind(section))
	_bookmarks.append(bookmark)
	panel.add_child(bookmark)
	return section

func _make_dial(caption: GameText.Key, property: StringName, large: bool = false) -> SettingsDial:
	var dial := SettingsDial.new()
	dial.caption = GameText.text(caption)
	dial.large = large
	dial.value_changed.connect(func(value: float):
		Config.set(property, value)
		_persist()
	)
	_connect_focus(dial)
	return dial

func _add_number(section: SettingsSection, caption: GameText.Key, property: StringName, minimum: float, maximum: float, step: float = 1.0, unit: String = "") -> SettingsNumber:
	var field := SettingsNumber.new()
	field.caption = GameText.text(caption)
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.unit = unit
	field.value_changed.connect(func(value: float):
		Config.set(property, value)
		field.set_value(float(Config.get(property)))
		_persist()
	)
	section.add_row(field)
	_connect_focus(field)
	return field

func _add_choice(section: SettingsSection, caption: String, items: PackedStringArray, ids: PackedInt32Array) -> SettingsChoice:
	var choice := SettingsChoice.new()
	choice.caption = caption
	choice.items = items
	choice.item_ids = ids
	section.add_row(choice)
	_connect_focus(choice)
	return choice

func _add_toggle(section: SettingsSection, caption: GameText.Key, property: StringName) -> SettingsChoice:
	var choice := _add_choice(section, GameText.text(caption), [GameText.text(GameText.Key.SETTINGS_DISABLED), GameText.text(GameText.Key.SETTINGS_ENABLED)], [0, 1])
	choice.toggle = true
	choice.item_selected.connect(func(index: int):
		Config.set(property, index > 0)
		_persist()
	)
	return choice

func _add_key(section: SettingsSection, caption: GameText.Key, action: String) -> SettingsButton:
	var button := SettingsButton.new()
	button.row_title = GameText.text(caption)
	button.pressed.connect(_begin_keybind_capture.bind(action))
	section.add_row(button, 74)
	_connect_focus(button)
	return button

func _connect_focus(control: Control) -> void:
	control.focus_entered.connect(func():
		var y := control.position.y + (control.get_parent() as Control).position.y
		if y < scroll.target + SettingsScroll.EDGE_SPACE:
			scroll.scroll_to(y - SettingsScroll.EDGE_SPACE, true)
		elif y + control.size.y > scroll.target + scroll.size.y - SettingsScroll.EDGE_SPACE:
			scroll.scroll_to(y + control.size.y - scroll.size.y + SettingsScroll.EDGE_SPACE, true)
	)

func _layout() -> void:
	var ui_scale := minf(1.0, minf(size.x / 850.0, size.y / 780.0))
	panel.scale = Vector2.ONE * ui_scale
	panel.position.y = PANEL_TOP * ui_scale
	panel.size = Vector2(PANEL_WIDTH, size.y / maxf(ui_scale, 0.01) - PANEL_TOP)
	if not visible:
		panel.position.x = HIDDEN_X * ui_scale
	scroll.position = Vector2(34, 0)
	scroll.size = Vector2(PANEL_WIDTH - 68, panel.size.y)
	var y := SettingsScroll.EDGE_SPACE
	for i in range(_sections.size()):
		var section := _sections[i]
		section.position = Vector2(0, y)
		section.size = Vector2(scroll.size.x - 24, section.content_height)
		y += section.content_height + 46
		_bookmarks[i].position = Vector2(PANEL_WIDTH - 2, 70 + i * 72)
		_bookmarks[i].size = Vector2(168, 58)
	var last_height: float = _sections.back().content_height
	scroll.content.size = Vector2(scroll.size.x, y - 46 + maxf(SettingsScroll.EDGE_SPACE, scroll.size.y - last_height - SettingsScroll.EDGE_SPACE))
	scroll.scroll_to(scroll.target)
	queue_redraw()

func show_popup() -> void:
	if _is_open:
		return
	if not visible:
		_previous_focus = get_viewport().gui_get_focus_owner()
	_is_open = true
	visible = true
	_sync_from_config()
	scroll.reset()
	_play_tween(true)
	master_dial.grab_focus()

func close_popup() -> void:
	if not _is_open:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	_pending_keybind_action = ""
	_refresh_keybind_labels()
	_is_open = false
	_play_tween(false)

func is_open() -> bool:
	return _is_open

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(SettingsPaint.OVERLAY, _overlay_alpha))

func _play_tween(opening: bool) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	if opening:
		_tween.tween_property(self, "_overlay_alpha", 0.70, 0.22)
		_tween.tween_property(panel, "position:x", 10.0, 0.30).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_tween.chain().tween_property(panel, "position:x", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "_overlay_alpha", 0.0, 0.20)
		_tween.tween_property(panel, "position:x", HIDDEN_X * panel.scale.x, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.finished.connect(func():
			if not _is_open:
				visible = false
				if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
					_previous_focus.grab_focus()
		)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not _is_open:
		get_viewport().set_input_as_handled()
		return
	if not _pending_keybind_action.is_empty() and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode != KEY_ESCAPE:
			Config.set(_pending_keybind_action, event.physical_keycode)
			_persist()
		_pending_keybind_action = ""
		_refresh_keybind_labels()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll.scroll_wheel((-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * event.factor)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		scroll.scroll_wheel(event.delta.y * 0.3)
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_popup()
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close_popup()
		get_viewport().set_input_as_handled()

func _jump_to_section(section: SettingsSection) -> void:
	scroll.scroll_to(section.position.y - SettingsScroll.EDGE_SPACE, true)

func _update_bookmarks(offset: float) -> void:
	var active := 0
	for i in range(_sections.size()):
		if _sections[i].position.y <= offset + SettingsScroll.EDGE_SPACE + 20:
			active = i
	for i in range(_bookmarks.size()):
		_bookmarks[i].selected = i == active
		_bookmarks[i].queue_redraw()

func _sync_from_config() -> void:
	master_dial.set_value(Config.master_db)
	music_dial.set_value(Config.music_db)
	sfx_dial.set_value(Config.sfx_db)
	offset_field.set_value(Config.offset)
	output_latency_field.set_value(Config.output_latency)
	max_fps_field.set_value(Config.max_fps)
	note_speed_field.set_value(Config.note_speed)
	judgment_line_field.set_value(Config.judgment_line_position)
	player_size_field.set_value(Config.player_size)
	play_area_tilt_field.set_value(Config.play_area_tilt)
	chart_threads_field.set_value(Config.chart_load_threads)
	window_mode_choice.select_id(Config.window_mode)
	vsync_choice.select_id(Config.vsync_mode)
	msaa_choice.select_id(Config.msaa)
	taa_choice.select(int(Config.taa))
	ignore_skin_choice.select(int(Config.ignore_chart_skin))
	language_choice.select(Localization.available_locales.find(Config.language))
	_refresh_keybind_labels()

func _begin_keybind_capture(action: String) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	_pending_keybind_action = action
	_refresh_keybind_labels()

func _refresh_keybind_labels() -> void:
	left_key.caption = _key_text("action_left", Config.action_left)
	right_key.caption = _key_text("action_right", Config.action_right)
	hit1_key.caption = _key_text("action_hit1", Config.action_hit1)
	hit2_key.caption = _key_text("action_hit2", Config.action_hit2)
	for button in [left_key, right_key, hit1_key, hit2_key]:
		button.queue_redraw()

func _key_text(action: String, keycode: Key) -> String:
	if _pending_keybind_action == action:
		return GameText.text(GameText.Key.SETTINGS_PRESS_KEY)
	if keycode > KEY_SPACE and keycode < KEY_SPECIAL:
		return String.chr(keycode)
	return OS.get_keycode_string(keycode)

func _persist() -> void:
	Config.config.save(Config.FILE_PATH)
