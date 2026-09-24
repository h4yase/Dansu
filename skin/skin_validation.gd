extends RefCounted
class_name SkinValidation

static func ensure_unique_animation_ids(skin_data) -> void:
	if skin_data == null:
		return

	var used := {}
	var next_id := 1
	for animation in skin_data.animations:
		if animation == null:
			continue

		var target_id := int(animation.id)
		if target_id <= 0 or used.has(target_id):
			while used.has(next_id):
				next_id += 1
			target_id = next_id
			next_id += 1

		animation.id = target_id
		used[target_id] = true

static func get_animation_ids(skin_data) -> Array[int]:
	var result: Array[int] = []
	if skin_data == null:
		return result
	for animation in skin_data.animations:
		if animation != null:
			result.append(int(animation.id))
	return result

static func cleanup_player_slots(skin_data) -> void:
	if skin_data == null:
		return

	var valid_ids := {}
	for animation in skin_data.animations:
		if animation != null:
			valid_ids[int(animation.id)] = animation

	skin_data.idle = _resolve_animation(skin_data.idle, valid_ids)
	skin_data.left = _resolve_animation(skin_data.left, valid_ids)
	skin_data.right = _resolve_animation(skin_data.right, valid_ids)
	skin_data.jump = _resolve_animation(skin_data.jump, valid_ids)
	skin_data.land = _resolve_animation(skin_data.land, valid_ids)

	var cleaned_hits: Array[PlayerAnimation] = []
	for animation in skin_data.hits:
		var resolved = _resolve_animation(animation, valid_ids)
		if resolved != null:
			cleaned_hits.append(resolved)
	skin_data.hits = cleaned_hits

static func _resolve_animation(animation, valid_ids: Dictionary):
	if animation == null:
		return null
	return valid_ids.get(int(animation.id))
