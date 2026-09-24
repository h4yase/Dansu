extends RefCounted
class_name PlayerSkinResolver

static func load_active() -> PlayerSkinData:
	var chart: Chart = CM.selected_chart
	var skin := PlayerSkinData.new()
	if _load_chart_skin(skin, chart):
		return skin
	if _load_custom_skin(skin):
		return skin
	return skin if skin.parse_objects(PlayerSkinData.TYPE.BUILT_IN, "danshe", "skin.json") else null

static func _load_chart_skin(skin: PlayerSkinData, chart: Chart) -> bool:
	if Config.ignore_chart_skin or chart == null or chart.file_skin.is_empty():
		return false
	var path := SkinSerialization.ensure_chart_skin_path(chart)
	return not path.is_empty() and skin.parse_objects(PlayerSkinData.TYPE.IN_CHART, "", path.get_file())

static func _load_custom_skin(skin: PlayerSkinData) -> bool:
	if Config.custom_skin_path.is_empty():
		return false
	var path := SkinSerialization.get_custom_skin_file_path()
	return skin.parse_objects(PlayerSkinData.TYPE.IN_SKIN_FOLDER, path.get_base_dir().get_file(), path.get_file())
