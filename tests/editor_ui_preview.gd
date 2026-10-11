extends Node

const OUTPUT := "res://mockup/editor-implementation-2026-10-11/revision-3"

func _ready() -> void:
	call_deferred("_show_editor")

func _show_editor() -> void:
	var chart := Chart.new()
	chart.storage_root = "res://contents/chartsets/dansu"
	chart.folder_name = "beyond desapair"
	chart.file_name = "easy.dansu"
	if not Parser.parse_meta(chart):
		get_tree().quit(1)
		return
	var parsed := Parser.new().parse_object(chart)
	if not parsed.success:
		get_tree().quit(1)
		return
	var original_title := chart.title
	var original_difficulty := chart.difficulty
	CM.selected_chartset = null
	CM.selected_chart = chart
	CM.parsed_chart = parsed.parsed_chart
	Game.current_time = 558.0
	Game.reopen_editor_without_chart_reload = true
	var editor: ChartEditor = load("res://scenes/chart/editor/editor_scene.tscn").instantiate()
	get_tree().root.add_child(editor)
	get_tree().current_scene = editor
	# Interactive preview edits only the fixture, never the source chart.
	chart.storage_root = "res://tests/fixtures"
	chart.folder_name = "editor_ui"
	chart.file_name = "preview.dansu"
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _capture("01-empty")
	editor.selection.select_point(CM.parsed_chart.rails[0], 0)
	await _capture("02-rail")
	editor.inspector.current_tab = 1
	await _capture("03-timing")
	editor.inspector.current_tab = 3
	await _capture("04-chart")
	editor.event_controller.toggle()
	await get_tree().create_timer(1.0).timeout
	await _capture("05-events")
	TranslationServer.set_locale("ko")
	editor.event_controller.toggle()
	editor.inspector.current_tab = 3
	editor.inspector_controller.update_skin_file_ui()
	var tabs: Array[GameText.Key] = [GameText.Key.EDITOR_TAB_PROPERTY, GameText.Key.EDITOR_TIMING, GameText.Key.EDITOR_SFX, GameText.Key.EDITOR_CHART]
	for index in range(tabs.size()):
		editor.inspector.set_tab_title(index, GameText.text(tabs[index]))
	await _capture("06-korean")
	TranslationServer.set_locale("en")
	editor.inspector_controller.update_skin_file_ui()
	for index in range(tabs.size()):
		editor.inspector.set_tab_title(index, GameText.text(tabs[index]))
	editor.title_line_edit.text = ""
	editor.title_line_edit.text_changed.emit("")
	editor.difficulty_line_edit.text = ""
	editor.difficulty_line_edit.text_changed.emit("")
	editor.inspector.current_tab = ChartEditor.PROPERTY_TAB
	editor.save_button.pressed.emit()
	await _capture("07-save-validation")
	editor.title_line_edit.text = original_title
	editor.title_line_edit.text_changed.emit(original_title)
	editor.difficulty_line_edit.text = original_difficulty
	editor.difficulty_line_edit.text_changed.emit(original_difficulty)
	editor.inspector.current_tab = ChartEditor.PROPERTY_TAB
	editor._set_current_time(27921.0)
	editor.selection.select_point(CM.parsed_chart.rails[0], 1)
	await _capture("08-bottom-edge")
	editor.song_slider.mouse_entered.emit()
	editor.save_button.mouse_entered.emit()
	await get_tree().create_timer(0.16).timeout
	await _capture("09-hover")
	editor.song_slider.mouse_exited.emit()
	editor.save_button.mouse_exited.emit()
	get_tree().quit()

func _capture(name: String) -> void:
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(name + ".png"))
