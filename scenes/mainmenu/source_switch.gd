extends Button
class_name SourceSwitch

signal tab_changed(tab: int)

const SLIDE_DURATION := 0.22
const TITLES := ["Official", "Community"]
const ICONS := [preload("res://resources/icons/checkbox-checked.svg"), preload("res://resources/icons/map.svg")]
const ICON_SIZE := 24.0
const ICON_GAP := 8.0
const SIDE_PADDING := 16.0

@export_range(0, 1) var current_tab := 0:
	set(value):
		var next := clampi(value, 0, 1)
		if current_tab == next:
			return
		current_tab = next
		_preview_consumed = _hovered
		if is_node_ready():
			_update_available()
			_slide_to(float(current_tab))
			tab_changed.emit(current_tab)

var _tab_disabled := [false, false]
var _hovered := false
var _preview_consumed := false
var _position := 0.0
var _slide: Tween
var _press: Tween
var _labels: Array[Label] = []
var _icons: Array[TextureRect] = []
var _clip: Control


func _ready() -> void:
	text = ""
	icon = null
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_clip = Control.new()
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_contents = true
	add_child(_clip)
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clip.offset_left = SIDE_PADDING
	_clip.offset_right = -SIDE_PADDING
	var content_width := 0.0
	for index in range(TITLES.size()):
		var label := Label.new()
		label.text = TITLES[index]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", get_theme_font("font"))
		label.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
		label.add_theme_color_override("font_color", Color.WHITE)
		_clip.add_child(label)
		_labels.append(label)
		var source_icon := TextureRect.new()
		source_icon.texture = ICONS[index]
		source_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		source_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		source_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		source_icon.size = Vector2.ONE * ICON_SIZE
		_clip.add_child(source_icon)
		_icons.append(source_icon)
		content_width = maxf(content_width, label.get_combined_minimum_size().x + ICON_SIZE + ICON_GAP)
	custom_minimum_size.x = ceilf(content_width + SIDE_PADDING * 2.0)
	resized.connect(_layout_labels)
	_clip.resized.connect(_layout_labels)
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	pressed.connect(_commit)
	visibility_changed.connect(_reset_preview)
	_position = float(current_tab)
	_update_available()
	_layout_labels()


func set_tab_disabled(tab: int, unavailable: bool) -> void:
	if tab < 0 or tab > 1:
		return
	_tab_disabled[tab] = unavailable
	if is_node_ready():
		_update_available()
		if disabled:
			_slide_to(float(current_tab))


func _update_available() -> void:
	disabled = _tab_disabled[1 - current_tab]


func _layout_labels() -> void:
	pivot_offset = size * 0.5
	for index in range(_labels.size()):
		var label_width := _labels[index].get_combined_minimum_size().x
		var group_width := ICON_SIZE + ICON_GAP + label_width
		var start_x := (_clip.size.x - group_width) * 0.5 + (float(index) - _position) * _clip.size.x
		_icons[index].position = Vector2(start_x, (_clip.size.y - ICON_SIZE) * 0.5)
		_labels[index].size = Vector2(label_width, _clip.size.y)
		_labels[index].position = Vector2(start_x + ICON_SIZE + ICON_GAP, 0.0)


func _set_slide_position(value: float) -> void:
	_position = value
	_layout_labels()


func _slide_to(target: float) -> void:
	if _slide:
		_slide.kill()
	_slide = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide.tween_method(_set_slide_position, _position, target, SLIDE_DURATION)


func _on_enter() -> void:
	_hovered = true
	if not disabled and not _preview_consumed:
		_slide_to(float(1 - current_tab))


func _on_exit() -> void:
	_hovered = false
	_preview_consumed = false
	_slide_to(float(current_tab))
	_on_up()


func _on_down() -> void:
	if disabled:
		return
	if _press:
		_press.kill()
	_press = create_tween()
	_press.tween_property(self, "scale", Vector2.ONE * 0.975, 0.06)


func _on_up() -> void:
	if _press:
		_press.kill()
	_press = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_press.tween_property(self, "scale", Vector2.ONE, 0.18)


func _commit() -> void:
	if disabled:
		return
	current_tab = 1 - current_tab
	# Keep the confirmed title visible until the pointer leaves the button.
	_preview_consumed = _hovered
	scale = Vector2.ONE * 0.975
	_on_up()


func _reset_preview() -> void:
	if not is_visible_in_tree():
		_hovered = false
		_preview_consumed = false
		if _slide:
			_slide.kill()
		if _press:
			_press.kill()
		scale = Vector2.ONE
		_set_slide_position(float(current_tab))
