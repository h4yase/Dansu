extends Sprite3D
class_name PlayerSprite

@export var effectplayer : AnimationPlayer

var skin : PlayerSkinData = PlayerSkinData.new()
var hit_index = 0 # 다음에 재생할 기본 노트 히트 애니메이션
var _animation : PlayerAnimation # 현재 재생중인 애니메이션
var _frame_index : int = 0 # 현재 재생중인 프레임 인덱스
var _animation_time : float = 0.0 # 재생중인 애니메이션이 지난 시간
var hold_last_frame := false

func _setup() -> void:
	hold_last_frame = false
	if not skin:
		return
	_apply_skin_scale()
	play_animation(skin.idle,true)
	
func _process(delta: float) -> void:
	if not skin or not _animation:
		return
	_animation_time += delta
	if _animation_time >= _animation.total_time:
		if _animation.return_idle and not hold_last_frame:
			play_animation(skin.idle)
	if _frame_index != _animation.get_index(_animation_time):
		_frame_index = _animation.get_index(_animation_time)
		texture = _animation.frames[_frame_index]
		offset = Vector2(0,texture.get_size().y / 2)

func get_hit_animation() -> PlayerAnimation:
	var size = skin.hits.size()
	if size < 1:
		return skin.idle
	if hit_index >= size:
		hit_index = 0
	var anim = skin.hits[hit_index]
	hit_index += 1
	return anim

func is_playing_animation(anim: PlayerAnimation) -> bool:
	return _animation == anim

func play_animation(anim: PlayerAnimation,play_effect:bool = true):
	if not anim:
		anim = get_hit_animation() 
	_animation = anim
	_animation_time= 0.0
	_frame_index = -1
	if play_effect and anim.effect != "none":
		effectplayer.play(anim.effect)
		effectplayer.seek(0,true,false)

func _apply_skin_scale() -> void:
	var scale_value := skin.scale if skin != null else 1.0
	if scale_value <= 0.0:
		scale_value = 1.0
	var parent_node := get_parent_node_3d()
	if parent_node != null:
		parent_node.scale = Vector3.ONE * scale_value
	scale = Vector3.ONE
