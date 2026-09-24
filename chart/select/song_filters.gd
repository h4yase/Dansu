extends RefCounted
class_name SongFilters

enum PlayHistory {ANY, PLAYED, UNPLAYED}

var sort: String
var reverse: bool = false
var nsfl: bool = false
var status: String = ""
var played: PlayHistory = PlayHistory.ANY
## Negative bounds mean that the filter is unset; zero is a valid bound.
var min_rating: float = -1.0
var max_rating: float = -1.0
var min_length_ms: int = -1
var max_length_ms: int = -1
var max_size_bytes: int = -1

func _init(online: bool = false) -> void:
	sort = "newest" if online else "title"

func copy() -> SongFilters:
	var result := SongFilters.new()
	result.sort = sort
	result.reverse = reverse
	result.nsfl = nsfl
	result.status = status
	result.played = played
	result.min_rating = min_rating
	result.max_rating = max_rating
	result.min_length_ms = min_length_ms
	result.max_length_ms = max_length_ms
	result.max_size_bytes = max_size_bytes
	return result

func has_play_history() -> bool:
	return played != PlayHistory.ANY

func matches_local(chart: Chart) -> bool:
	if min_rating >= 0 and chart.rating < min_rating:
		return false
	if max_rating >= 0 and chart.rating > max_rating:
		return false
	if min_length_ms >= 0 and chart.play_time_ms < min_length_ms:
		return false
	if max_length_ms >= 0 and chart.play_time_ms > max_length_ms:
		return false
	return not has_play_history() or (chart.play_count > 0) == (played == PlayHistory.PLAYED)

func active_count() -> int:
	return int(reverse) + int(nsfl) + int(not status.is_empty()) + int(has_play_history()) \
		+ int(min_rating >= 0) + int(max_rating >= 0) + int(min_length_ms >= 0) \
		+ int(max_length_ms >= 0) + int(max_size_bytes >= 0)

## Convert to a dictionary only at the HTTP query boundary.
func to_query() -> Dictionary:
	var query := {"sort": sort, "reverse": reverse, "nsfl": nsfl}
	if not status.is_empty():
		query.status = status
	if has_play_history():
		query.played = played == PlayHistory.PLAYED
	if min_rating >= 0:
		query.min_rating = min_rating
	if max_rating >= 0:
		query.max_rating = max_rating
	if min_length_ms >= 0:
		query.min_length_ms = min_length_ms
	if max_length_ms >= 0:
		query.max_length_ms = max_length_ms
	if max_size_bytes >= 0:
		query.max_size_bytes = max_size_bytes
	return query
