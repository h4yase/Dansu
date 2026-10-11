extends Node

var _failures := 0
var _checks := 0
var _interactions := 0
var _editor: ChartEditor

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var chart := Chart.new()
	chart.build_uuid()
	chart.title = "UI test"
	chart.difficulty = "Easy"
	chart.storage_root = "res://tests/fixtures"
	chart.folder_name = "editor_ui"
	chart.file_name = "test.dansu"
	var timing := Timing.new()
	timing.bpm = 215.0
	chart.timings.append(timing)
	CM.selected_chartset = null
	CM.selected_chart = chart
	CM.parsed_chart = ParsedChart.new(chart)
	Game.reopen_editor_without_chart_reload = true
	_editor = load("res://scenes/chart/editor/editor_scene.tscn").instantiate()
	get_tree().root.add_child(_editor)
	_editor.timeline = EditorTimeline.new(chart, 122.0)
	_editor.transport.timeline = _editor.timeline
	_editor._update_slider_range()
	await _settle()

	var points: EditorRailTimeline = _editor.get_node("Workspace/Transport/Row/Tracks/RailPoints/Timeline")
	var strip: Control = points
	var full_height := _editor.chart_root.size.y
	var playback_y := _editor.play_button.global_position.y
	_check(is_equal_approx(_editor.play_button.get_global_rect().get_center().y, _editor.song_slider.get_parent().get_global_rect().get_center().y), "Play and time are centered beside the complete track area")
	_check(_editor.get_node("Workspace/Transport").size.y <= 84.0, "Transport keeps the compact height")
	_check(not strip.visible, "No selection hides the rail point drawing")
	_check(not _editor.preview_column.visible, "Note editing reserves no preview column")
	_check(_editor.chart_panel.size.x > 900, "Canvas receives the reclaimed width")
	_check(_editor.inspector.get_tab_control(0).name == &"Property", "Property is the first tab")
	_check(_editor.title_line_edit.focus_mode != Control.FOCUS_NONE, "Text fields retain focus")
	for key in ["EDITOR_EVENTS_TOGGLE", "EDITOR_EDIT_SKIN", "EDITOR_SELECT_OBJECT", "EDITOR_SAVE", "EDITOR_INPUT_HINTS", "EDITOR_UNTITLED"]:
		_check(tr(key) != key, "New UI text is registered: " + key)

	_editor.title_line_edit.text = "Updated title"
	_editor.title_line_edit.text_changed.emit("Updated title")
	_editor.difficulty_line_edit.text = "Hard"
	_editor.difficulty_line_edit.text_changed.emit("Hard")
	_check(_editor.inspector_controller.title_summary.text == chart.title, "Title summary follows chart edits")
	_check(_editor.inspector_controller.difficulty_summary.text == "Hard", "Difficulty summary follows chart edits")
	chart.cover_image = load("res://icon.svg")
	_editor.inspector_controller.update_media_ui()
	_check(_editor.inspector_controller.header_cover.texture == chart.cover_image, "Header uses the current chart cover")
	_editor.inspector_controller._on_cover_failed(chart)
	_check(_editor.inspector_controller.header_cover.texture == null, "Failed covers leave no placeholder in the header")
	chart.cover_image = null
	_check(_editor.open_skin_editor_button.disabled, "Edit is disabled without a selected skin")
	_editor.skin_browser_button.pressed.emit()
	var skin_menu: PopupMenu = _editor.get_node("Dialogs/SkinPickerMenu")
	_check(skin_menu.get_item_index(0) >= 0 and skin_menu.get_item_index(EditorInspectorController.CREATE_NEW_SKIN_ID) >= 0, "Skin dropdown includes the fixture skin and Create")
	skin_menu.id_pressed.emit(0)
	skin_menu.hide()
	_check(chart.file_skin == "test_skin", "Skin choice updates the actual chart target")
	_check(_editor.skin_browser_button.text == "test_skin", "Skin dropdown displays its edit target")
	_check(not _editor.open_skin_editor_button.disabled, "Selected skin enables Edit")
	_check(_editor.skin_browser_button.get_parent() == _editor.open_skin_editor_button.get_parent(), "Skin selection and Edit share one row")

	var rail := Rail.new()
	for time in [558, 1953, 48000, 49395]:
		var point := RailPoint.new()
		point.time = time
		point.x = 0.5
		rail.points.append(point)
	rail.sort_points()
	CM.parsed_chart.rails.append(rail)
	_editor.refresh_views()
	_editor.selection.select_point(rail, 1)
	await _settle()
	_check(strip.visible, "Selected rail reveals the point strip")
	_check(is_equal_approx(_editor.chart_root.size.y, full_height), "Selecting a rail preserves canvas height")
	_check(is_equal_approx(playback_y, _editor.play_button.global_position.y), "Playback remains anchored when the strip appears")

	_check(is_equal_approx(points.global_position.x, _editor.song_slider.global_position.x) and is_equal_approx(points.size.x, _editor.song_slider.size.x), "Rail and song tracks share their horizontal bounds")
	_check(points._get_visible_point_indices(rail) == [0, 3, 1], "Only endpoints and the selected middle point are shown")
	_editor.selection.select_point(rail, 0)
	_check(points._get_visible_point_indices(rail) == [0, 3], "Selecting an endpoint shows only two points")
	_editor.selection.select_point(rail, 1)
	_check(points._get_point_hit_index(Vector2(points._time_to_x(48000), points.size.y * 0.5), rail) == -1, "Hidden middle points cannot be dragged from the timeline")
	var native_click_x := points.global_position.x + points._time_to_x(1953)
	var native_click_y := _editor.song_slider.global_position.y + _editor.song_slider.size.y * 0.5
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(native_click_x, native_click_y)
	click.global_position = click.position
	click.pressed = true
	get_viewport().push_input(click)
	click = click.duplicate()
	click.pressed = false
	get_viewport().push_input(click)
	_check(absf(points._time_to_x(int(_editor.song_slider.value)) - points._time_to_x(1953)) <= 1.0, "Native song seek aligns with the rail point within one pixel")
	var old_point_time := rail.points[1].time
	_editor.song_slider.value = 5000.0
	_check(is_equal_approx(Game.current_time, 5000.0), "Song seek changes playback time")
	_check(rail.points[1].time == old_point_time, "Song seek does not edit points")
	var start := points._time_to_x(558)
	var finish := points._time_to_x(49395)
	var fraction := (points._time_to_x(1953) - start) / (finish - start)
	_check(absf(fraction - 1395.0 / 48837.0) < 0.0001, "Point positions preserve their actual time proportions")
	points._begin_drag(Vector2(points._time_to_x(old_point_time), points.size.y * 0.5))
	points._drag_point_to(points._time_to_x(2200))
	points._end_drag()
	_check(rail.points[1].time == _editor.timeline.snap_time(2200), "Point drag uses the existing musical snap")
	_check(is_equal_approx(Game.current_time, 5000.0), "Point drag does not seek the song")
	_editor._undo_history()
	_check(CM.parsed_chart.rails[0].points[1].time == old_point_time, "Undo restores point time")
	var gesture = _editor.edit_controller.gesture
	gesture.editor = _editor
	gesture.dragged_point = CM.parsed_chart.rails[0].points[1]
	gesture.show_point_position(Vector2(400, 400))
	_check(_editor.get_node("PointPosition").visible, "Point position uses the authored scene")
	gesture.position_capsule.hide()
	gesture.update_box(Rect2(10, 10, 40, 40))
	_check(_editor.chart_panel.get_node("SelectionBox").visible, "Box selection uses the authored scene")
	gesture.marquee.hide()

	_editor.selection.clear()
	await _settle()
	_check(not strip.visible, "Clearing selection hides the point drawing")
	_check(is_equal_approx(_editor.chart_root.size.y, full_height), "Clearing selection preserves canvas height")
	_editor.event_controller.toggle()
	await _settle()
	_check(_editor.preview_column.visible and _editor.open_event_editor_button.button_pressed, "Events expose preview and update the toggle")
	_check(not strip.visible, "Event editing reserves no rail strip")
	_check(is_equal_approx(_editor.chart_root.size.y, full_height), "Events preserve canvas height")
	_editor.event_controller.toggle()
	await _settle()
	_check(not _editor.preview_column.visible and not _editor.open_event_editor_button.button_pressed, "Returning to notes restores the wide canvas")
	_check(_editor.chart_panel.clip_contents, "The chart panel clips note and rail drawing at its boundary")
	_check(_editor.play_button.get_node("Key/Label").text == "SPACE", "Space belongs inside the Play button")

	var button := _editor.play_button
	var feedback: DansuUIFeedback = button.get_node("Feedback")
	feedback.interaction.connect(_on_interaction)
	button.mouse_entered.emit()
	await get_tree().create_timer(0.16).timeout
	_check(feedback.get_node("Highlight").modulate.a > 0.5, "Hover animates the highlight")
	button.button_down.emit()
	await get_tree().create_timer(0.09).timeout
	_check(button.scale.x < 1.0, "Press animates the button")
	button.button_up.emit()
	await get_tree().create_timer(0.18).timeout
	_check(button.scale.is_equal_approx(Vector2.ONE), "Release returns to the original size")
	button.button_down.emit()
	await get_tree().create_timer(0.09).timeout
	button.disabled = true
	await _settle()
	_check(button.scale.is_equal_approx(Vector2.ONE), "Disabling a pressed button clears its scale")
	var before_disabled := _interactions
	button.mouse_entered.emit()
	button.button_down.emit()
	_check(_interactions == before_disabled, "Disabled buttons emit no hover or press feedback")
	button.disabled = false
	button.hide()
	_check(is_zero_approx(feedback.get_node("Highlight").modulate.a), "Hidden controls clear their highlight")
	button.show()
	var slider := _editor.song_slider
	var slider_feedback: DansuUIFeedback = slider.get_node("Feedback")
	var slider_rect := slider.get_global_rect()
	slider.mouse_entered.emit()
	await get_tree().create_timer(0.16).timeout
	_check(slider.self_modulate.r > 1.0 and is_zero_approx(slider_feedback.get_node("Highlight").modulate.a), "Seek hover brightens the track without a rectangular overlay")
	_check(slider.get_global_rect() == slider_rect, "Seek hover preserves track bounds")
	slider.mouse_exited.emit()
	await get_tree().create_timer(0.16).timeout
	_check(slider.self_modulate.is_equal_approx(Color.WHITE), "Seek brightness returns on exit")
	var save := _editor.save_button
	var save_feedback: DansuUIFeedback = save.get_node("Feedback")
	var save_rect := save.get_global_rect()
	save.mouse_entered.emit()
	await get_tree().create_timer(0.16).timeout
	_check(save.self_modulate.r > 1.0 and is_zero_approx(save_feedback.get_node("Highlight").modulate.a), "SAVE hover brightens its slanted surface without a rectangular overlay")
	_check(save.get_global_rect() == save_rect and save.get_theme_stylebox("hover") == save.get_theme_stylebox("normal"), "SAVE hover preserves its shape and bounds")
	save.mouse_exited.emit()
	await get_tree().create_timer(0.16).timeout
	_check(save.self_modulate.is_equal_approx(Color.WHITE), "SAVE brightness returns on exit")
	_check(absf(_editor.timeline.get_snap_interval_ms(0) - 60000.0 / 215.0 / 4.0) < 0.0001, "Quarter beats follow BPM instead of fixed milliseconds")

	_editor.title_line_edit.text = "   "
	_editor.title_line_edit.text_changed.emit("   ")
	_editor.difficulty_line_edit.text = ""
	_editor.difficulty_line_edit.text_changed.emit("")
	_editor.inspector.current_tab = ChartEditor.PROPERTY_TAB
	_check(not _editor.save_button.disabled, "SAVE stays available with missing metadata")
	_check(not _editor._save_chart(), "Missing metadata blocks saving")
	await get_tree().create_timer(0.075).timeout
	var title_error: Panel = _editor.title_line_edit.get_node("Feedback/Error")
	var difficulty_error: Panel = _editor.difficulty_line_edit.get_node("Feedback/Error")
	_check(_editor.inspector.current_tab == ChartEditor.CHART_TAB, "Invalid save opens CHART")
	_check(_editor.title_line_edit.has_focus(), "Invalid save focuses the first missing input")
	_check(title_error.modulate.a > 0.9 and difficulty_error.modulate.a > 0.9, "Both missing inputs flash red")
	_check(not is_zero_approx(_editor.title_line_edit.rotation), "Missing input shakes around its center")
	await get_tree().create_timer(0.8).timeout
	_check(is_zero_approx(title_error.modulate.a) and is_zero_approx(difficulty_error.modulate.a), "Error highlights return to normal")
	_check(is_zero_approx(_editor.title_line_edit.rotation) and is_zero_approx(_editor.difficulty_line_edit.rotation), "Input rotation returns to normal")
	_editor.title_line_edit.text = "Valid title"
	_editor.title_line_edit.text_changed.emit("Valid title")
	_editor.inspector.current_tab = ChartEditor.PROPERTY_TAB
	_check(not _editor._save_chart(), "Difficulty alone remains required")
	await get_tree().create_timer(0.075).timeout
	_check(is_zero_approx(title_error.modulate.a) and difficulty_error.modulate.a > 0.9, "Only the remaining missing input is highlighted")
	_editor.inspector.current_tab = ChartEditor.PROPERTY_TAB
	_check(is_zero_approx(difficulty_error.modulate.a) and is_zero_approx(_editor.difficulty_line_edit.rotation), "Hiding a rejected field clears the animation")
	_editor.queue_free()
	await get_tree().process_frame
	print("Editor UI: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _settle() -> void:
	for frame in range(4):
		await get_tree().process_frame

func _on_interaction(_kind: DansuUIFeedback.Kind) -> void:
	_interactions += 1

func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error(message)
