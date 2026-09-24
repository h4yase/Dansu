extends ChartEventFrame
class_name ThemeEventFrame

var bg_color: Color = Color.BLACK
var bg_color_2: Color = Color.BLACK
var rail_color: Color = Color.WHITE

func clone() -> ChartEventFrame:
	var result := ThemeEventFrame.new()
	result.time = time
	result.ease = ease
	result.bg_color = bg_color
	result.bg_color_2 = bg_color_2
	result.rail_color = rail_color
	return result
