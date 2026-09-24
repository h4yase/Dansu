extends RefCounted
class_name GameplayNoteState

var note: Note
var rail_state: GameplayRailState
var order: int
var node: GameNote

var processed := false
var judgement := Score.NONE
var release_processed := false
var release_judgement := Score.NONE

func _init(note_value: Note, rail_state_value: GameplayRailState, order_value: int) -> void:
	note = note_value
	rail_state = rail_state_value
	order = order_value
