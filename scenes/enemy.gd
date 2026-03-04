extends Node2D

@export var tile_size: int = 16
@export var map_path: NodePath
@export var player_path: NodePath
@export var camera_path: NodePath

@export var max_hp: int = 6
@export var damage_min: int = 1
@export var damage_max: int = 2

@export var move_time: float = 0.10

# Telegraph (enemy "leans" before hitting)
@export var telegraph_damage_bonus: int = 1
@export var telegraph_lean_px: int = 3
@export var telegraph_lean_time: float = 0.08

# Step dust
@export var step_dust_scene: PackedScene
@export var step_dust_offset_y: float = 6.0
@export var step_dust_trail_px: float = 4.0

# HP bar
@export var hp_per_segment: int = 2
@export var hp_bar_offset_y: int = 4
@export var hp_seg_w: int = 3
@export var hp_seg_h: int = 2
@export var hp_seg_gap: int = 1

# Pressure after treasure (1 extra turn => total 2 turns)
@export var extra_turns_when_player_has_treasure: int = 1

# Palette preset for this enemy. Leave blank to randomize.
@export var enemy_palette_preset: StringName = &""
const RANDOM_ENEMY_PALETTES: PackedStringArray = [
	"SLIME",
	"BLOOD",
	"ICE",
	"NEON",
	"SAND",
	"VOID",
]


var map: TileMapLayer
var player: Node
var cam: Node

var grid_pos: Vector2i
var hp: int

var _telegraphing: bool = false
var _telegraph_dir: Vector2i = Vector2i.ZERO

@onready var body: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("enemies")
	randomize()

	_resolve_refs()

	# If we still can't find the map, we can't function safely.
	if map == null:
		push_warning("Enemy has no map reference. Check map_path or scene structure.")
		queue_free()
		return

	hp = max_hp

	_apply_palette_to_enemy()

	# Snap to grid
	var local_pos: Vector2 = map.to_local(global_position)
	grid_pos = map.local_to_map(local_pos + Vector2(float(tile_size) * 0.5, float(tile_size) * 0.5))
	global_position = map.to_global(map.map_to_local(grid_pos))

	# Auto-connect to player turn signal
	if player != null and player.has_signal("turn_taken"):
		var c := Callable(self, "_on_player_turn_taken")
		if not player.is_connected("turn_taken", c):
			player.connect("turn_taken", c)

	queue_redraw()

func _apply_palette_to_enemy() -> void:
	# PaletteManager must be an Autoload singleton named "PaletteManager".
	# Applies to this enemy's Sprite2D material (if it uses the 2-tone palette shader).
	if body == null:
		return
	var preset: StringName = enemy_palette_preset
	if String(preset) == "":
		var n: int = RANDOM_ENEMY_PALETTES.size()
		if n <= 0:
			return
		var idx: int = int(randi() % n)
		preset = StringName(String(RANDOM_ENEMY_PALETTES[idx]))
	PaletteManager.apply_to_sprite(body, preset)


func _resolve_refs() -> void:
	# --- MAP ---
	map = null
	if map_path != NodePath("") and str(map_path) != "":
		map = get_node_or_null(map_path) as TileMapLayer
	if map == null:
		map = _find_tilemaplayer()

	# --- PLAYER ---
	player = null
	if player_path != NodePath("") and str(player_path) != "":
		player = get_node_or_null(player_path)
	if player == null:
		player = _find_node_named_upwards("Player")

	# --- CAMERA ---
	cam = null
	if camera_path != NodePath("") and str(camera_path) != "":
		cam = get_node_or_null(camera_path)
	if cam == null:
		cam = _find_camera2d_upwards()


func _find_tilemaplayer() -> TileMapLayer:
	var n: Node = get_parent()
	while n != null:
		for child in n.get_children():
			if child is TileMapLayer:
				return child as TileMapLayer
		n = n.get_parent()
	return null


func _find_node_named_upwards(name: StringName) -> Node:
	# Check parents for a sibling/child with this name
	var n: Node = get_parent()
	while n != null:
		var found: Node = n.get_node_or_null(NodePath(String(name)))
		if found != null:
			return found
		n = n.get_parent()

	# Last resort: global search
	var root: Node = get_tree().get_root()
	return root.find_child(String(name), true, false)


func _find_camera2d_upwards() -> Node:
	var n: Node = get_parent()
	while n != null:
		for child in n.get_children():
			if child is Camera2D:
				return child
			# common setup: Camera2D under Player
			if child.name == "Player":
				var cam2: Node = child.find_child("Camera2D", true, false)
				if cam2 != null:
					return cam2
		n = n.get_parent()

	return get_tree().get_root().find_child("Camera2D", true, false)


func _on_player_turn_taken(player_grid_pos: Vector2i) -> void:
	await take_turn(player_grid_pos)

	if GameManager.has_treasure and extra_turns_when_player_has_treasure > 0:
		for _i in range(extra_turns_when_player_has_treasure):
			await take_turn(player_grid_pos)


func take_turn(player_grid_pos: Vector2i) -> void:
	if player == null or map == null:
		return

	# Telegraph follow-up
	if _telegraphing:
		if _manhattan(grid_pos, player_grid_pos) == 1:
			if player.has_method("take_damage"):
				var dmg: int = randi_range(damage_min, damage_max) + telegraph_damage_bonus
				player.take_damage(dmg)
		_end_telegraph()
		return

	# Begin telegraph when adjacent
	if _manhattan(grid_pos, player_grid_pos) == 1:
		_begin_telegraph(player_grid_pos)
		return

	# Chase
	var step: Vector2i = _choose_step_toward(player_grid_pos)
	if step == Vector2i.ZERO:
		return

	if step.x < 0:
		body.flip_h = true
	elif step.x > 0:
		body.flip_h = false

	var next: Vector2i = grid_pos + step
	if _is_blocked(next):
		var alt: Vector2i = _choose_step_toward(player_grid_pos, true)
		if alt != Vector2i.ZERO and not _is_blocked(grid_pos + alt):
			step = alt
			next = grid_pos + step
		else:
			return

	grid_pos = next
	var target_global: Vector2 = map.to_global(map.map_to_local(grid_pos))

	var tw := create_tween()
	tw.tween_property(self, "global_position", target_global, move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	_spawn_step_dust(step)


func _choose_step_toward(target: Vector2i, force_other_axis: bool = false) -> Vector2i:
	var dx: int = target.x - grid_pos.x
	var dy: int = target.y - grid_pos.y

	if not force_other_axis:
		if abs(dx) > abs(dy):
			return Vector2i(sign(dx), 0)
		elif abs(dy) > abs(dx):
			return Vector2i(0, sign(dy))
		else:
			return Vector2i(sign(dx), 0) if randi() % 2 == 0 else Vector2i(0, sign(dy))
	else:
		if abs(dx) >= abs(dy):
			return Vector2i(0, sign(dy))
		else:
			return Vector2i(sign(dx), 0)


func _begin_telegraph(player_grid_pos: Vector2i) -> void:
	_telegraphing = true

	var dx: int = player_grid_pos.x - grid_pos.x
	var dy: int = player_grid_pos.y - grid_pos.y

	if abs(dx) > abs(dy):
		_telegraph_dir = Vector2i(sign(dx), 0)
	elif abs(dy) > abs(dx):
		_telegraph_dir = Vector2i(0, sign(dy))
	else:
		_telegraph_dir = Vector2i(sign(dx), 0) if randi() % 2 == 0 else Vector2i(0, sign(dy))

	var target := Vector2(float(_telegraph_dir.x * telegraph_lean_px), float(_telegraph_dir.y * telegraph_lean_px))
	var tw := create_tween()
	tw.tween_property(body, "position", target, telegraph_lean_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _end_telegraph() -> void:
	_telegraphing = false
	var tw := create_tween()
	tw.tween_property(body, "position", Vector2.ZERO, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _is_blocked(tile: Vector2i) -> bool:
	if map == null:
		return true
	var td: TileData = map.get_cell_tile_data(tile)
	if td == null:
		return true
	return bool(td.get_custom_data("blocked"))


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _spawn_step_dust(move_dir: Vector2i) -> void:
	if step_dust_scene == null:
		return

	var d := step_dust_scene.instantiate() as Node2D
	get_parent().add_child(d)

	var behind := Vector2(-float(move_dir.x), -float(move_dir.y)) * step_dust_trail_px
	var feet := Vector2(0.0, step_dust_offset_y)
	var spawn_pos := global_position + feet + behind

	if d.has_method("setup"):
		d.setup(spawn_pos)
	else:
		d.global_position = spawn_pos


func take_damage(amount: int) -> void:
	hp -= amount
	hp = max(hp, 0)
	queue_redraw()
	if hp <= 0:
		queue_free()


func get_grid_pos() -> Vector2i:
	return grid_pos


func _draw() -> void:
	var total_segments: int = int(ceil(float(max_hp) / float(hp_per_segment)))
	var filled_segments: int = int(ceil(float(hp) / float(hp_per_segment)))

	var gaps: int = maxi(0, total_segments - 1)
	var total_w: float = float(total_segments * hp_seg_w + gaps * hp_seg_gap)

	var sprite_top: float = -8.0
	var bar_y: float = sprite_top - float(hp_bar_offset_y) - float(hp_seg_h)
	var start_x: float = -total_w * 0.5

	for i in range(total_segments):
		var x: float = start_x + float(i * (hp_seg_w + hp_seg_gap))
		var col: Color = Color(0.35, 0.35, 0.35, 1)
		if i < filled_segments:
			col = Color(1, 1, 1, 1)
		draw_rect(Rect2(Vector2(x, bar_y), Vector2(float(hp_seg_w), float(hp_seg_h))), col, true)
