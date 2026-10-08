extends RefCounted
class_name Rail

var id := -1
var points: Array[RailPoint] = []
var notes: Array[Note] = []

func _init() -> void:
	points = []
	notes = []

var start_time: int:
	get:
		return points[0].time if not points.is_empty() else 0
	set(value):
		if not points.is_empty():
			points[0].time = value

var end_time: int:
	get:
		return int(points[points.size() - 1].time) if not points.is_empty() else 0
	set(value):
		if not points.is_empty():
			points[points.size() - 1].time = value

func copy_geometry() -> Rail:
	var copy := Rail.new()
	for point in points:
		var copied_point := RailPoint.new()
		copied_point.time = point.time
		copied_point.x = point.x
		copied_point.curve = point.curve
		copy.points.append(copied_point)
	return copy

func has_same_geometry(other: Rail) -> bool:
	if other == null or points.size() != other.points.size():
		return false
	for index in range(points.size()):
		var a := points[index]
		var b := other.points[index]
		if a.time != b.time or a.x != b.x or a.curve != b.curve:
			return false
	return true

func sort_points() -> void:
	var original_order: Dictionary = {}
	for index in range(points.size()):
		original_order[points[index]] = index
	points.sort_custom(func(a: RailPoint, b: RailPoint) -> bool:
		if a == b:
			return false
		if a == null:
			return false
		if b == null:
			return true
		if a.time == b.time:
			return int(original_order[a]) < int(original_order[b])
		return a.time < b.time
	)

func sort_notes() -> void:
	notes.sort_custom(func(a, b) -> bool: return a.time < b.time)

func _apply_curve(t: float, curve: float) -> float:
	curve = clamp(curve, -1.0, 1.0)
	if abs(curve) < 0.001:
		return t
	if curve > 0.0:
		return pow(t, 1.0 + curve * 2.0)
	return 1.0 - pow(1.0 - t, 1.0 + abs(curve) * 2.0)

func _get_rail_x_at_time(time_ms: int) -> float:
	if points.is_empty():
		return 0.0
	if points.size() == 1:
		return float(points[0].x)
	if time_ms <= int(points[0].time):
		return float(points[0].x)

	var last_index := points.size() - 1
	if time_ms >= int(points[last_index].time):
		return float(points[last_index].x)

	for i in range(points.size() - 1):
		var a = points[i]
		var b = points[i + 1]
		var t0 := int(a.time)
		var t1 := int(b.time)
		if time_ms < t0 or time_ms > t1:
			continue

		var x0 := float(a.x)
		var x1 := float(b.x)
		if t1 == t0:
			return x1

		var alpha := float(time_ms - t0) / float(t1 - t0)
		alpha = clamp(alpha, 0.0, 1.0)
		alpha = _apply_curve(alpha, float(a.curve))
		return lerp(x0, x1, alpha)

	return 0.0
