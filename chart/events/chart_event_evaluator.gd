extends RefCounted
class_name ChartEventEvaluator

class OverlayState:
	extends RefCounted
	var sprite := ""
	var position := Vector2.ZERO
	var scale := Vector2.ONE
	var rotation := 0.0
	var opacity := 1.0
	var frame_index := 0

static func evaluate_overlay(event: OverlayEvent, local_time: float) -> OverlayState:
	if event == null or event.frames.is_empty():
		return null
	var pair := frame_pair_indices(event.frames, local_time)
	var previous: OverlayEventFrame = event.frames[pair.x]
	var next: OverlayEventFrame = event.frames[pair.y]
	var alpha := frame_alpha(previous, next, local_time)
	var previous_state := _overlay_state_at(event.frames, pair.x)
	var next_state := _overlay_state_at(event.frames, pair.y)
	var state := OverlayState.new()
	state.sprite = previous_state.sprite
	state.position = previous_state.position.lerp(next_state.position, alpha)
	state.scale = previous_state.scale.lerp(next_state.scale, alpha)
	state.rotation = lerpf(previous_state.rotation, next_state.rotation, alpha)
	state.opacity = lerpf(previous_state.opacity, next_state.opacity, alpha)
	state.frame_index = pair.x if pair.x == pair.y or absf(local_time - previous.time) <= absf(next.time - local_time) else pair.y
	return state

static func frame_pair_indices(frames: Array, local_time: float) -> Vector2i:
	var previous_index := 0
	var next_index := frames.size() - 1
	for index in range(frames.size()):
		var frame = frames[index]
		if frame.time <= local_time:
			previous_index = index
		if frame.time >= local_time:
			next_index = index
			break
	return Vector2i(previous_index, next_index)

static func frame_alpha(previous: ChartEventFrame, next: ChartEventFrame, local_time: float) -> float:
	if previous == next or next.time <= previous.time:
		return 0.0
	var alpha := clampf((local_time - previous.time) / float(next.time - previous.time), 0.0, 1.0)
	return apply_ease(alpha, next.ease)

static func apply_ease(value: float, ease_name: String) -> float:
	match ease_name:
		"in_sine": return 1.0 - cos(value * PI * 0.5)
		"out_sine": return sin(value * PI * 0.5)
		"in_out_sine": return -(cos(PI * value) - 1.0) * 0.5
		"in_quad": return value * value
		"out_quad": return 1.0 - (1.0 - value) * (1.0 - value)
		"in_out_quad": return 2.0 * value * value if value < 0.5 else 1.0 - pow(-2.0 * value + 2.0, 2.0) * 0.5
		"in_cubic": return value * value * value
		"out_cubic": return 1.0 - pow(1.0 - value, 3.0)
		"in_out_cubic": return 4.0 * value * value * value if value < 0.5 else 1.0 - pow(-2.0 * value + 2.0, 3.0) * 0.5
		_: return value

static func _overlay_state_at(frames: Array[OverlayEventFrame], target_index: int) -> OverlayState:
	var state := OverlayState.new()
	var clamped_index := clampi(target_index, 0, frames.size() - 1)
	for index in range(clamped_index + 1):
		if not frames[index].sprite.is_empty():
			state.sprite = frames[index].sprite
		if frames[index].has_opacity:
			state.opacity = frames[index].opacity
	var frame := frames[clamped_index]
	state.position = frame.position
	state.scale = frame.scale
	state.rotation = frame.rotation
	return state
