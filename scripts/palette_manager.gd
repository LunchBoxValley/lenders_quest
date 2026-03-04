extends Node
class_name PaletteManager

# PICO-8 palette
const P: Dictionary = {
	"BLACK":  Color("#000000"),
	"NAVY":   Color("#1D2B53"),
	"PURPLE": Color("#7E2553"),
	"GREEN":  Color("#008751"),
	"BROWN":  Color("#AB5236"),
	"DKGRAY": Color("#5F574F"),
	"LTGRAY": Color("#C2C3C7"),
	"WHITE":  Color("#FFF1E8"),
	"RED":    Color("#FF004D"),
	"ORANGE": Color("#FFA300"),
	"YELLOW": Color("#FFEC27"),
	"LIME":   Color("#00E436"),
	"BLUE":   Color("#29ADFF"),
	"LAV":    Color("#83769C"),
	"PINK":   Color("#FF77A8"),
	"PEACH":  Color("#FFCCAA"),
}

# Presets store two colors: main + shadow
# Each preset value is a Dictionary with keys "main" and "shadow" (both Color).
const PRESETS: Dictionary = {
	"BONE":   {"main": P["WHITE"],  "shadow": P["LTGRAY"]},
	"SLIME":  {"main": P["LIME"],   "shadow": P["GREEN"]},
	"BLOOD":  {"main": P["RED"],    "shadow": P["PURPLE"]},
	"ICE":    {"main": P["BLUE"],   "shadow": P["NAVY"]},
	"SAND":   {"main": P["PEACH"],  "shadow": P["BROWN"]},
	"VOID":   {"main": P["LTGRAY"], "shadow": P["DKGRAY"]},
	"NEON":   {"main": P["YELLOW"], "shadow": P["ORANGE"]},
}

func apply_to_sprite(sprite: Sprite2D, preset_name: StringName) -> void:
	if sprite == null:
		return

	var key: String = String(preset_name)
	if not PRESETS.has(key):
		return

	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat == null:
		return
	if mat.shader == null:
		return

	# Make the material instance-local so we don't recolor shared resources
	sprite.material = mat.duplicate(true)
	mat = sprite.material as ShaderMaterial
	if mat == null:
		return

	# Only apply if shader has these uniforms
	if not _shader_has_uniform(mat.shader, "main_color"):
		return
	if not _shader_has_uniform(mat.shader, "shadow_color"):
		return

	# Typed access (avoid Variant inference warnings)
	var preset_dict: Dictionary = PRESETS[key] as Dictionary
	var main_c: Color = preset_dict["main"] as Color
	var shadow_c: Color = preset_dict["shadow"] as Color

	mat.set_shader_parameter("main_color", main_c)
	mat.set_shader_parameter("shadow_color", shadow_c)

func apply_to_node(root: Node, preset_name: StringName) -> void:
	if root == null:
		return

	for child in root.get_children():
		if child is Sprite2D:
			apply_to_sprite(child as Sprite2D, preset_name)
		apply_to_node(child, preset_name)

func _shader_has_uniform(shader: Shader, uniform_name: String) -> bool:
	var list: Array = shader.get_shader_uniform_list()
	for item in list:
		var d: Dictionary = item as Dictionary
		if d.has("name") and String(d["name"]) == uniform_name:
			return true
	return false
