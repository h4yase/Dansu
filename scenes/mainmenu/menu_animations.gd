extends Node
class_name MainMenuAnimations

@export var menu_buttons_animation: AnimationPlayer
@export var loading_animation: AnimationPlayer
@export var character_animation: AnimationPlayer
@export var logo_animation: AnimationPlayer
@export var charts_animation: AnimationPlayer
@export var search_animation: AnimationPlayer
@export var bottom_buttons_animation: AnimationPlayer
@export var song_info_animation: AnimationPlayer
@export var loading_start_animation: AnimationPlayer

func start_loading() -> void:
	loading_start_animation.play("fade")

func loading_done() -> void:
	menu_buttons_animation.play("fade")
	loading_animation.play("fade")
	character_animation.play("to_side")
	logo_animation.play("fade")

func clean_menu_things() -> void:
	menu_buttons_animation.play("fade",-1,-2,true)
	logo_animation.play("fade",-1,-2,true)
	character_animation.play("out")

func call_menu_things() -> void:
	menu_buttons_animation.play("fade")
	logo_animation.play("fade")
	character_animation.play("out",-1,-1,true)

func song_select_scene() -> void:
	charts_animation.play("fade")
	search_animation.play("fade")
	bottom_buttons_animation.play("fade")
	song_info_animation.play("fade")

func main_menu() -> void:
	charts_animation.play("fade",-1,-2,true)
	search_animation.play("fade",-1,-2,true)
	song_info_animation.play("fade",-1,-4,true)
	bottom_buttons_animation.play_backwards("fade")

func replay_charts() -> void:
	charts_animation.stop()
	charts_animation.play("fade")
	charts_animation.advance(0.0)
