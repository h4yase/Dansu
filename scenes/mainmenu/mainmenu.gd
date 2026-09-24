extends Control
class_name DansuMainMenu

@onready var inline_leaderboard: InlineLeaderboard = $ChartInfo/InlineLeaderboard
@onready var playlist_selector: Button = $Charts/VBoxContainer/TabBar/PlaylistSelector

const LOGO_IDLE_SCALE := 1.0
const LOGO_PEAK_SCALE := 1.15
const LOGO_DIP_SCALE := 0.96
const LOGO_PULSE_DURATION := 0.34
const LOGO_RETURN_SPEED := 12.0
const EXIT_START_DELAY := 0.4
const EXIT_FADE_DURATION := 1.5
const MIN_LOADING_DISPLAY_SECONDS := 1.0
const LOGIN_LOADING_TTL_SECONDS := 15.0

@export var progress_bar : ProgressBar
@export var current_chartset_label: Label
@export var search_input: LineEdit
@export var filter_button: Button
@export var source_tabs: SourceSwitch
@export var chart_scroll: ChartScroll
@export var exit_overlay: ColorRect
@export var audio_1: AudioStreamPlayer
@export var audio_2: AudioStreamPlayer
@export var menu_audio_switcher: MenuAudioSwitcher
@export var settings_popup: SettingsPopup
@export var logo: Control
@export var menu_buttons: VBoxContainer
@export var account_panel: AccountPanel
@export var username_setup_overlay: ColorRect
@export var username_input: LineEdit
@export var username_status: Label
@export var username_submit_button: Button
@export var bottom_buttons: HBoxContainer
@export var bottom_play_button: MenuBigButton
@export var bottom_edit_button: MenuBigButton
@export var new_chart_button: MenuBigButton
@export var edit_actions: HBoxContainer
@export var loved_button: LovedButton
@export var playlist_button: Button
@export var playlist_panel: PlaylistPanel
@export var new_difficulty_button: Button
@export var delete_difficulty_button: Button
@export var delete_chartset_button: Button
@export var delete_chart_dialog: ConfirmationDialog
@export var _publish_button: Button
@export var chart_info_panel: Panel
@export var _filter_popup: SongFilterPopup
@export var _catalogue: ChartCatalogue
@export var _publisher: ChartPublisher
@export var animations: MainMenuAnimations
@export var switch_player: AudioStreamPlayer
@export var bye_player: AudioStreamPlayer

var progress: float = 0.0
var loading_timer = 0.0
var is_exiting := false
var is_menu_transitioning := false
var is_editor_mode := false
var is_community_mode := false
var _local_filters: SongFilters = SongFilters.new(false)
var _local_search := ""
var _official_chartset_uuid := ""
var _official_chart_uuid := ""
var _community_chartset_uuid := ""
var _community_chart_uuid := ""
var _community_selection_restore_pending := false
var _loading_started_msec := 0
var _login_loading_deadline_msec := 0
var _loading_completion_started := false
var _auth_loading_started := false
var _logo_pulse_time := LOGO_PULSE_DURATION
var _last_logo_half_beat_key := ""
var _last_logo_chart_key := ""
var _last_logo_playback_msec := -1.0
var _pending_delete_scope := ""

func _enter_tree() -> void:
	if is_node_ready():
		call_deferred("_refresh_chart_browser")

func _ready() -> void:
	current_chartset_label.hide()
	_loading_started_msec = Time.get_ticks_msec()
	_loading_completion_started = Game.stage != Game.GameStage.Loading

	exit_overlay.visible = false
	exit_overlay.color.a = 0.0
	logo.offset_transform_enabled = true
	_refresh_logo_pivot()
	_set_button_group_interaction(bottom_buttons, false)

	CM.progress_changed.connect(_update_progress)
	CM.database_sync_finished.connect(_on_database_sync_finished)
	Auth.state_changed.connect(_on_auth_state_changed)
	username_input.text_submitted.connect(func(_value: String): _submit_username())
	username_submit_button.pressed.connect(_submit_username)
	_on_auth_state_changed()

	if Game.stage == Game.GameStage.Loading:
		CM._load(false)

	if search_input != null:
		search_input.text_changed.connect(_on_search_text_changed)

	_setup_catalogue()
	filter_button.pressed.connect(_show_filters)

	new_difficulty_button.pressed.connect(open_new_difficulty_editor)
	delete_difficulty_button.pressed.connect(_request_delete_difficulty)
	delete_chartset_button.pressed.connect(_request_delete_chartset)
	delete_chart_dialog.confirmed.connect(_confirm_chart_delete)
	delete_chart_dialog.canceled.connect(_cancel_chart_delete)
	delete_chart_dialog.theme = settings_popup.theme
	loved_button.pressed.connect(_catalogue.toggle_loved)
	playlist_button.pressed.connect(_open_playlists)
	playlist_selector.pressed.connect(_open_playlist_selector)
	var dropdown_icon := TextureRect.new()
	dropdown_icon.texture = preload("res://resources/icons/chevron-left.svg")
	dropdown_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dropdown_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dropdown_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	playlist_selector.add_child(dropdown_icon)
	dropdown_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	dropdown_icon.position = Vector2(playlist_selector.size.x - 32.0, 14.0)
	dropdown_icon.size = Vector2(20.0, 20.0)
	dropdown_icon.pivot_offset = Vector2(10.0, 10.0)
	dropdown_icon.rotation = -PI / 2.0
	playlist_panel.playlist_selected.connect(func(id: int, title: String):
		playlist_selector.text = title
		playlist_selector.tooltip_text = title
		_catalogue.set_playlist(id)
	)
	playlist_panel.membership_changed.connect(func():
		if _catalogue.playlist_id > 0:
			_catalogue.refresh()
	)
	playlist_panel.visibility_set.connect(func(blocked: bool): chart_scroll.input_blocked = blocked)
	playlist_panel.chartset_chosen.connect(_on_playlist_chartset_chosen)
	_apply_song_select_mode(false)

func _process(delta):
	if is_exiting:
		return

	loading_timer += delta
	_update_logo_pulse(delta)

	if (
		Game.stage == Game.GameStage.Main
		and Game.main_menu_state == Game.MainMenuState.SongSelect
		and is_editor_mode
		and not is_menu_transitioning
		and not _filter_popup.is_open()
		and not settings_popup.is_open()
		and not _publisher.busy
	):
		if Input.is_action_just_pressed("shortcut_create_chartset"):
			open_new_chart_editor()
		elif Input.is_action_just_pressed("shortcut_new_difficulty"):
			open_new_difficulty_editor()
		elif Input.is_action_just_pressed("shortcut_enter_editor"):
			open_selected_chart_editor()


func _input(event: InputEvent) -> void:
	if is_exiting:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		if Game.stage == Game.GameStage.Main and Game.main_menu_state == Game.MainMenuState.SongSelect:
			activate_song_action(true)
			get_viewport().set_input_as_handled()
		return
	if is_community_mode or (_filter_popup != null and _filter_popup.is_open()):
		return

	if (
		Game.stage == Game.GameStage.Main
		and Game.main_menu_state == Game.MainMenuState.SongSelect
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.ctrl_pressed
		and event.keycode == KEY_F5
	):
		_recalculate_all_chart_ratings()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if is_exiting:
		return

	if event.is_action_pressed("ui_cancel"):
		if playlist_panel.is_open():
			playlist_panel.close()
			get_viewport().set_input_as_handled()
			return
		if is_menu_transitioning:
			get_viewport().set_input_as_handled()
			return

		if (settings_popup != null and settings_popup.is_open()) or (_filter_popup != null and _filter_popup.is_open()):
			return

		if Game.main_menu_state == Game.MainMenuState.SongSelect:
			return_to_main_menu()
			get_viewport().set_input_as_handled()


func begin_song_select(editor_mode: bool = false) -> void:
	if is_exiting or is_menu_transitioning:
		return

	if Game.main_menu_state == Game.MainMenuState.SongSelect:
		return

	is_menu_transitioning = true
	var resume_community := is_community_mode and not editor_mode and Auth.is_authenticated()
	if not resume_community:
		_catalogue.set_active(false)
		is_community_mode = false
		source_tabs.current_tab = 0
		menu_audio_switcher.set_online_preview(false)
		chart_scroll.set_online_mode(false)
		search_input.max_length = 0
		search_input.set_block_signals(true)
		search_input.text = _local_search
		search_input.set_block_signals(false)
		chart_scroll.set_filters(_local_filters)
		chart_scroll.set_search_text(_local_search)
	_publisher.set_selection(CM.selected_chartset if editor_mode else null)
	_update_filter_button()
	_apply_song_select_mode(editor_mode)
	_set_button_group_interaction(menu_buttons, false)
	_set_button_group_interaction(bottom_buttons, false)
	Game.main_menu_state = Game.MainMenuState.SongSelect
	animations.clean_menu_things()
	await get_tree().create_timer(0.5).timeout
	if is_exiting or not is_inside_tree():
		return
	animations.song_select_scene()
	await animations.bottom_buttons_animation.animation_finished
	if is_exiting or not is_inside_tree():
		return
	_set_button_group_interaction(bottom_buttons, true)
	_update_editor_chart_actions()
	is_menu_transitioning = false
	_update_catalogue_state()


func return_to_main_menu() -> void:
	if is_exiting or is_menu_transitioning:
		return

	if Game.main_menu_state == Game.MainMenuState.Home:
		return

	is_menu_transitioning = true
	playlist_panel.close()
	_filter_popup.close_popup()
	_remember_source_selection()
	edit_actions.hide()
	new_difficulty_button.disabled = true
	delete_difficulty_button.disabled = true
	delete_chartset_button.disabled = true
	_set_button_group_interaction(bottom_buttons, false)
	_set_button_group_interaction(menu_buttons, false)
	Game.main_menu_state = Game.MainMenuState.Home
	animations.main_menu()
	animations.call_menu_things()
	await animations.bottom_buttons_animation.animation_finished
	if is_exiting or not is_inside_tree():
		return
	_set_button_group_interaction(menu_buttons, true)
	is_menu_transitioning = false


func _set_button_group_interaction(group: Control, enabled: bool) -> void:
	if group == null:
		return

	for child in group.get_children():
		if child is MenuBigButton:
			child.set_interaction_enabled(enabled)


func _apply_song_select_mode(editor_mode: bool) -> void:
	is_editor_mode = editor_mode
	bottom_play_button.visible = not editor_mode
	bottom_edit_button.visible = editor_mode
	new_chart_button.visible = editor_mode
	source_tabs.visible = not editor_mode
	edit_actions.visible = editor_mode
	inline_leaderboard.visible = not editor_mode
	loved_button.visible = not editor_mode and is_community_mode
	_update_playlist_button_visibility()
	_update_editor_chart_actions()

	if chart_info_panel != null and chart_info_panel.has_method("set_score_ui_bound"):
		chart_info_panel.set_score_ui_bound(not editor_mode)
	if chart_scroll != null:
		chart_scroll.set_editor_mode(editor_mode)


func begin_exit() -> void:
	if is_exiting:
		return

	is_exiting = true
	menu_audio_switcher.prepare_shutdown()
	playlist_panel.close()
	_catalogue.set_active(false)
	_filter_popup.close_popup()
	if settings_popup != null:
		settings_popup.close_popup()

	exit_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	await get_tree().create_timer(EXIT_START_DELAY).timeout

	exit_overlay.visible = true
	switch_player.play()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(exit_overlay, "color:a", 1.0, EXIT_FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if audio_1 != null:
		tween.tween_property(audio_1, "volume_db", -80.0, EXIT_FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if audio_2 != null:
		tween.tween_property(audio_2, "volume_db", -80.0, EXIT_FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await get_tree().create_timer(EXIT_FADE_DURATION * 0.1).timeout
	bye_player.play()
	await tween.finished
	menu_audio_switcher.stop_audio()
	get_tree().quit()

func _update_progress(_progress: float) -> void:
	progress = _progress
	if progress_bar != null:
		progress_bar.value = _progress
	_update_loading_status()


func _on_auth_state_changed() -> void:
	var signed_in := Auth.is_authenticated()
	var username_pending := Auth.is_username_setup_pending()
	var was_visible := username_setup_overlay.visible
	username_setup_overlay.visible = username_pending
	username_input.editable = not Auth.is_username_setup_submitting()
	username_submit_button.disabled = Auth.is_username_setup_submitting()
	username_submit_button.text = "Saving…" if Auth.is_username_setup_submitting() else "Continue"
	if username_pending:
		username_status.text = (
			""
			if Auth.status_message == "Choose a username to continue."
			else Auth.status_message
		)
		if not was_visible:
			username_input.clear()
			username_input.call_deferred("grab_focus")
	source_tabs.set_tab_disabled(1, not signed_in)
	if not signed_in and is_community_mode:
		_select_source_tab(0)
	account_panel.visible = signed_in and Game.stage == Game.GameStage.Main
	_update_playlist_button_visibility()
	_update_loading_status()


func _submit_username() -> void:
	if not Auth.is_username_setup_pending() or Auth.is_username_setup_submitting():
		return
	var username := username_input.text.strip_edges()
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z][A-Za-z0-9_]{2,23}$")
	if pattern.search(username) == null:
		username_status.text = "Use 3–24 English letters, numbers, or underscores, starting with a letter."
		username_input.grab_focus()
		return
	username_status.text = ""
	Auth.submit_username(username)


func _update_loading_status() -> void:
	if current_chartset_label == null or Game.stage != Game.GameStage.Loading:
		return
	current_chartset_label.visible = _auth_loading_started
	current_chartset_label.text = Auth.status_message.to_lower() if _auth_loading_started else ""

func _on_database_sync_finished(_success: bool) -> void:
	if _loading_completion_started:
		return

	_loading_completion_started = true
	var elapsed_seconds := float(Time.get_ticks_msec() - _loading_started_msec) / 1000.0
	var remaining_seconds := maxf(MIN_LOADING_DISPLAY_SECONDS - elapsed_seconds, 0.0)
	if remaining_seconds > 0.0:
		await get_tree().create_timer(remaining_seconds).timeout
	_auth_loading_started = true
	_login_loading_deadline_msec = Time.get_ticks_msec() + int(LOGIN_LOADING_TTL_SECONDS * 1000.0)
	if not Auth.is_authenticated() and not Auth.is_busy():
		Auth.login()
	_update_loading_status()
	while Auth.is_busy() and Time.get_ticks_msec() < _login_loading_deadline_msec:
		await get_tree().process_frame
	while Auth.is_username_setup_pending():
		await get_tree().process_frame
	if not is_inside_tree() or is_exiting:
		return

	_finish_loading()


func _finish_loading() -> void:
	print("[charts] load time %f" %loading_timer)
	_update_progress(1.0)
	if chart_scroll != null:
		chart_scroll.rebuild_items()
	if current_chartset_label != null:
		current_chartset_label.text = "enjoy!"
	Game.stage = Game.GameStage.Main
	Game.main_menu_state = Game.MainMenuState.Home
	_on_auth_state_changed()
	animations.loading_done()
	_refresh_chart_browser()


func _setup_catalogue() -> void:
	_filter_popup.theme = settings_popup.theme
	_filter_popup.applied.connect(_on_filters_applied)
	_filter_popup.visibility_set.connect(func(blocked: bool): chart_scroll.input_blocked = blocked)
	_catalogue.results_changed.connect(_on_community_results_changed)
	_catalogue.state_changed.connect(_update_catalogue_state)
	_catalogue.detail_cover_loaded.connect(chart_info_panel.show_detail_cover)
	_catalogue.detail_cover_failed.connect(chart_info_panel.show_detail_cover_failed)
	_catalogue.loved_state_changed.connect(_on_loved_state_changed)
	chart_scroll.load_more_requested.connect(_catalogue.load_next_page)
	source_tabs.tab_changed.connect(_select_source_tab)
	edit_actions.hide()
	_publish_button.pressed.connect(func(): _publisher.show_publish(settings_popup.theme))
	_publisher.state_changed.connect(_update_publish_state)
	CM.chartset_selected.connect(func(chartset: ChartSet):
		_publisher.set_selection(chartset if is_editor_mode else null)
		_update_editor_chart_actions()
		_update_playlist_button_visibility()
	)
	CM.chart_selected.connect(func(_chart: Chart):
		_update_catalogue_state()
		_update_editor_chart_actions()
		_update_playlist_button_visibility()
	)

func _update_publish_state() -> void:
	_publish_button.text = _publisher.button_text()
	var builtin_available := _publisher.can_publish_builtin() and _publisher.restriction(true).is_empty()
	_publish_button.tooltip_text = "Built-in upload is available for this chartset." if builtin_available and not _publisher.restriction().is_empty() else _publisher.restriction()
	_publish_button.disabled = _publisher.busy or _publisher.checking or _publisher.selection == null or (Auth.is_authenticated() and not _publisher.restriction().is_empty() and not builtin_available)


func _select_source_tab(tab: int) -> void:
	if is_editor_mode or Game.main_menu_state != Game.MainMenuState.SongSelect:
		return
	_remember_source_selection()
	if tab == 1 and not Auth.is_authenticated():
		Notification.notice("Sign in to access Community charts.", Notification.Type.WARNING)
		source_tabs.set_block_signals(true)
		source_tabs.current_tab = 0
		source_tabs.set_block_signals(false)
		tab = 0

	var source_changed := is_community_mode != (tab == 1)
	is_community_mode = tab == 1
	_community_selection_restore_pending = is_community_mode
	loved_button.visible = is_community_mode
	_update_playlist_button_visibility()
	menu_audio_switcher.set_online_preview(is_community_mode)
	chart_scroll.set_online_mode(is_community_mode)
	search_input.max_length = 255 if is_community_mode else 0
	search_input.set_block_signals(true)
	search_input.text = _catalogue.search_text if is_community_mode else _local_search
	search_input.set_block_signals(false)
	if is_community_mode:
		_catalogue.set_active(true)
	else:
		_catalogue.set_active(false)
		chart_scroll.set_filters(_local_filters)
		chart_scroll.set_search_text(_local_search)
		_restore_source_selection(false)
		if source_changed:
			animations.replay_charts()
	_update_filter_button()
	_update_catalogue_state()


func _on_community_results_changed(chartsets: Array[ChartSet]) -> void:
	chart_scroll.set_online_results(chartsets)
	if not _community_selection_restore_pending:
		return
	if chartsets.is_empty() and _catalogue.loading:
		return
	_restore_source_selection(true)
	_community_selection_restore_pending = false
	if Game.main_menu_state == Game.MainMenuState.SongSelect and is_community_mode:
		animations.replay_charts()


func _remember_source_selection() -> void:
	if CM.selected_chartset == null or CM.selected_chart == null:
		return
	if is_community_mode:
		_community_chartset_uuid = CM.selected_chartset.uuid
		_community_chart_uuid = CM.selected_chart.uuid
	else:
		_official_chartset_uuid = CM.selected_chartset.uuid
		_official_chart_uuid = CM.selected_chart.uuid


func _restore_source_selection(community: bool) -> void:
	var chartset_uuid := _community_chartset_uuid if community else _official_chartset_uuid
	var chart_uuid := _community_chart_uuid if community else _official_chart_uuid
	if chartset_uuid.is_empty():
		return
	var chartsets: Array[ChartSet] = chart_scroll.online_chartsets if community else CM.chartsets
	for chartset in chartsets:
		if chartset.uuid != chartset_uuid:
			continue
		var selected_chart: Chart = null
		for chart in chartset.charts:
			if chart.uuid == chart_uuid:
				selected_chart = chart
				break
		if selected_chart == null and not chartset.charts.is_empty():
			selected_chart = chartset.charts[0]
		CM.select_chartset(chartset)
		CM.select_chart(selected_chart)
		chart_scroll.rebuild_items(true)
		return


func _update_playlist_button_visibility() -> void:
	playlist_selector.visible = is_community_mode and not is_editor_mode and Auth.is_authenticated()
	if not Auth.is_authenticated():
		playlist_selector.text = "All Beatmaps"
	var has_online_chartset := _selected_online_chartset_id() > 0
	playlist_button.visible = is_community_mode and not is_editor_mode and Auth.is_authenticated() and has_online_chartset
	if not playlist_button.visible:
		playlist_panel.close()


func _selected_online_chartset_id() -> int:
	if CM.selected_chartset == null:
		return 0
	var metadata := CM.selected_chartset.online_metadata
	if metadata.is_empty():
		return 0
	return int(metadata.get("id", metadata.get("chartset_id", 0)))


func _on_loved_state_changed(loved: bool, busy: bool) -> void:
	loved_button.set_loved_state(loved, busy or not is_community_mode or CM.selected_chartset == null)


func _open_playlists() -> void:
	if is_menu_transitioning or is_exiting:
		return
	if playlist_panel.is_open():
		playlist_panel.close()
		return
	var metadata := {}
	if CM.selected_chartset != null:
		metadata = CM.selected_chartset.online_metadata
	playlist_panel.open(metadata, playlist_button.get_global_rect())


func _open_playlist_selector() -> void:
	if is_menu_transitioning or is_exiting:
		return
	if playlist_panel.is_open():
		playlist_panel.close()
		return
	playlist_panel.open_browser(playlist_selector.get_global_rect(), _catalogue.playlist_id)


func _on_playlist_chartset_chosen(metadata: Dictionary) -> void:
	var origin := str(metadata.get("origin", "community"))
	if origin == "official":
		source_tabs.set_block_signals(true)
		source_tabs.current_tab = 0
		source_tabs.set_block_signals(false)
		_select_source_tab(0)
		var uuid := str(metadata.get("chartset_uuid", ""))
		var local := CM.chartsets_by_uuid.get(uuid) as ChartSet
		if local == null:
			for candidate in CM.chartsets:
				if candidate.uuid.to_lower() == uuid.to_lower():
					local = candidate
					break
		if local == null:
			Notification.notice("This official chart is not installed.", Notification.Type.WARNING)
			return
		CM.select_chartset(local)
		CM.select_chart(local.charts[0] if not local.charts.is_empty() else null)
		return
	source_tabs.set_block_signals(true)
	source_tabs.current_tab = 1
	source_tabs.set_block_signals(false)
	_select_source_tab(1)
	_catalogue.show_chartset(metadata)

func _show_filters() -> void:
	if is_menu_transitioning or is_exiting:
		return
	_filter_popup.show_popup(is_community_mode, _catalogue.filters if is_community_mode else _local_filters, Auth.is_authenticated())

func _on_filters_applied(values: SongFilters) -> void:
	if is_community_mode:
		_catalogue.set_filters(values)
	else:
		_local_filters = values
		chart_scroll.set_filters(values)
	_update_filter_button()

func _update_filter_button() -> void:
	var count := (_catalogue.filters if is_community_mode else _local_filters).active_count()
	filter_button.text = "Filter" if count == 0 else "Filter (%d)" % count

func _update_catalogue_state() -> void:
	var caption := "Play"
	if _catalogue.downloading:
		caption = _catalogue.download_label()
	if bottom_play_button.button_text != caption:
		bottom_play_button.button_text = caption
	bottom_play_button.set_interaction_enabled(not is_menu_transitioning and not is_exiting and CM.selected_chart != null and not _catalogue.downloading and (not is_community_mode or not _catalogue.loading or _catalogue.loading_more))

func activate_song_action(autoplay: bool = false) -> void:
	if is_menu_transitioning or is_exiting or playlist_panel.is_open() or _filter_popup.is_open() or settings_popup.is_open() or username_setup_overlay.visible or _catalogue.downloading or _publisher.busy or CM.selected_chart == null:
		return
	_remember_source_selection()
	if is_community_mode:
		_catalogue.activate_selection(autoplay)
	else:
		Game.play_selected_chart(autoplay)


func _on_search_text_changed(new_text: String) -> void:
	if is_community_mode:
		_catalogue.set_search(new_text)
	elif chart_scroll != null:
		_local_search = new_text
		chart_scroll.set_search_text(new_text)

func _refresh_chart_browser() -> void:
	if is_community_mode and _catalogue != null:
		menu_audio_switcher.set_online_preview(true)
		_catalogue.set_active(true)
	if chart_scroll != null:
		chart_scroll.refresh_after_resume()
	if not is_editor_mode:
		_restore_source_selection(is_community_mode)
	if chart_info_panel != null and chart_info_panel.has_method("refresh_selected_chart"):
		chart_info_panel.call("refresh_selected_chart")
	if inline_leaderboard != null and not is_editor_mode:
		inline_leaderboard.refresh_selected_chart()

func _recalculate_all_chart_ratings() -> void:
	var result := CM.recalculate_all_ratings()
	var updated := result.updated
	var failed := result.failed
	var total := result.total
	var message := "[rating] all charts are recalculated: %d/%d" % [updated, total]
	if failed > 0:
		message += " (failed: %d)" % failed
		Notification.notice(message, Notification.Type.WARNING)
	else:
		print(message)

func open_new_chart_editor() -> void:
	if EditorChartOps.prepare_new_chartset_chart() == null:
		return
	Transition.transition_to("res://scenes/chart/editor/editor_scene.tscn", 1)

func open_new_difficulty_editor() -> void:
	if EditorChartOps.prepare_new_difficulty_chart() == null:
		return
	Transition.transition_to("res://scenes/chart/editor/editor_scene.tscn", 1)


func _update_editor_chart_actions() -> void:
	var has_chart := (
		is_editor_mode
		and not is_community_mode
		and CM.selected_chart != null
		and CM.selected_chartset != null
	)
	new_difficulty_button.disabled = not has_chart
	delete_chartset_button.disabled = not has_chart
	delete_difficulty_button.disabled = not has_chart or CM.selected_chartset.charts.size() <= 1
	delete_difficulty_button.tooltip_text = (
		"Use Delete Chartset for the last difficulty."
		if has_chart and CM.selected_chartset.charts.size() <= 1
		else ""
	)


func _request_delete_difficulty() -> void:
	var selected_chart := CM.selected_chart
	var selected_chartset := CM.selected_chartset
	if selected_chart == null or selected_chartset == null:
		return
	if selected_chartset.charts.size() <= 1:
		Notification.notice(
			"This is the last difficulty. Use Delete Chartset instead.",
			Notification.Type.WARNING
		)
		return
	_pending_delete_scope = "difficulty"
	_open_delete_dialog(
		"Delete Difficulty",
		"Move difficulty '%s' to the Recycle Bin?" % selected_chart.difficulty
	)


func _request_delete_chartset() -> void:
	if CM.selected_chart == null or CM.selected_chartset == null:
		return
	_pending_delete_scope = "chartset"
	_open_delete_dialog(
		"Delete Chartset",
		"Move chartset '%s' and all of its difficulties and resources to the Recycle Bin?"
			% CM.selected_chart.title
	)


func _open_delete_dialog(dialog_title: String, message: String) -> void:
	delete_chart_dialog.title = dialog_title
	delete_chart_dialog.dialog_text = message
	delete_chart_dialog.ok_button_text = dialog_title
	delete_chart_dialog.popup_centered(Vector2i(520, 0))


func _cancel_chart_delete() -> void:
	_pending_delete_scope = ""


func _confirm_chart_delete() -> void:
	var scope := _pending_delete_scope
	_pending_delete_scope = ""
	var selected_chart := CM.selected_chart
	var selected_chartset := CM.selected_chartset
	if selected_chart == null or selected_chartset == null:
		return

	var restore_folder := selected_chartset.folder_name
	var error := ERR_INVALID_PARAMETER
	match scope:
		"difficulty":
			error = EditorChartOps.discard_editor_difficulty(selected_chart, selected_chart.file_path)
		"chartset":
			error = EditorChartOps.discard_editor_chartset(selected_chartset)
		_:
			return

	if error != OK:
		Notification.notice("Failed to delete %s." % scope, Notification.Type.ERROR)
		return

	CM.parsed_chart = null
	CM.select_chart(null)
	CM.select_chartset(null)
	CM.reload_editor_library()
	if scope == "difficulty":
		_restore_editor_chartset_selection(restore_folder)
	chart_scroll.rebuild_items()
	Notification.notice("%s moved to the Recycle Bin." % scope.capitalize())
	_update_editor_chart_actions()


func _restore_editor_chartset_selection(folder_name: String) -> void:
	for chartset: ChartSet in CM.editor_chartsets:
		if chartset.folder_name != folder_name or chartset.charts.is_empty():
			continue
		CM.select_chartset(chartset)
		CM.select_chart(chartset.charts[0])
		return

func open_selected_chart_editor() -> void:
	if not CM.parse_selected_chart():
		return
	Transition.transition_to("res://scenes/chart/editor/editor_scene.tscn", 1)


func _update_logo_pulse(delta: float) -> void:
	if logo == null:
		return

	var chart := CM.selected_chart
	var playback_msec := _get_logo_chart_time_msec()
	if chart == null or playback_msec < 0.0:
		_last_logo_half_beat_key = ""
		_last_logo_chart_key = ""
		_last_logo_playback_msec = -1.0
		_logo_pulse_time = minf(_logo_pulse_time + delta, LOGO_PULSE_DURATION)
		logo.offset_transform_scale = logo.offset_transform_scale.lerp(
			Vector2.ONE * LOGO_IDLE_SCALE,
			delta * LOGO_RETURN_SPEED
		)
		return

	var chart_key := chart.uuid if not chart.uuid.is_empty() else chart.file_path
	if chart_key != _last_logo_chart_key or playback_msec + 1.0 < _last_logo_playback_msec:
		_last_logo_half_beat_key = ""
		_logo_pulse_time = LOGO_PULSE_DURATION

	var beat_key := _get_logo_beat_key(chart, playback_msec)
	if beat_key != "" and beat_key != _last_logo_half_beat_key:
		_last_logo_half_beat_key = beat_key
		_logo_pulse_time = 0.0

	_last_logo_chart_key = chart_key
	_last_logo_playback_msec = playback_msec
	_logo_pulse_time = minf(_logo_pulse_time + delta, LOGO_PULSE_DURATION)

	var target_scale := Vector2.ONE * _get_logo_pulse_scale(_logo_pulse_time / LOGO_PULSE_DURATION)
	logo.offset_transform_scale = logo.offset_transform_scale.lerp(
		target_scale,
		delta * LOGO_RETURN_SPEED
	)


func _refresh_logo_pivot() -> void:
	if logo == null:
		return

	logo.offset_transform_pivot_ratio = Vector2(0.5, 0.5)


func _get_logo_chart_time_msec() -> float:
	if menu_audio_switcher == null:
		return -1.0
	return menu_audio_switcher.get_current_chart_time_msec()


func _get_logo_beat_key(chart: Chart, playback_msec: float) -> String:
	if chart == null:
		return ""

	var active_timing: Timing = null
	var active_timing_index := -1

	for index in range(chart.timings.size()):
		var timing := chart.timings[index]
		if timing == null or timing.bpm <= 0.0:
			continue
		if timing.time <= playback_msec:
			active_timing = timing
			active_timing_index = index
		else:
			break

	if active_timing == null:
		for index in range(chart.timings.size()):
			var timing := chart.timings[index]
			if timing != null and timing.bpm > 0.0:
				active_timing = timing
				active_timing_index = index
				break

	if active_timing == null:
		return ""

	var beat_msec := 60000.0 / active_timing.bpm
	if beat_msec <= 0.0:
		return ""

	var local_msec := maxf(playback_msec - float(active_timing.time), 0.0)
	var beat_index := int(floor(local_msec / beat_msec))
	return "%d:%d" % [active_timing_index, beat_index]


func _get_logo_pulse_scale(phase: float) -> float:
	var t := clampf(phase, 0.0, 1.0)

	if t < 0.18:
		return lerpf(LOGO_IDLE_SCALE, LOGO_PEAK_SCALE, ease(t / 0.18, 0.45))
	if t < 0.46:
		return lerpf(LOGO_PEAK_SCALE, LOGO_DIP_SCALE, ease((t - 0.18) / 0.28, 1.4))
	return lerpf(LOGO_DIP_SCALE, LOGO_IDLE_SCALE, ease((t - 0.46) / 0.54, 2.0))
