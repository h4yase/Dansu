extends Button

@export var title_key := ""
@export var shortcut_key := ""
@export var tool_icon: Texture2D
@export var flip_icon := false

func _ready() -> void:
	$Key.text = shortcut_key
	$Icon.texture = tool_icon
	$Icon.flip_h = flip_icon
	$Title.text = title_key
