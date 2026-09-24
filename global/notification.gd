extends Node

enum Type {NOTICE, WARNING, ERROR}

const MAX_VISIBLE := 5
const DISPLAY_SECONDS := 2.5
const STACK_WIDTH := 680.0
const STACK_BOTTOM := 22.0
const ITEM_MIN_HEIGHT := 58.0
const ITEM_GAP := 10

class PendingNotice extends RefCounted:
	var message: String
	var type: Type

	func _init(p_message: String, p_type: Type) -> void:
		message = p_message
		type = p_type

var _stack: VBoxContainer
var _pending: Array[PendingNotice] = []
var _dismiss_queue: Array[Control] = []
var _visible_count := 0
var _dismissing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func notice(message: String, type: Type = Type.NOTICE) -> void:
	var clean_message := message.strip_edges()
	if clean_message.is_empty():
		return
	match type:
		Type.ERROR:
			push_error(clean_message)
		Type.WARNING:
			push_warning(clean_message)
		Type.NOTICE:
			print(clean_message)
	_pending.append(PendingNotice.new(clean_message, type))
	call_deferred("_pump")


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "AlertLayer"
	layer.layer = 1000
	add_child(layer)

	var viewport_root := Control.new()
	viewport_root.name = "AlertViewport"
	viewport_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(viewport_root)

	_stack = VBoxContainer.new()
	_stack.name = "AlertStack"
	_stack.set_anchor(SIDE_LEFT, 0.5)
	_stack.set_anchor(SIDE_TOP, 1.0)
	_stack.set_anchor(SIDE_RIGHT, 0.5)
	_stack.set_anchor(SIDE_BOTTOM, 1.0)
	_stack.offset_left = -STACK_WIDTH * 0.5
	_stack.offset_top = -STACK_BOTTOM
	_stack.offset_right = STACK_WIDTH * 0.5
	_stack.offset_bottom = -STACK_BOTTOM
	_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.add_theme_constant_override("separation", ITEM_GAP)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_root.add_child(_stack)


func _pump() -> void:
	if _stack == null or not is_instance_valid(_stack):
		return
	while _visible_count < MAX_VISIBLE and not _pending.is_empty():
		var entry: PendingNotice = _pending.pop_front()
		_show_alert(entry.message, entry.type)


func _show_alert(message: String, type: Type) -> void:
	var slot := MarginContainer.new()
	slot.name = "Alert"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_child(slot)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(0.0, ITEM_MIN_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.offset_transform_enabled = true
	panel.add_theme_stylebox_override("panel", _panel_style(type))
	slot.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var marker := Label.new()
	marker.custom_minimum_size = Vector2(26.0, 0.0)
	marker.text = _marker_text(type)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_color_override("font_color", _accent_color(type))
	marker.add_theme_font_size_override("font_size", 24)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(marker)

	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color("f5f2ff"))
	label.add_theme_font_size_override("font_size", 20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	_visible_count += 1
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	panel.offset_transform_position = Vector2(0.0, ITEM_MIN_HEIGHT + STACK_BOTTOM)
	panel.offset_transform_scale = Vector2(0.96, 0.96)
	panel.offset_transform_pivot_ratio = Vector2(0.5, 1.0)

	var enter := create_tween().set_parallel(true)
	enter.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	enter.set_trans(Tween.TRANS_BACK)
	enter.set_ease(Tween.EASE_OUT)
	enter.tween_property(panel, "offset_transform_position", Vector2.ZERO, 0.34)
	enter.tween_property(panel, "offset_transform_scale", Vector2.ONE, 0.34)
	enter.tween_property(panel, "modulate:a", 1.0, 0.18)

	get_tree().create_timer(DISPLAY_SECONDS, true, false, true).timeout.connect(
		_queue_dismiss.bind(slot, panel)
	)


func _queue_dismiss(slot: Control, panel: Control) -> void:
	if not is_instance_valid(slot) or not is_instance_valid(panel):
		return
	slot.set_meta("alert_panel", panel)
	_dismiss_queue.append(slot)
	if not _dismissing:
		call_deferred("_dismiss_next")


func _dismiss_next() -> void:
	if _dismissing or _dismiss_queue.is_empty():
		return
	_dismissing = true
	var slot: Control = _dismiss_queue.pop_front()
	if is_instance_valid(slot):
		var panel := slot.get_meta("alert_panel") as Control
		if is_instance_valid(panel):
			var leave := create_tween().set_parallel(true)
			leave.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			leave.set_trans(Tween.TRANS_QUAD)
			leave.set_ease(Tween.EASE_IN)
			leave.tween_property(panel, "offset_transform_position", Vector2(0.0, 18.0), 0.2)
			leave.tween_property(panel, "modulate:a", 0.0, 0.16)
			await leave.finished
			var height: float = slot.size.y
			slot.custom_minimum_size.y = height
			panel.hide()
			var collapse := create_tween()
			collapse.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			collapse.set_trans(Tween.TRANS_QUAD)
			collapse.set_ease(Tween.EASE_IN_OUT)
			collapse.tween_property(slot, "custom_minimum_size:y", 0.0, 0.16)
			await collapse.finished
		slot.queue_free()
		_visible_count = maxi(0, _visible_count - 1)
	_dismissing = false
	_pump()
	if not _dismiss_queue.is_empty():
		call_deferred("_dismiss_next")


func _panel_style(type: Type) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("161422f2")
	style.border_width_left = 5
	style.border_color = _accent_color(type)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style


func _accent_color(type: Type) -> Color:
	match type:
		Type.ERROR:
			return Color("ff5d73")
		Type.WARNING:
			return Color("ffc65c")
		_:
			return Color("8068f2")


func _marker_text(type: Type) -> String:
	match type:
		Type.ERROR:
			return "×"
		Type.WARNING:
			return "!"
		_:
			return "●"
