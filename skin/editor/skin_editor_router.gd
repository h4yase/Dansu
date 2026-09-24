extends RefCounted
class_name SkinEditorRouter

const SKIN_EDITOR_SCENE_PATH := "res://scenes/skin/editor/skin_editor.tscn"

static func open_custom_skin_editor() -> void:
	var skin_path := SkinSerialization.ensure_custom_skin_path()
	if skin_path == "":
		return

	var context = SkinEditorContext.new()
	context.open_mode = SkinEditorContext.OpenMode.CUSTOM
	context.return_target = SkinEditorContext.ReturnTarget.MENU
	context.skin_file_path = skin_path
	context.previous_custom_skin_path = Config.custom_skin_path
	Game.skin_editor_request = context
	Transition.transition_to(SKIN_EDITOR_SCENE_PATH, 0.45)

static func open_chart_skin_editor(chart) -> void:
	if chart == null:
		return

	var context = SkinEditorContext.new()
	context.open_mode = SkinEditorContext.OpenMode.CHART
	context.return_target = SkinEditorContext.ReturnTarget.EDITOR
	context.chart_folder_path = ProjectSettings.globalize_path(chart.folder_path)
	context.referenced_skin_file_name = chart.file_skin
	if chart.file_skin != "":
		context.skin_file_path = SkinSerialization.ensure_chart_skin_path(chart)
	Game.skin_editor_request = context
	Game.reopen_editor_without_chart_reload = true
	Transition.transition_to(SKIN_EDITOR_SCENE_PATH, 0.45)

static func open_new_chart_skin_editor(chart) -> void:
	if chart == null:
		return

	var context = SkinEditorContext.new()
	context.open_mode = SkinEditorContext.OpenMode.CHART
	context.return_target = SkinEditorContext.ReturnTarget.EDITOR
	context.chart_folder_path = ProjectSettings.globalize_path(chart.folder_path)
	Game.skin_editor_request = context
	Game.reopen_editor_without_chart_reload = true
	Transition.transition_to(SKIN_EDITOR_SCENE_PATH, 0.45)
