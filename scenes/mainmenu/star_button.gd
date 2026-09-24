extends TextureRect
class_name DifficultyStar

@export_group("Node References")
@export var rating_label: Label
@export var selection_glow: TextureRect

const NORMAL_BRIGHTNESS := 0.75
const SELECTED_BRIGHTNESS := 1.0
const NORMAL_ALPHA := 0.9
const SELECTED_ALPHA := 1.0
const HOVER_ALPHA := 1.0
const NORMAL_SCALE := Vector2.ONE
const SELECTED_SCALE := Vector2(1.12, 1.12)
const HOVER_SCALE := Vector2(1.16, 1.16)
const CLICK_SCALE := Vector2(0.92, 0.92)
const APPEAR_SCALE := Vector2(0.78, 0.78)
const APPEAR_DURATION := 0.18

var rating := 0.0
var chart : Chart

var hover_tween: Tween
var click_tween: Tween
var appear_tween: Tween
var hovered := false
var base_color := Color.WHITE

func _ready() -> void:
	offset_transform_enabled = true
	offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	gui_input.connect(_on_gui_input)
	CM.chart_selected.connect(_update_selected_state)

	base_color = Rating.get_color_from_rating(rating)
	rating_label.text = str(int(rating))
	_update_selected_state(CM.selected_chart)


func play_appear_animation(delay: float = 0.0) -> void:
	if hover_tween:
		hover_tween.kill()
	if click_tween:
		click_tween.kill()
	if appear_tween:
		appear_tween.kill()

	offset_transform_scale = APPEAR_SCALE
	modulate.a = NORMAL_ALPHA

	appear_tween = create_tween()
	appear_tween.set_trans(Tween.TRANS_BACK)
	appear_tween.set_ease(Tween.EASE_OUT)

	if delay > 0.0:
		appear_tween.tween_interval(delay)

	appear_tween.tween_method(_apply_appear_progress, 0.0, 1.0, APPEAR_DURATION)


func _apply_appear_progress(progress: float) -> void:
	# Resolve the current selection every frame so selection updates preserve the stagger.
	var is_selected := chart != null and chart == CM.selected_chart
	var target_scale := HOVER_SCALE if hovered else (SELECTED_SCALE if is_selected else NORMAL_SCALE)
	var target_alpha := HOVER_ALPHA if hovered else (SELECTED_ALPHA if is_selected else NORMAL_ALPHA)
	offset_transform_scale = APPEAR_SCALE.lerp(target_scale, progress)
	modulate.a = lerpf(NORMAL_ALPHA, target_alpha, clampf(progress, 0.0, 1.0))


func _on_enter() -> void:
	hovered = true
	_apply_hover_state()


func _on_exit() -> void:
	hovered = false
	_apply_hover_state()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed()


func _pressed() -> void:
	if chart == null:
		return

	if CM.selected_chartset != chart.chart_set:
		CM.select_chartset(chart.chart_set)
	CM.select_chart(chart)
	_play_click_animation()


func _apply_hover_state() -> void:
	if appear_tween and appear_tween.is_running():
		return
	if click_tween:
		click_tween.kill()
	if hover_tween:
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_trans(Tween.TRANS_BACK)
	hover_tween.set_ease(Tween.EASE_OUT)

	var rest_scale := SELECTED_SCALE if chart != null and chart == CM.selected_chart else NORMAL_SCALE
	var rest_alpha := SELECTED_ALPHA if chart != null and chart == CM.selected_chart else NORMAL_ALPHA

	if hovered:
		hover_tween.tween_property(self, "offset_transform_scale", HOVER_SCALE, 0.15)
		hover_tween.parallel().tween_property(self, "modulate:a", HOVER_ALPHA, 0.15).set_trans(Tween.TRANS_SINE)
	else:
		hover_tween.tween_property(self, "offset_transform_scale", rest_scale, 0.2)
		hover_tween.parallel().tween_property(self, "modulate:a", rest_alpha, 0.2).set_trans(Tween.TRANS_SINE)


func _play_click_animation() -> void:
	if appear_tween:
		appear_tween.kill()
	if click_tween:
		click_tween.kill()

	if hover_tween:
		hover_tween.kill()

	click_tween = create_tween()
	click_tween.set_trans(Tween.TRANS_BACK)
	click_tween.set_ease(Tween.EASE_OUT)
	click_tween.tween_property(self, "offset_transform_scale", CLICK_SCALE, 0.05)
	click_tween.tween_property(
		self,
		"offset_transform_scale",
		HOVER_SCALE if hovered else (SELECTED_SCALE if chart != null and chart == CM.selected_chart else NORMAL_SCALE),
		0.14
	)
	var rest_alpha := SELECTED_ALPHA if chart == CM.selected_chart else NORMAL_ALPHA
	click_tween.parallel().tween_property(self, "modulate:a", HOVER_ALPHA if hovered else rest_alpha, 0.12).set_trans(Tween.TRANS_SINE)


func _update_selected_state(_selected_chart: Chart) -> void:
	var is_selected := chart != null and chart == CM.selected_chart
	var brightness := SELECTED_BRIGHTNESS if is_selected else NORMAL_BRIGHTNESS
	selection_glow.visible = is_selected
	self_modulate = Color(
		base_color.r * brightness,
		base_color.g * brightness,
		base_color.b * brightness,
		1.0
	)
	_apply_hover_state()
