extends RefCounted
class_name CommunityChartCache

static func load_chartset(metadata: Dictionary) -> ChartSet:
	if not metadata.get("charts") is Array:
		return null
	var folder_name := ChartPackageInstaller.download_folder_name(metadata)
	var folder_path := FileSystem.community_cache_path.path_join(folder_name)
	var manifest := ChartPackageInstaller.read_revision_manifest(folder_path)
	if str(manifest.get("chartset_uuid", "")).to_lower() != str(metadata.get("chartset_uuid", "")).to_lower():
		return null

	var chartset := ChartSet.new()
	chartset.uuid = str(metadata.get("chartset_uuid", ""))
	chartset.status = str(metadata.get("status"),"")
	chartset.folder_name = folder_name
	chartset.online_metadata = metadata.duplicate(true)
	for entry in metadata.charts:
		if not entry is Dictionary:
			return null
		var relative_path := str(entry.get("relative_chart_path", ""))
		var full_path := folder_path.path_join(relative_path)
		if not ChartPackageInstaller.safe_relative(relative_path) or not FileAccess.file_exists(full_path):
			return null
		var checksum := str(entry.get("checksum_sha256", "")).to_lower()
		if checksum.length() != 64 or FileAccess.get_sha256(full_path).to_lower() != checksum:
			return null
		var chart := Chart.new()
		chart.storage_root = FileSystem.community_cache_path
		chart.folder_name = folder_name
		chart.file_name = relative_path
		chart.chart_set = chartset
		if not Parser.parse_meta(chart):
			return null
		chart.uuid = str(entry.get("chart_uuid", chart.uuid))
		chart.filehash = checksum
		chart.rating = float(entry.get("rating", chart.rating))
		chart.rating_calculated = true
		chart.online_metadata = entry.duplicate(true)
		chartset.charts.append(chart)
	return chartset if not chartset.charts.is_empty() else null


static func touch(chartset: ChartSet) -> void:
	if chartset == null:
		return
	var folder_path := FileSystem.community_cache_path.path_join(chartset.folder_name)
	var manifest := ChartPackageInstaller.read_revision_manifest(folder_path)
	if manifest.is_empty():
		return
	manifest["last_used_at"] = int(Time.get_unix_time_from_system())
	FileSystem.write_text_atomic(
		folder_path.path_join(ChartPackageInstaller.REVISION_MANIFEST_NAME),
		JSON.stringify(manifest)
	)
