extends Node
class_name MapGenerator

# --- Paths ---
@export var map_path: NodePath
@export var player_path: NodePath

# --- Room size in tiles ---
@export var width_tiles: int = 20
@export var height_tiles: int = 12
@export var tile_size_px: int = 16

# --- Tile info (match your TileSet) ---
@export var tile_source_id: int = 0
@export var floor_atlas_coords: Vector2i = Vector2i(2, 0)

# --- Custom-data keys used in your TileSet ---
@export var exit_custom_key: StringName = &"exit"
@export var landmark_custom_key: StringName = &"landmark"
@export var treasure_custom_key: StringName = &"treasure"
@export var blocked_custom_key: StringName = &"blocked"

# --- Generation settings ---
@export var rock_count: int = 18
@export var reroll_attempts: int = 60

# Where to draw the room (tile coords)
@export var origin_cell: Vector2i = Vector2i.ZERO

# Keep OFF for v0 unless you really need it
@export var center_room_on_player: bool = false

# --- Procgen v0 tuning ---
@export var auto_tune_player_for_room: bool = true
@export var force_axis_aligned_landmark_clue: bool = true
@export var debug_check_exit_reachable: bool = true

# --- Seed (0 = random every time) ---
@export var map_seed: int = 0
var last_seed_used: int = 0

# Remember last room rectangle (for debug checks)
var _last_origin: Vector2i = Vector2i.ZERO
var _last_w: int = 0
var _last_h: int = 0

func _ready() -> void:
	var map: TileMapLayer = get_node_or_null(map_path) as TileMapLayer
	if map == null:
		push_warning("MapGenerator: map_path not set or not a TileMapLayer.")
		return

	if auto_tune_player_for_room:
		_tune_player_for_room(width_tiles, height_tiles)

	generate(map, width_tiles, height_tiles, map_seed)

	if debug_check_exit_reachable:
		call_deferred("_post_ready_sanity_check")

func generate(map: TileMapLayer, w: int, h: int, seed_in: int) -> bool:
	if w < 5 or h < 5:
		push_warning("MapGenerator: room too small. Need at least 5x5.")
		return false

	_last_w = w
	_last_h = h

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if seed_in != 0:
		rng.seed = seed_in
		last_seed_used = seed_in
	else:
		rng.randomize()
		last_seed_used = int(rng.seed)

	# Grab templates from the CURRENT map before clearing it
	var wall_tmpl: Dictionary = _find_first_blocked_tile_template(map)
	if wall_tmpl.is_empty():
		push_warning("MapGenerator: couldn't find ANY tile with custom_data 'blocked' to use as walls.")
		return false

	var exit_tmpl: Dictionary = _find_first_custom_tile_template(map, exit_custom_key)
	if exit_tmpl.is_empty():
		push_warning("MapGenerator: couldn't find an 'exit' tile template. Player expects one.")
		return false

	var landmark_tmps: Array[Dictionary] = _find_all_custom_tile_templates(map, landmark_custom_key)

	# Decide origin
	var origin: Vector2i = origin_cell
	if center_room_on_player:
		var player_for_origin: Node2D = get_node_or_null(player_path) as Node2D
		if player_for_origin != null:
			var local_pos: Vector2 = map.to_local(player_for_origin.global_position)
			var half: float = float(tile_size_px) * 0.5
			var player_cell: Vector2i = map.local_to_map(local_pos + Vector2(half, half))
			origin = player_cell - Vector2i(int(w / 2.0), int(h / 2.0))

	_last_origin = origin

	# Clamp rocks so we never “fill the room”
	var interior_w: int = maxi(0, w - 2)
	var interior_h: int = maxi(0, h - 2)
	var interior_cells: int = interior_w * interior_h
	var safe_max_rocks: int = maxi(0, interior_cells - 12)
	var rocks: int = mini(rock_count, safe_max_rocks)

	# Try until connected
	for _try: int in range(reroll_attempts):
		var blocked: Array[PackedByteArray] = _make_blocked_grid(w, h)
		_sprinkle_rocks(blocked, w, h, rocks, rng)

		if _all_floors_connected(blocked, w, h):
			_paint_map(map, origin, blocked, w, h, wall_tmpl)

			# Put required templates back so Player.gd can randomize exit/landmark/treasure
			_place_template_tile(map, origin + Vector2i(1, 1), exit_tmpl)

			if not landmark_tmps.is_empty():
				_place_landmark_templates(map, origin, w, h, landmark_tmps)

			_force_player_spawn_inside(map, origin, w, h)

			return true

	push_warning("MapGenerator: failed to generate a connected room after %d rerolls." % reroll_attempts)
	return false

# ----------------------------
# Player tuning for small Procgen v0 rooms
# ----------------------------
func _tune_player_for_room(w: int, h: int) -> void:
	var player: Node = get_node_or_null(player_path)
	if player == null:
		return

	# Keep Player room-boundary math consistent with actual tile room size.
	player.set("room_width_px", w * tile_size_px)
	player.set("room_height_px", h * tile_size_px)

	# Scale distances for small maps (no integer-division warnings)
	var size_score: int = w + h
	var min_t: int = clampi(int(float(size_score) / 4.0), 4, 10)
	var min_e: int = clampi(int(float(size_score) / 5.0), 4, 8)

	player.set("min_treasure_dist_from_player", min_t)
	player.set("min_landmark_dist_from_player", min_t)
	player.set("min_exit_dist_from_player", min_e)
	player.set("min_exit_dist_from_treasure", min_e)

	var max_near: int = clampi(int(float(mini(w, h)) / 2.0), 3, 8)
	player.set("landmark_treasure_max_dist", max_near)
	player.set("landmark_treasure_min_dist", mini(2, max_near))

	if force_axis_aligned_landmark_clue:
		player.set("landmark_axis_aligned_chance_percent", 100)

# ----------------------------
# Post-ready sanity check (treasure/exit reachability)
# ----------------------------
func _post_ready_sanity_check() -> void:
	var map: TileMapLayer = get_node_or_null(map_path) as TileMapLayer
	var player: Node2D = get_node_or_null(player_path) as Node2D
	if map == null or player == null:
		return

	var player_cell: Vector2i = _compute_player_cell(map, player)
	var treasure_cell: Vector2i = _find_first_custom_tile_pos(map, treasure_custom_key)
	var exit_cell: Vector2i = _find_first_custom_tile_pos(map, exit_custom_key)

	var has_treasure: bool = treasure_cell.x <= 900000
	var has_exit: bool = exit_cell.x <= 900000

	if not has_treasure:
		push_warning("MapGenerator sanity: No treasure tile found.")
	if not has_exit:
		push_warning("MapGenerator sanity: No exit tile found.")

	if has_treasure:
		var player_to_treasure_ok: bool = _reachable_not_blocked(map, player_cell, treasure_cell, _last_origin, _last_w, _last_h)
		if not player_to_treasure_ok:
			push_warning("MapGenerator sanity: Treasure is NOT reachable from player.")

	if has_exit:
		var player_to_exit_ok: bool = _reachable_not_blocked(map, player_cell, exit_cell, _last_origin, _last_w, _last_h)
		if not player_to_exit_ok:
			push_warning("MapGenerator sanity: Exit is NOT reachable from player. This should not happen in Procgen v0 room.")

	if has_treasure and has_exit:
		var treasure_to_exit_ok: bool = _reachable_not_blocked(map, treasure_cell, exit_cell, _last_origin, _last_w, _last_h)
		if not treasure_to_exit_ok:
			push_warning("MapGenerator sanity: Exit is NOT reachable from treasure.")

func _compute_player_cell(map: TileMapLayer, player: Node2D) -> Vector2i:
	# Avoid Variant-inference warnings: explicitly type Variant
	var v: Variant = player.get("grid_pos")
	if typeof(v) == TYPE_VECTOR2I:
		return v as Vector2i

	var local_pos: Vector2 = map.to_local(player.global_position)
	var half: float = float(tile_size_px) * 0.5
	return map.local_to_map(local_pos + Vector2(half, half))

func _find_first_custom_tile_pos(map: TileMapLayer, key: StringName) -> Vector2i:
	var used: Array[Vector2i] = map.get_used_cells()
	for cell: Vector2i in used:
		var td: TileData = map.get_cell_tile_data(cell)
		if td != null and bool(td.get_custom_data(key)):
			return cell
	return Vector2i(999999, 999999)

func _reachable_not_blocked(map: TileMapLayer, start: Vector2i, goal: Vector2i, origin: Vector2i, w: int, h: int) -> bool:
	if start == goal:
		return true

	var minx: int = origin.x
	var miny: int = origin.y
	var maxx: int = origin.x + w - 1
	var maxy: int = origin.y + h - 1

	var q: Array[Vector2i] = [start]
	var seen: Dictionary = {}
	seen[start] = true

	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	var qi: int = 0
	while qi < q.size():
		var p: Vector2i = q[qi]
		qi += 1

		for d: Vector2i in dirs:
			var n: Vector2i = p + d

			if n.x < minx or n.y < miny or n.x > maxx or n.y > maxy:
				continue
			if seen.has(n):
				continue

			var td: TileData = map.get_cell_tile_data(n)
			if td == null:
				continue
			if bool(td.get_custom_data(blocked_custom_key)):
				continue

			if n == goal:
				return true

			seen[n] = true
			q.append(n)

	return false

# ----------------------------
# Player spawn fix
# ----------------------------
func _force_player_spawn_inside(map: TileMapLayer, origin: Vector2i, w: int, h: int) -> void:
	var player: Node2D = get_node_or_null(player_path) as Node2D
	if player == null:
		return

	var sx: int = clampi(int(float(w) / 2.0), 1, w - 2)
	var sy: int = clampi(int(float(h) / 2.0), 1, h - 2)
	var spawn_cell: Vector2i = origin + Vector2i(sx, sy)

	player.global_position = map.to_global(map.map_to_local(spawn_cell))
	player.set("grid_pos", spawn_cell)

# ----------------------------
# Blocked grid + connectivity
# ----------------------------
func _make_blocked_grid(w: int, h: int) -> Array[PackedByteArray]:
	var rows: Array[PackedByteArray] = []
	rows.resize(h)

	for y: int in range(h):
		var row: PackedByteArray = PackedByteArray()
		row.resize(w)
		for x: int in range(w):
			var is_border: bool = (x == 0 or y == 0 or x == w - 1 or y == h - 1)
			row[x] = 1 if is_border else 0
		rows[y] = row

	return rows

func _sprinkle_rocks(blocked: Array[PackedByteArray], w: int, h: int, count: int, rng: RandomNumberGenerator) -> void:
	if count <= 0:
		return

	var placed: int = 0
	var attempts: int = count * 12
	while placed < count and attempts > 0:
		attempts -= 1
		var x: int = rng.randi_range(1, w - 2)
		var y: int = rng.randi_range(1, h - 2)
		if blocked[y][x] == 0:
			blocked[y][x] = 1
			placed += 1

func _all_floors_connected(blocked: Array[PackedByteArray], w: int, h: int) -> bool:
	var total_floor: int = 0
	var start: Vector2i = Vector2i(-1, -1)

	for y: int in range(h):
		for x: int in range(w):
			if blocked[y][x] == 0:
				total_floor += 1
				if start.x == -1:
					start = Vector2i(x, y)

	if total_floor == 0:
		return false

	var visited: Array[PackedByteArray] = []
	visited.resize(h)
	for y: int in range(h):
		var row: PackedByteArray = PackedByteArray()
		row.resize(w)
		visited[y] = row

	var q: Array[Vector2i] = [start]
	visited[start.y][start.x] = 1

	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	var qi: int = 0
	var reached: int = 0

	while qi < q.size():
		var p: Vector2i = q[qi]
		qi += 1
		reached += 1

		for d: Vector2i in dirs:
			var nx: int = p.x + d.x
			var ny: int = p.y + d.y

			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if blocked[ny][nx] == 1:
				continue
			if visited[ny][nx] == 1:
				continue

			visited[ny][nx] = 1
			q.append(Vector2i(nx, ny))

	return reached == total_floor

# ----------------------------
# Paint tiles
# ----------------------------
func _paint_map(map: TileMapLayer, origin: Vector2i, blocked: Array[PackedByteArray], w: int, h: int, wall_tmpl: Dictionary) -> void:
	map.clear()

	var wsid: int = int(wall_tmpl["sid"])
	var wac: Vector2i = wall_tmpl["ac"]
	var walt: int = int(wall_tmpl["alt"])

	for y: int in range(h):
		for x: int in range(w):
			var cell: Vector2i = origin + Vector2i(x, y)
			if blocked[y][x] == 1:
				map.set_cell(cell, wsid, wac, walt)
			else:
				map.set_cell(cell, tile_source_id, floor_atlas_coords, 0)

# ----------------------------
# Template helpers
# ----------------------------
func _find_first_blocked_tile_template(map: TileMapLayer) -> Dictionary:
	var used: Array[Vector2i] = map.get_used_cells()
	for cell: Vector2i in used:
		var td: TileData = map.get_cell_tile_data(cell)
		if td != null and bool(td.get_custom_data(blocked_custom_key)):
			return {
				"sid": map.get_cell_source_id(cell),
				"ac": map.get_cell_atlas_coords(cell),
				"alt": map.get_cell_alternative_tile(cell),
			}
	return {}

func _find_first_custom_tile_template(map: TileMapLayer, key: StringName) -> Dictionary:
	var used: Array[Vector2i] = map.get_used_cells()
	for cell: Vector2i in used:
		var td: TileData = map.get_cell_tile_data(cell)
		if td != null and bool(td.get_custom_data(key)):
			return {
				"sid": map.get_cell_source_id(cell),
				"ac": map.get_cell_atlas_coords(cell),
				"alt": map.get_cell_alternative_tile(cell),
			}
	return {}

func _find_all_custom_tile_templates(map: TileMapLayer, key: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}

	var used: Array[Vector2i] = map.get_used_cells()
	for cell: Vector2i in used:
		var td: TileData = map.get_cell_tile_data(cell)
		if td == null:
			continue
		if not bool(td.get_custom_data(key)):
			continue

		var sid: int = map.get_cell_source_id(cell)
		var ac: Vector2i = map.get_cell_atlas_coords(cell)
		var alt: int = map.get_cell_alternative_tile(cell)
		var k: String = "%s|%s|%s" % [sid, ac, alt]

		if seen.has(k):
			continue
		seen[k] = true
		out.append({"sid": sid, "ac": ac, "alt": alt})

	return out

func _place_template_tile(map: TileMapLayer, cell: Vector2i, tmpl: Dictionary) -> void:
	map.set_cell(cell, int(tmpl["sid"]), tmpl["ac"], int(tmpl["alt"]))

func _place_landmark_templates(map: TileMapLayer, origin: Vector2i, w: int, h: int, tmps: Array[Dictionary]) -> void:
	var candidates: Array[Vector2i] = []

	var player_spawn: Vector2i = origin + Vector2i(
		clampi(int(float(w) / 2.0), 1, w - 2),
		clampi(int(float(h) / 2.0), 1, h - 2)
	)

	var exit_cell: Vector2i = origin + Vector2i(1, 1)

	for y: int in range(1, h - 1):
		for x: int in range(1, w - 1):
			var cell: Vector2i = origin + Vector2i(x, y)

			if cell == player_spawn:
				continue
			if cell == exit_cell:
				continue

			var td: TileData = map.get_cell_tile_data(cell)
			if td == null:
				continue
			if bool(td.get_custom_data(blocked_custom_key)):
				continue

			var dist_from_player: int = absi(cell.x - player_spawn.x) + absi(cell.y - player_spawn.y)
			if dist_from_player < 3:
				continue

			candidates.append(cell)

	if candidates.is_empty():
		push_warning("MapGenerator: no valid landmark cells found.")
		return

	var placed_cells: Array[Vector2i] = []
	var used: Dictionary = {}

	for tmpl: Dictionary in tmps:
		var best_cell: Vector2i = Vector2i(999999, 999999)
		var best_score: int = -999999

		for cell: Vector2i in candidates:
			if used.has(cell):
				continue

			var score: int = 0
			score += absi(cell.x - player_spawn.x) + absi(cell.y - player_spawn.y)

			for other: Vector2i in placed_cells:
				score += absi(cell.x - other.x) + absi(cell.y - other.y)

			if score > best_score:
				best_score = score
				best_cell = cell

		if best_cell.x > 900000:
			break

		_place_template_tile(map, best_cell, tmpl)
		used[best_cell] = true
		placed_cells.append(best_cell)
