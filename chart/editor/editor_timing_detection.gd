extends Node
class_name EditorTimingDetection

@export var editor: ChartEditor
@export var detect_button: Button
@export var status_label: Label

var _worker: Thread
var _source_chart: Chart
var _source_audio := ""
var _source_times := PackedInt64Array()
var _source_bpms := PackedFloat64Array()

func _ready() -> void:
	detect_button.pressed.connect(detect)
	set_process(false)

func detect() -> void:
	if _worker != null or editor == null or editor.chart == null:
		return
	if editor.chart.file_audio.is_empty():
		status_label.text = GameText.text(GameText.Key.EDITOR_NO_AUDIO)
		return
	_source_chart = editor.chart
	_source_audio = editor.chart.folder_path.path_join(editor.chart.file_audio)
	_source_times.clear()
	_source_bpms.clear()
	for timing in editor.chart.timings:
		_source_times.append(timing.time)
		_source_bpms.append(timing.bpm)
	_worker = Thread.new()
	var path := _source_audio
	var error := _worker.start(func() -> DansuBPMResult: return DansuBPM.analyze(path))
	if error != OK:
		_worker = null
		_source_chart = null
		status_label.text = GameText.text(GameText.Key.EDITOR_TIMING_FAILED)
		return
	detect_button.disabled = true
	status_label.text = GameText.text(GameText.Key.EDITOR_TIMING_DETECTING)
	set_process(true)

func _process(_delta: float) -> void:
	if _worker.is_alive():
		return
	var result: DansuBPMResult = _worker.wait_to_finish()
	_worker = null
	detect_button.disabled = false
	set_process(false)
	if not _source_is_current():
		status_label.text = GameText.text(GameText.Key.EDITOR_TIMING_CHANGED)
	elif result == null or not result.is_ok():
		status_label.text = GameText.text(GameText.Key.EDITOR_TIMING_FAILED)
		if result != null:
			status_label.text += "\n" + result.error
	else:
		_apply_result(result)
	_source_chart = null

func _source_is_current() -> bool:
	if editor.chart != _source_chart:
		return false
	if editor.chart.folder_path.path_join(editor.chart.file_audio) != _source_audio:
		return false
	if editor.chart.timings.size() != _source_times.size():
		return false
	for index in range(_source_times.size()):
		var timing := editor.chart.timings[index]
		if timing.time != _source_times[index] or timing.bpm != _source_bpms[index]:
			return false
	return true

func _apply_result(result: DansuBPMResult) -> void:
	var timings: Array[Timing] = []
	for point: DansuBPMTimingPoint in result.timing_points:
		var timing := Timing.new()
		timing.time = int(round(point.time * 1000.0))
		timing.bpm = point.bpm
		timings.append(timing)
	timings.sort_custom(func(a: Timing, b: Timing) -> bool: return a.time < b.time)
	editor._push_history_snapshot()
	editor.chart.timings = timings
	editor.inspector_controller.rebuild_timing_ui()
	editor.refresh_views()
	editor._update_save_button_state()
	status_label.text = GameText.text(GameText.Key.EDITOR_TIMING_DETECTED) % [result.bpm, result.offset_ms, result.confidence * 100.0, timings.size()]
	if not result.warnings.is_empty():
		status_label.text += "\n" + GameText.text(GameText.Key.EDITOR_TIMING_REVIEW)

func _exit_tree() -> void:
	if _worker != null and _worker.is_started():
		_worker.wait_to_finish()
