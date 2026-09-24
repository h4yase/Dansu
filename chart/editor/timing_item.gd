extends PanelContainer
class_name EditorTimingItem

signal changed(item)
signal remove_requested(item)
signal change_started(item)

@export var bpm_line_edit: LineEdit
@export var time_line_edit: LineEdit
@export var remove_button: Button

var timing: Timing = null
var _syncing := false

func _ready() -> void:
	bpm_line_edit.text_submitted.connect(_commit_bpm)
	bpm_line_edit.focus_exited.connect(_commit_current_bpm)
	time_line_edit.text_submitted.connect(_commit_time)
	time_line_edit.focus_exited.connect(_commit_current_time)
	remove_button.pressed.connect(_request_remove)
	UIFocusUtils.disable_focus_recursive(self)

func bind(timing_value: Timing) -> void:
	timing = timing_value
	_syncing = true
	bpm_line_edit.text = str(timing.bpm)
	time_line_edit.text = str(timing.time)
	_syncing = false

func _commit_bpm(value: String) -> void:
	if _syncing or timing == null:
		return
	if value.is_valid_float():
		if is_equal_approx(timing.bpm, value.to_float()):
			return
		change_started.emit(self)
		timing.bpm = value.to_float()
	changed.emit(self)

func _commit_current_bpm() -> void:
	_commit_bpm(bpm_line_edit.text)

func _commit_time(value: String) -> void:
	if _syncing or timing == null:
		return
	if value.is_valid_int():
		if timing.time == value.to_int():
			return
		change_started.emit(self)
		timing.time = value.to_int()
	changed.emit(self)

func _commit_current_time() -> void:
	_commit_time(time_line_edit.text)

func _request_remove() -> void:
	remove_requested.emit(self)
