extends Control
class_name DansuUIFeedback

signal interaction(kind: Kind)

enum Kind { HOVER, PRESS, CONFIRM, REJECT }

@export var hover_sound: AudioStream
@export var press_sound: AudioStream
@export var confirm_sound: AudioStream
@export var reject_sound: AudioStream
@export var animate_scale := true
@export var highlight_enabled := true
@export var animate_brightness := false

@onready var _target: Control = get_parent()
@onready var _highlight: Panel = $Highlight
@onready var _error: Panel = $Error
@onready var _sound: AudioStreamPlayer = $Sound

var _hovered := false
var _focused := false
var _hover_tween: Tween
var _press_tween: Tween
var _error_tween: Tween

func _process(_delta: float) -> void:
	if not _enabled() and (_hovered or _focused or _error.modulate.a > 0.0 or (animate_scale and _target.scale != Vector2.ONE)):
		_reset_feedback()

func _ready() -> void:
	_target.mouse_entered.connect(_on_mouse_entered)
	_target.mouse_exited.connect(_on_mouse_exited)
	_target.focus_entered.connect(_on_focus_entered)
	_target.focus_exited.connect(_on_focus_exited)
	_target.visibility_changed.connect(_on_visibility_changed)
	_target.resized.connect(_update_pivot)
	_update_pivot()
	if _target is BaseButton:
		_target.button_down.connect(_on_button_down)
		_target.button_up.connect(_on_button_up)
		if _target is OptionButton:
			_target.item_selected.connect(_on_item_selected)
	elif _target is LineEdit:
		_target.text_submitted.connect(_on_text_submitted)
	elif _target is Slider:
		_target.drag_started.connect(_on_button_down)
		_target.drag_ended.connect(_on_drag_ended)
	elif _target is SpinBox:
		var input: LineEdit = _target.get_line_edit()
		input.focus_entered.connect(_on_focus_entered)
		input.focus_exited.connect(_on_focus_exited)
		input.text_submitted.connect(_on_text_submitted)

func _update_pivot() -> void:
	_target.pivot_offset = _target.size * 0.5

func reject() -> void:
	if not _enabled() or not _target.is_visible_in_tree():
		return
	if _error_tween != null:
		_error_tween.kill()
	_feedback(Kind.REJECT, reject_sound)
	_error.modulate.a = 1.0
	_error_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for angle in [-0.018, 0.018, -0.012, 0.012, 0.0]:
		_error_tween.tween_property(_target, "rotation", angle, 0.055)
	_error_tween.tween_property(_error, "modulate:a", 0.0, 0.3).set_delay(0.15)

func _enabled() -> bool:
	if _target is BaseButton:
		return not _target.disabled
	if _target is LineEdit:
		return _target.editable
	if _target is Slider:
		return _target.editable
	return true

func _on_mouse_entered() -> void:
	if not _enabled():
		return
	_hovered = true
	_feedback(Kind.HOVER, hover_sound)
	_update_highlight()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_highlight()

func _on_focus_entered() -> void:
	_focused = true
	_update_highlight()

func _on_focus_exited() -> void:
	_focused = false
	_update_highlight()

func _update_highlight() -> void:
	if _hover_tween != null:
		_hover_tween.kill()
	var opacity := 0.0
	var active := _enabled() and (_focused or _hovered)
	if highlight_enabled and _enabled():
		opacity = 1.0 if _focused else (0.65 if _hovered else 0.0)
	_hover_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(_highlight, "modulate:a", opacity, 0.12)
	if animate_brightness:
		var color := Color(1.12, 1.12, 1.12) if active else Color.WHITE
		_hover_tween.parallel().tween_property(_target, "self_modulate", color, 0.12)

func _on_button_down() -> void:
	if not _enabled():
		return
	_feedback(Kind.PRESS, press_sound)
	_animate_press(Vector2(0.97, 0.97), 0.06)

func _on_button_up() -> void:
	_animate_press(Vector2.ONE, 0.14)

func _animate_press(next_scale: Vector2, duration: float) -> void:
	if not animate_scale:
		return
	if _press_tween != null:
		_press_tween.kill()
	_press_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_press_tween.tween_property(_target, "scale", next_scale, duration)

func _on_text_submitted(_text: String) -> void:
	_feedback(Kind.CONFIRM, confirm_sound)

func _on_item_selected(_index: int) -> void:
	_feedback(Kind.CONFIRM, confirm_sound)

func _on_drag_ended(changed: bool) -> void:
	_on_button_up()
	if changed:
		_feedback(Kind.CONFIRM, confirm_sound)

func _feedback(kind: Kind, stream: AudioStream) -> void:
	interaction.emit(kind)
	if stream != null:
		_sound.stream = stream
		_sound.play()

func _on_visibility_changed() -> void:
	if _target.is_visible_in_tree():
		return
	_reset_feedback()

func _reset_feedback() -> void:
	_hovered = false
	_focused = false
	if _hover_tween != null:
		_hover_tween.kill()
	if _press_tween != null:
		_press_tween.kill()
	if _error_tween != null:
		_error_tween.kill()
	_highlight.modulate.a = 0.0
	_error.modulate.a = 0.0
	_target.rotation = 0.0
	if animate_brightness:
		_target.self_modulate = Color.WHITE
	if animate_scale:
		_target.scale = Vector2.ONE
