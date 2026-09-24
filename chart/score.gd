extends RefCounted
class_name Score

# name
enum {NONE,MISS,PERFECT_PLUS,PERFECT,GREAT,OK,BAD}
# Timings
enum T {NONE=-1,MISS=105,PERFECT_PLUS=21,PERFECT=42,GREAT=63,OK=84,BAD=105}
enum T_V2 {NONE=-1,MISS=1,PERFECT_PLUS=20,PERFECT=40,GREAT=80,OK=120,BAD=180}
# Scores
enum S {MISS=0,PERFECT_PLUS=100,PERFECT=99,GREAT=50,OK=25,BAD=10}
const TRACE_TOP_SCORE := 50.0
const SPIKE_DODGE_SCORE := 25.0
const OVER_100_DISPLAY_MAX := 101.0

# count of judgement for result
var notes := 0
var perfect_plus := 0
var perfect := 0 
var great := 0
var ok := 0
var bad := 0
var miss := 0

var replay: Replay
var replay_path: String:
	get:
		return Replay.path_for(submission_id)
var signed_timings : Array[float] = []
var stored_avg_signed_timing := 0.0
var avg_signed_timings : float :
	get :
		if signed_timings.size() <= 0:
			return stored_avg_signed_timing
		var total = 0
		for value in signed_timings:
			total += value
		return total / signed_timings.size()


var score :float = 0 # current score
var max_score :float = 0
var high_combo := 0

var object_hash = ""
var db_id := -1
var chart_db_id := -1
var played_at := 0
var scoring_version := 2
var unstable_rate := 0.0
var stored_total_score := -1.0
var submission_id := ""
var submitted := false
var submission_error := ""
var submission_response: Dictionary = {}
var chart_title := ""
var chart_artist := ""
var chart_difficulty := ""
var chart_folder_name := ""
var chart_file_name := ""

func get_judgement(time_gap) -> int:
	if abs(time_gap) < T.PERFECT_PLUS:
		return PERFECT_PLUS
	elif abs(time_gap) < T.PERFECT:
		return PERFECT
	elif abs(time_gap) < T.GREAT:
		return GREAT
	elif abs(time_gap) < T.OK:
		return OK
	elif abs(time_gap) < T.BAD:
		return BAD
	return NONE

func add_note_result(note: Note, judgement: int, gap: float) -> void:
	var max_points := _get_max_points_for_note(note)
	if judgement == NONE and max_points <= 0.0:
		return
	
	if [Note.NoteType.HIT,Note.NoteType.MOVE].has(note.type) and judgement != MISS:
		signed_timings.append(gap)
	max_score += max_points
	notes += 1

	var awarded_points := _get_awarded_points_for_note(note, judgement)

	if judgement == PERFECT_PLUS:
		perfect_plus += 1
	elif judgement == PERFECT:
		perfect += 1
	elif judgement == GREAT:
		great += 1
	elif judgement == OK:
		ok += 1
	elif judgement == BAD:
		bad += 1
	elif judgement == MISS:
		miss += 1
	elif judgement == NONE:
		return

	score += awarded_points


func add_spike_dodge(note: Note) -> void:
	var max_points := _get_max_points_for_note(note)
	if max_points <= 0.0:
		return

	max_score += max_points
	score += SPIKE_DODGE_SCORE
	notes += 1
	perfect_plus += 1


func _get_max_points_for_note(note: Note) -> float:
	if note == null:
		return S.PERFECT_PLUS

	match int(note.type):
		int(Note.NoteType.TRACE):
			return TRACE_TOP_SCORE
		int(Note.NoteType.SPIKE):
			return SPIKE_DODGE_SCORE
		_:
			return S.PERFECT_PLUS

func _get_awarded_points_for_note(note: Note, judgement: int) -> float:
	if note != null:
		match int(note.type):
			int(Note.NoteType.TRACE):
				if judgement == PERFECT_PLUS:
					return TRACE_TOP_SCORE
				if judgement == MISS:
					return S.MISS
				return 0.0
			int(Note.NoteType.SPIKE):
				if judgement == MISS:
					return S.MISS
				return 0.0

	match judgement:
		PERFECT_PLUS:
			return S.PERFECT_PLUS
		PERFECT:
			return S.PERFECT
		GREAT:
			return S.GREAT
		OK:
			return S.OK
		BAD:
			return S.BAD
		_:
			return S.MISS

var rank_color: Color:
	get:
		return ScoreRank.color_for_score(total_score)

var rank_str: String:
	get:
		return ScoreRank.label_for_score(total_score)

var total_score: float:
	get:

		if stored_total_score >= 0.0:
			return stored_total_score
		
		# Avoid / 0
		if notes == 0:
			return 101.0
		
		# All Just
		if great == 0 and ok == 0 and bad == 0 and miss == 0:
			return _get_all_just_display_score()

		if max_score <= 0.0:
			return 0.0
		
		# raw_score
		return score / max_score * 100.0

func _get_all_just_display_score() -> float:
	var just_ratio := clampf(float(perfect_plus) / float(notes), 0.0, 1.0)
	return 100.0 + (_remap_over_100_ratio(just_ratio) * (OVER_100_DISPLAY_MAX - 100.0))

func _remap_over_100_ratio(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	if is_equal_approx(t, 0.0) or is_equal_approx(t, 1.0):
		return t
	return t ** (5.0 - (2.0 * t))
