extends RefCounted
class_name GameplayRailState

var rail: Rail
var order: int
var node: GameRail

func _init(rail_value: Rail, order_value: int) -> void:
	rail = rail_value
	order = order_value
