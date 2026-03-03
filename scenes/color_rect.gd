extends ColorRect

@export var warmup_enabled: bool = true

func _ready() -> void:
	if material != null:
		material = material.duplicate(true)

	var sm := material as ShaderMaterial
	if sm == null:
		return

	sm.set_shader_parameter("warmup_enabled", warmup_enabled)

	# Matches shader TIME closely enough (seconds since engine start)
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	sm.set_shader_parameter("warmup_start_time", now_sec)
