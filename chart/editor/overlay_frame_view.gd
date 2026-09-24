extends EditorEventPreview

func _apply_drag(mouse_position: Vector2) -> void:
	super._apply_drag(mouse_position)
	if _drag_changed and event_editor.event_controller != null:
		event_editor.event_controller.refresh_inspector()

func _draw() -> void:
	_drawn_overlays.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color("101018"))
	_draw_stage_grid()
	if event_editor == null:
		return
	var event: ChartEvent = event_editor.selection.selected_event
	var index: int = event_editor.selection.selected_event_frame_index
	if not event is OverlayEvent or index < 0 or index >= event.frames.size():
		return
	# Resolve only this keyframe, never the transport's interpolated state.
	var state := ChartEventEvaluator._overlay_state_at(event.frames, index)
	var texture := _load_event_texture(event_editor.chart, state.sprite)
	if texture == null:
		return
	var rect := _get_stage_rect()
	var stage_scale := _get_stage_scale()
	var data := OverlayDrawState.new()
	data.event = event
	data.frame_index = index
	data.center = rect.position + rect.size * OverlayEventFrame.anchor_to_vector(event.anchor) + state.position * stage_scale
	data.scale = state.scale * stage_scale
	data.rotation = deg_to_rad(state.rotation)
	data.texture_size = texture.get_size()
	data.stage_scale = stage_scale
	_drawn_overlays.append(data)
	draw_set_transform(data.center, data.rotation, data.scale)
	draw_texture(texture, -texture.get_size() * 0.5, Color(1, 1, 1, state.opacity))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_draw_overlay_selection(data)
