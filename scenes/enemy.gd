extends Node2D

@export var tile_size: int = 16
@export var map_path: NodePath
@export var player_path: NodePath
@export var camera_path: NodePath

@export var max_hp: int = 6
@export var damage_min: int = 1
@export var damage_max: int = 2

@export var move_time: float = 0.10

# Telegraph
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

# Hit flash
@export var hit_flash_blinks: int = 2
@export var hit_flash_time: float = 0.05

# Hitstop + shake
@export var hitstop_frames: int = 1
@export var shake_on_hit_strength: float = 2.0
@export var shake_on_hurt_strength: float = 1.5
@export var shake_frames: int = 2

var map: TileMapLayer
var player: Node
var cam: Node

var grid_pos: Vector2i
var hp: int
var _hit_flash_playing: bool = false

var _telegraphing: bool = false
var _telegraph_dir: Vector2i = Vector2i.ZERO

@onready var body: Sprite2D = $Sprite2D

func _ready() -> void:
	map = get_node(map_path) as TileMapLayer
	player = get_node_or_null(player_path)
	cam = get_node_or_null(camera_path)

	hp = max_hp

	grid_pos = Vector2i(
		round(position.x / tile_size),
		round(position.y / tile_size)
	)
	position = Vector2(grid_pos.x * tile_size, grid_pos.y * tile_size)

	randomize()
	queue_redraw()

func take_turn(player_grid_pos: Vector2i) -> void:
	if player == null:
		return

	if _telegraphing:
		if _manhattan(grid_pos, player_grid_pos) == 1:
			var dmg := randi_range(damage_min, damage_max) + telegraph_damage_bonus
			player.take_damage(dmg)
			_do_shake(shake_on_hit_strength)
			await _do_hitstop()
			_end_telegraph()
			return
		else:
			_end_telegraph()

	if _manhattan(grid_pos, player_grid_pos) == 1:
		_begin_telegraph(player_grid_pos)
		return

	var step := _choose_step_toward(player_grid_pos)
	if step == Vector2i.ZERO:
		return

	if step.x < 0:
		body.flip_h = true
	elif step.x > 0:
		body.flip_h = false

	var next := grid_pos + step
	if _is_blocked(next):
		return

	grid_pos = next
	var target_pos := Vector2(grid_pos.x * tile_size, grid_pos.y * tile_size)

	var tw := create_tween()
	tw.tween_property(self, "position", target_pos, move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	_spawn_step_dust(step)

func _spawn_step_dust(move_dir: Vector2i) -> void:
	if step_dust_scene == null:
		return

	var d := step_dust_scene.instantiate() as Node2D
	get_parent().add_child(d)

	var behind := Vector2(-move_dir.x, -move_dir.y) * step_dust_trail_px
	var feet := Vector2(0.0, step_dust_offset_y)
	var spawn_pos := global_position + feet + behind

	if d.has_method("setup"):
		d.setup(spawn_pos)
	else:
		d.global_position = spawn_pos

func _begin_telegraph(player_grid_pos: Vector2i) -> void:
	_telegraphing = true
	var dx := player_grid_pos.x - grid_pos.x
	var dy := player_grid_pos.y - grid_pos.y

	if abs(dx) > abs(dy):
		_telegraph_dir = Vector2i(sign(dx), 0)
	elif abs(dy) > abs(dx):
		_telegraph_dir = Vector2i(0, sign(dy))
	else:
		if randi() % 2 == 0:
			_telegraph_dir = Vector2i(sign(dx), 0)
		else:
			_telegraph_dir = Vector2i(0, sign(dy))

	var target := Vector2(_telegraph_dir.x * telegraph_lean_px, _telegraph_dir.y * telegraph_lean_px)
	var tw := create_tween()
	tw.tween_property(body, "position", target, telegraph_lean_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _end_telegraph() -> void:
	_telegraphing = false
	var tw := create_tween()
	tw.tween_property(body, "position", Vector2.ZERO, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _choose_step_toward(target: Vector2i) -> Vector2i:
	var dx := target.x - grid_pos.x
	var dy := target.y - grid_pos.y

	if abs(dx) > abs(dy):
		return Vector2i(sign(dx), 0)
	elif abs(dy) > abs(dx):
		return Vector2i(0, sign(dy))
	else:
		if randi() % 2 == 0:
			return Vector2i(sign(dx), 0)
		else:
			return Vector2i(0, sign(dy))

func _is_blocked(tile: Vector2i) -> bool:
	var world_pos := Vector2(tile.x * tile_size, tile.y * tile_size)
	var cell := map.local_to_map(world_pos)
	var td: TileData = map.get_cell_tile_data(cell)

	if td == null:
		return true

	var blocked_val = td.get_custom_data("blocked")
	if blocked_val == null:
		return false

	return bool(blocked_val)

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
	for _i in range(hit_flash_blinks):
		body.visible = false
		await get_tree().create_timer(hit_flash_time).timeout
		body.visible = true
		await get_tree().create_timer(hit_flash_time).timeout
	_hit_flash_playing = false

func get_grid_pos() -> Vector2i:
	return grid_pos

func _on_player_turn_taken(player_grid_pos: Vector2i) -> void:
	await take_turn(player_grid_pos)

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
		var col := Color(1,1,1,1) if i < filled_segments else Color(0.35,0.35,0.35,1)
		draw_rect(Rect2(Vector2(x, bar_y), Vector2(hp_seg_w, hp_seg_h)), col, true)
