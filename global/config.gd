extends Node
class_name AppConfig


#SECTION
const FILE_PATH := "user://config.cfg"
const ENGINE_CONFIG_PATH := "user://project_settings.cfg"
const SECTION_GRAPHICS := "Graphics"
const SECTION_GAMEPLAY := "GamePlay"
const SECTION_KEYBINDS := "KeyBinds"
const SECTION_AUDIO := "Audio"
const SECTION_ETC := "ETC"

## CONST
const FILE_EXTENSION = ".dansu"
const DEFAULT_SKIN_PATH = "res://contents/skins/danshe/skin.json"
const SERVER_URL = ServerURLs.BASE_URL
const MIN_MAX_FPS := 30
const MAX_FINITE_FPS := 1000
const MIN_OUTPUT_LATENCY := 1
const MAX_OUTPUT_LATENCY := 100

var config := ConfigFile.new()
var _engine_config := ConfigFile.new()

func apply_settings() -> void:
	max_fps = max_fps
	action_left = action_left
	action_right = action_right
	action_hit1 = action_hit1
	action_hit2 = action_hit2
	ignore_chart_skin = ignore_chart_skin
	window_mode = window_mode
	window_size = window_size
	master_db = master_db
	music_db = music_db
	sfx_db = sfx_db
	offset = offset
	note_speed = note_speed
	judgment_line_position = judgment_line_position
	player_size = player_size
	play_area_tilt = play_area_tilt
	vsync_mode = vsync_mode
	taa = taa
	msaa = msaa
	postaa = postaa
	chart_load_threads = chart_load_threads
	call_deferred("_center_window_if_windowed")
	

var language: String:
	get:
		return str(config.get_value(SECTION_GAMEPLAY, "language", "en"))
	set(value):
		config.set_value(SECTION_GAMEPLAY, "language", value)

## KEY BINDS

func _set_key_event(key_bind:Key,action_name:String):
	if key_bind != 0 and key_bind != KEY_ESCAPE:
		config.set_value(SECTION_KEYBINDS,action_name,key_bind)
		var input_event = InputEventKey.new()
		input_event.physical_keycode = key_bind
		InputMap.action_erase_events(action_name)
		InputMap.action_add_event(action_name, input_event)

var action_left: Key:
	get:
		return config.get_value(SECTION_KEYBINDS,"action_left",KEY_LEFT)
	set(value):
		config.set_value(SECTION_KEYBINDS,"action_left",value)
		_set_key_event(value,"action_left")

var action_right: Key:
	get:
		return config.get_value(SECTION_KEYBINDS,"action_right",KEY_RIGHT)
	set(value):
		config.set_value(SECTION_KEYBINDS,"action_right",value)
		_set_key_event(value,"action_right")
	
var action_hit1: Key:
	get:
		return config.get_value(SECTION_KEYBINDS,"action_hit1",KEY_Z)
	set(value):
		config.set_value(SECTION_KEYBINDS,"action_hit1",value)
		_set_key_event(value,"action_hit1")

var action_hit2: Key:
	get:
		return config.get_value(SECTION_KEYBINDS,"action_hit2",KEY_X)
	set(value):
		config.set_value(SECTION_KEYBINDS,"action_hit2",value)
		_set_key_event(value,"action_hit2")

## GRAPHICS

var max_fps: int:
	get:
		return _sanitize_max_fps_value(config.get_value(SECTION_GRAPHICS, "max_fps", 0))
	set(value):
		value = _sanitize_max_fps_value(value)
		config.set_value(SECTION_GRAPHICS, "max_fps", value)

var window_size: Vector2i:
	get:
		var main_display = DisplayServer.get_primary_screen()
		var screen_size = DisplayServer.screen_get_size(main_display)
		return config.get_value(SECTION_GRAPHICS, "window_size", screen_size) as Vector2i
	set(value):
		get_window().size = value
		config.set_value(SECTION_GRAPHICS, "window_size", value)
		call_deferred("_center_window_if_windowed")

var window_mode: DisplayServer.WindowMode:
	get:
		var value = config.get_value(SECTION_GRAPHICS,"window_mode",DisplayServer.WINDOW_MODE_FULLSCREEN)
		value = _sanitize_window_mode(value)
		return value
	set(value):
		value = _sanitize_window_mode(value)
		config.set_value(SECTION_GRAPHICS,"window_mode",value)
		DisplayServer.window_set_mode(value)
		call_deferred("_center_window_if_windowed")

var vsync_mode: DisplayServer.VSyncMode:
	get:
		var value = config.get_value(SECTION_GRAPHICS,"vsync_mode",DisplayServer.VSYNC_ADAPTIVE)
		if value > 4:
			value = DisplayServer.VSYNC_ADAPTIVE
		return value
	set(value):
		if value > 4:
			value = DisplayServer.VSYNC_ADAPTIVE
		config.set_value(SECTION_GRAPHICS,"vsync_mode",value)

var msaa: Viewport.MSAA:
	get:
		return config.get_value(SECTION_GRAPHICS,"msaa",Viewport.MSAA_2X)
	set(value):
		var vp := get_viewport()
		vp.msaa_2d = value
		vp.msaa_3d = value
		config.set_value(SECTION_GRAPHICS,"msaa",value)

var postaa : Viewport.ScreenSpaceAA:
	get:
		return config.get_value(SECTION_GRAPHICS,"post_aa",Viewport.SCREEN_SPACE_AA_FXAA)
	set(value):
		var vp := get_viewport()
		config.set_value(SECTION_GRAPHICS,"post_aa",value)
		vp.screen_space_aa = value

var taa : bool:
	get:
		return config.get_value(SECTION_GRAPHICS,"taa",false)
	set(value):
		var vp := get_viewport()
		vp.use_taa = value
		config.set_value(SECTION_GRAPHICS,"taa",value)

## Gameplay

var ignore_chart_skin: bool:
	get:
		return config.get_value(SECTION_GAMEPLAY,"ignore_chart_skin",false)
	set(value):
		config.set_value(SECTION_GAMEPLAY,"ignore_chart_skin",value)

var custom_skin_path: String:
	get:
		var value := str(config.get_value(SECTION_GAMEPLAY, "custom_skin_path", ""))
		if value.get_extension().to_lower() == "json":
			return value.get_base_dir()
		return value
	set(value):
		var next_value := str(value).strip_edges()
		if next_value.get_extension().to_lower() == "json":
			next_value = next_value.get_base_dir()
		config.set_value(SECTION_GAMEPLAY, "custom_skin_path", next_value)

var note_speed: float:
	get:
		return config.get_value(SECTION_GAMEPLAY,"note_speed",30)
	set(value):
		config.set_value(SECTION_GAMEPLAY,"note_speed",value)

var judgment_line_position: float:
	get:
		return clampf(config.get_value(SECTION_GAMEPLAY, "judgment_line_position", 0.0), -50.0, 50.0)
	set(value):
		config.set_value(SECTION_GAMEPLAY, "judgment_line_position", clampf(value, -50.0, 50.0))

var player_size: float:
	get:
		return clampf(config.get_value(SECTION_GAMEPLAY, "player_size", 1.0), 0.5, 2.0)
	set(value):
		config.set_value(SECTION_GAMEPLAY, "player_size", clampf(value, 0.5, 2.0))

var play_area_tilt: float:
	get:
		return clampf(config.get_value(SECTION_GAMEPLAY, "play_area_tilt", 25.0), 0.0, 90.0)
	set(value):
		config.set_value(SECTION_GAMEPLAY, "play_area_tilt", clampf(value, 0.0, 90.0))

## Audio
var master_db: float:
	get:
		return config.get_value(SECTION_AUDIO,"master_db",1)
	set(value):
		var db = linear_to_db(value)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)
		config.set_value(SECTION_AUDIO,"master_db",value)

var music_db: float:
	get:
		return config.get_value(SECTION_AUDIO,"music_db",1)
	set(value):
		var db = linear_to_db(value)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), db)
		config.set_value(SECTION_AUDIO,"music_db",value)
		
var sfx_db: float:
	get:
		return config.get_value(SECTION_AUDIO,"sfx_db",config.get_value(SECTION_AUDIO,"hit_effect",1))
	set(value):
		var db = linear_to_db(value)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), db)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("HitEffect"), db)
		config.set_value(SECTION_AUDIO,"sfx_db",value)
		if config.has_section_key(SECTION_AUDIO, "hit_effect"):
			config.erase_section_key(SECTION_AUDIO, "hit_effect")

var offset: int:
	get:
		return config.get_value(SECTION_AUDIO,"audio_offset",0)
	set(value):
		config.set_value(SECTION_AUDIO,"audio_offset",value)

var output_latency: int:
	get:
		var default_value := int(ProjectSettings.get_setting_with_override("audio/driver/output_latency"))
		return clampi(int(_engine_config.get_value("audio", "driver/output_latency", default_value)), MIN_OUTPUT_LATENCY, MAX_OUTPUT_LATENCY)
	set(value):
		value = clampi(value, MIN_OUTPUT_LATENCY, MAX_OUTPUT_LATENCY)
		_engine_config.set_value("audio", "driver/output_latency", value)
		# The audio driver reads this override before autoloads run on the next launch.
		var error := _engine_config.save(ENGINE_CONFIG_PATH)
		if error != OK:
			push_error("Failed to save output latency: %s" % error_string(error))

## ETC

var chart_load_threads: int:
	get:
		return config.get_value(SECTION_ETC,"chart_load_threads",2)
	set(value):
		config.set_value(SECTION_ETC,"chart_load_threads",value)

func _ready() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	config.load(FILE_PATH)
	_engine_config.load(ENGINE_CONFIG_PATH)
	if config.has_section_key(SECTION_ETC, "server_api_url"):
		config.erase_section_key(SECTION_ETC, "server_api_url")
	save_config()

func save_config() -> void:
	apply_settings()
	config.save(FILE_PATH)

func _center_window_if_windowed() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return

	var window := get_window()
	if window == null:
		return

	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()

	var screen_pos := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	var target_size := window.size
	@warning_ignore("integer_division")
	var centered_position := screen_pos + (screen_size - target_size) / 2

	DisplayServer.window_set_position(Vector2i(centered_position))

func _sanitize_window_mode(value) -> DisplayServer.WindowMode:
	var mode := int(value)
	if mode == DisplayServer.WINDOW_MODE_MINIMIZED:
		return DisplayServer.WINDOW_MODE_WINDOWED
	if mode < 0 or mode > int(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN):
		return DisplayServer.WINDOW_MODE_FULLSCREEN
	return mode as DisplayServer.WindowMode


func _sanitize_max_fps_value(value) -> int:
	var fps := int(value)
	if fps <= 0:
		return 0
	if fps < MIN_MAX_FPS:
		return MIN_MAX_FPS
	if fps > MAX_FINITE_FPS:
		return 0
	return fps
