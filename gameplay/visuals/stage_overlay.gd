extends Control

@export var visualizer: GameplayStageVisualizer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var low: float = visualizer.low_energy if visualizer != null else 0.0
	var mid: float = visualizer.mid_energy if visualizer != null else 0.0
	var high: float = visualizer.high_energy if visualizer != null else 0.0
	var volume: float = visualizer.volume_level if visualizer != null else 0.0
	var time_seconds: float = maxf(Game.current_time, 0.0) * 0.001

	var baseline_y := size.y - 15.0
	var points := PackedVector2Array()
	const POINT_COUNT := 65
	for index in range(POINT_COUNT):
		var progress := float(index) / float(POINT_COUNT - 1)
		var x := progress * size.x
		var edge_envelope := pow(abs(progress * 2.0 - 1.0), 1.45)
		var wave := sin(float(index) * 0.62 - time_seconds * 3.1)
		var secondary := sin(float(index) * 0.21 + time_seconds * 1.7) * 0.45
		var y := baseline_y - (wave + secondary) * (0.8 + low * 3.2) * (0.35 + edge_envelope * 0.65)
		points.append(Vector2(x, y))

	var accent := Color(0.48, 0.46, 0.68, 0.56 + volume * 0.12)
	var dim := Color(0.30, 0.30, 0.38, 0.46)
	draw_polyline(points, accent, 2.5 + volume * 0.30, true)
	draw_line(Vector2(0.0, size.y - 8.0), Vector2(size.x, size.y - 8.0), dim, 2.0, true)
	draw_line(Vector2(0.0, size.y - 3.0), Vector2(size.x, size.y - 3.0), Color(0.18, 0.18, 0.22, 0.8), 5.0)

	var tick_spacing := 48.0
	var tick_count := int(ceil(size.x / tick_spacing))
	for index in range(tick_count + 1):
		var x := float(index) * tick_spacing
		var tick_height: float = 2.0 + high * 6.0 * (0.35 + 0.65 * abs(sin(float(index) * 1.71 + time_seconds)))
		draw_line(Vector2(x, baseline_y + 3.0), Vector2(x, baseline_y + 3.0 - tick_height), Color(accent.r, accent.g, accent.b, 0.18 + mid * 0.16), 1.0)
