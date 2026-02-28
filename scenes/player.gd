extends Node2D

signal turn_taken(player_grid_pos: Vector2i)

@export var tile_size: int = 16
@export var map_path: NodePath
@export var enemy_path: NodePath
@export var camera_path: NodePath

@export var max_hp: int = 10
@export var damage_min: int = 2
@export var damage_max: int = 3

@export var move_time: float = 0.10

@export var step_dust_scene: PackedScene
@export var step_dust_offset_y: float = 6.0
@export var step_dust_trail_px: float = 4.0

@export var hp_per_segment: int = 2
@export var hp_bar_offset_y: int = 4
@export var hp_seg_w: int = 3
@export var hp_seg_h: int = 2
@export var hp_seg_gap: int = 1

@export var hit_flash_blinks: int = 2
@export var hit_flash_time: float = 0.05

@export var hitstop_frames: int = 1
@export var shake_on_hit_strength: float = 2.0
@export var shake_on_hurt_strength: float = 1.5
@export var shake_frames: int = 2

# ------------------------------------------------
# Zelda-style edge control (default = open world)
# ------------------------------------------------
@export var edge_transition_requires_door: bool = false
@export var door_custom_key: StringName = &"door"

@export var room_width_px: int = 320
@export var room_height_px: int = 192

@export var empty_cells_are_blocked: bool = false

# ------------------------------------------------
# Hazard tiles (spikes, lava, etc.)
# ------------------------------------------------
@export var hazard_custom_key: StringName = &"hazard"
@export var hazard_damage_key: StringName = &"hazard_damage"
@export var hazard_default_damage: int = 1
@export var hazard_hitstop_frames: int = 1
@export var hazard_shake_strength: float = 1.5

# ------------------------------------------------
# Treasure tiles (HIDDEN + REVEAL)
# ------------------------------------------------
@export var treasure_custom_key: StringName = &"treasure"

# Atlas coords you provided:
@export var treasure_atlas_coords: Vector2i = Vector2i(1, 0)
@export var floor_atlas_coords: Vector2i = Vector2i(2, 0)

# Usually 0; keep exported in case your source id differs
@export var tile_source_id: int = 0

# Reveal radius in tiles
@export var treasure_reveal_radius: int = 3

# ------------------------------------------------
# Exit tile -> Settlement
# ------------------------------------------------
@export var exit_custom_key: StringName = &"exit"
@export var settlement_scene: PackedScene

var map: TileMapLayer
var enemy: Node
var cam: Node

var grid_pos: Vector2i
var hp: int
var _hit_flash_playing: bool = false
var _busy: bool = false

# Hidden treasure positions (stored at start)
var _hidden_treasures: Array[Vector2i] = []

@onready var body: Sprite2D = $Sprite2D


func _ready() -> void:
	map = get_node(map_path) as TileMapLayer
	enemy = get_node_or_null(enemy_path)
	cam = get_node_or_null(camera_path)

	hp = max_hp

	var local_pos: Vector2 = map.to_local(global_position)
	grid_pos = map.local_to_map(local_pos + Vector2(tile_size * 0.5, tile_size * 0.5))
	global_position = map.to_global(map.map_to_local(grid_pos))

	_cache_and_hide_treasures()
	_reveal_treasures_near(grid_pos, treasure_reveal_radius)

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return

	var dir: Vector2i = Vector2i.ZERO

	if event.is_action_pressed("ui_right"):
		dir = Vector2i(1, 0)
	elif event.is_action_pressed("ui_left"):
		dir = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_down"):
		dir = Vector2i(0, 1)
	elif event.is_action_pressed("ui_up"):
		dir = Vector2i(0, -1)

	if dir != Vector2i.ZERO:
		await try_move_or_attack(dir)


func try_move_or_attack(dir: Vector2i) -> void:
	if map == null:
		return

	_busy = true

	if dir.x < 0:
		body.flip_h = true
	elif dir.x > 0:
		body.flip_h = false

	var next: Vector2i = grid_pos + dir

	# --- Bump attack ---
	if enemy != null and enemy.has_method("get_grid_pos") and enemy.has_method("take_damage"):
		var enemy_grid: Vector2i = enemy.get_grid_pos()
		if enemy_grid == next:
			var dmg: int = randi_range(damage_min, damage_max)
			enemy.take_damage(dmg)

			_do_shake(shake_on_hit_strength)
			await _do_hitstop()

			_busy = false
			turn_taken.emit(grid_pos)
			return

	# --- Door requirement only when crossing to a new room ---
	if edge_transition_requires_door and _crosses_room_boundary(grid_pos, next):
		var ok: bool = _is_door(grid_pos) or _is_door(next)
		if not ok:
			_busy = false
			return

	# --- Collision ---
	if _is_blocked(next):
		_busy = false
		return

	# --- Move ---
	grid_pos = next
	var target_global: Vector2 = map.to_global(map.map_to_local(grid_pos))

	var tw: Tween = create_tween()
	tw.tween_property(self, "global_position", target_global, move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	_spawn_step_dust(dir)

	# Reveal before pickup (so treasure becomes visible when close)
	_reveal_treasures_near(grid_pos, treasure_reveal_radius)

	# Hazard + treasure checks
	await _apply_hazard_if_needed(grid_pos)
	_apply_treasure_if_needed(grid_pos)

	# End turn (GameManager debt tick happens here)
	_busy = false
	turn_taken.emit(grid_pos)

	# Exit check (after turn tick so settlement uses updated debt/turn)
	_apply_exit_if_needed(grid_pos)


# ------------------------------------------------
# Treasure: hide + reveal
# ------------------------------------------------
func _cache_and_hide_treasures() -> void:
	_hidden_treasures.clear()

	var cells: Array[Vector2i] = map.get_used_cells()
	for cell in cells:
		var sid: int = map.get_cell_source_id(cell)
		if sid != tile_source_id:
			continue

		var ac: Vector2i = map.get_cell_atlas_coords(cell)
		if ac == treasure_atlas_coords:
			_hidden_treasures.append(cell)
			map.set_cell(cell, tile_source_id, floor_atlas_coords, 0)


func _reveal_treasures_near(center: Vector2i, radius: int) -> void:
	if _hidden_treasures.is_empty():
		return

	var still_hidden: Array[Vector2i] = []
	for pos in _hidden_treasures:
		var dist: int = abs(pos.x - center.x) + abs(pos.y - center.y) # Manhattan
		if dist <= radius:
			map.set_cell(pos, tile_source_id, treasure_atlas_coords, 0)
		else:
			still_hidden.append(pos)

	_hidden_treasures = still_hidden


func _apply_treasure_if_needed(tile: Vector2i) -> void:
	var td: TileData = map.get_cell_tile_data(tile)
	if td == null:
		return

	var is_treasure: bool = bool(td.get_custom_data(treasure_custom_key))
	if not is_treasure:
		return

	var value: int = GameManager.roll_treasure_value()
	GameManager.found_treasure(value)

	# Replace with normal floor after pickup
	map.set_cell(tile, tile_source_id, floor_atlas_coords, 0)


# ------------------------------------------------
# Exit -> Settlement
# ------------------------------------------------
func _apply_exit_if_needed(tile: Vector2i) -> void:
	var td: TileData = map.get_cell_tile_data(tile)
	if td == null:
		return

	var is_exit: bool = bool(td.get_custom_data(exit_custom_key))
	if not is_exit:
		return

	if settlement_scene != null:
		get_tree().change_scene_to_packed(settlement_scene)


# ------------------------------------------------
# Existing helpers
# ------------------------------------------------
func _crosses_room_boundary(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	var room_w_tiles: int = maxi(1, int(floor(float(room_width_px) / float(tile_size))))
	var room_h_tiles: int = maxi(1, int(floor(float(room_height_px) / float(tile_size))))

	var from_room := Vector2i(
		int(floor(float(from_tile.x) / float(room_w_tiles))),
		int(floor(float(from_tile.y) / float(room_h_tiles)))
	)
	var to_room := Vector2i(
		int(floor(float(to_tile.x) / float(room_w_tiles))),
		int(floor(float(to_tile.y) / float(room_h_tiles)))
	)
	return from_room != to_room


func _is_blocked(tile: Vector2i) -> bool:
	var td: TileData = map.get_cell_tile_data(tile)
	if td == null:
		return empty_cells_are_blocked
	return bool(td.get_custom_data("blocked"))


func _is_door(tile: Vector2i) -> bool:
	var td: TileData = map.get_cell_tile_data(tile)
	if td == null:
		return false
	return bool(td.get_custom_data(door_custom_key))


func _apply_hazard_if_needed(tile: Vector2i) -> void:
	var td: TileData = map.get_cell_tile_data(tile)
	if td == null:
		return

	var is_hazard: bool = bool(td.get_custom_data(hazard_custom_key))
	if not is_hazard:
		return

	var dmg: int = hazard_default_damage
	var raw = td.get_custom_data(hazard_damage_key)
	if typeof(raw) == TYPE_INT:
		dmg = int(raw)

	take_damage(dmg)

	_do_shake(hazard_shake_strength)
	var frames: int = maxi(1, hazard_hitstop_frames)
	for _i in range(frames):
		await get_tree().process_frame


func get_grid_pos() -> Vector2i:
	return grid_pos


func _spawn_step_dust(move_dir: Vector2i) -> void:
	if step_dust_scene == null:
		return

	var d: Node2D = step_dust_scene.instantiate() as Node2D
	get_parent().add_child(d)

	var behind: Vector2 = Vector2(-move_dir.x, -move_dir.y) * step_dust_trail_px
	var feet: Vector2 = Vector2(0.0, step_dust_offset_y)
	var spawn_pos: Vector2 = global_position + feet + behind

	if d.has_method("setup"):
		d.setup(spawn_pos)
	else:
		d.global_position = spawn_pos


func take_damage(amount: int) -> void:
	hp -= amount
	hp = max(hp, 0)

	queue_redraw()
	_play_hit_flash()

	_do_shake(shake_on_hurt_strength)
	await _do_hitstop()

	if hp <= 0:
		queue_free()


func _do_shake(strength: float) -> void:
	if cam != null and cam.has_method("shake"):
		cam.shake(strength, shake_frames)


func _do_hitstop() -> void:
	for _i in range(maxi(1, hitstop_frames)):
		await get_tree().process_frame


func _play_hit_flash() -> void:
	if body == null or _hit_flash_playing:
		return
	_hit_flash_playing = true

	var original_modulate: Color = body.modulate

	for _i in range(hit_flash_blinks):
		body.modulate = Color(1, 1, 1, 1)
		await get_tree().create_timer(hit_flash_time).timeout
		body.modulate = Color(1, 1, 1, 0.2)
		await get_tree().create_timer(hit_flash_time).timeout

	body.modulate = original_modulate
	_hit_flash_playing = false


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
