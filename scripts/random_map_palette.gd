extends TileMapLayer

@export var palette_enabled: bool = true
@export var delay_frames: int = 1

# Pick from presets in PaletteManager
@export var random_presets: PackedStringArray = PackedStringArray([
	"SAND",
	"VOID",
	"ICE",
	"SLIME",
	"NEON",
	"BLOOD",
])

func _ready() -> void:
	if not palette_enabled:
		return
	call_deferred("_apply_after_ready")

func _apply_after_ready() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for _i in range(maxi(0, delay_frames)):
		await tree.process_frame
	_apply_random_preset()

func _apply_random_preset() -> void:
	var mat: ShaderMaterial = material as ShaderMaterial
	if mat == null:
		push_warning("TileMapLayer has no ShaderMaterial. Assign the 2-tone palette shader material to the TileMapLayer.")
		return

	# Duplicate so we don’t recolor other layers by accident
	material = mat.duplicate(true)
	mat = material as ShaderMaterial
	if mat == null:
		return

	if random_presets.size() == 0:
		return

	var idx: int = int(randi() % random_presets.size())
	var preset_key: String = String(random_presets[idx])

	if not PaletteManager.PRESETS.has(preset_key):
		push_warning("Preset not found in PaletteManager.PRESETS: " + preset_key)
		return

	var preset_dict: Dictionary = PaletteManager.PRESETS[preset_key] as Dictionary
	var main_c: Color = preset_dict["main"] as Color
	var shadow_c: Color = preset_dict["shadow"] as Color

	mat.set_shader_parameter("main_color", main_c)
	mat.set_shader_parameter("shadow_color", shadow_c)
