extends Control

@onready var _editor: ChartEditor = owner

var _last_time := INF
var _last_scale := INF
var _last_size := Vector2.ZERO

func _process(_delta: float) -> void:
	if _last_time == Game.current_time and _last_scale == _editor.get_pixels_per_ms() and _last_size == size:
		return
	_last_time = Game.current_time
	_last_scale = _editor.get_pixels_per_ms()
	_last_size = size
	queue_redraw()

func _draw() -> void:
	if _editor.timeline == null:
		return
	var panel := _editor.chart_panel
	var scale_ms := _editor.get_pixels_per_ms()
	var judge_y := _editor.get_judge_y()
	var top_time := Game.current_time + judge_y / scale_ms
	var bottom_time := Game.current_time - (panel.size.y - judge_y) / scale_ms
	var font := get_theme_font("font", "Label")
	var color := Color("b2a8c6")
	for index in range(_editor.chart.timings.size()):
		var timing := _editor.chart.timings[index]
		var segment_top := top_time
		if index + 1 < _editor.chart.timings.size():
			segment_top = minf(segment_top, _editor.chart.timings[index + 1].time - 1)
		var segment_bottom := bottom_time if index == 0 else maxf(bottom_time, timing.time)
		var beat_ms := 60000.0 / timing.bpm
		var label_step := maxi(1, int(ceil(54.0 / (beat_ms * scale_ms))))
		var first_beat := int(ceil((segment_bottom - timing.time) / beat_ms / label_step)) * label_step
		var last_beat := int(floor((segment_top - timing.time) / beat_ms))
		for beat in range(first_beat, last_beat + 1, label_step):
			var time_ms := timing.time + beat * beat_ms
			var y := panel.position.y + judge_y + (Game.current_time - time_ms) * scale_ms
			if y < 15.0 or y > panel.size.y - 15.0:
				continue
			draw_string(font, Vector2(2, y - 2), "%db" % beat, HORIZONTAL_ALIGNMENT_LEFT, 60, 14, color)
			draw_string(font, Vector2(2, y + 14), str(int(round(time_ms))), HORIZONTAL_ALIGNMENT_LEFT, 60, 11, Color(0.47, 0.43, 0.55))
	for step in range(11):
		var x := panel.position.x + panel.size.x * step / 10.0
		var text := "%.1f" % (step / 10.0)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var left := minf(x - width * 0.5, size.x - width)
		draw_string(font, Vector2(left, panel.size.y + 22), text, HORIZONTAL_ALIGNMENT_LEFT, 40, 12, color)

