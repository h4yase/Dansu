extends Node
class_name EditorInspectorController

const CREATE_NEW_SKIN_ID := 1000000

@export var editor: ChartEditor
@export var title_line_edit: LineEdit
@export var artist_line_edit: LineEdit
@export var creator_line_edit: LineEdit
@export var difficulty_line_edit: LineEdit
@export var source_line_edit: LineEdit
@export var tags_line_edit: LineEdit
@export var beat_division_slider: HSlider
@export var beat_division_label: Label
@export var add_timing_button: Button
@export var timing_list_container: VBoxContainer
@export var timing_template: Node
@export var skin_file_label: Label
@export var skin_browser_button: Button
@export var cover_texture_rect: TextureRect
@export var cover_file_label: Label
@export var audio_file_label: Label
@export var cover_browser_button: Button
@export var audio_browser_button: Button
@export var skin_picker_menu: PopupMenu
@export var cover_file_dialog: FileDialog
@export var audio_file_dialog: FileDialog

var timing_scene := preload("res://scenes/chart/editor/ui/inspector/timing.tscn")
var timing_items: Array[EditorTimingItem] = []
var _syncing_metadata := false
var _skin_picker_items: Array[String] = []
var _default_cover_texture: Texture2D

func connect_dialogs() -> void:
	if skin_picker_menu != null:
		skin_picker_menu.id_pressed.connect(_on_skin_picker_id_pressed)
	if cover_file_dialog != null:
		cover_file_dialog.file_selected.connect(_on_cover_file_selected)
	if audio_file_dialog != null:
		audio_file_dialog.file_selected.connect(_on_audio_file_selected)

	if cover_browser_button != null:
		cover_browser_button.pressed.connect(open_cover_browser)
	if audio_browser_button != null:
		audio_browser_button.pressed.connect(open_audio_browser)
	if cover_texture_rect != null:
		_default_cover_texture = cover_texture_rect.texture
	if CoverLoader != null:
		if not CoverLoader.cover_loaded.is_connected(_on_cover_loaded):
			CoverLoader.cover_loaded.connect(_on_cover_loaded)
		if not CoverLoader.cover_failed.is_connected(_on_cover_failed):
			CoverLoader.cover_failed.connect(_on_cover_failed)

func refresh_metadata_fields() -> void:
	if editor == null or editor.chart == null:
		return
	_syncing_metadata = true
	title_line_edit.text = editor.chart.title
	artist_line_edit.text = editor.chart.artist
	creator_line_edit.text = editor.chart.creator
	difficulty_line_edit.text = editor.chart.difficulty
	source_line_edit.text = editor.chart.source
	tags_line_edit.text = editor.chart.tags
	_syncing_metadata = false
	update_skin_file_ui()
	update_media_ui()

func update_skin_file_ui() -> void:
	if skin_file_label == null or editor == null or editor.chart == null:
		return
	skin_file_label.text = editor.chart.file_skin if editor.chart.file_skin != "" else "(no linked skin file)"
	skin_file_label.tooltip_text = skin_file_label.text

func update_media_ui() -> void:
	if editor == null or editor.chart == null:
		return
	if cover_file_label != null:
		cover_file_label.text = editor.chart.file_cover_art if not editor.chart.file_cover_art.is_empty() else "(no linked cover art)"
		cover_file_label.tooltip_text = cover_file_label.text
	if audio_file_label != null:
		audio_file_label.text = editor.chart.file_audio if not editor.chart.file_audio.is_empty() else "(no linked audio file)"
		audio_file_label.tooltip_text = audio_file_label.text
	_update_cover_preview()

func _update_cover_preview() -> void:
	if cover_texture_rect == null or editor == null or editor.chart == null:
		return
	if editor.chart.cover_image != null:
		cover_texture_rect.texture = editor.chart.cover_image
		return
	cover_texture_rect.texture = _default_cover_texture
	if not editor.chart.file_cover_art.is_empty():
		CoverLoader.request_cover(editor.chart)

func rebuild_timing_ui() -> void:
	if editor == null or editor.chart == null or editor.timeline == null:
		return
	editor.timeline.ensure_timings()
	for item in timing_items:
		if item != null and item != timing_template:
			item.queue_free()
	timing_items.clear()

	for index in range(editor.chart.timings.size()):
		var item: EditorTimingItem
		if index == 0:
			item = timing_template as EditorTimingItem
		else:
			item = timing_scene.instantiate() as EditorTimingItem
			timing_list_container.add_child(item)
		item.bind(editor.chart.timings[index])
		if not item.change_started.is_connected(on_timing_item_change_started):
			item.change_started.connect(on_timing_item_change_started)
		if not item.changed.is_connected(on_timing_item_changed):
			item.changed.connect(on_timing_item_changed)
		if not item.remove_requested.is_connected(on_timing_remove_requested):
			item.remove_requested.connect(on_timing_remove_requested)
		timing_items.append(item)

func update_beat_division_ui() -> void:
	if beat_division_slider == null or editor == null or editor.timeline == null:
		return
	var divisions := editor._get_supported_beat_divisions()
	beat_division_slider.min_value = 0
	beat_division_slider.max_value = divisions.size() - 1
	beat_division_slider.step = 1
	var target_index := divisions.find(editor.timeline.beat_division)
	if target_index == -1:
		target_index = divisions.find(4)
		if target_index == -1:
			target_index = 0
	editor.timeline.beat_division = divisions[target_index]
	beat_division_slider.value = target_index
	beat_division_label.text = "1/%d" % editor.timeline.beat_division

func on_title_changed(new_text: String) -> void:
	if _syncing_metadata or editor == null or editor.chart == null:
		return
	editor.chart.title = new_text
	editor._update_save_button_state()

func on_artist_changed(new_text: String) -> void:
	if _syncing_metadata or editor == null or editor.chart == null:
		return
	editor.chart.artist = new_text

func on_difficulty_changed(new_text: String) -> void:
	if _syncing_metadata or editor == null or editor.chart == null:
		return
	if EditorChartOps.has_duplicate_difficulty(editor.chart, new_text):
		_syncing_metadata = true
		editor.chart.difficulty = ""
		difficulty_line_edit.text = ""
		_syncing_metadata = false
	else:
		editor.chart.difficulty = new_text.strip_edges()
	editor._update_save_button_state()

func on_creator_changed(new_text: String) -> void:
	if not _syncing_metadata and editor != null and editor.chart != null:
		editor.chart.creator = new_text

func on_source_changed(new_text: String) -> void:
	if not _syncing_metadata and editor != null and editor.chart != null:
		editor.chart.source = new_text

func on_tags_changed(new_text: String) -> void:
	if not _syncing_metadata and editor != null and editor.chart != null:
		editor.chart.tags = new_text

func on_beat_division_slider_changed(value: float) -> void:
	if editor == null or editor.timeline == null:
		return
	var divisions := editor._get_supported_beat_divisions()
	var index := clampi(int(round(value)), 0, divisions.size() - 1)
	if editor.timeline.beat_division == divisions[index]:
		return
	editor._push_history_snapshot()
	editor.timeline.beat_division = divisions[index]
	beat_division_label.text = "1/%d" % editor.timeline.beat_division
	editor.refresh_views()

func add_timing() -> void:
	if editor == null or editor.chart == null or editor.timeline == null:
		return
	editor._push_history_snapshot()
	var new_timing := Timing.new()
	new_timing.time = editor.timeline.snap_time(int(round(Game.current_time)))
	new_timing.bpm = 120.0 if editor.chart.timings.is_empty() else editor.chart.timings.back().bpm
	editor.chart.timings.append(new_timing)
	editor.chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)
	rebuild_timing_ui()
	editor.refresh_views()

func on_timing_item_change_started(_item: EditorTimingItem) -> void:
	if editor != null:
		editor._push_history_snapshot()

func on_timing_item_changed(_item: EditorTimingItem) -> void:
	if editor == null or editor.chart == null:
		return
	editor.chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)
	rebuild_timing_ui()
	editor.refresh_views()

func on_timing_remove_requested(item: EditorTimingItem) -> void:
	if editor == null or editor.chart == null:
		return
	if editor.chart.timings.size() <= 1:
		return
	editor._push_history_snapshot()
	editor.chart.timings.erase(item.timing)
	rebuild_timing_ui()
	editor.refresh_views()

func open_skin_browser() -> void:
	if editor == null or editor.chart == null or skin_picker_menu == null:
		return
	var chart_folder_path := ProjectSettings.globalize_path(editor.chart.folder_path)
	var skins_root_path := SkinSerialization.get_chart_skin_root_path(chart_folder_path)
	FileSystem.ensure_dir(skins_root_path)

	_skin_picker_items.clear()
	skin_picker_menu.clear()
	var folder_names := DirAccess.get_directories_at(skins_root_path)
	folder_names.sort()
	for folder_name in folder_names:
		var skin_json_path := skins_root_path.path_join(folder_name).path_join(SkinSerialization.CHART_SKIN_JSON_NAME)
		if not FileAccess.file_exists(skin_json_path):
			continue
		var id := _skin_picker_items.size()
		_skin_picker_items.append(folder_name)
		var label := folder_name
		if folder_name == editor.chart.file_skin:
			label = "%s (current)" % folder_name
		skin_picker_menu.add_item(label, id)

	if not _skin_picker_items.is_empty():
		skin_picker_menu.add_separator()
	skin_picker_menu.add_item("Create New One", CREATE_NEW_SKIN_ID)

	var button_rect := skin_browser_button.get_global_rect() if skin_browser_button != null else Rect2(Vector2.ZERO, Vector2.ZERO)
	var popup_position := Vector2i(int(button_rect.position.x), int(button_rect.position.y + button_rect.size.y))
	skin_picker_menu.popup(Rect2i(popup_position, Vector2i(260, 0)))

func _on_skin_picker_id_pressed(id: int) -> void:
	if editor == null or editor.chart == null:
		return
	if id == CREATE_NEW_SKIN_ID:
		editor.open_new_chart_skin_editor()
		return
	if id < 0 or id >= _skin_picker_items.size():
		return
	var selected_skin := _skin_picker_items[id]
	if editor.chart.file_skin == selected_skin:
		return
	editor._push_history_snapshot()
	editor.chart.file_skin = selected_skin
	update_skin_file_ui()
	editor._update_save_button_state()

func open_cover_browser() -> void:
	if editor == null or editor.chart == null or cover_file_dialog == null:
		return
	var chart_folder_path := ProjectSettings.globalize_path(editor.chart.folder_path)
	cover_file_dialog.current_dir = chart_folder_path
	if not editor.chart.file_cover_art.is_empty():
		cover_file_dialog.current_path = ProjectSettings.globalize_path(editor.chart.get_cover_path())
	cover_file_dialog.popup_centered_ratio(0.7)

func open_audio_browser() -> void:
	if editor == null or editor.chart == null or audio_file_dialog == null:
		return
	var chart_folder_path := ProjectSettings.globalize_path(editor.chart.folder_path)
	audio_file_dialog.current_dir = chart_folder_path
	if not editor.chart.file_audio.is_empty():
		audio_file_dialog.current_path = ProjectSettings.globalize_path(editor.chart.folder_path.path_join(editor.chart.file_audio))
	audio_file_dialog.popup_centered_ratio(0.7)

func _on_cover_file_selected(path: String) -> void:
	var relative_path := _resolve_chart_media_relative_path(path)
	if relative_path.is_empty() or editor == null or editor.chart == null:
		return
	editor._push_history_snapshot()
	editor.chart.file_cover_art = relative_path
	editor.chart.cover_image = null
	update_media_ui()
	editor._update_save_button_state()

func _on_audio_file_selected(path: String) -> void:
	var relative_path := _resolve_chart_media_relative_path(path)
	if relative_path.is_empty() or editor == null or editor.chart == null:
		return
	editor._push_history_snapshot()
	editor.chart.file_audio = relative_path
	update_media_ui()
	if editor.transport != null:
		editor.transport.chart = editor.chart
		editor.transport.load_stream()
	if editor.timeline != null and editor.transport != null:
		editor.timeline = EditorTimeline.new(editor.chart, editor.transport.stream_length_sec)
		editor.transport.timeline = editor.timeline
		Game.current_time = editor.timeline.clamp_time(Game.current_time)
		editor._update_slider_range()
	if editor.view_controller != null:
		editor.view_controller.mark_layout_dirty()
	editor._update_time_ui(true)
	editor._update_save_button_state()

func _on_cover_loaded(chart: Chart, texture: Texture2D) -> void:
	if editor == null or editor.chart == null or chart != editor.chart or texture == null:
		return
	if cover_texture_rect != null and cover_texture_rect.texture != texture:
		cover_texture_rect.texture = texture

func _on_cover_failed(chart: Chart) -> void:
	if editor == null or editor.chart == null or chart != editor.chart:
		return
	if cover_texture_rect != null:
		cover_texture_rect.texture = _default_cover_texture

func _get_chart_relative_path(path: String) -> String:
	if editor == null or editor.chart == null:
		return ""
	var selected_path := path.simplify_path().replace("\\", "/")
	var chart_folder_path := ProjectSettings.globalize_path(editor.chart.folder_path).simplify_path().replace("\\", "/")
	var folder_prefix := chart_folder_path + "/"
	var selected_path_lower := selected_path.to_lower()
	var folder_prefix_lower := folder_prefix.to_lower()
	if not selected_path_lower.begins_with(folder_prefix_lower):
		return ""
	return selected_path.substr(folder_prefix.length()).replace("\\", "/")

func _resolve_chart_media_relative_path(path: String) -> String:
	if editor == null or editor.chart == null:
		return ""

	var relative_path := _get_chart_relative_path(path)
	if not relative_path.is_empty():
		return relative_path

	return _copy_file_into_chart_folder(path)

func _copy_file_into_chart_folder(source_path: String) -> String:
	if editor == null or editor.chart == null:
		return ""

	var normalized_source_path := source_path.simplify_path()
	if normalized_source_path.is_empty() or not FileAccess.file_exists(normalized_source_path):
		return ""

	var target_path := FileSystem.copy_file_unique(normalized_source_path, editor.chart.folder_path)
	return target_path.get_file() if not target_path.is_empty() else ""
