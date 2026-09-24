extends RefCounted
class_name SongListItem

enum ItemType {
	CHARTSET,
	CHART,
}

var type: ItemType = ItemType.CHARTSET
var chartset: ChartSet = null
var charts: Array[Chart] = []
var primary_chart: Chart = null
