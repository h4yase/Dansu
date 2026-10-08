extends RefCounted
class_name GameplayMeshBuild

var rail: Rail
var geometry: Rail
var note: Note
var note_time := 0
var note_length := 0
var note_speed := 0.0
var body_width := 0.0
var owner_transform := Transform3D.IDENTITY
var arrays: Array = []

func build_arrays() -> void:
	if note == null:
		var path := GameRail._sample_curve_points_for_rail(geometry, note_speed)
		arrays = GameRail.build_ribbon_arrays(path, GameRail.DEFAULT_WIDTH + GameRail.DEFAULT_OUTLINE_SIZE * 2.0)
	else:
		var path := GameplayLongNoteVisual.sample_note_path(geometry, note_time, note_length, owner_transform.affine_inverse(), note_speed)
		arrays = GameRail.build_open_ribbon_arrays(path, body_width)

func apply() -> void:
	var mesh := GameRail.mesh_from_arrays(arrays)
	if note == null:
		GameRail.cache_built_mesh(self, mesh)
	else:
		GameplayLongNoteVisual.cache_built_mesh(self, mesh)

static func build_all(builds: Array[GameplayMeshBuild]) -> void:
	for build in builds:
		build.build_arrays()
