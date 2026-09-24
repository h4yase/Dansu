extends RefCounted
class_name GameplayPlayfield

const PLAY_AREA_SIZE : Vector2 = Vector2(15,50)
const SPAWN_FADE_PORTION := 0.18
const JUDGEMENT_Z := -0.5


static func get_spawn_fade_distance() -> float:
	return PLAY_AREA_SIZE.y * SPAWN_FADE_PORTION

static func get_visible_travel_time_ms() -> float:
	return PLAY_AREA_SIZE.y / maxf(Config.note_speed, 0.001) * 1000.0

static func get_spawn_fade_alpha(time_ms: float, current_time: float) -> float:
	var progress := 1.0 - ((time_ms - current_time) / get_visible_travel_time_ms())
	return clampf(progress / SPAWN_FADE_PORTION, 0.0, 1.0)

static func normalized_x_to_world(value: float) -> float:
	return (clampf(value, 0.0, 1.0) - 0.5) * PLAY_AREA_SIZE.x

static func rail_origin_z(start_time: int, current_time: float) -> float:
	return PLAY_AREA_SIZE.y - ((float(start_time) - current_time) * Config.note_speed/ 1000.0)

static func local_z_from_start(start_time: int, time_ms: int) -> float:
	return -((float(time_ms) - float(start_time)) * Config.note_speed/ 1000.0)
