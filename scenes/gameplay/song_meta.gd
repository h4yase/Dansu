extends Control
class_name GameplaySongMeta

@export var title_label: Label
@export var info_label: Label
@export var cover: TextureRect

var _chart: Chart

func _ready() -> void:
	_chart = CM.selected_chart
	title_label.text = _chart.title + " - " + _chart.artist
	info_label.text = _chart.difficulty + " - " + _chart.creator
	cover.texture = _chart.detail_cover_image if _chart.detail_cover_image != null else _chart.cover_image
	if cover.texture == null:
		CoverLoader.cover_loaded.connect(_on_cover_loaded)
		CoverLoader.request_cover(_chart)


func _on_cover_loaded(chart: Chart, texture: Texture2D) -> void:
	if chart != _chart:
		return
	cover.texture = chart.detail_cover_image if chart.detail_cover_image != null else texture
