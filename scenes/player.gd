extends Node2D

signal turn_taken(player_grid_pos: Vector2i)

@export var tile_size: int = 16
@export var map_path: NodePath
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

# Swing shake (even on miss)
@export var shake_on_swing_strength: float = 4.0
@export var shake_on_swing_frames: int = 8

# Zelda-style edge control (optional)
@export var edge_transition_requires_door: bool = false
@export var door_custom_key: StringName = &"door"
@export var room_width_px: int = 320
@export var room_height_px: int = 192

@export var empty_cells_are_blocked: bool = false

# Hazard tiles
@export var hazard_custom_key: StringName = &"hazard"
@export var hazard_damage_key: StringName = &"hazard_damage"
@export var hazard_default_damage: int = 1
@export var hazard_hitstop_frames: int = 1
@export var hazard_shake_strength: float = 1.5

# Treasure (hidden + reveal)
@export var treasure_custom_key: StringName = &"treasure"
@export var treasure_atlas_coords: Vector2i = Vector2i(1, 0)
@export var floor_atlas_coords: Vector2i = Vector2i(2, 0)
@export var tile_source_id: int = 0
@export var treasure_reveal_radius: int = 3

# Random treasure + clue
@export var randomize_treasure_each_run: bool = true
@export var run_start_clue_enabled: bool = true
@export var run_start_clue_duration_sec: float = 2.8

# Random exit each run (visible)
@export var randomize_exit_each_run: bool = true

# Fair randomness
@export var placement_attempts: int = 200
@export var min_treasure_dist_from_player: int = 10
@export var min_exit_dist_from_player: int = 8
@export var min_exit_dist_from_treasure: int = 8

# Landmark system
@export var landmark_enabled: bool = true
@export var landmark_custom_key: StringName = &"landmark"
@export var landmark_name_custom_key: StringName = &"land_mark_name"
@export var landmark_treasure_max_dist: int = 6
@export var landmark_treasure_min_dist: int = 2
@export var min_landmark_dist_from_player: int = 10
@export var min_landmark_dist_from_exit: int = 4

# NEW: clue readability preference
@export var landmark_axis_aligned_chance_percent: int = 60

# Procgen source of truth
@export var procgen_use_mapgenerator_results: bool = true

# Exit -> Settlement
@export var exit_custom_key: StringName = &"exit"
@export var settlement_scene: PackedScene
@export var death_delay_sec: float = 0.30

# Exit spin juice
@export var exit_spin_enabled: bool = true
@export var exit_spin_flips: int = 10
@export var exit_spin_interval_sec: float = 0.05
@export var exit_spin_bob_px: float = 1.0

# Potion
@export var potion_heal_amount: int = 3

# Manual sword swing
@export var manual_swing_bonus_damage: int = 1
@export var swing_time: float = 0.08
@export var swing_return_time: float = 0.06
@export var swing_degrees: float = 65.0

# Swoosh + spark
@export var sword_swoosh_scene: PackedScene
@export var hit_spark_scene: PackedScene

# Extraction Mode UI + Exit blink
@export var toast_label_path: NodePath
@export var toast_duration_sec: float = 1.2
@export var exit_blink_enabled: bool = true
@export var exit_blink_period_sec: float = 0.25

# Palette (2-tone shader via PaletteManager)
@export var apply_player_palette_on_ready: bool = true
@export var player_palette_preset: StringName = &"BONE"

var map: TileMapLayer
var cam: Node

var grid_pos: Vector2i
var hp: int
var _hit_flash_playing: bool = false
var _busy: bool = false
var _turn_locked: bool = false
var _dead: bool = false
var _exiting: bool = false

var _hidden_treasures: Array[Vector2i] = []

# Exit tiles cache for blinking (also used for exit logic)
var _exit_tiles: Array[Dictionary] = []
var _exit_blink_running: bool = false
var _exit_blink_show_exit: bool = true

# Run placement memory (fair randomness)
var _run_exit_pos: Vector2i = Vector2i(999999, 999999)
var _run_treasure_pos: Vector2i = Vector2i(999999, 999999)

# Landmark memory
var _run_landmark_pos: Vector2i = Vector2i(999999, 999999)
var _run_landmark_name: String = ""

# Procgen cells written by MapGenerator.gd
var procgen_spawn_cell: Vector2i = Vector2i(999999, 999999)
var procgen_treasure_cell: Vector2i = Vector2i(999999, 999999)
var procgen_exit_cell: Vector2i = Vector2i(999999, 999999)
var procgen_clue_landmark_cell: Vector2i = Vector2i(999999, 999999)
var procgen_has_clue_landmark: bool = false

# Toast
var _toast_label: Label
var _toast_token: int = 0

# Loadout effects
var _attack_bonus: int = 0
var _hazard_reduction: int = 0
var _potion_charges: int = 0

# Equipped state + facing
var _has_sword: bool = false
var _facing: Vector2i = Vector2i(1, 0)

@onready var visual: Node2D = $Visual
@onready var body: Sprite2D = $Visual/Body
@onready var hand_socket: Marker2D = $Visual/HandSocket
@onready var sword_sprite: Sprite2D = $Visual/HandSocket/SwordSprite
@onready var sword_tip: Marker2D = $Visual/HandSocket/SwordTip


func _ready() -> void:
	randomize()

	map = get_node(map_path) as TileMapLayer
	cam = get_node_or_null(camera_path)

	_toast_label = get_node_or_null(toast_label_path) as Label
	_clear_toast()

	hp = max_hp
	_apply_loadout_from_shop()
	_apply_player_palette_if_needed()

	# Snap player to grid as a safe fallback before procgen handoff.
	var local_pos: Vector2 = map.to_local(global_position)
	grid_pos = map.local_to_map(local_pos + Vector2(float(tile_size) * 0.5, float(tile_size) * 0.5))
	global_position = map.to_global(map.map_to_local(grid_pos))

	# Preferred path: MapGenerator already chose spawn / treasure / exit / clue landmark.
	if _apply_procgen_source_of_truth():
		_cache_exit_tiles()

		if run_start_clue_enabled and _run_treasure_pos.x < 900000:
			if _run_landmark_pos.x < 900000 and _run_landmark_name != "":
				_show_landmark_direction_clue()
			else:
				_show_run_start_clue(_run_treasure_pos)

		_cache_and_hide_treasures()
		_reveal_treasures_near(grid_pos, treasure_reveal_radius)
		queue_redraw()
		return

	# Legacy fallback: older scenes can still randomize from Player if procgen data is absent.
	var exit_tmpl: Dictionary = {}
	if randomize_exit_each_run:
		exit_tmpl = _get_exit_template()
		if not exit_tmpl.is_empty():
			_run_exit_pos = _place_random_exit_tile(exit_tmpl)

	_cache_exit_tiles()

	if landmark_enabled:
		var types: Array[Dictionary] = _collect_landmark_types_from_map_and_clear()
		if types.size() > 0:
			var result: Dictionary = _place_random_landmark(types)
			if not result.is_empty():
				_run_landmark_pos = result["pos"]
				_run_landmark_name = String(result["name"])

	if randomize_treasure_each_run:
		_run_treasure_pos = _place_random_treasure_tile()

	if randomize_exit_each_run and not exit_tmpl.is_empty():
		_ensure_exit_far_from_treasure(exit_tmpl)
		_cache_exit_tiles()

	if run_start_clue_enabled and _run_treasure_pos.x < 900000:
		if _run_landmark_pos.x < 900000 and _run_landmark_name != "":
			_show_landmark_direction_clue()
		else:
			_show_run_start_clue(_run_treasure_pos)

	_cache_and_hide_treasures()
	_reveal_treasures_near(grid_pos, treasure_reveal_radius)

	queue_redraw()


# Called by Main.gd during the enemy phase so the player can't act mid-enemy-turn.
func set_turn_locked(locked: bool) -> void:
	_turn_locked = locked


# ----------------------------
# Loadout
# ----------------------------
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


func _apply_player_palette_if_needed() -> void:
	if not apply_player_palette_on_ready:
		return
	if visual == null:
		return
	# PaletteManager must be an Autoload singleton named "PaletteManager".
	PaletteManager.apply_to_node(visual, player_palette_preset)

func _unhandled_input(event: InputEvent) -> void:
	if _busy or _turn_locked or _dead or _exiting:
		return

	if event.is_action_pressed("ui_accept"):
		await _try_manual_swing()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var kc: Key = (event as InputEventKey).keycode
		if kc == KEY_H:
			_try_use_potion()
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


# ----------------------------
# Helpers
# ----------------------------
func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _steps_word(n: int) -> String:
	return "step" if n == 1 else "steps"

func _dir_x(dx: int) -> String:
	return "EAST" if dx > 0 else "WEST"

func _dir_y(dy: int) -> String:
	return "SOUTH" if dy > 0 else "NORTH"

func _is_valid_procgen_cell(cell: Vector2i) -> bool:
	return cell.x <= 900000 and cell.y <= 900000


func _get_landmark_name_at_cell(cell: Vector2i) -> String:
	if map == null:
		return "Landmark"

	var td: TileData = map.get_cell_tile_data(cell)
	if td == null:
		return "Landmark"

	var name_val: Variant = td.get_custom_data(landmark_name_custom_key)
	if typeof(name_val) == TYPE_STRING:
		var nm: String = String(name_val)
		if nm != "":
			return nm

	return "Landmark"


func _apply_procgen_source_of_truth() -> bool:
	if not procgen_use_mapgenerator_results:
		return false

	var have_spawn: bool = _is_valid_procgen_cell(procgen_spawn_cell)
	var have_treasure: bool = _is_valid_procgen_cell(procgen_treasure_cell)
	var have_exit: bool = _is_valid_procgen_cell(procgen_exit_cell)

	if not have_spawn or not have_treasure or not have_exit:
		return false

	grid_pos = procgen_spawn_cell
	global_position = map.to_global(map.map_to_local(grid_pos))

	_run_treasure_pos = procgen_treasure_cell
	_run_exit_pos = procgen_exit_cell

	if procgen_has_clue_landmark or _is_valid_procgen_cell(procgen_clue_landmark_cell):
		procgen_has_clue_landmark = _is_valid_procgen_cell(procgen_clue_landmark_cell)

	if procgen_has_clue_landmark:
		_run_landmark_pos = procgen_clue_landmark_cell
		_run_landmark_name = _get_landmark_name_at_cell(procgen_clue_landmark_cell)
	else:
		_run_landmark_pos = Vector2i(999999, 999999)
		_run_landmark_name = ""

	return true

func _show_landmark_direction_clue() -> void:
	if _run_landmark_pos.x > 900000 or _run_treasure_pos.x > 900000:
		_show_toast("Clue: Near the %s." % _run_landmark_name, run_start_clue_duration_sec)
		return

	var dx: int = _run_treasure_pos.x - _run_landmark_pos.x
	var dy: int = _run_treasure_pos.y - _run_landmark_pos.y

	if dx == 0 and dy == 0:
		_show_toast("Clue: Near the %s." % _run_landmark_name, run_start_clue_duration_sec)
		return

	var parts: Array[String] = []

	if dx != 0:
		var nx: int = abs(dx)
		parts.append("%d %s %s" % [nx, _steps_word(nx), _dir_x(dx)])

	if dy != 0:
		var ny: int = abs(dy)
		parts.append("%d %s %s" % [ny, _steps_word(ny), _dir_y(dy)])

	var msg: String
	if parts.size() == 1:
		msg = "Clue: From the %s, go %s." % [_run_landmark_name, parts[0]]
	else:
		msg = "Clue: From the %s, go %s, then %s." % [_run_landmark_name, parts[0], parts[1]]

	_show_toast(msg, run_start_clue_duration_sec)

func _get_enemy_at_tile(tile: Vector2i) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for e in tree.get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		if not e.has_method("get_grid_pos"):
			continue
		if e.get_grid_pos() == tile:
			return e
	return null


# ----------------------------
# Combat
# ----------------------------
func _try_manual_swing() -> void:
	if not _has_sword:
		return

	_busy = true

	if cam != null and cam.has_method("shake"):
		cam.shake(shake_on_swing_strength, shake_on_swing_frames)

	if sword_swoosh_scene != null and sword_tip != null:
		var swoosh := sword_swoosh_scene.instantiate()
		get_parent().add_child(swoosh)
		if swoosh.has_method("start"):
			swoosh.start(sword_tip)

	await _do_swing_anim()

	var target_tile: Vector2i = grid_pos + _facing
	var e := _get_enemy_at_tile(target_tile)

	if e != null and e.has_method("take_damage"):
		var dmg: int = randi_range(damage_min, damage_max) + _attack_bonus + manual_swing_bonus_damage
		e.take_damage(dmg)
		if e is Node2D:
			_spawn_hit_spark((e as Node2D).global_position)
		_do_shake(shake_on_hit_strength)
		await _do_hitstop()

	_busy = false
	turn_taken.emit(grid_pos)


func _do_swing_anim() -> void:
	if hand_socket == null:
		return
	hand_socket.rotation_degrees = 0.0
	var tw := create_tween()
	tw.tween_property(hand_socket, "rotation_degrees", swing_degrees, swing_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(hand_socket, "rotation_degrees", 0.0, swing_return_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished


func _spawn_hit_spark(at_global: Vector2) -> void:
	if hit_spark_scene == null:
		return
	var sp := hit_spark_scene.instantiate() as Node2D
	get_parent().add_child(sp)
	sp.global_position = at_global


# ----------------------------
# Potion
# ----------------------------
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


# ----------------------------
# Movement + attack + treasure + exit
# ----------------------------
func try_move_or_attack(dir: Vector2i) -> void:
	if map == null or _dead or _exiting:
		return

	_busy = true
	_facing = dir

	if dir.x < 0:
		visual.scale.x = -1.0
	elif dir.x > 0:
		visual.scale.x = 1.0

	var next: Vector2i = grid_pos + dir

	var e := _get_enemy_at_tile(next)
	if e != null and e.has_method("take_damage"):
		var dmg: int = randi_range(damage_min, damage_max) + _attack_bonus
		e.take_damage(dmg)
		if e is Node2D:
			_spawn_hit_spark((e as Node2D).global_position)
		_do_shake(shake_on_hit_strength)
		await _do_hitstop()
		_busy = false
		turn_taken.emit(grid_pos)
		return

	if edge_transition_requires_door and _crosses_room_boundary(grid_pos, next):
		var ok: bool = _is_door(grid_pos) or _is_door(next)
		if not ok:
			_busy = false
			return

	if _is_blocked(next):
		_busy = false
		return

	grid_pos = next
	var target_global: Vector2 = map.to_global(map.map_to_local(grid_pos))

	var tw: Tween = create_tween()
	tw.tween_property(self, "global_position", target_global, move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished

	_spawn_step_dust(dir)
	_reveal_treasures_near(grid_pos, treasure_reveal_radius)

	await _apply_hazard_if_needed(grid_pos)
	_apply_treasure_if_needed(grid_pos)

	if _dead:
		_busy = false
		return

	if _is_exit_location(grid_pos):
		_busy = false
		await _exit_sequence()
		return

	_busy = false
	turn_taken.emit(grid_pos)


# ----------------------------
# Exit logic + juice
# ----------------------------
func _is_exit_location(tile: Vector2i) -> bool:
	for e in _exit_tiles:
		if e["pos"] == tile:
			if GameManager.has_treasure and exit_blink_enabled and not _exit_blink_show_exit:
				_exit_blink_show_exit = true
				_restore_exit_tiles()
			return true
	var td: TileData = map.get_cell_tile_data(tile)
	return td != null and bool(td.get_custom_data(exit_custom_key))


func _exit_sequence() -> void:
	if _exiting:
		return
	_exiting = true
	_busy = true

	_exit_blink_running = false
	_exit_blink_show_exit = true
	_restore_exit_tiles()

	GameManager.death_reason = "flee" if not GameManager.has_treasure else "none"

	if exit_spin_enabled:
		await _do_exit_spin()

	if settlement_scene != null and get_tree() != null:
		get_tree().change_scene_to_packed(settlement_scene)


func _do_exit_spin() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var base_scale_x: float = -1.0 if visual.scale.x < 0.0 else 1.0
	var base_pos: Vector2 = visual.position
	for i in range(maxi(1, exit_spin_flips)):
		var s: float = base_scale_x if (i % 2 == 0) else -base_scale_x
		visual.scale.x = s
		if exit_spin_bob_px > 0.0:
			visual.position = base_pos + Vector2(0.0, (-exit_spin_bob_px if (i % 2 == 0) else exit_spin_bob_px))
		await tree.create_timer(exit_spin_interval_sec).timeout
	visual.scale.x = base_scale_x
	visual.position = base_pos


# ----------------------------
# Extraction Mode: toast + exit blink
# ----------------------------
func _enter_extraction_mode() -> void:
	_show_toast("TREASURE FOUND!\nESCAPE!", toast_duration_sec)
	if exit_blink_enabled and not _exit_blink_running and _exit_tiles.size() > 0:
		_exit_blink_running = true
		_exit_blink_show_exit = true
		_exit_blink_loop()


func _exit_blink_loop() -> void:
	while is_inside_tree() and not _dead and not _exiting and GameManager.has_treasure and _exit_blink_running:
		_exit_blink_show_exit = not _exit_blink_show_exit
		if _exit_blink_show_exit:
			_restore_exit_tiles()
		else:
			_hide_exit_tiles_as_floor()
		var tree := get_tree()
		if tree == null:
			break
		await tree.create_timer(exit_blink_period_sec).timeout
	if is_inside_tree():
		_exit_blink_show_exit = true
		_restore_exit_tiles()
	_exit_blink_running = false


func _cache_exit_tiles() -> void:
	_exit_tiles.clear()
	for cell in map.get_used_cells():
		var td: TileData = map.get_cell_tile_data(cell)
		if td != null and bool(td.get_custom_data(exit_custom_key)):
			_exit_tiles.append({
				"pos": cell,
				"sid": map.get_cell_source_id(cell),
				"ac": map.get_cell_atlas_coords(cell),
				"alt": map.get_cell_alternative_tile(cell),
			})


func _restore_exit_tiles() -> void:
	for e in _exit_tiles:
		map.set_cell(e["pos"], int(e["sid"]), e["ac"], int(e["alt"]))


func _hide_exit_tiles_as_floor() -> void:
	for e in _exit_tiles:
		map.set_cell(e["pos"], tile_source_id, floor_atlas_coords, 0)


# ----------------------------
# Random Exit (FAIR)
# ----------------------------
func _get_exit_template() -> Dictionary:
	for cell in map.get_used_cells():
		var td: TileData = map.get_cell_tile_data(cell)
		if td != null and bool(td.get_custom_data(exit_custom_key)):
			return {
				"sid": map.get_cell_source_id(cell),
				"ac": map.get_cell_atlas_coords(cell),
				"alt": map.get_cell_alternative_tile(cell),
			}
	return {}


func _place_random_exit_tile(tmpl: Dictionary) -> Vector2i:
	for cell in map.get_used_cells():
		var td: TileData = map.get_cell_tile_data(cell)
		if td != null and bool(td.get_custom_data(exit_custom_key)):
			map.set_cell(cell, tile_source_id, floor_atlas_coords, 0)

	var candidates: Array[Vector2i] = _gather_floor_candidates(true)
	if candidates.is_empty():
		return Vector2i(999999, 999999)

	var pick: Vector2i = candidates[randi() % candidates.size()]
	for _i in range(placement_attempts):
		var c: Vector2i = candidates[randi() % candidates.size()]
		if _manhattan(c, grid_pos) >= min_exit_dist_from_player:
			pick = c
			break

	map.set_cell(pick, int(tmpl["sid"]), tmpl["ac"], int(tmpl["alt"]))
	return pick


func _ensure_exit_far_from_treasure(tmpl: Dictionary) -> void:
	# Exit is placed before treasure, so after treasure placement we enforce a minimum distance.
	if _run_exit_pos.x >= 900000:
		return
	if _run_treasure_pos.x >= 900000:
		return

	# Already far enough
	if _manhattan(_run_exit_pos, _run_treasure_pos) >= min_exit_dist_from_treasure:
		return

	# Clear any existing exit tiles back to floor
	for cell in map.get_used_cells():
		var td: TileData = map.get_cell_tile_data(cell)
		if td != null and bool(td.get_custom_data(exit_custom_key)):
			map.set_cell(cell, tile_source_id, floor_atlas_coords, 0)

	var candidates: Array[Vector2i] = _gather_floor_candidates(true)
	if candidates.is_empty():
		return

	# Prefer candidates that satisfy BOTH: far from player AND far from treasure
	var legal: Array[Vector2i] = []
	for c in candidates:
		if _manhattan(c, grid_pos) < min_exit_dist_from_player:
			continue
		if _manhattan(c, _run_treasure_pos) < min_exit_dist_from_treasure:
			continue
		legal.append(c)

	var pick2: Vector2i
	if not legal.is_empty():
		pick2 = legal[randi() % legal.size()]
	else:
		# Fallback: at least be far from player (original rule)
		pick2 = candidates[randi() % candidates.size()]
		for _i in range(placement_attempts):
			var c2: Vector2i = candidates[randi() % candidates.size()]
			if _manhattan(c2, grid_pos) >= min_exit_dist_from_player:
				pick2 = c2
				break

	map.set_cell(pick2, int(tmpl["sid"]), tmpl["ac"], int(tmpl["alt"]))
	_run_exit_pos = pick2


# ----------------------------
# Landmark: collect + place
# ----------------------------
func _collect_landmark_types_from_map_and_clear() -> Array[Dictionary]:
	var types: Array[Dictionary] = []
	for cell in map.get_used_cells():
		var td: TileData = map.get_cell_tile_data(cell)
		if td == null:
			continue
		if not bool(td.get_custom_data(landmark_custom_key)):
			continue

		var sid: int = map.get_cell_source_id(cell)
		var ac: Vector2i = map.get_cell_atlas_coords(cell)
		var alt: int = map.get_cell_alternative_tile(cell)

		var name_val: Variant = td.get_custom_data(landmark_name_custom_key)
		var nm: String = "Landmark"
		if typeof(name_val) == TYPE_STRING:
			nm = String(name_val)

		types.append({"sid": sid, "ac": ac, "alt": alt, "name": nm})
		map.set_cell(cell, tile_source_id, floor_atlas_coords, 0)

	return types


func _place_random_landmark(types: Array[Dictionary]) -> Dictionary:
	if types.is_empty():
		return {}

	var picked_type: Dictionary = types[randi() % types.size()]
	var sid: int = int(picked_type["sid"])
	var ac: Vector2i = picked_type["ac"]
	var alt: int = int(picked_type["alt"])
	var nm: String = String(picked_type["name"])

	var candidates: Array[Vector2i] = _gather_floor_candidates(true)
	if candidates.is_empty():
		return {}

	var have_exit: bool = (_run_exit_pos.x < 900000)

	var legal: Array[Vector2i] = []
	for c in candidates:
		if _manhattan(c, grid_pos) < min_landmark_dist_from_player:
			continue
		if have_exit and _manhattan(c, _run_exit_pos) < min_landmark_dist_from_exit:
			continue
		legal.append(c)

	var pick: Vector2i = legal[randi() % legal.size()] if not legal.is_empty() else candidates[randi() % candidates.size()]

	map.set_cell(pick, sid, ac, alt)
	return {"pos": pick, "name": nm}


# ----------------------------
# Treasure placement (prefer near landmark, not TOO close, prefer clean clues)
# ----------------------------
func _place_random_treasure_tile() -> Vector2i:
	for cell in map.get_used_cells():
		if map.get_cell_source_id(cell) != tile_source_id:
			continue
		if map.get_cell_atlas_coords(cell) == treasure_atlas_coords:
			map.set_cell(cell, tile_source_id, floor_atlas_coords, 0)

	var all_candidates: Array[Vector2i] = _gather_floor_candidates(false)
	if all_candidates.is_empty():
		return Vector2i(999999, 999999)

	var have_exit: bool = (_run_exit_pos.x < 900000)
	var have_landmark: bool = (_run_landmark_pos.x < 900000)

	if have_landmark:
		var near: Array[Vector2i] = []
		for c in all_candidates:
			var d: int = _manhattan(c, _run_landmark_pos)
			if d >= landmark_treasure_min_dist and d <= landmark_treasure_max_dist:
				near.append(c)

		# Relax if too strict on small maps (but don't allow treasure directly on the landmark)
		if near.is_empty():
			var relaxed_min: int = maxi(1, landmark_treasure_min_dist - 1)
			for c2 in all_candidates:
				var d2: int = _manhattan(c2, _run_landmark_pos)
				if d2 >= relaxed_min and d2 <= landmark_treasure_max_dist:
					near.append(c2)

		# Prefer clean clue (same row/col) some of the time
		if not near.is_empty():
			var roll: int = int(randi() % 100)
			if roll < landmark_axis_aligned_chance_percent:
				var axis: Array[Vector2i] = []
				for c3 in near:
					if c3.x == _run_landmark_pos.x or c3.y == _run_landmark_pos.y:
						axis.append(c3)
				if not axis.is_empty():
					near = axis

		if not near.is_empty():
			var pick_near: Vector2i = near[randi() % near.size()]
			for _i in range(placement_attempts):
				var c4: Vector2i = near[randi() % near.size()]
				if _manhattan(c4, grid_pos) < min_treasure_dist_from_player:
					continue
				if have_exit and _manhattan(c4, _run_exit_pos) < min_exit_dist_from_treasure:
					continue
				pick_near = c4
				break

			map.set_cell(pick_near, tile_source_id, treasure_atlas_coords, 0)
			return pick_near

	# Fallback: fair anywhere
	var pick: Vector2i = all_candidates[randi() % all_candidates.size()]
	for _i in range(placement_attempts):
		var c5: Vector2i = all_candidates[randi() % all_candidates.size()]
		if _manhattan(c5, grid_pos) < min_treasure_dist_from_player:
			continue
		if have_exit and _manhattan(c5, _run_exit_pos) < min_exit_dist_from_treasure:
			continue
		pick = c5
		break

	map.set_cell(pick, tile_source_id, treasure_atlas_coords, 0)
	return pick


func _gather_floor_candidates(avoid_exit_tile: bool) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for cell in map.get_used_cells():
		if cell == grid_pos:
			continue
		if map.get_cell_source_id(cell) != tile_source_id:
			continue
		if map.get_cell_atlas_coords(cell) != floor_atlas_coords:
			continue

		var td: TileData = map.get_cell_tile_data(cell)
		if td == null:
			continue
		if bool(td.get_custom_data("blocked")):
			continue
		if bool(td.get_custom_data(hazard_custom_key)):
			continue
		if bool(td.get_custom_data(door_custom_key)):
			continue
		if avoid_exit_tile and bool(td.get_custom_data(exit_custom_key)):
			continue
		if bool(td.get_custom_data(treasure_custom_key)):
			continue
		if bool(td.get_custom_data(landmark_custom_key)):
			continue

		candidates.append(cell)
	return candidates


# ----------------------------
# Directional clue fallback (no landmark)
# ----------------------------
func _show_run_start_clue(tpos: Vector2i) -> void:
	var bounds := _compute_walkable_floor_bounds()
	if bounds.size == Vector2i.ZERO:
		return

	var mid_x: float = float(bounds.position.x) + float(bounds.size.x) * 0.5
	var mid_y: float = float(bounds.position.y) + float(bounds.size.y) * 0.5

	var r: int = randi() % 3
	var text: String
	if r == 0:
		text = "Clue: It's in the NORTH half." if float(tpos.y) < mid_y else "Clue: It's in the SOUTH half."
	elif r == 1:
		text = "Clue: It's closer to the WEST." if float(tpos.x) < mid_x else "Clue: It's closer to the EAST."
	else:
		var ns: String = "NORTH" if float(tpos.y) < mid_y else "SOUTH"
		var ew: String = "WEST" if float(tpos.x) < mid_x else "EAST"
		text = "Clue: %s-%s quarter." % [ns, ew]

	_show_toast(text, run_start_clue_duration_sec)


func _compute_walkable_floor_bounds() -> Rect2i:
	var first: bool = true
	var minp: Vector2i = Vector2i.ZERO
	var maxp: Vector2i = Vector2i.ZERO

	for cell in map.get_used_cells():
		if map.get_cell_source_id(cell) != tile_source_id:
			continue
		if map.get_cell_atlas_coords(cell) != floor_atlas_coords:
			continue
		var td: TileData = map.get_cell_tile_data(cell)
		if td == null:
			continue
		if bool(td.get_custom_data("blocked")):
			continue

		if first:
			minp = cell
			maxp = cell
			first = false
		else:
			minp.x = mini(minp.x, cell.x)
			minp.y = mini(minp.y, cell.y)
			maxp.x = maxi(maxp.x, cell.x)
			maxp.y = maxi(maxp.y, cell.y)

	if first:
		return Rect2i()

	return Rect2i(minp, (maxp - minp) + Vector2i(1, 1))


# ----------------------------
# Treasure hide/reveal
# ----------------------------
func _cache_and_hide_treasures() -> void:
	_hidden_treasures.clear()
	for cell in map.get_used_cells():
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
		if _manhattan(pos, center) <= radius:
			map.set_cell(pos, tile_source_id, treasure_atlas_coords, 0)
		else:
			still_hidden.append(pos)
	_hidden_treasures = still_hidden


func _apply_treasure_if_needed(tile: Vector2i) -> void:
	var td: TileData = map.get_cell_tile_data(tile)
	if td == null:
		return
	if not bool(td.get_custom_data(treasure_custom_key)):
		return

	var value: int = GameManager.roll_treasure_value()
	GameManager.found_treasure(value)
	map.set_cell(tile, tile_source_id, floor_atlas_coords, 0)

	_enter_extraction_mode()


# ----------------------------
# Toast
# ----------------------------
func _show_toast(text: String, sec: float) -> void:
	if _toast_label == null:
		return
	_toast_token += 1
	var my_token: int = _toast_token
	_toast_label.text = text
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(sec).timeout
	if my_token == _toast_token:
		_clear_toast()


func _clear_toast() -> void:
	if _toast_label != null:
		_toast_label.text = ""


# ----------------------------
# Map helpers
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
	if not bool(td.get_custom_data(hazard_custom_key)):
		return

	var dmg: int = hazard_default_damage
	var raw: Variant = td.get_custom_data(hazard_damage_key)
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
	var behind: Vector2 = Vector2(-float(move_dir.x), -float(move_dir.y)) * step_dust_trail_px
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


# ----------------------------
# Public helpers (used by Main.gd for enemy placement)
# ----------------------------
func get_grid_pos() -> Vector2i:
	return grid_pos

func get_run_exit_pos() -> Vector2i:
	return _run_exit_pos

func get_run_treasure_pos() -> Vector2i:
	return _run_treasure_pos

func get_run_landmark_pos() -> Vector2i:
	return _run_landmark_pos

func get_walkable_floor_candidates(avoid_exit_tile: bool = true) -> Array[Vector2i]:
	return _gather_floor_candidates(avoid_exit_tile)
