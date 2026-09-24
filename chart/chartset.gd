extends RefCounted
class_name ChartSet

var charts: Array[Chart] = []
var db_id: int = -1
var uuid := ""
var folder_name: String
var online_metadata: Dictionary = {}
var pack_id: String = ""

func build_uuid() -> void:
	uuid = ChartIdentity.generate_uuid()
