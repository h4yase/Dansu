extends Control

@export var editor: ChartEditor

const PEAKS_PER_SECOND := 200.0
const WAVE_COLOR := Color(0.25, 0.36, 0.46, 0.28)

var _peaks := PackedFloat32Array()
var _peak_msec := 1000.0 / PEAKS_PER_SECOND
var _stream: AudioStream
var _source_path := ""
var _source_modified := 0
var _needs_build := false
var _worker: Thread
var _cancel_mutex := Mutex.new()
var _cancel_requested := false
var _last_time := INF
var _last_scale := INF
var _last_judge_y := INF
var _last_size := Vector2.ZERO

func _ready() -> void:
		editor.transport.stream_loaded.connect(_load_stream)

func _exit_tree() -> void:
	_cancel_build()
	if _worker != null:
		_worker.wait_to_finish()

func _load_stream(stream: AudioStream, path: String) -> void:
	var modified := FileAccess.get_modified_time(path) if not path.is_empty() else 0
	if path == _source_path and modified == _source_modified and (stream == null) == (_stream == null):
		return
	_source_path = path
	_source_modified = modified
	_stream = stream
	_peaks.clear()
	_needs_build = true
	_cancel_build()
	queue_redraw()

func _cancel_build() -> void:
	_cancel_mutex.lock()
	_cancel_requested = true
	_cancel_mutex.unlock()

func _process(_delta: float) -> void:
	if _worker != null and not _worker.is_alive():
		var result: PackedFloat32Array = _worker.wait_to_finish()
		_worker = null
		if not _needs_build:
			_peaks = result
			queue_redraw()
	if _needs_build and _worker == null:
		_needs_build = false
		if _stream != null:
			_cancel_mutex.lock()
			_cancel_requested = false
			_cancel_mutex.unlock()
			_worker = Thread.new()
			var mix_rate := AudioServer.get_mix_rate()
			_peak_msec = maxi(1, int(round(mix_rate / PEAKS_PER_SECOND))) * 1000.0 / mix_rate
			var error := _worker.start(_build_peaks.bind(_stream, mix_rate))
			if error != OK:
				_worker = null
				push_warning("Could not start audio waveform analysis: %s" % error)

	var time := Game.current_time
	var scale := editor.get_pixels_per_ms()
	var judge_y := editor.get_judge_y()
	if time != _last_time or scale != _last_scale or judge_y != _last_judge_y or size != _last_size:
		_last_time = time
		_last_scale = scale
		_last_judge_y = judge_y
		_last_size = size
		queue_redraw()

func _build_peaks(stream: AudioStream, mix_rate: float) -> PackedFloat32Array:
	var peaks := PackedFloat32Array()
	var playback := stream.instantiate_playback()
	if playback == null:
		return peaks
	var frames_per_peak := maxi(1, int(round(mix_rate / PEAKS_PER_SECOND)))
	var total_frames := int(ceil(stream.get_length() * mix_rate))
	playback.start()
	for frame_start in range(0, total_frames, frames_per_peak):
		_cancel_mutex.lock()
		var cancelled := _cancel_requested
		_cancel_mutex.unlock()
		if cancelled:
			break
		var frames := playback.mix_audio(1.0, mini(frames_per_peak, total_frames - frame_start))
		if frames.is_empty():
			break
		var peak := 0.0
		for frame in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		peaks.append(minf(peak, 1.0))
	playback.stop()
	return peaks

func _draw() -> void:
	if _peaks.is_empty() or _last_scale <= 0.0:
		return
	var center_x := size.x * 0.5
	var half_width := size.x * 0.45
	for y in range(int(ceil(size.y))):
		var top_time := _last_time + (_last_judge_y - y) / _last_scale
		var bottom_time := top_time - 1.0 / _last_scale
		var first := maxi(0, int(floor(bottom_time / _peak_msec)))
		var last := mini(_peaks.size() - 1, int(floor(top_time / _peak_msec)))
		if first > last:
			continue
		var peak := 0.0
		for index in range(first, last + 1):
			peak = maxf(peak, _peaks[index])
		var width := peak * half_width
		draw_line(Vector2(center_x - width, y), Vector2(center_x + width, y), WAVE_COLOR)
