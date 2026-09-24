extends RefCounted
class_name ChartIdentity

static func generate_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		push_error("Failed to generate chart UUID")
		return ""
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]
