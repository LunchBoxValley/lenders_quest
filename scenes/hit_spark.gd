extends Node2D

@export var life_sec: float = 0.12
@export var pop_sec: float = 0.04

@export var core_size: int = 4
@export var ray_count: int = 6
@export var ray_len: int = 10
@export var ray_thickness: int = 2

@export var chip_count: int = 5
@export var chip_size: int = 2
@export var chip_spread_px: float = 10.0

# Keep it white/gray for now
@export var core_color: Color = Color(1, 1, 1, 1)
@export var ray_color: Color = Color(1, 1, 1, 0.95)
@export var chip_color: Color = Color(0.85, 0.85, 0.85, 1)

var _mat_add: CanvasItemMaterial


func _ready() -> void:
	# Additive blend makes it feel like a bright CRT-ish “flash”
	_mat_add = CanvasItemMaterial.new()
	_mat_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_build_core()
	_build_rays()
	_build_chips()

	# Pop + fade
	scale = Vector2(0.6, 0.6)
	modulate = Color(1, 1, 1, 1)

	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.25, 1.25), pop_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), life_sec - pop_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "modulate:a", 0.0, life_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await tw.finished
	queue_free()


func _build_core() -> void:
	var core := ColorRect.new()
	core.color = core_color
	core.size = Vector2(core_size, core_size)
	core.position = -core.size * 0.5
	core.material = _mat_add
	add_child(core)

	# Tiny second core for a “double pop”
	var core2 := ColorRect.new()
	core2.color = Color(1, 1, 1, 0.6)
	core2.size = Vector2(core_size + 2, core_size + 2)
	core2.position = -core2.size * 0.5
	core2.material = _mat_add
	add_child(core2)


func _build_rays() -> void:
	# Slight random rotation so it doesn’t look stamped
	var base_rot := randf_range(0.0, TAU)

	for i in range(ray_count):
		var ray_node := Node2D.new()
		ray_node.rotation = base_rot + (TAU * float(i) / float(ray_count))
		add_child(ray_node)

		var r := ColorRect.new()
		r.color = ray_color
		r.size = Vector2(ray_len, ray_thickness)
		r.position = Vector2(0.0, -float(ray_thickness) * 0.5) # start at center, extend outward
		r.material = _mat_add
		ray_node.add_child(r)


func _build_chips() -> void:
	for _i in range(chip_count):
		var cnode := Node2D.new()
		add_child(cnode)

		var chip := ColorRect.new()
		chip.color = chip_color
		chip.size = Vector2(chip_size, chip_size)
		chip.position = -chip.size * 0.5
		chip.material = _mat_add
		cnode.add_child(chip)

		# Launch direction + distance
		var dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		if dir.length() < 0.01:
			dir = Vector2(1, 0)
		dir = dir.normalized()

		var dist := randf_range(chip_spread_px * 0.5, chip_spread_px)
		var target := dir * dist

		var tw := create_tween()
		tw.tween_property(cnode, "position", target, life_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
