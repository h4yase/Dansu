extends Node

signal cover_loaded(chart: Chart, texture: Texture2D)
signal cover_failed(chart: Chart)

class CoverResult extends RefCounted:
	var chart: Chart
	var image: Image

	func _init(p_chart: Chart, p_image: Image) -> void:
		chart = p_chart
		image = p_image

var worker := Thread.new()
var mutex := Mutex.new()
var semaphore := Semaphore.new()
var queued_charts: Array[Chart] = []
var queued_ids := {}
var completed_results: Array[CoverResult] = []
var is_stopping := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	worker.start(Callable(self, "_worker_loop"))


func _exit_tree() -> void:
	is_stopping = true
	semaphore.post()

	if worker.is_started():
		worker.wait_to_finish()


func request_cover(chart: Chart) -> void:
	_enqueue_charts([chart], false)


func replace_queue(charts: Array[Chart]) -> void:
	_enqueue_charts(charts, true)


func _enqueue_charts(charts: Array[Chart], replace_existing: bool) -> void:
	var filtered: Array[Chart] = []
	var filtered_ids := {}

	for chart in charts:
		if chart == null or chart.cover_image != null:
			continue

		var cover_path := chart.get_cover_path()
		if cover_path.is_empty():
			continue

		var chart_id := chart.get_instance_id()
		if filtered_ids.has(chart_id):
			continue

		filtered_ids[chart_id] = true
		filtered.append(chart)

	if replace_existing:
		mutex.lock()
		queued_charts = filtered
		queued_ids = filtered_ids.duplicate()
		mutex.unlock()
		for _i in range(filtered.size()):
			semaphore.post()
		return

	mutex.lock()
	for chart in filtered:
		var chart_id := chart.get_instance_id()
		if queued_ids.has(chart_id):
			continue
		queued_ids[chart_id] = true
		queued_charts.append(chart)
		semaphore.post()
	mutex.unlock()


func _process(_delta: float) -> void:
	var results: Array[CoverResult] = []

	mutex.lock()
	if not completed_results.is_empty():
		results = completed_results
		completed_results = []
	mutex.unlock()

	for result in results:
		var chart: Chart = result.chart
		if chart == null:
			continue

		mutex.lock()
		queued_ids.erase(chart.get_instance_id())
		mutex.unlock()

		var image: Image = result.image
		if image == null:
			cover_failed.emit(chart)
			continue

		if chart.cover_image == null:
			chart.cover_image = ImageTexture.create_from_image(image)

		cover_loaded.emit(chart, chart.cover_image)


func _worker_loop() -> void:
	while true:
		semaphore.wait()

		if is_stopping:
			return

		var chart: Chart = null

		mutex.lock()
		if not queued_charts.is_empty():
			chart = queued_charts.pop_front()
		mutex.unlock()

		if chart == null:
			continue

		var image := chart.load_cover_image_data()

		mutex.lock()
		completed_results.append(CoverResult.new(chart, image))
		mutex.unlock()
