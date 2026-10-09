extends TextureRect

@export var editor: Node
var events_dirty := true
var chart_dirty := true
var viewport: SubViewport
var game: Node
var _enabled := false
var _preview_ready := false
var _worker: Thread
var _source_chart: ParsedChart
var _source_speed := 0.0
var _mesh_builds: Array[GameplayMeshBuild] = []
var _apply_index := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	viewport = $SubViewport
	texture = viewport.get_texture()
	game = $SubViewport/Gameplay
	set_preview_enabled(false)

func set_preview_enabled(enabled: bool) -> void:
	_enabled = enabled
	set_process(enabled or _worker != null)
	game.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if enabled:
		chart_dirty = true
		events_dirty = true
	else:
		_preview_ready = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED

func _process(_delta: float) -> void:
	if game == null or CM.parsed_chart == null:
		return
	if _source_chart != CM.parsed_chart or _source_speed != Config.note_speed:
		chart_dirty = true
	if _worker != null:
		if _worker.is_alive():
			return
		_worker.wait_to_finish()
		_worker = null
	if not _enabled:
		_mesh_builds.clear()
		set_process(false)
		return
	if chart_dirty:
		_start_mesh_build()
		return
	if not _preview_ready:
		var started := Time.get_ticks_usec()
		while _apply_index < _mesh_builds.size():
			_mesh_builds[_apply_index].apply()
			_apply_index += 1
			if Time.get_ticks_usec() - started >= 2000:
				return
		_mesh_builds.clear()
		game.finish_editor_preview_meshes()
		_preview_ready = true
	game.update_editor_preview(false, events_dirty)
	events_dirty = false

func _start_mesh_build() -> void:
	chart_dirty = false
	_preview_ready = false
	_source_chart = CM.parsed_chart
	_source_speed = Config.note_speed
	_mesh_builds = game.prepare_editor_preview_meshes()
	_apply_index = 0
	events_dirty = true
	_worker = Thread.new()
	var builds := _mesh_builds
	var error := _worker.start(func(): GameplayMeshBuild.build_all(builds))
	if error != OK:
		_worker = null
		GameplayMeshBuild.build_all(builds)

func _exit_tree() -> void:
	if _worker != null and _worker.is_started():
		_worker.wait_to_finish()
