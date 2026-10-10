extends Control
class_name SettingsSection

var caption := ""
var icon: Texture2D
var content_height := 76.0
var _rows: Array[Control] = []
var _dials: Array[SettingsDial] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(_layout)
	_layout()

func add_row(row: Control, height: float = 78.0) -> void:
	row.position = Vector2(0, content_height)
	row.size = Vector2(size.x, height)
	content_height += height
	_rows.append(row)
	add_child(row)

func add_dials(master: SettingsDial, music: SettingsDial, sfx: SettingsDial) -> void:
	_dials.assign([master, music, sfx])
	for dial in _dials:
		add_child(dial)
	content_height += 436.0
	_layout()

func _layout() -> void:
	for row in _rows:
		row.size.x = size.x
	if not _dials.is_empty():
		_dials[0].position = Vector2((size.x - 300) * 0.5, 64)
		_dials[0].size = Vector2(300, 250)
		for i in range(1, _dials.size()):
			_dials[i].position = Vector2((i - 1) * size.x / 2.0, 314)
			_dials[i].size = Vector2(size.x / 2.0, 190)
	queue_redraw()

func _draw() -> void:
	if icon != null:
		draw_texture_rect(icon, Rect2(0, 18, 28, 28), false, SettingsPaint.ACCENT)
	SettingsPaint.text(self, caption, Rect2(40, 4, size.x - 44, 52), 28)
	draw_line(Vector2(0, 64), Vector2(size.x, 64), SettingsPaint.BORDER, 1.0)
