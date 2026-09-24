extends Camera3D

@export var player : Node3D

var follow_character := true
var target_position := Vector2.ZERO
var target_zoom := 1.0
var _base_position := Vector3.ZERO
var _base_fov := 75.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_base_position = position
	_base_fov = fov


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var desired_x := _base_position.x + target_position.x
	if follow_character and player != null:
		desired_x += player.position.x
	position.x = lerp(position.x, desired_x, delta * 20.0)
	position.y = lerp(position.y, _base_position.y + target_position.y, delta * 20.0)
	fov = lerp(fov, _base_fov / maxf(target_zoom, 0.01), delta * 10.0)
