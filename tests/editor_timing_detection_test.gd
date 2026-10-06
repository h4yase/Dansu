extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Pass an audio path, expected BPM and expected offset (ms) after --")
		get_tree().quit(1)
		return
	var expected_bpm := float(args[1])
	var expected_offset := int(args[2])
	var chart := Chart.new()
	chart.storage_root = args[0].get_base_dir()
	chart.file_audio = args[0].get_file()
	chart.title = "Native timing test"
	var original := Timing.new()
	original.bpm = 120.0
	chart.timings.append(original)
	get_tree().root.get_node("CM").set("selected_chart", chart)
	get_tree().root.get_node("Game").set("reopen_editor_without_chart_reload", true)
	var scene := load("res://scenes/chart/editor/editor_scene.tscn") as PackedScene
	var editor := scene.instantiate() as ChartEditor
	get_tree().root.add_child(editor)
	var tabs: TabContainer = editor.get_node("Inspector")
	tabs.current_tab = 2
	var detection: EditorTimingDetection = editor.get_node("Controllers/TimingDetection")
	detection.detect_button.pressed.emit()
	assert(detection.detect_button.disabled, "Detection did not start in background")
	while detection.is_processing():
		await get_tree().process_frame
	assert(chart.timings.size() == 1)
	assert(chart.timings[0].bpm == expected_bpm)
	assert(chart.timings[0].time == expected_offset)
	assert(editor._has_unsaved_changes())
	print("APPLIED: ", detection.status_label.text)
	editor._undo_history()
	assert(chart.timings[0].bpm == 120 && chart.timings[0].time == 0)
	editor._redo_history()
	assert(chart.timings[0].bpm == expected_bpm && chart.timings[0].time == expected_offset)
	detection.detect_button.pressed.emit()
	chart.timings[0].bpm = expected_bpm + 1
	while detection.is_processing():
		await get_tree().process_frame
	assert(chart.timings[0].bpm == expected_bpm + 1, "Detection overwrote timing edited during analysis")
	print("STALE RESULT: ", detection.status_label.text)
	chart.file_audio = "missing.mp3"
	detection.detect_button.pressed.emit()
	while detection.is_processing():
		await get_tree().process_frame
	assert(chart.timings[0].bpm == expected_bpm + 1)
	print("FAILED INPUT: ", detection.status_label.text)
	editor.queue_free()
	await get_tree().process_frame
	print("Timing button, native worker, apply, undo, redo and stale-result checks passed.")
	get_tree().quit()
