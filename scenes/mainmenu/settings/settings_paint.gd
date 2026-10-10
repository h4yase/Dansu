extends RefCounted
class_name SettingsPaint

const FONT := preload("res://resources/fonts/thin/BebasNeue-Regular.ttf")
const TITLE_FONT := preload("res://resources/fonts/bold/Next Bravo.ttf")
const ROW_FONT_SIZE := 18
# Colors from the main menu and editor UI theme.
const INK := Color.WHITE
const MUTED := Color("dfdfdf")
const ACCENT := Color("705bde")
const SURFACE := Color("1e1c30")
const INPUT := Color("1e1c3073")
const HOVER := Color("262433")
const BORDER := Color("564d8d")
const FIELD_BORDER := Color("564d8d59")
const TRACK := Color("1e1f30")
const SELECTED := Color("5b4bb0")
const OVERLAY := Color("05050a")

static func text(canvas: Control, caption: String, rect: Rect2, font_size: int = 20, color: Color = INK, centered: bool = false, font: Font = FONT) -> void:
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	while width > rect.size.x and font_size > 12:
		font_size -= 1
		width = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := rect.position.x + (rect.size.x - width) * 0.5 if centered else rect.position.x
	var y := rect.get_center().y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	canvas.draw_string(font, Vector2(x, y), caption, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, font_size, color)

static func box(canvas: Control, rect: Rect2, color: Color, border: Color = Color.TRANSPARENT, radius: int = 14) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	canvas.draw_style_box(style, rect)
