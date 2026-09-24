extends Control
class_name DifficultySelector

var star: PackedScene = preload("res://scenes/mainmenu/star_button.tscn")
const STAR_APPEAR_DELAY_STEP := 0.035
const STAR_APPEAR_MAX_DELAY := 0.16

@export var chart_scroll: ChartScroll

var single_chart_mode := false

func _ready() -> void:
	CM.chartset_selected.connect(_update)
	CM.chart_selected.connect(_on_chart_selected)

	if chart_scroll != null:
		chart_scroll.single_chart_mode_changed.connect(set_single_chart_mode)
		single_chart_mode = chart_scroll.is_single_chart_mode()

	if CM.selected_chartset != null:
		_update(CM.selected_chartset)

func _update(_chartset: ChartSet) -> void:
	_rebuild()


func _on_chart_selected(_chart: Chart) -> void:
	if single_chart_mode:
		_rebuild()


func set_single_chart_mode(enabled: bool) -> void:
	if single_chart_mode == enabled:
		return
	single_chart_mode = enabled
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var sorted_charts: Array[Chart] = []
	if single_chart_mode:
		if CM.selected_chart != null:
			sorted_charts.append(CM.selected_chart)
	elif CM.selected_chartset != null:
		sorted_charts = CM.selected_chartset.charts.duplicate()
		sorted_charts.sort_custom(_sort_by_rating)

	var delay_step := minf(STAR_APPEAR_DELAY_STEP, STAR_APPEAR_MAX_DELAY / maxi(sorted_charts.size() - 1, 1))
	for index in range(sorted_charts.size()):
		var chart: Chart = sorted_charts[index]
		var new_star := star.instantiate() as DifficultyStar
		if new_star == null:
			continue
		new_star.rating = chart.rating
		new_star.chart = chart
		add_child(new_star)
		new_star.play_appear_animation(index * delay_step)

func _sort_by_rating(a: Chart, b: Chart) -> bool:
	var ar := a.rating
	var br := b.rating
	return ar < br
