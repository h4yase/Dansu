extends Node
class_name EditorTransport

const SFX_PLAYER_COUNT := 8

var chart: Chart = null
var timeline: EditorTimeline = null
var hitsound_manager: EditorHitsoundManager = null

var playing := false

var _audio_player: AudioStreamPlayer
var _audio_started := false
var _audio_start_target_usec := 0
var _audio_start_position_sec := 0.0
var _song_finished_usec := 0

var stream_length_sec := 0.0
var stream_length_msec := 0.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_index := 0

var _playback_notes: Array[Note] = []
var _playback_note_index := 0
var _last_sfx_time := -1000000.0

var _release_notes: Array[Note] = []
var _release_note_index := 0
var _last_release_sfx_time := -1000000.0

func setup() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "EditorAudioPlayer"
	_audio_player.bus = "Music"
	_audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_audio_player)

	for i in range(SFX_PLAYER_COUNT):
		var sfx := AudioStreamPlayer.new()
		sfx.name = "EditorSFXPlayer%d" % i
		sfx.bus = "SFX"
		sfx.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(sfx)
		_sfx_players.append(sfx)

func load_stream() -> void:
	_audio_player.stop()
	_audio_player.stream = chart.get_stream() if chart != null else null
	playing = false
	_audio_started = false
	_audio_start_target_usec = 0
	_audio_start_position_sec = 0.0
	_song_finished_usec = 0

	if chart != null and _audio_player.stream != null:
		stream_length_sec = _audio_player.stream.get_length()
		stream_length_msec = stream_length_sec * 1000.0
	else:
		stream_length_sec = 0.0
		stream_length_msec = 0.0

func toggle() -> void:
	if playing:
		pause()
	else:
		start()

func start() -> void:
	if chart == null or _audio_player.stream == null:
		return
	playing = true
	_restart_from_current_time()

func pause() -> void:
	if playing:
		_tick()
	playing = false
	_audio_player.stop()
	_audio_started = false
	_audio_start_target_usec = 0
	_song_finished_usec = 0

func update() -> void:
	if not playing:
		return
	_tick()

func seek() -> void:
	if playing:
		_restart_from_current_time()

func rebuild_playback_notes() -> void:
	_playback_notes.clear()
	_release_notes.clear()
	if CM.parsed_chart == null:
		_reset_sfx_cursor(Game.current_time)
		return
	for rail in CM.parsed_chart.rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note == null:
				continue
			_playback_notes.append(note)
			if int(note.length) > 0:
				_release_notes.append(note)
	_playback_notes.sort_custom(func(a: Note, b: Note) -> bool: return a.time < b.time)
	_release_notes.sort_custom(func(a: Note, b: Note) -> bool: return a.end_time < b.end_time)
	_reset_sfx_cursor(Game.current_time)

func _tick() -> void:
	if chart == null or _audio_player.stream == null:
		return

	var now_usec := Time.get_ticks_usec()
	var previous_time := Game.current_time

	if not _audio_started:
		_maybe_start_audio(now_usec)
		Game.current_time = timeline.clamp_time(
			_audio_start_position_sec * 1000.0 + float(now_usec - _audio_start_target_usec) / 1000.0
		)
	elif _song_finished_usec > 0:
		Game.current_time = timeline.clamp_time(
			stream_length_msec + float(now_usec - _song_finished_usec) / 1000.0
		)
	else:
		var playback_sec :float = clamp(_audio_player.get_playback_position(), 0.0, stream_length_sec)
		Game.current_time = timeline.clamp_time(playback_sec * 1000.0)
		if playback_sec >= stream_length_sec - 0.02 or not _audio_player.playing:
			_song_finished_usec = now_usec

	_play_sfx_between(previous_time, Game.current_time)

	if is_equal_approx(Game.current_time, timeline.get_max_time()):
		playing = false
		_audio_player.stop()
		_audio_started = false
		_audio_start_target_usec = 0
		_song_finished_usec = 0

func _restart_from_current_time() -> void:
	if chart == null or _audio_player.stream == null:
		return
	_audio_player.stop()
	var t := timeline.clamp_time(Game.current_time)
	_audio_started = false
	_song_finished_usec = 0
	_reset_sfx_cursor(t)

	if t < 0.0:
		_audio_start_position_sec = 0.0
		_audio_start_target_usec = Time.get_ticks_usec() + int(-t * 1000.0)
		return
	if t >= stream_length_msec:
		_audio_start_position_sec = stream_length_sec
		_audio_started = true
		_song_finished_usec = Time.get_ticks_usec() - int((t - stream_length_msec) * 1000.0)
		return

	_audio_start_position_sec = t / 1000.0
	_audio_start_target_usec = Time.get_ticks_usec()
	_maybe_start_audio(Time.get_ticks_usec())

func _maybe_start_audio(now_usec: int) -> void:
	if _audio_started or _audio_player.stream == null:
		return
	var play_usec := _audio_start_target_usec - int(AudioServer.get_time_to_next_mix() * 1000000.0)
	if now_usec < play_usec:
		return
	_audio_player.play(_audio_start_position_sec)
	_audio_started = true

func _play_sfx_between(from_time: float, to_time: float) -> void:
	if to_time < from_time:
		_reset_sfx_cursor(to_time)
		return
	if _playback_notes.is_empty():
		return
	if from_time < _last_sfx_time:
		_reset_sfx_cursor(from_time)
	while _playback_note_index < _playback_notes.size():
		var note := _playback_notes[_playback_note_index]
		if note.time > to_time:
			break
		if note.time > from_time:
			_play_sfx(hitsound_manager.get_stream_for_note(note))
		_playback_note_index += 1
	_last_sfx_time = to_time
	_play_release_sfx_between(from_time, to_time)

func _play_release_sfx_between(from_time: float, to_time: float) -> void:
	if _release_notes.is_empty():
		return
	if from_time < _last_release_sfx_time:
		_reset_sfx_cursor(from_time)
	while _release_note_index < _release_notes.size():
		var note := _release_notes[_release_note_index]
		var release_time := note.end_time
		if release_time > to_time:
			break
		if release_time > from_time:
			_play_sfx(hitsound_manager.get_release_stream())
		_release_note_index += 1
	_last_release_sfx_time = to_time

func _play_sfx(stream: AudioStream) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var player := _sfx_players[_next_sfx_index]
	_next_sfx_index = (_next_sfx_index + 1) % _sfx_players.size()
	player.stream = stream
	player.play()

func _reset_sfx_cursor(time_ms: float) -> void:
	_playback_note_index = 0
	while _playback_note_index < _playback_notes.size() and _playback_notes[_playback_note_index].time < time_ms:
		_playback_note_index += 1
	_last_sfx_time = time_ms - 0.001

	_release_note_index = 0
	while _release_note_index < _release_notes.size() and _release_notes[_release_note_index].end_time < time_ms:
		_release_note_index += 1
	_last_release_sfx_time = time_ms - 0.001
