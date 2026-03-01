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

	map = get_node(map_path) as TileMapLayer
	player = get_node_or_null(player_path)
	cam = get_node_or_null(camera_path)

	hp = max_hp

	# Snap to grid
	var local_pos := map.to_local(global_position)
	grid_pos = map.local_to_map(local_pos + Vector2(tile_size * 0.5, tile_size * 0.5))
	global_position = map.to_global(map.map_to_local(grid_pos))

	# Auto-connect to player turn signal
	if player != null and player.has_signal("turn_taken"):
		var c := Callable(self, "_on_player_turn_taken")
		if not player.is_connected("turn_taken", c):
			player.connect("turn_taken", c)

	randomize()
	queue_redraw()


func _on_player_turn_taken(player_grid_pos: Vector2i) -> void:
	await take_turn(player_grid_pos)

	# Extra pressure after treasure pickup
	if GameManager.has_treasure and extra_turns_when_player_has_treasure > 0:
		for _i in range(extra_turns_when_player_has_treasure):
			await take_turn(player_grid_pos)


func take_turn(player_grid_pos: Vector2i) -> void:
	if player == null:
		return

	# Telegraph follow-up
	if _telegraphing:
		if _manhattan(grid_pos, player_grid_pos) == 1:
			if player.has_method("take_damage"):
				var dmg := randi_range(damage_min, damage_max) + telegraph_damage_bonus
				player.take_damage(dmg)
		_end_telegraph()
		return

	# Begin telegraph when adjacent
	if _manhattan(grid_pos, player_grid_pos) == 1:
		_begin_telegraph(player_grid_pos)
		return

	# Chase
	var step := _choose_step_toward(player_grid_pos)
	if step == Vector2i.ZERO:
		return

	if step.x < 0:
		body.flip_h = true
	elif step.x > 0:
		body.flip_h = false

	var next := grid_pos + step
	if _is_blocked(next):
		var alt := _choose_step_toward(player_grid_pos, true)
		if alt != Vector2i.ZERO and not _is_blocked(grid_pos + alt):
			step = alt
			next = grid_pos + step
		else:
			return

	grid_pos = next
	var target_global := map.to_global(map.map_to_local(grid_pos))

	var tw := create_tween()
	tw.tween_property(self, "global_position", target_global, move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	_spawn_step_dust(step)


func _choose_step_toward(target: Vector2i, force_other_axis: bool = false) -> Vector2i:
	var dx := target.x - grid_pos.x
	var dy := target.y - grid_pos.y

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

	var dx := player_grid_pos.x - grid_pos.x
	var dy := player_grid_pos.y - grid_pos.y

	if abs(dx) > abs(dy):
		_telegraph_dir = Vector2i(sign(dx), 0)
	elif abs(dy) > abs(dx):
		_telegraph_dir = Vector2i(0, sign(dy))
	else:
		_telegraph_dir = Vector2i(sign(dx), 0) if randi() % 2 == 0 else Vector2i(0, sign(dy))

	var target := Vector2(_telegraph_dir.x * telegraph_lean_px, _telegraph_dir.y * telegraph_lean_px)
	var tw := create_tween()
	tw.tween_property(body, "position", target, telegraph_lean_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _end_telegraph() -> void:
	_telegraphing = false
	var tw := create_tween()
	tw.tween_property(body, "position", Vector2.ZERO, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _is_blocked(tile: Vector2i) -> bool:
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

	var behind := Vector2(-move_dir.x, -move_dir.y) * step_dust_trail_px
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
