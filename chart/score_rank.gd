extends RefCounted
class_name ScoreRank

const MAX_SCORE := 101.0
const DATA := [
	{"label": "D", "min": 0.0, "color": Color("e8e6e8ff")},
	{"label": "C", "min": 70.0, "color": Color("ebf6feff")},
	{"label": "B", "min": 85.0, "color": Color("d35f71")},
	{"label": "A", "min": 90.0, "color": Color("c6fba6")},
	{"label": "S", "min": 95.0, "color": Color("f6ecbe")},
	{"label": "S+", "min": 99.0, "color": Color("f9deb2")},
	{"label": "SS", "min": 100.0, "color": Color("e9a4e4")},
	{"label": "X", "min": 101.0, "color": Color("91c5e4ff")},
]

static func index_for_score(value: float) -> int:
	var result := 0
	for index in range(DATA.size()):
		if value >= minimum(index):
			result = index
	return result

static func label_for_score(value: float) -> String:
	return label(index_for_score(value))

static func color_for_score(value: float) -> Color:
	return color(index_for_score(value))

static func label(index: int) -> String:
	return str(DATA[clampi(index, 0, DATA.size() - 1)]["label"])

static func color(index: int) -> Color:
	return DATA[clampi(index, 0, DATA.size() - 1)]["color"] as Color

static func minimum(index: int) -> float:
	return float(DATA[clampi(index, 0, DATA.size() - 1)]["min"])

static func maximum(index: int) -> float:
	return minimum(index + 1) if index + 1 < DATA.size() else MAX_SCORE
