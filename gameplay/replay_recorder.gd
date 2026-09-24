extends RefCounted
class_name ReplayRecorder

var replay: Replay
var enabled := false

func setup(chart, should_record: bool) -> void:
	enabled = should_record
	replay = null
	if not enabled:
		return

	replay = Replay.new()
	replay.setup(chart)

func record(inputs: Array[ReplayInput]) -> void:
	if not enabled or replay == null:
		return

	for input in inputs:
		var saved := replay.add_input(input.timing, input.type)
		if saved != null:
			saved.order = input.order
