extends RefCounted
class_name ServerURLs

const BASE_URL := "https://dansu.h4ya.net"
const API_PREFIX := "/api/v1"

static func api(path: String = "") -> String:
	return BASE_URL + API_PREFIX + path

static func resolve(path: String) -> String:
	if path.begins_with("/") and not path.begins_with("//") and not "\\" in path:
		return BASE_URL + path
	if path.begins_with(BASE_URL + "/") and not "\\" in path:
		return path
	return ""

static func query(values: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in values:
		if values[key] == null:
			continue
		var value := str(values[key])
		if values[key] is bool:
			value = "true" if values[key] else "false"
		parts.append(str(key).uri_encode() + "=" + value.uri_encode())
	return "&".join(parts)
