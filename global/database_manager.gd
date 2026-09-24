extends Node
class_name DatabaseManager

const DATABASE_PATH := "user://dansu.db"

var connection = null


func _ready() -> void:
	if not ClassDB.class_exists("DansuDB"):
		push_error("[database] DansuDB extension is unavailable")
		return
	connection = ClassDB.instantiate("DansuDB")
	if not connection.open(DATABASE_PATH):
		var open_error := str(connection.get_last_error_message())
		if open_error.contains("schema version is incompatible"):
			connection = null
			_discard_incompatible_database()
			connection = ClassDB.instantiate("DansuDB")
			if not connection.open(DATABASE_PATH):
				open_error = connection.get_last_error_message()
				push_error("[database] recreate failed: %s" % open_error)
				connection = null
				return
		else:
			push_error("[database] open failed: %s" % open_error)
			connection = null
			return
	print("[database] opened %s (schema %d, SQLite %s)" % [
		DATABASE_PATH,
		connection.get_schema_version(),
		connection.get_sqlite_version(),
	])


func _exit_tree() -> void:
	if connection != null:
		connection.close()


func _discard_incompatible_database() -> void:
	for suffix in ["", "-wal", "-shm"]:
		var path: String = DATABASE_PATH + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	push_warning("[database] discarded incompatible chart cache")
