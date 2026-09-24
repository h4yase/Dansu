extends RefCounted
class_name OnlineChartMapper

static func from_metadata(data: Dictionary) -> ChartSet:
	if not data.get("charts") is Array or not data.get("chartset_uuid") is String:
		return null
	var chartset := ChartSet.new()
	chartset.uuid = data.chartset_uuid
	chartset.online_metadata = data.duplicate(true)
	for entry in data.charts:
		if not entry is Dictionary or not entry.get("chart_uuid") is String:
			return null
		var chart := Chart.new()
		chart.chart_set = chartset
		chart.uuid = entry.chart_uuid
		chart.online_metadata = entry.duplicate(true)
		chart.title = str(entry.get("title", ""))
		chart.artist = str(entry.get("artist", ""))
		chart.creator = str(entry.get("creator_display") if entry.get("creator_display") != null else "")
		chart.source = str(entry.get("source", ""))
		chart.tags = str(entry.get("tags", ""))
		chart.difficulty = str(entry.get("difficulty_name", ""))
		chart.rating = float(entry.get("rating", 0))
		chart.play_time_ms = int(entry.get("play_time_ms", 0))
		chart.preview_time = float(entry.get("preview_time_ms", 0))
		chart.build_search_string()
		chartset.charts.append(chart)
	return chartset if not chartset.charts.is_empty() else null

static func primary(chartset: ChartSet) -> Chart:
	for chart in chartset.charts:
		if chart.online_metadata.get("id") == chartset.online_metadata.get("primary_chart_id"):
			return chart
	return chartset.charts[0] if not chartset.charts.is_empty() else null
