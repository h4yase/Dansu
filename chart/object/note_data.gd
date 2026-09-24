extends RefCounted
class_name Note
enum NoteType {NONE = 0, HIT = 1, MOVE = 2, TRACE = 3, SPIKE = 4}
enum Dir {LEFT, RIGHT, NONE = -1}

var time: int
var type: NoteType = NoteType.NONE
var dir: Dir

var length: int

var end_time: int:
	get:
		return time + maxi(length, 0)

var animation: int
var hitsound: int = -1
