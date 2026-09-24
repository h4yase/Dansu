extends Sprite2D
class_name ResultPlayerSprite

var skin : PlayerSkinData
var hit_index = 0
var current_animation : PlayerAnimation
var current_frame_index : int = 0
var animation_time : float = 0.0

func _process(delta: float) -> void:
	if not skin or not current_animation:
		return
	animation_time += delta
	if animation_time >= current_animation.total_time:
		if current_animation.return_idle:
			play_animation(skin.idle)
	if current_frame_index != current_animation.get_index(animation_time):
		current_frame_index = current_animation.get_index(animation_time)
		texture = current_animation.frames[current_frame_index]

func play_animation(anim: PlayerAnimation):
	if not anim:
		anim = get_hit_animation() 
	current_animation = anim
	animation_time= 0.0
	current_frame_index = -1

func get_hit_animation() -> PlayerAnimation:
	var size = skin.hits.size()
	if size < 1:
		return skin.idle
	if hit_index >= size:
		hit_index = 0
	var anim = skin.hits[hit_index]
	hit_index += 1
	return anim

func _apply_skin_scale() -> void:
	var scale_value := skin.scale if skin != null else 1.0
	if scale_value <= 0.0:
		scale_value = 1.0
	scale = Vector2.ONE * scale_value / 4
	print(scale)
