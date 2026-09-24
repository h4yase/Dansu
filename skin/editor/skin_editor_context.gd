extends RefCounted
class_name SkinEditorContext

enum OpenMode { CUSTOM, CHART }
enum ReturnTarget { MENU, EDITOR }
enum DragKind { NONE, SPRITE, FRAME }

var open_mode: OpenMode = OpenMode.CUSTOM
var return_target: ReturnTarget = ReturnTarget.MENU
var skin_file_path := ""
var chart_folder_path := ""
var referenced_skin_file_name := ""
var previous_custom_skin_path := ""

var selected_animation_index := -1
var selected_frame_index := -1
var selected_sprite_file_name := ""

var drag_kind: DragKind = DragKind.NONE
var drag_sprite_file_name := ""
var drag_frame_index := -1
var drag_reorder_target_index := -1

func clear_drag() -> void:
	drag_kind = DragKind.NONE
	drag_sprite_file_name = ""
	drag_frame_index = -1
	drag_reorder_target_index = -1
