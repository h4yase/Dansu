extends Node3D


func _on_particles_finished() -> void:
	queue_free()
