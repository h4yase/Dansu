@tool
extends Texture2D
class_name ResizableTexture2D

@export var source: Texture2D:
	set(value):
		source = value
		emit_changed()

@export_range(1, 512, 1)
var display_height := 32:
	set(value):
		display_height = maxi(value, 1)
		emit_changed()

func _get_width() -> int:
	if source == null or source.get_height() <= 0:
		return display_height

	return roundi(
		float(source.get_width()) /
		float(source.get_height()) *
		display_height
	)

func _get_height() -> int:
	return display_height

func _has_alpha() -> bool:
	return source != null and source.has_alpha()

func _draw(
	canvas_item: RID,
	position: Vector2,
	modulate: Color,
	transpose: bool
) -> void:
	if source == null:
		return

	source.draw_rect(
		canvas_item,
		Rect2(position, Vector2(_get_width(), _get_height())),
		false,
		modulate,
		transpose
	)

func _draw_rect(
	canvas_item: RID,
	rect: Rect2,
	tile: bool,
	modulate: Color,
	transpose: bool
) -> void:
	if source != null:
		source.draw_rect(canvas_item, rect, tile, modulate, transpose)
