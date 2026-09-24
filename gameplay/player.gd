extends Node3D
class_name Player

@export var sprite: PlayerSprite
@export var hit_star_effect_scene: PackedScene
@export var hit_star_offset := Vector3(0.0, 0.06, 0.03)

var standing_rail: Rail = null
var _is_moving := false

func _ready() -> void:
	_setup_skin()

func _setup_skin() -> void:
	var skin := PlayerSkinResolver.load_active()
	if skin == null:
		return
	sprite.skin = skin
	sprite._setup()

func _process(delta: float) -> void:
	if standing_rail == null:
		return
	var target_x := GameplayPlayfield.normalized_x_to_world(
		standing_rail._get_rail_x_at_time(int(Game.current_time))
	)
	if _is_moving:
		position.x = lerp(position.x, target_x, delta * 18.0)
		if abs(position.x - target_x) < 0.01:
			_is_moving = false
			if sprite.skin and not sprite.hold_last_frame and _should_return_to_idle_after_move():
				sprite.play_animation(sprite.skin.idle)
	else:
		position.x = target_x

func move_to_rail(rail: Rail, play_direction_animation: bool = true) -> void:
	if rail == standing_rail:
		return
	var prev_x := position.x
	standing_rail = rail
	_is_moving = true

	if sprite.skin and play_direction_animation and not sprite.hold_last_frame:
		var target_x := GameplayPlayfield.normalized_x_to_world(
			rail._get_rail_x_at_time(int(Game.current_time))
		)
		var move_animation := sprite.skin.left if target_x < prev_x else sprite.skin.right
		if move_animation != null:
			sprite.play_animation(move_animation)

func play_hit_animation(note: Note = null) -> void:
	if not sprite.skin or (sprite.hold_last_frame and note == null):
		return

	var custom_animation: PlayerAnimation = null
	if note != null and int(note.animation) != 0:
		custom_animation = sprite.skin.get_animation_via_id(int(note.animation))

	if custom_animation != null:
		sprite.play_animation(custom_animation)
		return

	sprite.play_animation(sprite.get_hit_animation())


func spawn_hit_stars() -> void:
	if hit_star_effect_scene == null:
		return
	var effect := hit_star_effect_scene.instantiate() as Node3D
	var scene_root := get_tree().current_scene
	if effect == null or scene_root == null:
		return
	scene_root.add_child(effect)
	effect.global_position = global_position + hit_star_offset

func play_move_note_animation(note: Note, dir: Note.Dir = Note.Dir.NONE) -> void:
	if not sprite.skin or (sprite.hold_last_frame and note == null):
		return

	var custom_animation: PlayerAnimation = null
	if note != null and int(note.animation) != 0:
		custom_animation = sprite.skin.get_animation_via_id(int(note.animation))

	if custom_animation != null:
		sprite.play_animation(custom_animation)
		return

	var default_animation := sprite.get_hit_animation()
	if default_animation != null:
		sprite.play_animation(default_animation)
		return

	if dir == Note.Dir.LEFT and sprite.skin.left != null:
		sprite.play_animation(sprite.skin.left)
	elif dir == Note.Dir.RIGHT and sprite.skin.right != null:
		sprite.play_animation(sprite.skin.right)

func set_hold_animation(active: bool) -> void:
	if sprite == null:
		return
	var was_holding := sprite.hold_last_frame
	sprite.hold_last_frame = active
	if was_holding and not active and sprite.skin != null:
		sprite.play_animation(sprite.skin.idle, false)

func _should_return_to_idle_after_move() -> bool:
	if not sprite.skin:
		return false
	return (
		(sprite.skin.left != null and sprite.is_playing_animation(sprite.skin.left)) or
		(sprite.skin.right != null and sprite.is_playing_animation(sprite.skin.right))
	)

func reset() -> void:
	standing_rail = null
	_is_moving = false
	position = Vector3.ZERO
	_setup_skin()
