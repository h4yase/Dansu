extends Node2D

@export var bar_count := 64
@export var bar_width := 8.0
@export var spacing := 2.0
@export var max_height := 200.0
@export var amplitude := 250.0

@export var reverse := false
@export var multi: MultiMeshInstance2D

const MIN_FREQ := 20.0
const MAX_FREQ := 20000.0

var spectrum: AudioEffectSpectrumAnalyzerInstance
var heights: Array[float]

func _ready() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)

	var mm := MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.instance_count = bar_count

	multi.multimesh = mm

	spectrum = AudioServer.get_bus_effect_instance(
		AudioServer.get_bus_index("Master"),
		0
	)

	heights.resize(bar_count)

	for i in bar_count:
		heights[i] = 2.0
		mm.set_instance_color(i, Color.WHITE)

func _process(delta: float) -> void:
	if not is_instance_valid(spectrum):
		spectrum = AudioServer.get_bus_effect_instance(
			AudioServer.get_bus_index("Master"),
			0
		) as AudioEffectSpectrumAnalyzerInstance
		if not is_instance_valid(spectrum):
			return

	for i in bar_count:

		var t0 := float(i) / bar_count
		var t1 := float(i + 1) / bar_count

		var low := MIN_FREQ * pow(MAX_FREQ / MIN_FREQ, t0)
		var high := MIN_FREQ * pow(MAX_FREQ / MIN_FREQ, t1)

		var mag := spectrum.get_magnitude_for_frequency_range(low, high)

		# dB 변환
		var db := linear_to_db(max(mag.length(), 0.00001))

		var target := remap(db, -60.0, 0.0, 2.0, max_height)
		target = clamp(target, 2.0, max_height)

		heights[i] = lerp(
			heights[i],
			target,
			delta * 20.0
		)

	update_mesh()

func update_mesh() -> void:

	var mm := multi.multimesh

	for i in bar_count:

		var h = heights[i]

		var _transform := Transform2D.IDENTITY

		_transform.x = Vector2(bar_width, 0)

		_transform.y = Vector2(0, -h - 20)

		_transform.origin = Vector2(
			i * (bar_width + spacing),
			0
		) + Vector2(bar_width * 0.5, 0)

		mm.set_instance_transform_2d(i, _transform)
