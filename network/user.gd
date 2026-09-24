
# TODO: REPLACE Dict

extends RefCounted
class_name User

var steam_name: String
var username: String
var user_id: int
var steam_id: String
var avatar_url: String
var sr_total: float
var global_rank: int
var groups: int


func _init(data: Dictionary) -> void:
	username = data.get("username", "")
	steam_id = data.get("steam_id", "")
	avatar_url = data.get("avatar_url", "")
	sr_total = data.get("sr_total", 0.0)
	global_rank = data.get("global_rank", 0)
	groups = data.get("groups",1)
