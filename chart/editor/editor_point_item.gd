extends PanelContainer
class_name EditorPointItem

@export var number_label: Label
@export var time_edit: LineEdit
@export var position_slider: HSlider
@export var position_value: Label
@export var curve_slider: HSlider
@export var curve_value: Label
@export var selected_style: StyleBox

var editor: ChartEditor
var rail: Rail
var point: RailPoint
var _normal_style: StyleBox
var _syncing := false
var _time_history_pending := true

func _ready() -> void:
	_normal_style = get_theme_stylebox("panel")
	gui_input.connect(_on_input)
	position_slider.gui_input.connect(_on_input)
	curve_slider.gui_input.connect(_on_input)
	position_slider.value_changed.connect(_on_position_changed)
	curve_slider.value_changed.connect(_on_curve_changed)
	time_edit.focus_entered.connect(_on_time_focus)
	time_edit.text_changed.connect(_on_time_changed)
	time_edit.text_submitted.connect(_finish_time_edit)
	time_edit.focus_exited.connect(_finish_time_edit)
	UIFocusUtils.disable_focus_recursive(self)

func sync(index: int) -> void:
	_syncing = true
	number_label.text = "#%d" % (index + 1)
	if not time_edit.has_focus():
		time_edit.text = str(point.time)
	position_slider.value = point.x
	curve_slider.value = point.curve
	position_value.text = "%.2f" % point.x
	curve_value.text = "%.2f" % point.curve
	var selected := editor.selection.selected_points.has(point)
	add_theme_stylebox_override("panel", selected_style if selected else _normal_style)
	_syncing = false

func _select_point() -> void:
	if editor.selection.get_point() != point or not editor.selection.selected_notes.is_empty():
		editor.selection.select_point(rail, rail.points.find(point))

func _on_input(event: InputEvent) -> void:
	if editor == null or not event is InputEventMouseButton:
		return
	if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.ctrl_pressed:
			editor.selection.select_point(rail, rail.points.find(point), true)
		else:
			_select_point()

func _on_position_changed(value: float) -> void:
	if _syncing or editor == null or is_equal_approx(point.x, value):
		return
	_select_point()
	editor.push_history_snapshot()
	point.x = value
	editor.view_controller.refresh_geometry([rail])
	editor.selection.refresh()

func _on_curve_changed(value: float) -> void:
	if _syncing or editor == null or is_equal_approx(point.curve, value):
		return
	_select_point()
	editor.push_history_snapshot()
	point.curve = value
	editor.view_controller.refresh_geometry([rail])
	editor.selection.refresh()

func _on_time_focus() -> void:
	_time_history_pending = true
	if editor != null:
		_select_point()

func _on_time_changed(value: String) -> void:
	if _syncing or editor == null or not value.is_valid_int():
		return
	var next_time := maxi(editor.timeline.get_min_time(), value.to_int())
	next_time = EditorChartOps.constrain_rail_point_time(rail, point, next_time)
	if next_time == point.time:
		return
	_select_point()
	if _time_history_pending:
		editor.push_history_snapshot()
		_time_history_pending = false
	point.time = next_time
	rail.sort_points()
	editor.selection.selected_point_index = rail.points.find(point)
	editor.view_controller.refresh_geometry([rail])
	editor.selection.refresh()

func _finish_time_edit(_value: String = "") -> void:
	_syncing = true
	time_edit.text = str(point.time)
	_syncing = false
	_time_history_pending = true
