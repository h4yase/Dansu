extends MeshInstance3D
@export var player : Node

func _process(_delta: float) -> void:
	position.x = player.position.x
