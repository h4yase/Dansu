extends Sprite3D
class_name GameplayJudgePopup

const JUST_TEXTURE := preload("res://resources/textures/judges/just.png")
const GOOD_TEXTURE := preload("res://resources/textures/judges/good.png")
const OK_TEXTURE := preload("res://resources/textures/judges/ok.png")
const BAD_TEXTURE := preload("res://resources/textures/judges/nah.png")
const MISS_TEXTURE := preload("res://resources/textures/judges/miss.png")
const JUST_PLUS_TEXTURE := preload("res://resources/textures/judges/just_plus.png")

const HOLD_DURATION := 0.2
const FADE_DURATION := 0.1
const RISE_SPEED := 1.0

var judgement := Score.NONE
var _hold_remaining := HOLD_DURATION
var _fade_remaining := FADE_DURATION


func _ready() -> void:
	_apply_texture()


func _process(delta: float) -> void:
	if _hold_remaining > 0.0:
		_hold_remaining -= delta
		position.y += RISE_SPEED * delta * 0.5
		return

	if _fade_remaining > 0.0:
		position.y += RISE_SPEED * delta
		_fade_remaining -= delta
		modulate.a = maxf(_fade_remaining / FADE_DURATION, 0.0)
		return

	queue_free()


func _apply_texture() -> void:
	match judgement:
		Score.MISS:
			texture = MISS_TEXTURE
		Score.PERFECT:
			texture = JUST_TEXTURE
		Score.GREAT:
			texture = GOOD_TEXTURE
		Score.OK:
			texture = OK_TEXTURE
		Score.BAD:
			texture = BAD_TEXTURE
		Score.PERFECT_PLUS:
			texture = JUST_PLUS_TEXTURE
		_:
			texture = null
