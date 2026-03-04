extends Node

@export var ui_palette_enabled: bool = true
@export var delay_frames: int = 1

# Which PaletteManager presets can be used for UI
@export var random_presets: PackedStringArray = PackedStringArray([
	"BONE",
	"SLIME",
	"BLOOD",
	"ICE",
	"SAND",
	"VOID",
	"NEON",
])

# If you add any label to this group, it won't be recolored
@export var skip_group: StringName = &"ui_no_palette"

# Optional: give text a shadow for readability
@export var apply_shadow: bool = true
@export var shadow_offset: Vector2i = Vector2i(1, 1)

func _ready() -> void:
	if not ui_palette_enabled:
		return
	call_deferred("_apply_after_ready")

func _apply_after_ready() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for _i in range(maxi(0, delay_frames)):
		await tree.process_frame

	_apply_random_ui_palette()

func _apply_random_ui_palette() -> void:
	if random_presets.size() == 0:
		return

	var idx: int = int(randi() % random_presets.size())
	var preset_key: String = String(random_presets[idx])

	if not PaletteManager.PRESETS.has(preset_key):
		push_warning("UI preset not found in PaletteManager.PRESETS: " + preset_key)
		return

	var preset_dict: Dictionary = PaletteManager.PRESETS[preset_key] as Dictionary
	var main_c: Color = preset_dict["main"] as Color
	var shadow_c: Color = preset_dict["shadow"] as Color

	_apply_to_tree(self, main_c, shadow_c)

func _apply_to_tree(n: Node, main_c: Color, shadow_c: Color) -> void:
	# Apply to labels on this node
	if n is Label:
		var lab := n as Label
		if not lab.is_in_group(skip_group):
			_apply_to_label(lab, main_c, shadow_c)

	elif n is RichTextLabel:
		var r := n as RichTextLabel
		if not r.is_in_group(skip_group):
			# RichTextLabel uses default_color in many themes
			r.add_theme_color_override("default_color", main_c)
			r.add_theme_color_override("font_color", main_c)
			if apply_shadow:
				r.add_theme_color_override("font_shadow_color", shadow_c)

	# Recurse
	for child in n.get_children():
		_apply_to_tree(child, main_c, shadow_c)

func _apply_to_label(lab: Label, main_c: Color, shadow_c: Color) -> void:
	# If you're using LabelSettings, update it (best quality).
	# Otherwise, theme overrides still work.
	var ls := lab.label_settings
	if ls != null:
		lab.label_settings = ls.duplicate(true)
		ls = lab.label_settings
		ls.font_color = main_c
		if apply_shadow:
			ls.shadow_color = shadow_c
			ls.shadow_offset = Vector2(shadow_offset.x, shadow_offset.y)
			ls.shadow_size = 1

	# Theme overrides (works even without LabelSettings)
	lab.add_theme_color_override("font_color", main_c)
	if apply_shadow:
		lab.add_theme_color_override("font_shadow_color", shadow_c)
		lab.add_theme_constant_override("shadow_offset_x", shadow_offset.x)
		lab.add_theme_constant_override("shadow_offset_y", shadow_offset.y)
