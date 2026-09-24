extends RefCounted
class_name GameplayAudio

const DEFAULT_HIT_SFX := preload("res://resources/audio/hitsounds/chop.wav")
const DEFAULT_MOVE_SFX := preload("res://resources/audio/hitsounds/chop.wav")
const SFX_PLAYER_COUNT := 20
const SONG_FADE_DELAY_MS := 1000.0
const SONG_FADE_DB_PER_SECOND := 30.0
const MUSIC_BUS := &"Music"

var is_song_playing := false
var song_end := 0

var _host: Node
var _song_player: AudioStreamPlayer
var _clock: GameClock
var _chart: ParsedChart
var _base_volume_db := 0.0
var _armed := false
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player := 0

# Compatibility bridge: HitsoundResolver currently expects a Dictionary.
# Remove this after HitsoundResolver gets a typed lookup API.
var _hitsound_streams: Dictionary = {}

func setup(host: Node, song_player: AudioStreamPlayer, chart: ParsedChart, clock: GameClock) -> void:
	_host = host
	_song_player = song_player
	_chart = chart
	_clock = clock

	_song_player.bus = MUSIC_BUS
	_song_player.stream = chart.chart.get_stream()
	_base_volume_db = _song_player.volume_db
	_prepare_sfx_players()
	_rebuild_hitsounds()

func reset(play_time_ms: float) -> void:
	_song_player.stop()
	_song_player.stream_paused = false
	_song_player.volume_db = _base_volume_db
	is_song_playing = false
	_armed = false
	_next_sfx_player = 0
	song_end = int(play_time_ms + SONG_FADE_DELAY_MS) if play_time_ms > 0.0 else 0

func play_song() -> void:
	_armed = true

func update(time_ms: int, delta: float) -> void:
	if _armed and not is_song_playing:
		var startup_delay_sec := AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
		var play_call_usec := _clock.start_target_usec - int(startup_delay_sec * 1000000.0)
		if Time.get_ticks_usec() >= play_call_usec:
			_song_player.play(_clock.playback_start_ms / 1000.0)
			is_song_playing = true

	if song_end > 0 and time_ms > song_end:
		_song_player.volume_db = maxf(
			-80.0,
			_song_player.volume_db - delta * SONG_FADE_DB_PER_SECOND
		)

func pause() -> void:
	if is_song_playing:
		_song_player.stream_paused = true

func resume() -> void:
	if is_song_playing:
		_song_player.stream_paused = false

func stop() -> void:
	_armed = false
	is_song_playing = false
	_song_player.stop()

func freeze() -> void:
	if _song_player != null:
		_song_player.stream_paused = true

func play_note_sfx(note: Note) -> void:
	var stream := HitsoundResolver.for_note(
		_chart.chart,
		_hitsound_streams,
		note,
		DEFAULT_HIT_SFX,
		DEFAULT_MOVE_SFX
	)
	play_sfx(stream)

func play_long_release_sfx() -> void:
	var stream := HitsoundResolver.long_note_release(
		_chart.chart,
		_hitsound_streams,
		DEFAULT_HIT_SFX
	)
	play_sfx(stream)

func play_sfx(stream: AudioStream) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var player := _sfx_players[_next_sfx_player]
	_next_sfx_player = (_next_sfx_player + 1) % _sfx_players.size()
	player.stream = stream
	player.play()

func _prepare_sfx_players() -> void:
	if not _sfx_players.is_empty():
		return
	for index in range(SFX_PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "GameplaySFXPlayer%d" % index
		player.bus = "SFX"
		_host.add_child(player)
		_sfx_players.append(player)

func _rebuild_hitsounds() -> void:
	_hitsound_streams.clear()
	for hitsound in _chart.hitsounds:
		if hitsound != null and hitsound.stream != null:
			_hitsound_streams[hitsound.id] = hitsound.stream
