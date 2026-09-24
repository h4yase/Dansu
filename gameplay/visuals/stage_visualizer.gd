extends Node3D
class_name GameplayStageVisualizer

const DETAIL_SHADER := preload("res://resources/shaders/stage_detail.gdshader")
const JUDGEMENT_SHADER := preload("res://resources/shaders/judgement_line.gdshader")
const SPECTRUM_BUS := &"Music"
const WAVE_SAMPLE_COUNT := 48
const MIN_FREQUENCY_HZ := 55.0
const MAX_FREQUENCY_HZ := 12000.0
const ABSOLUTE_FLOOR_DB := -62.0
const ABSOLUTE_CEILING_DB := -12.0
const VISUAL_VOLUME_NOISE_FLOOR := 0.08
const VISUAL_VOLUME_BODY_FLOOR := 0.10
const VISUAL_VOLUME_BODY_CEILING := 0.62
const VISUAL_VOLUME_PEAK_FLOOR := 0.76
const VISUAL_VOLUME_PEAK_CEILING := 0.98
const VISUAL_VOLUME_MIN := 0.10
const VISUAL_VOLUME_BODY := 0.46
const VISUAL_VOLUME_TRANSIENT := 0.62
const VISUAL_VOLUME_PEAK := 0.32
const VOLUME_FAST_RESPONSE := 34.0
const VOLUME_SLOW_ATTACK_RESPONSE := 3.2
const VOLUME_SLOW_RELEASE_RESPONSE := 1.1
const VOLUME_ATTACK_RESPONSE := 30.0
const VOLUME_RELEASE_RESPONSE := 15.0
const SCROLL_LOOP_LENGTH := 48.0
const WAVE_Z_MIN := -50.0
const WAVE_Z_MAX := 4.0
const WALL_INNER_X := 8.0
const WALL_WIDTH := 3.2
const WALL_ANGLE := 0.43633231
const WALL_BASE_Y := -0.065
const WAVE_BASE_OFFSET := 0.72
const WAVE_SURFACE_Y := -0.018
const WAVE_BACKING_Y := -0.055
const DETAIL_Y := 0.018
const FLOOR_DETAIL_MIX := 0.38
const FLOOR_RAIL_MIX := 0.12
const FLOOR_VALUE_FROM_BACKGROUND := 0.42
const FLOOR_VALUE_FROM_RAIL := 0.07
const FLOOR_MIN_VALUE := 0.012
const FLOOR_MAX_VALUE := 0.045
const GUIDE_BASE_MIX := 0.28
const GUIDE_RAIL_MIX := 0.62
const GUIDE_VALUE_FROM_BACKGROUND := 0.48
const GUIDE_VALUE_FROM_RAIL := 0.82
const GUIDE_MIN_VALUE := 0.42
const GUIDE_MAX_VALUE := 0.92
const GROUND_LINE_OPACITY := 0.58
const GROUND_FLOOR_OPACITY := 0.10
const GROUND_VOLUME_ALPHA_BOOST := 0.34

@export var ground: MeshInstance3D
@export var player: Node3D
@export var vignette: ColorRect
@export_range(0.0, 10.0, 0.1) var scroll_speed := 3.2

var accent_color: Color
var guide_color: Color
var _floor_color: Color
var _detail_color: Color

var low_energy := 0.0
var mid_energy := 0.0
var high_energy := 0.0
var volume_level := 0.0

var _ground_material: ShaderMaterial = null
var _spectrum: AudioEffectSpectrumAnalyzerInstance = null
var _spectrum_levels := PackedFloat32Array()
var _scroll_phase := 0.0
var _shader_scroll_offset := 0.0
var _volume_fast := 0.0
var _volume_slow := 0.0

var _stage_shell: Node3D = null
var _shell_material: StandardMaterial3D = null
var _scrolling_details: Node3D = null
var _detail_material: ShaderMaterial = null
var _wave_left: ImmediateMesh = null
var _wave_right: ImmediateMesh = null
var _wave_material: ShaderMaterial = null
var _judgement_material: ShaderMaterial = null


func _ready() -> void:
	_spectrum_levels.resize(WAVE_SAMPLE_COUNT)
	_cache_ground_material()
	_find_spectrum_analyzer()


func _process(delta: float) -> void:
	_update_audio_levels(delta)
	var playback_seconds := maxf(Game.current_time, 0.0) * 0.001
	_shader_scroll_offset = playback_seconds * scroll_speed
	_scroll_phase = fposmod(_shader_scroll_offset, SCROLL_LOOP_LENGTH)
	if _scrolling_details != null:
		_scrolling_details.position.z = _scroll_phase
	_update_waveforms(playback_seconds)
	_update_judgement_line()
	_update_shader_parameters()


func set_theme_colors(base_color: Color, detail_color: Color, rail_color: Color) -> void:
	_update_theme_palette(base_color, detail_color, rail_color)
	if _ground_material != null:
		_ground_material.set_shader_parameter("floor_color", _floor_color)
	if vignette != null and vignette.material is ShaderMaterial:
		var vignette_material := vignette.material as ShaderMaterial
		vignette_material.set_shader_parameter("edge_color", _floor_color.darkened(0.36))
	_ensure_themed_visuals()
	_update_judgement_line()
	_update_shader_parameters()


func _update_theme_palette(base_color: Color, detail_color: Color, rail_color: Color) -> void:
	var base := Color(base_color.r, base_color.g, base_color.b, 1.0)
	var detail := Color(detail_color.r, detail_color.g, detail_color.b, 1.0)
	_detail_color = detail
	accent_color = Color(rail_color.r, rail_color.g, rail_color.b, 1.0)

	var background_value := maxf(base.v, detail.v)
	var floor_seed := base.lerp(detail, FLOOR_DETAIL_MIX).lerp(accent_color, FLOOR_RAIL_MIX)
	var floor_value := clampf(
		background_value * FLOOR_VALUE_FROM_BACKGROUND + accent_color.v * FLOOR_VALUE_FROM_RAIL,
		FLOOR_MIN_VALUE,
		FLOOR_MAX_VALUE
	)
	_floor_color = Color.from_hsv(
		floor_seed.h,
		clampf(floor_seed.s * 1.12, 0.0, 0.88),
		floor_value,
		1.0
	)

	var guide_seed := detail.lerp(base, GUIDE_BASE_MIX).lerp(accent_color, GUIDE_RAIL_MIX)
	var guide_value := clampf(
		maxf(
			background_value * GUIDE_VALUE_FROM_BACKGROUND,
			accent_color.v * GUIDE_VALUE_FROM_RAIL
		),
		GUIDE_MIN_VALUE,
		GUIDE_MAX_VALUE
	)
	guide_color = Color.from_hsv(
		guide_seed.h,
		clampf(guide_seed.s * 1.08, 0.0, 0.92),
		guide_value,
		1.0
	)


func _ensure_themed_visuals() -> void:
	if _stage_shell != null:
		return
	_create_stage_shell()
	_create_scrolling_details()
	_create_waveforms()
	_create_judgement_line()


func _cache_ground_material() -> void:
	if ground == null:
		return
	_ground_material = ground.get_active_material(0) as ShaderMaterial


func _find_spectrum_analyzer() -> void:
	if is_instance_valid(_spectrum):
		return
	_spectrum = null
	var bus_index := AudioServer.get_bus_index(SPECTRUM_BUS)
	if bus_index < 0:
		return
	for effect_index in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect := AudioServer.get_bus_effect(bus_index, effect_index)
		if effect is AudioEffectSpectrumAnalyzer:
			var instance := AudioServer.get_bus_effect_instance(bus_index, effect_index) as AudioEffectSpectrumAnalyzerInstance
			if is_instance_valid(instance):
				_spectrum = instance
				return


func _update_audio_levels(delta: float) -> void:
	if not is_instance_valid(_spectrum):
		_find_spectrum_analyzer()
	if not is_instance_valid(_spectrum):
		low_energy = _smooth_energy(low_energy, 0.0, delta)
		mid_energy = _smooth_energy(mid_energy, 0.0, delta)
		high_energy = _smooth_energy(high_energy, 0.0, delta)
		volume_level = _smooth_volume(volume_level, 0.0, delta)
		return
	var spectrum := _spectrum

	var frequency_ratio := MAX_FREQUENCY_HZ / MIN_FREQUENCY_HZ
	var instant_low := 0.0
	var instant_mid := 0.0
	var instant_high := 0.0
	for index in range(WAVE_SAMPLE_COUNT):
		var from_ratio := float(index) / float(WAVE_SAMPLE_COUNT)
		var to_ratio := float(index + 1) / float(WAVE_SAMPLE_COUNT)
		var from_hz := MIN_FREQUENCY_HZ * pow(frequency_ratio, from_ratio)
		var to_hz := MIN_FREQUENCY_HZ * pow(frequency_ratio, to_ratio)
		var magnitude := spectrum.get_magnitude_for_frequency_range(
			from_hz,
			to_hz,
			AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX
		)
		var target := _normalize_magnitude(magnitude.length())
		if index < 12:
			instant_low += target
		elif index < 32:
			instant_mid += target
		else:
			instant_high += target
		_spectrum_levels[index] = _smooth_energy(_spectrum_levels[index], target, delta)

	var low_target := _average_spectrum_range(0, 12)
	var mid_target := _average_spectrum_range(12, 32)
	var high_target := _average_spectrum_range(32, WAVE_SAMPLE_COUNT)
	low_energy = _smooth_energy(low_energy, low_target, delta)
	mid_energy = _smooth_energy(mid_energy, mid_target, delta)
	high_energy = _smooth_energy(high_energy, high_target, delta)
	instant_low /= 12.0
	instant_mid /= 20.0
	instant_high /= 16.0
	var absolute_volume := instant_low * 0.55 + instant_mid * 0.35 + instant_high * 0.10
	_volume_fast = lerpf(_volume_fast, absolute_volume, 1.0 - exp(-delta * VOLUME_FAST_RESPONSE))
	var slow_response := VOLUME_SLOW_ATTACK_RESPONSE if absolute_volume > _volume_slow else VOLUME_SLOW_RELEASE_RESPONSE
	_volume_slow = lerpf(_volume_slow, absolute_volume, 1.0 - exp(-delta * slow_response))
	var normalized_volume := smoothstep(VISUAL_VOLUME_BODY_FLOOR, VISUAL_VOLUME_BODY_CEILING, absolute_volume)
	var transient_volume := clampf(
		(_volume_fast - _volume_slow) / maxf(1.0 - _volume_slow, 0.001),
		0.0,
		1.0
	)
	var body_level := pow(normalized_volume, 0.72)
	var peak_level := pow(smoothstep(VISUAL_VOLUME_PEAK_FLOOR, VISUAL_VOLUME_PEAK_CEILING, absolute_volume), 2.4)
	var visual_volume := 0.0
	if absolute_volume > VISUAL_VOLUME_NOISE_FLOOR:
		visual_volume = VISUAL_VOLUME_MIN
		visual_volume += body_level * VISUAL_VOLUME_BODY
		visual_volume += pow(transient_volume, 0.55) * VISUAL_VOLUME_TRANSIENT
		visual_volume += peak_level * VISUAL_VOLUME_PEAK
		visual_volume = clampf(visual_volume, VISUAL_VOLUME_MIN, 1.0)
	volume_level = _smooth_volume(volume_level, visual_volume, delta)


func _normalize_magnitude(value: float) -> float:
	var decibels := linear_to_db(maxf(value, 0.00001))
	return clampf(
		(decibels - ABSOLUTE_FLOOR_DB) / (ABSOLUTE_CEILING_DB - ABSOLUTE_FLOOR_DB),
		0.0,
		1.0
	)


func _smooth_energy(current: float, target: float, delta: float) -> float:
	var response := 13.0 if target > current else 5.0
	return lerpf(current, target, 1.0 - exp(-delta * response))


func _smooth_volume(current: float, target: float, delta: float) -> float:
	var response := VOLUME_ATTACK_RESPONSE if target > current else VOLUME_RELEASE_RESPONSE
	return lerpf(current, target, 1.0 - exp(-delta * response))


func _average_spectrum_range(start_index: int, end_index: int) -> float:
	var total := 0.0
	var count := maxi(end_index - start_index, 1)
	for index in range(start_index, end_index):
		total += _spectrum_levels[index]
	return total / float(count)


func _update_shader_parameters() -> void:
	if _shell_material != null:
		_shell_material.albedo_color = accent_color
	if _ground_material != null:
		_ground_material.set_shader_parameter("scroll_offset", _shader_scroll_offset)
		_ground_material.set_shader_parameter("line_opacity", GROUND_LINE_OPACITY)
		_ground_material.set_shader_parameter("floor_opacity", GROUND_FLOOR_OPACITY)
		_ground_material.set_shader_parameter("volume_alpha_boost", GROUND_VOLUME_ALPHA_BOOST)
		_ground_material.set_shader_parameter("low_energy", low_energy)
		_ground_material.set_shader_parameter("mid_energy", mid_energy)
		_ground_material.set_shader_parameter("high_energy", high_energy)
		_ground_material.set_shader_parameter("volume_level", volume_level)
		_ground_material.set_shader_parameter("accent_color", accent_color)
		_ground_material.set_shader_parameter("guide_color", guide_color)
		_ground_material.set_shader_parameter("detail_color", _detail_color)
	if _detail_material != null:
		_detail_material.set_shader_parameter("tint_color", accent_color)
		_detail_material.set_shader_parameter("scroll_offset", _scroll_phase)
		_detail_material.set_shader_parameter("low_energy", low_energy)
		_detail_material.set_shader_parameter("volume_level", volume_level)
	if _wave_material != null:
		_wave_material.set_shader_parameter("low_energy", low_energy)
		_wave_material.set_shader_parameter("volume_level", volume_level)


func _create_vertex_material(render_priority: int = 0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = render_priority
	return material


func _create_detail_material(scroll_offset: float = 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = DETAIL_SHADER
	material.set_shader_parameter("scroll_offset", scroll_offset)
	material.set_shader_parameter("fade_start_z", -GameplayPlayfield.PLAY_AREA_SIZE.y)
	material.set_shader_parameter(
		"fade_end_z",
		-GameplayPlayfield.PLAY_AREA_SIZE.y + GameplayPlayfield.get_spawn_fade_distance()
	)
	return material


func _get_wall_transform(side: float) -> Transform3D:
	var cosine := cos(WALL_ANGLE)
	var sine := sin(WALL_ANGLE)
	var outward := Vector3(side * cosine, sine, 0.0)
	var normal := Vector3(-side * sine, cosine, 0.0)
	var forward := Vector3(0.0, 0.0, 1.0)
	var basis := Basis(outward, normal, forward)
	return Transform3D(basis, Vector3(side * WALL_INNER_X, WALL_BASE_Y, 0.0))


func _create_stage_shell() -> void:
	_shell_material = _create_vertex_material(0)
	_stage_shell = Node3D.new()
	_stage_shell.name = "StageShell"
	add_child(_stage_shell)

	for side_value in [-1.0, 1.0]:
		var side := float(side_value)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)

		var wall_color := Color(0.035, 0.035, 0.035, 1.0)
		wall_color.a = 0.075
		_add_prism(surface, Vector3(WALL_WIDTH * 0.5, -0.045, -23.0), Vector3(WALL_WIDTH, 0.045, 60.0), wall_color)

		var edge_color := Color.WHITE
		edge_color.a = 0.095
		_add_prism(surface, Vector3(0.04, 0.0, -23.0), Vector3(0.045, 0.032, 60.0), edge_color)
		_add_prism(surface, Vector3(WALL_WIDTH - 0.04, 0.0, -23.0), Vector3(0.045, 0.032, 60.0), edge_color)

		var seam_color := Color.WHITE
		seam_color.a = 0.032
		for seam_index in range(1, 4):
			var seam_x := WALL_WIDTH * float(seam_index) / 4.0
			_add_prism(surface, Vector3(seam_x, -0.002, -23.0), Vector3(0.018, 0.014, 58.0), seam_color)

		var mesh := surface.commit()
		if mesh != null and mesh.get_surface_count() > 0:
			mesh.surface_set_material(0, _shell_material)
		var wall_instance := MeshInstance3D.new()
		wall_instance.name = "WallLeft" if side < 0.0 else "WallRight"
		wall_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wall_instance.mesh = mesh
		wall_instance.transform = _get_wall_transform(side)
		_stage_shell.add_child(wall_instance)


func _create_scrolling_details() -> void:
	_detail_material = _create_detail_material()
	_scrolling_details = Node3D.new()
	_scrolling_details.name = "ScrollingDetails"
	add_child(_scrolling_details)

	var row_z := PackedFloat32Array([-46.0, -40.0, -34.0, -28.0, -22.0, -16.0, -10.0, -4.0])
	for side_value in [-1.0, 1.0]:
		var side := float(side_value)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for loop_index in range(2):
			var loop_offset := -SCROLL_LOOP_LENGTH * float(loop_index)
			for row_index in range(row_z.size()):
				var z := row_z[row_index] + loop_offset
				var side_offset := 0.38 if side > 0.0 else 0.0
				var x := 0.48 + fmod(float(row_index) * 0.91 + side_offset, WALL_WIDTH - 0.92)
				var elevation := 0.030 + float((row_index + (1 if side > 0.0 else 0)) % 3) * 0.025
				var rotation := side * (0.07 + fmod(float(row_index) * 0.105, 0.29))
				var color := Color.WHITE
				color.a = 0.14 + float(row_index % 3) * 0.025
				match (row_index + (1 if side > 0.0 else 0)) % 4:
					0:
						_add_cross(surface, Vector3(x, elevation, z), 0.74, 0.11, color, rotation)
					1:
						_add_dot_matrix(surface, Vector3(x, elevation, z), side, color, rotation * 0.45)
					2:
						_add_bar_cluster(surface, Vector3(x, elevation, z), side, color, rotation)
					_:
						var accent := Color.WHITE
						accent.a = 0.17
						_add_triangle(surface, Vector3(x, elevation + 0.045, z), Vector2(0.60, 0.50), accent, side)
						_add_prism(surface, Vector3(x + 0.48, elevation, z + 0.38), Vector3(0.40, 0.040, 0.16), color, -rotation * 0.72)

		var mesh := surface.commit()
		if mesh != null and mesh.get_surface_count() > 0:
			mesh.surface_set_material(0, _detail_material)
		var detail_instance := MeshInstance3D.new()
		detail_instance.name = "DetailsLeft" if side < 0.0 else "DetailsRight"
		detail_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		detail_instance.mesh = mesh
		detail_instance.transform = _get_wall_transform(side)
		_scrolling_details.add_child(detail_instance)


func _create_waveforms() -> void:
	_wave_material = _create_detail_material()
	_wave_material.render_priority = -1
	_wave_left = ImmediateMesh.new()
	_wave_right = ImmediateMesh.new()

	var left_instance := MeshInstance3D.new()
	left_instance.name = "SpectrumLeft"
	left_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	left_instance.mesh = _wave_left
	left_instance.transform = _get_wall_transform(-1.0)
	add_child(left_instance)

	var right_instance := MeshInstance3D.new()
	right_instance.name = "SpectrumRight"
	right_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	right_instance.mesh = _wave_right
	right_instance.transform = _get_wall_transform(1.0)
	add_child(right_instance)


func _update_waveforms(playback_seconds: float) -> void:
	if _wave_left == null or _wave_right == null:
		return
	var row_spacing := (WAVE_Z_MAX - WAVE_Z_MIN) / float(WAVE_SAMPLE_COUNT - 1)
	var fractional_shift := fposmod(playback_seconds * scroll_speed, row_spacing)
	_build_waveform_surface(_wave_left, fractional_shift)
	_build_waveform_surface(_wave_right, fractional_shift)


func _build_waveform_surface(mesh: ImmediateMesh, z_shift: float) -> void:
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _wave_material)
	for index in range(WAVE_SAMPLE_COUNT):
		var progress := float(index) / float(WAVE_SAMPLE_COUNT - 1)
		var z := lerpf(WAVE_Z_MIN, WAVE_Z_MAX, progress) + z_shift
		var source_index := (index + int(_scroll_phase * 1.7)) % WAVE_SAMPLE_COUNT
		var level := _spectrum_levels[source_index]
		var x := WAVE_BASE_OFFSET + 0.15 + level * 1.18
		var top_y := WAVE_SURFACE_Y - level * 0.012
		var wall_color := accent_color
		wall_color.a = 0.10 + level * 0.18
		var base_color := wall_color
		base_color.a *= 0.35

		mesh.surface_set_color(base_color)
		mesh.surface_add_vertex(Vector3(x, WAVE_BACKING_Y, z))
		mesh.surface_set_color(wall_color)
		mesh.surface_add_vertex(Vector3(x, top_y, z))
	mesh.surface_end()

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _wave_material)
	for index in range(WAVE_SAMPLE_COUNT):
		var progress := float(index) / float(WAVE_SAMPLE_COUNT - 1)
		var z := lerpf(WAVE_Z_MIN, WAVE_Z_MAX, progress) + z_shift
		var source_index := (index + int(_scroll_phase * 1.7)) % WAVE_SAMPLE_COUNT
		var level := _spectrum_levels[source_index]
		var amplitude := 0.15 + level * 1.18
		var x := WAVE_BASE_OFFSET + amplitude
		var half_width := 0.035 + level * 0.035
		var top_y := WAVE_SURFACE_Y - level * 0.012
		var color := accent_color
		color.a = 0.30 + level * 0.46 + volume_level * 0.08

		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(x - half_width, top_y, z))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(x + half_width, top_y, z))
	mesh.surface_end()

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _wave_material)
	for index in range(WAVE_SAMPLE_COUNT):
		var progress := float(index) / float(WAVE_SAMPLE_COUNT - 1)
		var z := lerpf(WAVE_Z_MIN, WAVE_Z_MAX, progress) + z_shift
		var source_index := (index + int(_scroll_phase * 1.7)) % WAVE_SAMPLE_COUNT
		var level := _spectrum_levels[source_index]
		var x := WAVE_BASE_OFFSET + 0.22 + level * 1.18
		var half_width := 0.065 + level * 0.025
		var shadow_color := _floor_color.darkened(0.58)
		shadow_color.a = 0.12

		mesh.surface_set_color(shadow_color)
		mesh.surface_add_vertex(Vector3(x - half_width, WAVE_BACKING_Y + 0.004, z))
		mesh.surface_set_color(shadow_color)
		mesh.surface_add_vertex(Vector3(x + half_width, WAVE_BACKING_Y + 0.004, z))
	mesh.surface_end()


func _create_judgement_line() -> void:
	_judgement_material = ShaderMaterial.new()
	_judgement_material.shader = JUDGEMENT_SHADER
	_judgement_material.render_priority = -1

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var judgement_z := GameplayPlayfield.JUDGEMENT_Z

	var shadow_color := Color(0.0, 0.0, 0.0, 1.0)
	shadow_color.a = 0.137
	_add_prism(surface, Vector3(0.0, 0.010, judgement_z), Vector3(16.0, 0.016, 0.23), shadow_color)

	var body_color := Color(0.33, 0.0, 0.0, 1.0)
	body_color.a = 0.38
	_add_prism(surface, Vector3(0.0, 0.028, judgement_z), Vector3(15.72, 0.020, 0.13), body_color)

	var core_color := Color(0.67, 0.0, 0.0, 1.0)
	core_color.a = 0.278
	_add_prism(surface, Vector3(0.0, 0.050, judgement_z - 0.003), Vector3(15.34, 0.013, 0.042), core_color)

	for side_value in [-1.0, 1.0]:
		var side := float(side_value)
		var cap_color := Color(1.0, 0.0, 0.0, 1.0)
		cap_color.a = 0.72
		_add_prism(
			surface,
			Vector3(side * 7.79, 0.030, judgement_z),
			Vector3(0.20, 0.050, 0.40),
			cap_color
		)
		_add_prism(
			surface,
			Vector3(side * 7.48, 0.044, judgement_z),
			Vector3(0.30, 0.017, 0.21),
			core_color
		)

	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, _judgement_material)
	var line_instance := MeshInstance3D.new()
	line_instance.name = "JudgementLine"
	line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line_instance.mesh = mesh
	add_child(line_instance)


func _update_judgement_line() -> void:
	if _judgement_material == null:
		return
	_judgement_material.set_shader_parameter("rail_color", accent_color)
	_judgement_material.set_shader_parameter("guide_color", guide_color)
	_judgement_material.set_shader_parameter("emission_energy", 0.10 + volume_level * 0.12)


func _add_cross(surface: SurfaceTool, center: Vector3, size: float, thickness: float, color: Color, rotation: float) -> void:
	_add_prism(surface, center, Vector3(size, 0.055, thickness), color, rotation)
	_add_prism(surface, center, Vector3(thickness, 0.055, size), color, rotation)


func _add_dot_matrix(surface: SurfaceTool, center: Vector3, side: float, color: Color, rotation: float) -> void:
	var axis_x := Vector3(cos(rotation), 0.0, sin(rotation))
	var axis_z := Vector3(-sin(rotation), 0.0, cos(rotation))
	for row in range(4):
		for column in range(6):
			var offset := axis_x * side * (float(column) - 2.5) * 0.20
			offset += axis_z * (float(row) - 1.5) * 0.21
			_add_prism(surface, center + offset, Vector3(0.075, 0.032, 0.075), color, rotation)


func _add_bar_cluster(surface: SurfaceTool, center: Vector3, side: float, color: Color, rotation: float) -> void:
	var axis_x := Vector3(cos(rotation), 0.0, sin(rotation))
	var axis_z := Vector3(-sin(rotation), 0.0, cos(rotation))
	for index in range(7):
		var length := 0.30 + float(index % 4) * 0.14
		var offset := axis_x * side * float(index) * 0.13
		offset += axis_z * float(index) * 0.18
		_add_prism(surface, center + offset, Vector3(length, 0.036, 0.060), color, rotation)


func _add_triangle(surface: SurfaceTool, center: Vector3, size: Vector2, color: Color, side: float) -> void:
	var a := center + Vector3(-side * size.x * 0.5, 0.0, size.y * 0.5)
	var b := center + Vector3(side * size.x * 0.5, 0.0, 0.0)
	var c := center + Vector3(-side * size.x * 0.5, 0.0, -size.y * 0.5)
	_add_colored_triangle(surface, a, b, c, color)


func _add_prism(surface: SurfaceTool, base_center: Vector3, size: Vector3, color: Color, rotation: float = 0.0) -> void:
	var axis_x := Vector3(cos(rotation), 0.0, sin(rotation)) * size.x * 0.5
	var axis_z := Vector3(-sin(rotation), 0.0, cos(rotation)) * size.z * 0.5
	var up := Vector3(0.0, size.y, 0.0)
	var a := base_center - axis_x - axis_z
	var b := base_center + axis_x - axis_z
	var c := base_center - axis_x + axis_z
	var d := base_center + axis_x + axis_z
	var top_a := a + up
	var top_b := b + up
	var top_c := c + up
	var top_d := d + up
	var side_color := color.darkened(0.48)
	side_color.a = color.a * 0.82

	_add_colored_triangle(surface, top_a, top_c, top_b, color)
	_add_colored_triangle(surface, top_b, top_c, top_d, color)
	_add_colored_triangle(surface, a, top_a, b, side_color)
	_add_colored_triangle(surface, b, top_a, top_b, side_color)
	_add_colored_triangle(surface, b, top_b, d, side_color)
	_add_colored_triangle(surface, d, top_b, top_d, side_color)
	_add_colored_triangle(surface, d, top_d, c, side_color)
	_add_colored_triangle(surface, c, top_d, top_c, side_color)
	_add_colored_triangle(surface, c, top_c, a, side_color)
	_add_colored_triangle(surface, a, top_c, top_a, side_color)


func _add_colored_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.add_vertex(b)
	surface.set_color(color)
	surface.add_vertex(c)
