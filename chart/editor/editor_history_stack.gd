extends RefCounted
class_name EditorHistoryStack

const MAX_STEPS := 128

var _undo: Array[EditorSnapshotValue] = []
var _redo: Array[EditorSnapshotValue] = []

func push(snapshot: EditorSnapshotValue) -> void:
	if not _undo.is_empty() and EditorHistory.same_snapshot(_undo.back(), snapshot):
		return
	_undo.append(snapshot)
	if _undo.size() > MAX_STEPS:
		_undo.remove_at(0)
	_redo.clear()

func undo(current_snapshot: EditorSnapshotValue) -> EditorSnapshotValue:
	if _undo.is_empty():
		return null
	_redo.append(current_snapshot)
	return _undo.pop_back()

func redo(current_snapshot: EditorSnapshotValue) -> EditorSnapshotValue:
	if _redo.is_empty():
		return null
	_undo.append(current_snapshot)
	return _redo.pop_back()
