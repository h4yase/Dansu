extends Control
class_name InlineLeaderboardRow

signal action_pressed(action: String, item: Dictionary)

const BODY_FONT := preload("res://resources/fonts/BebasNeue-Regular.ttf")
const RANK_FONT := preload("res://resources/fonts/Next Bravo.ttf")
const PLACEHOLDER := preload("res://icon.svg")

static var _avatar_cache: Dictionary = {}

var _content: HBoxContainer
var _grade: Label
var _place: Label
var _name_label: Label
var _accuracy: Label
var _combo: Label
var _avatar: TextureRect
var _avatar_request: HTTPRequest

var _actions: HBoxContainer
var _appear: Tween
var _hover: Tween
var _actions_hide_tween: Tween

var _hovered := false
var _item: Dictionary = {}
var _replay_button: Button
var _detail_button: Button
var _detail_clip: Control
var _detail_status: Label
var _judgements: HBoxContainer
var _detail_tween: Tween
var _detail_request: HTTPRequest
var _detail_data: Dictionary = {}
var _detail_open := false
var _detail_appear: Tween
const JUDGEMENTS := [
	["JUST+", "perfect_plus_count"], ["JUST", "perfect_count"],
	["GOOD", "great_count"], ["OK", "ok_count"],
	["NAH", "bad_count"], ["MISS", "miss_count"],
]


func _ready() -> void:
	custom_minimum_size = Vector2(0, 82)
	mouse_filter = Control.MOUSE_FILTER_PASS
	offset_transform_enabled = true

	_content = HBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.offset_transform_enabled = true
	_content.offset_transform_pivot_ratio = Vector2(0.0, 0.5)
	_content.add_theme_constant_override("separation", 16)
	add_child(_content)

	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.anchor_bottom = 0.0
	_content.offset_bottom = 82.0
	_content.offset_left = 12
	_content.offset_right = -20

	var rank_column := VBoxContainer.new()
	rank_column.custom_minimum_size.x = 86
	rank_column.alignment = BoxContainer.ALIGNMENT_CENTER
	rank_column.add_theme_constant_override("separation", -5)
	rank_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(rank_column)

	_grade = _label(rank_column, 40)
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade.add_theme_font_override("font", RANK_FONT)
	_grade.add_theme_color_override("font_shadow_color", Color("705bde"))
	_grade.add_theme_constant_override("shadow_offset_y", 3)
	_grade.add_theme_constant_override("shadow_outline_size", 5)

	_place = _label(rank_column, 18)
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place.modulate.a = 0.7

	_avatar = TextureRect.new()
	_avatar.texture = PLACEHOLDER
	_avatar.custom_minimum_size = Vector2(60, 60)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_avatar)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(details)

	_name_label = _label(details, 26)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 24)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(stats)

	_accuracy = _label(stats, 23)

	_combo = _label(stats, 21)
	_combo.modulate.a = 0.8

	_setup_actions()
	_setup_detail()

	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_on_mouse_exited)


func _setup_actions() -> void:
	_actions = HBoxContainer.new()
	_actions.mouse_filter = Control.MOUSE_FILTER_PASS
	_actions.offset_transform_enabled = true
	_actions.add_theme_constant_override("separation", 8)

	add_child(_actions)

	_actions.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_actions.offset_left = -258
	_actions.offset_right = -20
	_actions.offset_top = 21
	_actions.offset_bottom = 61

	_actions.size_flags_horizontal = Control.SIZE_SHRINK_END

	var profile := _action_button("PROFILE")
	var replay := _action_button("REPLAY")
	var more := _action_button("DETAIL")
	_replay_button = replay
	_detail_button = more
	profile.disabled = true
	profile.tooltip_text = "Profile is not available yet"

	profile.pressed.connect(
		func():
			action_pressed.emit("profile", _item)
	)

	replay.pressed.connect(
		func():
			action_pressed.emit("replay", _item)
	)

	more.pressed.connect(
		func():
			action_pressed.emit("more", _item)
	)

	for button: Button in [profile, replay, more]:
		button.mouse_entered.connect(_set_hover.bind(true))
		button.mouse_exited.connect(_on_mouse_exited)

	_actions.modulate.a = 0.0
	_actions.offset_transform_position = Vector2(18, 0)
	_actions.visible = false


func _action_button(text: String) -> Button:
	var button := Button.new()

	button.text = text
	button.custom_minimum_size = Vector2(74, 40)
	button.focus_mode = Control.FOCUS_NONE

	button.add_theme_font_override("font", BODY_FONT)
	button.add_theme_font_size_override("font_size", 18)

	_actions.add_child(button)

	return button


func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()

	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)

	parent.add_child(label)

	return label


func set_entry(item: Dictionary, maximum_combo: int) -> void:
	_item = item
	_replay_button.disabled = not bool(item.get("replay_available", false))
	_replay_button.tooltip_text = "Watch replay" if not _replay_button.disabled else "Replay unavailable"
	_detail_button.disabled = int(item.get("score_id", -1)) <= 0

	var accuracy := float(item.get("total_score", 0.0))

	_grade.text = ScoreRank.label_for_score(accuracy)

	var color := ScoreRank.color_for_score(accuracy)
	_grade.add_theme_color_override(
		"font_color",
		color.lightened(0.4) if color.get_luminance() < 0.15 else color
	)

	_place.text = "#%d" % int(item.get("rank", 0))
	_name_label.text = str(item.get("username", "PLAYER"))
	_accuracy.text = "%.2f%%" % accuracy

	var combo := int(item.get("max_combo", 0))

	_combo.text = "%d COMBO%s" % [
		combo,
		" · FC" if maximum_combo > 0 and combo >= maximum_combo else ""
	]

	_load_avatar(str(item.get("avatar_url", "")))


func _setup_detail() -> void:
	_detail_clip = Control.new()
	_detail_clip.clip_contents = true
	_detail_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail_clip)
	_detail_clip.anchor_right = 1.0
	_detail_clip.offset_top = 82.0
	_detail_clip.offset_bottom = 82.0
	_detail_clip.offset_left = 18.0
	_detail_clip.offset_right = -20.0
	_detail_status = _label(_detail_clip, 20)
	_detail_status.position = Vector2(0, 8)
	_judgements = HBoxContainer.new()
	_judgements.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_judgements.anchor_right = 1.0
	_judgements.offset_top = 12.0
	_judgements.offset_bottom = 86.0
	_detail_clip.add_child(_judgements)
	_judgements.hide()


func toggle_details(chart_id: int) -> void:
	_detail_open = not _detail_open
	_detail_button.text = "CLOSE" if _detail_open else "DETAIL"
	if _detail_tween:
		_detail_tween.kill()
	_detail_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_detail_tween.tween_method(_set_detail_height, _detail_clip.size.y, 100.0 if _detail_open else 0.0, 0.22)
	if not _detail_open or not _detail_data.is_empty() or is_instance_valid(_detail_request):
		return
	_detail_status.hide()
	var score_id := int(_item.get("score_id", -1))
	if chart_id <= 0 or score_id <= 0:
		_detail_error("Score details unavailable")
		return
	_detail_request = HTTPRequest.new()
	_detail_request.timeout = 15.0
	_detail_request.max_redirects = 0
	_detail_request.body_size_limit = 256 * 1024
	add_child(_detail_request)
	_detail_request.request_completed.connect(_on_detail_loaded.bind(chart_id, score_id))
	var url := ServerURLs.api("/leaderboards/charts/%d/scores/%d" % [chart_id, score_id])
	if _detail_request.request(url, Auth.authorization_headers()) != OK:
		_detail_request.queue_free()
		_detail_request = null
		_detail_error("Could not load details. Close and retry.")


func _set_detail_height(height: float) -> void:
	_detail_clip.size.y = height
	_detail_clip.modulate.a = clampf(height / 100.0, 0.0, 1.0)
	custom_minimum_size.y = 82.0 + height


func _on_detail_loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, chart_id: int, score_id: int) -> void:
	if is_instance_valid(_detail_request):
		_detail_request.queue_free()
	_detail_request = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_detail_error("Could not load details. Close and retry.")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or int(data.get("chart_id", -1)) != chart_id or int(data.get("score_id", -1)) != score_id:
		_detail_error("Invalid score details")
		return
	for judgement in JUDGEMENTS:
		if not data.has(judgement[1]):
			_detail_error("Judgement counts unavailable")
			return
	_detail_data = data
	_detail_status.hide()
	for judgement in JUDGEMENTS:
		var count := _label(_judgements, 23)
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.text = "%s\n%d" % [judgement[0], int(data[judgement[1]])]
	_judgements.show()
	_judgements.modulate.a = 0.0
	if _detail_appear:
		_detail_appear.kill()
	_detail_appear = create_tween()
	_detail_appear.tween_property(_judgements, "modulate:a", 1.0, 0.18)


func _detail_error(message: String) -> void:
	_detail_status.text = message
	_detail_status.show()


func set_replay_loading(loading: bool) -> void:
	_replay_button.disabled = loading or not bool(_item.get("replay_available", false))
	_replay_button.text = "REPLAY"


func _exit_tree() -> void:
	if is_instance_valid(_detail_request):
		_detail_request.cancel_request()


func play_appear(delay: float) -> void:
	if _appear:
		_appear.kill()

	modulate.a = 0.0
	offset_transform_position = Vector2(-28, 0)

	_appear = create_tween()

	if delay > 0.0:
		_appear.tween_interval(delay)

	_appear.tween_property(
		self,
		"offset_transform_position",
		Vector2.ZERO,
		0.25
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_appear.parallel().tween_property(
		self,
		"modulate:a",
		1.0,
		0.2
	)


func _set_hover(hovered: bool) -> void:
	_hovered = hovered

	if _hover:
		_hover.kill()

	if _actions_hide_tween:
		_actions_hide_tween.kill()
		_actions_hide_tween = null

	_hover = create_tween()
	_hover.set_parallel(true)
	_hover.set_trans(Tween.TRANS_CUBIC)
	_hover.set_ease(Tween.EASE_OUT)

	_hover.tween_property(
		_content,
		"offset_transform_position",
		Vector2(7, 0) if hovered else Vector2.ZERO,
		0.14
	)

	_hover.tween_property(
		_content,
		"offset_transform_scale",
		Vector2.ONE * (1.015 if hovered else 1.0),
		0.14
	)

	if hovered:
		_actions.visible = true

		_hover.tween_property(
			_actions,
			"modulate:a",
			1.0,
			0.14
		)

		_hover.tween_property(
			_actions,
			"offset_transform_position",
			Vector2.ZERO,
			0.18
		)
	else:
		_hover.tween_property(
			_actions,
			"modulate:a",
			0.0,
			0.12
		)

		_hover.tween_property(
			_actions,
			"offset_transform_position",
			Vector2(18, 0),
			0.16
		)

		_actions_hide_tween = create_tween()
		_actions_hide_tween.tween_interval(0.17)
		_actions_hide_tween.tween_callback(
			func():
				if not _hovered:
					_actions.visible = false
		)


func _on_mouse_exited() -> void:
	# Control 사이를 이동할 때 mouse_exited가 순간적으로 발생할 수 있어서
	# 한 프레임 뒤 실제 마우스 위치를 검사함.
	call_deferred("_check_hover_state")


func _check_hover_state() -> void:
	var mouse := get_global_mouse_position()

	if get_global_rect().has_point(mouse):
		return

	if _actions.visible and _actions.get_global_rect().has_point(mouse):
		return

	_set_hover(false)


func _load_avatar(url: String) -> void:
	if _avatar_cache.has(url):
		_avatar.texture = _avatar_cache[url]
		return

	if not (
		url.begins_with("https://")
		or url.begins_with("http://127.0.0.1:")
		or url.begins_with("http://localhost:")
	):
		return

	_avatar_request = HTTPRequest.new()
	_avatar_request.timeout = 10.0
	_avatar_request.body_size_limit = 2 * 1024 * 1024
	add_child(_avatar_request)

	_avatar_request.request_completed.connect(_on_avatar.bind(url))

	if _avatar_request.request(url) != OK:
		_avatar_request.queue_free()
		_avatar_request = null


func _on_avatar(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	url: String
) -> void:
	_avatar_request.queue_free()
	_avatar_request = null

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return

	var image := Image.new()

	var error := image.load_jpg_from_buffer(body)

	if error != OK:
		error = image.load_png_from_buffer(body)

	if error != OK:
		error = image.load_webp_from_buffer(body)

	if error != OK:
		return

	image.resize(96, 96, Image.INTERPOLATE_LANCZOS)

	_avatar.texture = ImageTexture.create_from_image(image)

	if _avatar_cache.size() >= 64:
		_avatar_cache.erase(_avatar_cache.keys()[0])

	_avatar_cache[url] = _avatar.texture
