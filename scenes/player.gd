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

# Swing shake (even on miss) - boosted defaults
@export var shake_on_swing_strength: float = 4.0
@export var shake_on_swing_frames: int = 8

@export var edge_transition_requires_door: bool = false
@export var door_custom_key: StringName = &"door"

@export var room_width_px: int = 320
@export var room_height_px: int = 192

@export var empty_cells_are_blocked: bool = false

@export var hazard_custom_key: StringName = &"hazard"
@export var hazard_damage_key: StringName = &"hazard_damage"
@export var hazard_default_damage: int = 1
@export var hazard_hitstop_frames: int = 1
@export var hazard_shake_strength: float = 1.5

@export var treasure_custom_key: StringName = &"treasure"
@export var treasure_atlas_coords: Vector2i = Vector2i(1, 0)
@export var floor_atlas_coords: Vector2i = Vector2i(2, 0)
@export var tile_source_id: int = 0
@export var treasure_reveal_radius: int = 3

@export var exit_custom_key: StringName = &"exit"
@export var settlement_scene: PackedScene
@export var death_delay_sec: float = 0.30

@export var potion_heal_amount: int = 3

# ----------------------------
# Manual swing settings
# ----------------------------
@export var manual_swing_bonus_damage: int = 1
@export var swing_time: float = 0.08
@export var swing_return_time: float = 0.06
@export var swing_degrees: float = 65.0

# ----------------------------
# Sword swoosh + hit spark
# ----------------------------
@export var sword_swoosh_scene: PackedScene
@export var hit_spark_scene: PackedScene

var map: TileMapLayer
var enemy: Node
var cam: Node

var grid_pos: Vector2i
var hp: int
var _hit_flash_playing: bool = false
var _busy: bool = false
var _dead: bool = false

var _hidden_treasures: Array[Vector2i] = []

# Loadout effects
var _attack_bonus: int = 0
var _hazard_reduction: int = 0
var _potion_charges: int = 0

# Equipped state + facing
var _has_sword: bool = false
var _facing: Vector2i = Vector2i(1, 0) # default face right

@onready var visual: Node2D = $Visual
@onready var body: Sprite2D = $Visual/Body
@onready var hand_socket: Marker2D = $Visual/HandSocket
@onready var sword_sprite: Sprite2D = $Visual/HandSocket/SwordSprite
@onready var sword_tip: Marker2D = $Visual/HandSocket/SwordTip


func _ready() -> void:
	map = get_node(map_path) as TileMapLayer
	enemy = get_node_or_null(enemy_path)
	cam = get_node_or_null(camera_path)

	hp = max_hp
	_apply_loadout_from_shop()

	var local_pos: Vector2 = map.to_local(global_position)
	grid_pos = map.local_to_map(local_pos + Vector2(tile_size * 0.5, tile_size * 0.5))
	global_position = map.to_global(map.map_to_local(grid_pos))

	_cache_and_hide_treasures()
	_reveal_treasures_near(grid_pos, treasure_reveal_radius)

	queue_redraw()


func _apply_loadout_from_shop() -> void:
	_attack_bonus = 0
	_hazard_reduction = 0
	_potion_charges = 0
	_has_sword = false

	if sword_sprite != null:
		sword_sprite.visible = false

	if GameManager.shop_item_id == 1:
		_attack_bonus = 1
		_has_sword = true
		if sword_sprite != null:
			sword_sprite.visible = true
	elif GameManager.shop_item_id == 2:
		_hazard_reduction = 1
	elif GameManager.shop_item_id == 3:
		_potion_charges = 1


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _dead:
		return

	if event.is_action_pressed("ui_accept"):
		await _try_manual_swing()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var kc: Key = (event as InputEventKey).keycode
		if kc == KEY_H:
			await _try_use_potion()
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


func _try_manual_swing() -> void:
	if not _has_sword:
		return

	_busy = true

	# Visible shake even on miss
	if cam != null and cam.has_method("shake"):
		cam.shake(shake_on_swing_strength, shake_on_swing_frames)

	# Swoosh even on miss
	if sword_swoosh_scene != null and sword_tip != null:
		var swoosh := sword_swoosh_scene.instantiate()
		get_parent().add_child(swoosh)
		if swoosh.has_method("start"):
			swoosh.start(sword_tip)

	await _do_swing_anim()

	var target_tile: Vector2i = grid_pos + _facing

	var hit: bool = false
	if enemy != null and enemy.has_method("get_grid_pos") and enemy.has_method("take_damage"):
		var enemy_grid: Vector2i = enemy.get_grid_pos()
		if enemy_grid == target_tile:
			var dmg: int = randi_range(damage_min, damage_max) + _attack_bonus + manual_swing_bonus_damage
			enemy.take_damage(dmg)
			hit = true

			_spawn_hit_spark(enemy.global_position)

	if hit:
		_do_shake(shake_on_hit_strength)
		await _do_hitstop()

	_busy = false
	turn_taken.emit(grid_pos)


func _spawn_hit_spark(at_global: Vector2) -> void:
	if hit_spark_scene == null:
		return
	var sp := hit_spark_scene.instantiate() as Node2D
	get_parent().add_child(sp)
	sp.global_position = at_global


func _do_swing_anim() -> void:
	if hand_socket == null:
		return

	hand_socket.rotation_degrees = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(hand_socket, "rotation_degrees", swing_degrees, swing_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(hand_socket, "rotation_degrees", 0.0, swing_return_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished


func _try_use_potion() -> void:
	if _potion_charges <= 0:
		return
	if hp >= max_hp:
		return

	_busy = true
	hp = min(max_hp, hp + potion_heal_amount)
	_potion_charges -= 1
	queue_redraw()
	_busy = false
	turn_taken.emit(grid_pos)


func try_move_or_attack(dir: Vector2i) -> void:
	if map == null or _dead:
		return

	_busy = true
	_facing = dir

	if dir.x < 0:
		visual.scale.x = -1.0
	elif dir.x > 0:
		visual.scale.x = 1.0

	var next: Vector2i = grid_pos + dir

	# Bump attack (quick jab)
	if enemy != null and enemy.has_method("get_grid_pos") and enemy.has_method("take_damage"):
		var enemy_grid: Vector2i = enemy.get_grid_pos()
		if enemy_grid == next:
			var dmg: int = randi_range(damage_min, damage_max) + _attack_bonus
			enemy.take_damage(dmg)

			_spawn_hit_spark(enemy.global_position)

			_do_shake(shake_on_hit_strength)
			await _do_hitstop()

			_busy = false
			turn_taken.emit(grid_pos)
			return

	# Door check crossing rooms
	if edge_transition_requires_door and _crosses_room_boundary(grid_pos, next):
		var ok: bool = _is_door(grid_pos) or _is_door(next)
		if not ok:
			_busy = false
			return

	# Collision
	if _is_blocked(next):
		_busy = false
		return

	# Move
	grid_pos = next
	var target_global: Vector2 = map.to_global(map.map_to_local(grid_pos))

	var tw: Tween = create_tween()
	tw.tween_property(self, "global_position", target_global, move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	_spawn_step_dust(dir)
	_reveal_treasures_near(grid_pos, treasure_reveal_radius)

	await _apply_hazard_if_needed(grid_pos)
	_apply_treasure_if_needed(grid_pos)

	_busy = false
	turn_taken.emit(grid_pos)
	_apply_exit_if_needed(grid_pos)


# ----------------------------
# Treasure hide/reveal
# ----------------------------
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
		var dist: int = abs(pos.x - center.x) + abs(pos.y - center.y)
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
	map.set_cell(tile, tile_source_id, floor_atlas_coords, 0)


# ----------------------------
# Exit / Settlement
# ----------------------------
func _apply_exit_if_needed(tile: Vector2i) -> void:
	var td: TileData = map.get_cell_tile_data(tile)
	if td == null:
		return
	var is_exit: bool = bool(td.get_custom_data(exit_custom_key))
	if not is_exit:
		return

	if not GameManager.has_treasure:
		GameManager.death_reason = "flee"
	else:
		GameManager.death_reason = "none"

	if settlement_scene != null:
		get_tree().change_scene_to_packed(settlement_scene)


# ----------------------------
# Helpers / hazard / dust / death / draw
# ----------------------------
func _crosses_room_boundary(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	var room_w_tiles: int = maxi(1, int(floor(float(room_width_px) / float(tile_size))))
	var room_h_tiles: int = maxi(1, int(floor(float(room_height_px) / float(tile_size))))
	var from_room := Vector2i(int(floor(float(from_tile.x) / float(room_w_tiles))), int(floor(float(from_tile.y) / float(room_h_tiles))))
	var to_room := Vector2i(int(floor(float(to_tile.x) / float(room_w_tiles))), int(floor(float(to_tile.y) / float(room_h_tiles))))
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
	if _dead:
		return

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

	dmg = max(0, dmg - _hazard_reduction)
	if dmg <= 0:
		return

	_do_shake(hazard_shake_strength)

	var frames: int = maxi(1, hazard_hitstop_frames)
	var tree := get_tree()
	if tree != null:
		for _i in range(frames):
			await tree.process_frame

	await take_damage(dmg)


func _do_hitstop() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for _i in range(maxi(1, hitstop_frames)):
		await tree.process_frame


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
	if _dead:
		return

	hp -= amount
	hp = max(hp, 0)

	queue_redraw()
	_play_hit_flash()

	_do_shake(shake_on_hurt_strength)
	await _do_hitstop()

	if hp <= 0:
		await _die_hp()


func _die_hp() -> void:
	if _dead:
		return
	_dead = true
	_busy = true

	GameManager.death_reason = "hp"
	await get_tree().create_timer(death_delay_sec).timeout

	if settlement_scene != null:
		get_tree().change_scene_to_packed(settlement_scene)


func _do_shake(strength: float) -> void:
	if cam != null and cam.has_method("shake"):
		cam.shake(strength, shake_frames)


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
