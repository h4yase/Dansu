extends RefCounted
class_name Playlist

const RECENT_ID := -1
const RECENT_LIMIT := 1000

var id := 0
var name := "All Beatmaps"
var kind := ""
var chartsets: Array[ChartSet] = []
var played_chartset_ids: Array[int] = []
var busy := false


func filtered_chartsets(filters: SongFilters, search_text: String) -> Array[ChartSet]:
	var result: Array[ChartSet] = []
	for chartset in chartsets:
		var data := chartset.online_metadata
		if not filters.nsfl and bool(data.get("is_nsfl", false)):
			continue
		var status := str(data.get("status", ""))
		if not filters.status.is_empty() and status != filters.status:
			if filters.status != "published" or status != "pending":
				continue
		var length := int(data.get("primary_play_time_ms", 0))
		if filters.min_length_ms >= 0 and length < filters.min_length_ms:
			continue
		if filters.max_length_ms >= 0 and length > filters.max_length_ms:
			continue
		if filters.max_size_bytes >= 0:
			if data.get("package_size_bytes") == null or int(data.package_size_bytes) > filters.max_size_bytes:
				continue
		if filters.has_play_history():
			var played := played_chartset_ids.has(int(data.get("id", 0)))
			if played != (filters.played == SongFilters.PlayHistory.PLAYED):
				continue
		if _matches_chart(chartset, filters, search_text.strip_edges().to_lower()):
			result.append(chartset)
	# Startup requests already return farming order.
	if filters.sort != "farming" and not (kind == "recent" and filters.sort == "newest"):
		result.sort_custom(func(a: ChartSet, b: ChartSet) -> bool:
			var left := _sort_value(a, filters.sort)
			var right := _sort_value(b, filters.sort)
			if left == right:
				left = float(a.online_metadata.get("id", 0))
				right = float(b.online_metadata.get("id", 0))
			return left < right if filters.sort == "length" else left > right
		)
	if filters.reverse:
		result.reverse()
	return result


func _matches_chart(chartset: ChartSet, filters: SongFilters, search: String) -> bool:
	for chart in chartset.charts:
		if filters.min_rating >= 0 and chart.rating < filters.min_rating:
			continue
		if filters.max_rating >= 0 and chart.rating > filters.max_rating:
			continue
		if search.is_empty():
			return true
		var values := PackedStringArray()
		for value in chart.online_metadata.values():
			values.append(str(value) if value != null else "")
		if " ".join(values).to_lower().contains(search):
			return true
	return false


func _sort_value(chartset: ChartSet, sort: String) -> float:
	var data := chartset.online_metadata
	match sort:
		"length": return float(data.get("primary_play_time_ms", 0))
		"popularity": return float(data.get("play_count", 0))
	var date = data.get("published_at")
	if date == null:
		date = data.get("created_at", "")
	return Time.get_unix_time_from_datetime_string(str(date))


func contains(chartset_id: int) -> bool:
	for chartset in chartsets:
		if int(chartset.online_metadata.get("id", 0)) == chartset_id:
			return true
	return false


func record_recent(chartset: ChartSet) -> void:
	var chartset_id := int(chartset.online_metadata.get("id", 0))
	for index in range(chartsets.size()):
		if int(chartsets[index].online_metadata.get("id", 0)) == chartset_id:
			chartsets.remove_at(index)
			break
	chartsets.push_front(chartset)
	if not played_chartset_ids.has(chartset_id):
		played_chartset_ids.append(chartset_id)
	if chartsets.size() > RECENT_LIMIT:
		var oldest: ChartSet = chartsets.pop_back()
		played_chartset_ids.erase(int(oldest.online_metadata.get("id", 0)))


func set_chartset(chartset: ChartSet, added: bool) -> bool:
	if id <= 0 or busy or chartset == null or not Auth.is_authenticated() or not CM.playlists.has(self):
		return false
	var chartset_id := int(chartset.online_metadata.get("id", 0))
	if chartset_id <= 0:
		return false
	var request := HTTPRequest.new()
	request.timeout = 20
	request.max_redirects = 0
	CM.add_child(request)
	var method := HTTPClient.METHOD_PUT if added else HTTPClient.METHOD_DELETE
	var error := request.request(
		ServerURLs.api("/playlists/%d/chartsets/%d" % [id, chartset_id]),
		Auth.authorization_headers(), method
	)
	if error != OK:
		request.queue_free()
		return false
	busy = true
	CM.playlist_state_changed.emit()
	var response: Array = await request.request_completed
	request.queue_free()
	busy = false
	if not CM.playlists.has(self) or not Auth.is_authenticated():
		return false
	var success: bool = response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 204
	if success:
		if added and not contains(chartset_id):
			chartsets.append(chartset)
			for playlist in CM.playlists:
				if playlist.played_chartset_ids.has(chartset_id) and not played_chartset_ids.has(chartset_id):
					played_chartset_ids.append(chartset_id)
		elif not added:
			for index in range(chartsets.size()):
				if int(chartsets[index].online_metadata.get("id", 0)) == chartset_id:
					chartsets.remove_at(index)
					break
	CM.playlist_state_changed.emit()
	if success:
		CM.playlists_changed.emit()
	return success
