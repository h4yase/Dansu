extends Button

@export var shortcut_key := ""
@export var tool_icon: Texture2D
@export var flip_icon := false

func _ready() -> void:
	var title := text
	text = ""
	var key_label := Label.new()
	key_label.text = shortcut_key
	key_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	key_label.position = Vector2(6, 3)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_label.add_theme_font_size_override("font_size", 16)
	key_label.add_theme_color_override("font_color", Color(0.8, 0.75, 1.0))
	add_child(key_label)
	var image := TextureRect.new()
	image.texture = tool_icon
	image.flip_h = flip_icon
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	image.anchor_left = 0.5
	image.anchor_right = 0.5
	image.offset_left = -28.0
	image.offset_right = 28.0
	image.offset_top = 25.0
	image.offset_bottom = 57.0
	var name_label := Label.new()
	name_label.text = title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 14)
	add_child(name_label)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_left = 2.0
	name_label.offset_right = -2.0
	name_label.offset_top = -25.0
	name_label.offset_bottom = -3.0
