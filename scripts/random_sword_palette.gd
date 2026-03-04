extends Sprite2D

@export var enabled: bool = true
@export var delay_frames: int = 1  # wait until other palettes apply

# PICO-8 bright-ish mains for a sword
const MAIN_CHOICES: Array[Color] = [
	Color("#FF004D"), # red
	Color("#FFA300"), # orange
	Color("#FFEC27"), # yellow
	Color("#00E436"), # lime
	Color("#29ADFF"), # blue
	Color("#FF77A8"), # pink
	Color("#FFCCAA"), # peach
]

func _ready() -> void:
	if not enabled:
		return
	call_deferred("_apply_after_ready")

func _apply_after_ready() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for _i in range(maxi(0, delay_frames)):
		await tree.process_frame
	_apply_random()

func _apply_random() -> void:
	# Requires this Sprite2D to already have the 2-tone palette shader material
	var mat: ShaderMaterial = material as ShaderMaterial
	if mat == null:
		push_warning("SwordSprite has no ShaderMaterial. Assign the 2-tone palette shader material first.")
		return

	# Duplicate so we don't recolor shared materials
	material = mat.duplicate(true)
	mat = material as ShaderMaterial
	if mat == null:
		return

	var idx: int = int(randi() % MAIN_CHOICES.size())
	var main_c: Color = MAIN_CHOICES[idx]
	var shadow_c: Color = _pick_shadow_for(main_c)

	mat.set_shader_parameter("main_color", main_c)
	mat.set_shader_parameter("shadow_color", shadow_c)

func _pick_shadow_for(main_c: Color) -> Color:
	# Keep shadows inside the PICO-8 palette
	if main_c == Color("#29ADFF"):
		return Color("#1D2B53") # navy
	if main_c == Color("#00E436"):
		return Color("#008751") # green
	if main_c == Color("#FFEC27"):
		return Color("#FFA300") # orange
	if main_c == Color("#FF004D") or main_c == Color("#FF77A8"):
		return Color("#7E2553") # purple
	return Color("#5F574F") # dkgray fallback
