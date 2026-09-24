extends RefCounted
class_name ReplayInput

enum InputType {
	NONE = 0,
	HIT1_DOWN = 1,
	HIT1_UP = -1,
	HIT2_DOWN = 2,
	HIT2_UP = -2,
	MOVELEFT_DOWN = 3,
	MOVELEFT_UP = -3,
	MOVERIGHT_DOWN = 4,
	MOVERIGHT_UP = -4,
}
var timing: int
var type: InputType
var order := -1


func _init(timing_value: int = 0, type_value: InputType = InputType.NONE) -> void:
	timing = timing_value
	type = type_value


static func is_valid_type(value: int) -> bool:
	return value in [-4, -3, -2, -1, 1, 2, 3, 4]
