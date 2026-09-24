extends TextureRect

@export var editor: Node
var events_dirty := true
var chart_dirty := true
var viewport: SubViewport
var game: Node

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	viewport = $SubViewport
	texture = viewport.get_texture()
	game = $SubViewport/Gameplay
	set_preview_enabled(false)

func set_preview_enabled(enabled: bool) -> void:
	set_process(enabled)
	game.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if enabled:
		chart_dirty = true
		events_dirty = true
		_process(0.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED

func _process(_delta: float) -> void:
	if game == null or CM.parsed_chart == null:
		return
	game.update_editor_preview(chart_dirty, events_dirty)
	chart_dirty = false
	events_dirty = false
