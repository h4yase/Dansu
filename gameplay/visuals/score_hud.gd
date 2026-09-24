extends HBoxContainer
class_name GameplayScoreHUD

@export var rank_label: Label
@export var accuracy_label: Label

var _rank_threshold := 30
var _shown_rank := ""
var _last_judgement_count := -1
var _rank_tween: Tween


func reset(total_notes: int) -> void:
	_rank_threshold = mini(30, maxi(1, ceili(total_notes * 0.5)))
	_shown_rank = ""
	_last_judgement_count = -1
	if _rank_tween:
		_rank_tween.kill()
	rank_label.text = ""
	# Keep its layout space while hiding the unstable early rank.
	rank_label.modulate.a = 0.0
	rank_label.offset_transform_enabled = true
	rank_label.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	rank_label.offset_transform_scale = Vector2.ONE
	accuracy_label.text = "0.00%"
	accuracy_label.modulate.a = 1.0
	accuracy_label.offset_transform_enabled = true
	accuracy_label.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	accuracy_label.offset_transform_scale = Vector2.ONE


func refresh(current_score: Score, completed_notes: int) -> void:
	if _last_judgement_count == current_score.notes:
		return
	_last_judgement_count = current_score.notes
	accuracy_label.text = "%.2f%%" % current_score.total_score
	if completed_notes < _rank_threshold:
		return
	var next_rank := current_score.rank_str
	if next_rank == _shown_rank:
		return
	_shown_rank = next_rank
	rank_label.text = next_rank
	rank_label.add_theme_color_override("font_color", current_score.rank_color)
	if _rank_tween:
		_rank_tween.kill()
	_rank_tween = create_tween().set_parallel(true)
	for label: Label in [rank_label, accuracy_label]:
		label.modulate.a = 0.3
		label.offset_transform_scale = Vector2(0.82, 0.82)
		_rank_tween.tween_property(label, "modulate:a", 1.0, 0.12)
		_rank_tween.tween_property(label, "offset_transform_scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
