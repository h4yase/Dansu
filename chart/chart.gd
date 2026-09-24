extends RefCounted
class_name Chart

enum Availability {
	UNKNOWN,
	AVAILABLE,
	MISSING,
	INVALID,
}

const DEFAULT_HITSOUND_HIT := 0
const DEFAULT_HITSOUND_MOVE := 1
const DEFAULT_HITSOUND_TRACE := 2
const DEFAULT_HITSOUND_SPIKE := 3
const DEFAULT_HITSOUND_LONGNOTE_RELEASE := 4
const DEFAULT_HITSOUND_SLOT_COUNT := 5
const CHART_SKINS_DIR_NAME := "skins"
const CHART_SKIN_JSON_NAME := "skin.json"
const CHART_SKIN_SPRITES_DIR_NAME := "sprites"

func _init() -> void:
	timings = []
	default_hitsounds = PackedInt32Array([-1, -1, -1, -1, -1])

var version: int = 1
var db_id: int = -1
var uuid: String = ""
var filehash: String = ""
var file_modified_time: int = 0
var file_size: int = 0
var availability: Availability = Availability.UNKNOWN
var storage_root: String = FileSystem.official_chart_path
var folder_name: String = ""
var file_name: String = ""
var online_metadata: Dictionary = {}
var chart_set: ChartSet = null

var skin_path: String:
	get:
		if file_skin == "":
			return ""
		return skin_directory_path.path_join(CHART_SKIN_JSON_NAME)

var skin_directory_path: String:
	get:
		if file_skin == "":
			return ""
		return skin_root_path.path_join(file_skin)

var skin_root_path: String:
	get:
		return folder_path.path_join(CHART_SKINS_DIR_NAME)

var file_path: String:
	get:
		return storage_root.path_join(folder_name).path_join(file_name)

var folder_path: String:
	get:
		return storage_root.path_join(folder_name)

var search_string: String = ""
var search_string_lower: String = ""

func build_search_string() -> void:
	search_string = title + "-" + artist + "-" + creator + "-" + tags + "-" + difficulty + "-" + source
	search_string_lower = search_string.to_lower()

var title: String = ""
var artist: String = ""
var creator: String = ""
var source: String = ""
var tags: String = ""
var difficulty: String = ""
var rating: float = 0.0
var rating_calculated := false
var last_played_at: int = 0
var best_score: float = 0.0
var play_count: int = 0
var current_version_play_count: int = 0

var preview_time := -1.0
var play_time_ms := 0
var timings: Array[Timing]
var default_hitsounds: PackedInt32Array

var file_audio: String = ""
var file_cover_art: String = ""
var file_skin: String = ""

var cover_image: Texture2D
var detail_cover_image: Texture2D

func copy_shared_metadata_from(source_chart: Chart) -> void:
	if source_chart == null:
		return
	version = source_chart.version
	title = source_chart.title
	artist = source_chart.artist
	creator = source_chart.creator
	source = source_chart.source
	tags = source_chart.tags
	preview_time = source_chart.preview_time
	file_audio = source_chart.file_audio
	file_cover_art = source_chart.file_cover_art
	file_skin = source_chart.file_skin
	cover_image = source_chart.cover_image

func get_cover_path() -> String:
	if file_cover_art.is_empty():
		return ""
	return folder_path.path_join(file_cover_art)

func load_cover_image_data() -> Image:
	var cover_path := get_cover_path()
	if cover_path.is_empty():
		return null
	return FileSystem.get_image(cover_path)

func get_stream() -> AudioStream:
	if file_audio.is_empty():
		return null

	var full_path := folder_path.path_join(file_audio)
	if not FileAccess.file_exists(full_path):
		return null

	var ext := file_audio.get_extension().to_lower()
	match ext:
		"mp3":
			return AudioStreamMP3.load_from_file(full_path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(full_path)
		"wav":
			return AudioStreamWAV.load_from_file(full_path)
		_:
			push_warning("not supported audio format: %s" % ext)
			return null

func reset_default_hitsounds() -> void:
	default_hitsounds = PackedInt32Array([-1, -1, -1, -1, -1])

func get_default_hitsound_id(slot: int) -> int:
	if slot < 0 or slot >= default_hitsounds.size():
		return -1
	return int(default_hitsounds[slot])

func set_default_hitsound_id(slot: int, hitsound_id: int) -> void:
	if slot < 0:
		return
	while default_hitsounds.size() < DEFAULT_HITSOUND_SLOT_COUNT:
		default_hitsounds.append(-1)
	if slot >= default_hitsounds.size():
		return
	default_hitsounds[slot] = hitsound_id

func get_default_hitsound_slot_for_note(note: Note) -> int:
	if note == null:
		return DEFAULT_HITSOUND_HIT
	match int(note.type):
		int(Note.NoteType.MOVE):
			return DEFAULT_HITSOUND_MOVE
		int(Note.NoteType.TRACE):
			return DEFAULT_HITSOUND_TRACE
		int(Note.NoteType.SPIKE):
			return DEFAULT_HITSOUND_SPIKE
		_:
			return DEFAULT_HITSOUND_HIT

func build_uuid() -> void:
	uuid = ChartIdentity.generate_uuid()
