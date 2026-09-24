extends RefCounted
class_name UIFocusUtils

static func disable_focus_recursive(root: Node) -> void:
	if root == null:
		return
	if root is Control and not _should_preserve_focus(root as Control):
		(root as Control).focus_mode = Control.FOCUS_NONE
	for child in root.get_children():
		disable_focus_recursive(child)

static func release_text_input_focus(viewport: Viewport) -> void:
	if viewport == null:
		return
	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner is Control and _should_preserve_focus(focus_owner as Control):
		(focus_owner as Control).release_focus()

static func _should_preserve_focus(control: Control) -> bool:
	return control is LineEdit or control is SpinBox
