extends Node3D
class_name GameNote

const VISUAL_SURFACE_OFFSET := 0.025
const VISUAL_RENDER_PRIORITY := 1

var move_texture : Texture2D = preload("res://resources/textures/gameplay/move_note.png")
var spike_texture : Texture2D = preload("res://resources/textures/gameplay/spike_note.png")
var trace_texture : Texture2D = preload("res://resources/textures/gameplay/trace_note.png")

@export var note_sprite: Sprite3D
@export var note_shadow: Sprite3D
@export var break_effect_scene: PackedScene
@export var long_note_visual: GameplayLongNoteVisual

signal consumed(judge: int, note_node: GameNote)

var note: Note
var rail: Rail
var is_consumed := false
var waiting_for_long_release := false
var _note_base_modulate := Color.WHITE
var _note_shadow_base_modulate := Color.WHITE
var _spawn_fade_active := false
var _failed_long_note := false

func _ready() -> void:
	set_process(false)
	if note == null or rail == null:
		return
	position.x = GameplayPlayfield.normalized_x_to_world(rail._get_rail_x_at_time(note.time))
	position.y = VISUAL_SURFACE_OFFSET
	position.z = GameplayPlayfield.local_z_from_start(rail.start_time, note.time)
	_configure_sprite_depth(note_sprite)
	_set_note_texture()
	_cache_base_modulates()
	_setup_long_note_visual()
	_initialize_spawn_fade()


func _configure_sprite_depth(sprite: Sprite3D) -> void:
	if sprite == null:
		return
	sprite.no_depth_test = true
	sprite.render_priority = VISUAL_RENDER_PRIORITY

func _cache_base_modulates() -> void:
	if note_sprite != null:
		_note_base_modulate = note_sprite.modulate
	if note_shadow != null:
		_note_shadow_base_modulate = note_shadow.modulate


func _setup_long_note_visual() -> void:
	if long_note_visual == null:
		return
	long_note_visual.configure(note, rail, self, note_sprite)


func prebake_long_note_visual(note_data: Note, rail_data: Rail) -> void:
	note = note_data
	rail = rail_data
	if note == null or rail == null:
		return
	position.x = GameplayPlayfield.normalized_x_to_world(rail._get_rail_x_at_time(note.time))
	position.y = VISUAL_SURFACE_OFFSET
	position.z = GameplayPlayfield.local_z_from_start(rail.start_time, note.time)
	_set_note_texture()
	if long_note_visual != null:
		long_note_visual.prebake(note, rail, self, note_sprite)

func _set_note_texture() -> void:
	note_sprite.flip_h = false
	match note.type:
		Note.NoteType.NONE:
			visible = false
		Note.NoteType.HIT:
			#note_sprite.modulate = Color(0.697, 0.925, 0.998, 1.0)
			pass
		Note.NoteType.MOVE:
			note_sprite.texture = move_texture
			note_shadow.texture = move_texture
			# note_sprite.modulate = Color(0.84, 0.496, 1.0, 1.0)
			match note.dir:
				Note.Dir.LEFT:
					note_shadow.flip_h = true
				Note.Dir.RIGHT:
					note_sprite.flip_h = true
		Note.NoteType.TRACE:
			note_sprite.texture = trace_texture
			note_shadow.texture = trace_texture
		Note.NoteType.SPIKE:
			note_sprite.texture = spike_texture
			note_shadow.texture = spike_texture
	if note_sprite.texture != null:
		note_sprite.offset.y = note_sprite.texture.get_size().y / 2
		note_shadow.offset.y = note_shadow.texture.get_size().y / 2


func _initialize_spawn_fade() -> void:
	if not visible or note_sprite == null:
		return
	_spawn_fade_active = true
	_set_visual_alpha(0.0)
	set_process(true)
	_update_spawn_fade()


func _update_spawn_fade() -> void:
	if not _spawn_fade_active or note == null:
		return
	var fade_alpha := GameplayPlayfield.get_spawn_fade_alpha(note.time, Game.current_time)
	_set_visual_alpha(fade_alpha)
	if fade_alpha >= 1.0:
		_spawn_fade_active = false
		set_process(_failed_long_note)


func _set_visual_alpha(alpha: float) -> void:
	if note_sprite != null:
		note_sprite.modulate = Color(_note_base_modulate.r, _note_base_modulate.g, _note_base_modulate.b, _note_base_modulate.a * alpha)
	if note_shadow != null:
		note_shadow.modulate = Color(
			_note_shadow_base_modulate.r,
			_note_shadow_base_modulate.g,
			_note_shadow_base_modulate.b,
			_note_shadow_base_modulate.a * alpha
		)

func consume(judge: int) -> void:
	if is_consumed:
		return

	is_consumed = true
	if judge != Score.MISS and judge != Score.NONE:
		_spawn_break_effect()

	if _is_long_note() and judge == Score.MISS:
		_fail_long_note()
		consumed.emit(judge, self)
		return

	if _is_long_note() and judge != Score.MISS and judge != Score.NONE:
		waiting_for_long_release = true
		note_sprite.visible = false
		note_shadow.visible = false
		long_note_visual.set_holding(true)
		consumed.emit(judge, self)
		return

	consumed.emit(judge, self)
	queue_free()


func finish_long_note(judge: int) -> void:
	if not waiting_for_long_release:
		return
	waiting_for_long_release = false
	if judge == Score.MISS:
		_fail_long_note()
		return
	if long_note_visual != null:
		long_note_visual.set_holding(false)
		if judge != Score.MISS and judge != Score.NONE:
			_spawn_break_effect_for_sprite(long_note_visual.get_tail_cap())
	queue_free()


func _fail_long_note() -> void:
	if _failed_long_note:
		return
	_failed_long_note = true
	var brightness := GameplayLongNoteVisual.FAILED_BRIGHTNESS
	_note_base_modulate = Color(_note_base_modulate.r * brightness, _note_base_modulate.g * brightness, _note_base_modulate.b * brightness, _note_base_modulate.a)
	_note_shadow_base_modulate = Color(_note_shadow_base_modulate.r * brightness, _note_shadow_base_modulate.g * brightness, _note_shadow_base_modulate.b * brightness, _note_shadow_base_modulate.a)
	_set_visual_alpha(GameplayPlayfield.get_spawn_fade_alpha(note.time, Game.current_time))
	if long_note_visual != null:
		long_note_visual.set_failed()
	set_process(true)


func _is_long_note() -> bool:
	return (
		note != null
		and note.length > 0
		and (note.type == Note.NoteType.HIT or note.type == Note.NoteType.MOVE)
	)


func _spawn_break_effect() -> void:
	_spawn_break_effect_for_sprite(note_sprite)


func _spawn_break_effect_for_sprite(sprite: Sprite3D) -> void:
	if break_effect_scene == null or sprite == null or sprite.texture == null:
		return
	var effect := break_effect_scene.instantiate() as GameplayNoteBreakEffect
	var scene_root := get_tree().current_scene
	if effect == null or scene_root == null:
		return

	scene_root.add_child(effect)
	var effect_transform := sprite.global_transform
	var offset := Vector3(sprite.offset.x, sprite.offset.y, 0.0) * sprite.pixel_size
	effect_transform.origin = sprite.to_global(offset)
	effect.global_transform = effect_transform
	effect.play(
		sprite.texture,
		sprite.modulate,
		sprite.flip_h,
		sprite.pixel_size,
		Config.note_speed
	)

func _process(_delta) -> void:
	_update_spawn_fade()
	if _failed_long_note and Game.current_time > note.end_time + Score.T.BAD:
		queue_free()
