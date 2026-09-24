extends RefCounted
class_name Timing

var time: int = 0
var _bpm: float = 1.0
var bpm: float:
	get:
		return _bpm
	set(value):
		if value <= 0:
			_bpm = 1
		else:
			_bpm = value
