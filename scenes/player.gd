extends Node2D

signal turn_taken(player_grid_pos: Vector2i)

@export var tile_size: int = 16
@export var map_path: NodePath
@export var enemy_path: NodePath
@export var camera_path: NodePath

@export var max_hp: int = 10
@export var damage_min: int = 2
@export var damage_max: int = 3

# Movement feel
@export var move_time: float = 0.10

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
var enemy: Node
var cam: Node

var grid_pos: Vector2i
var hp: int
var _hit_flash_playing: bool = false
var _busy: bool = false

@onready var body: Sprite2D = $Sprite2D

func _ready() -> void:
	map = get_node(map_path) as TileMapLayer
	enemy = get_node_or_null(enemy_path)
	cam = get_node_or_null(camera_path)

	hp = max_hp

	grid_pos = Vector2i(
		round(position.x / tile_size),
		round(position.y / tile_size)
	)
	position = Vector2(grid_pos.x * tile_size, grid_pos.y * tile_size)

	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return

	var dir := Vector2i.ZERO

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

	# Face direction
	if dir.x < 0:
		body.flip_h = true
	elif dir.x > 0:
		body.flip_h = false

	var next := grid_pos + dir

	# --- Bump attack ---
	if enemy != null and enemy.has_method("get_grid_pos") and enemy.has_method("take_damage"):
		var enemy_grid: Vector2i = enemy.get_grid_pos()
		if enemy_grid == next:
			var dmg := randi_range(damage_min, damage_max)
			enemy.take_damage(dmg)

			_do_shake(shake_on_hit_strength)
			await _do_hitstop()

			_busy = false
			turn_taken.emit(grid_pos)
			return

	# --- Movement ---
	if _is_blocked(next):
		_busy = false
		return

	grid_pos = next
	var target_pos := Vector2(grid_pos.x * tile_size, grid_pos.y * tile_size)

	var tw := create_tween()
	tw.tween_property(self, "position", target_pos, move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	_spawn_step_dust(dir)

	_busy = false
	turn_taken.emit(grid_pos)

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
