extends RefCounted
class_name GameInputFrame

var time: int
var simulation_target: int
var exclusive := true
var inputs: Array[ReplayInput] = []
var failed := false
var error := ""
