extends RefCounted
class_name EditorSnapshotValue

## Value representation used by history and dirty-state comparisons.
func comparison_values() -> Array:
	return []

static func array_values(items: Array) -> Array:
	var result: Array = []
	for item: EditorSnapshotValue in items:
		result.append(item.comparison_values())
	return result
