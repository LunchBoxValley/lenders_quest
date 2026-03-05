extends Node
class_name MapGenerator

# --- Paths ---
@export var map_path: NodePath
@export var player_path: NodePath

# --- Room size in tiles ---
@export var width_tiles: int = 20
@export var height_tiles: int = 12

# --- Tile info (match your TileSet) ---
@export var tile_source_id: int = 0
@export var floor_atlas_coords: Vector2i = Vector2i(2, 0)

# --- Custom-data keys used in your TileSet ---
@export var exit_custom_key: StringName = &"exit"
@export var landmark_custom_key: StringName = &"landmark"
@export var blocked_custom_key: StringName = &"blocked"

# --- Generation settings ---
@export var rock_count: int = 18
@export var reroll_attempts: int = 60

# Where to draw the room (tile coords)
@export var origin_cell: Vector2i = Vector2i.ZERO

# If true, we center the room around where the player currently is
@export var center_room_on_player: bool = false
@export var tile_size_px: int = 16  # used only for centering math

# --- Seed (0 = random every time) ---
@export var seed: int = 0
var last_seed_used: int = 0

func _ready() -> void:
	var map := get_node_or_null(map_path) as TileMapLayer
	if map == null:
		push_warning("MapGenerator: map_path not set or not a TileMapLayer.")
		return

	generate(map, width_tiles, height_tiles, seed)

func generate(map: TileMapLayer, w: int, h: int, seed_in: int) -> bool:
	if w < 5 or h < 5:
		push_warning("MapGenerator: room too small. Need at least 5x5.")
		return false

	var rng := RandomNumberGenerator.new()
	if seed_in != 0:
		rng.seed = seed_in
		last_seed_used = seed_in
	else:
		rng.randomize()
		last_seed_used = int(rng.seed)

	# Grab templates from the CURRENT map before clearing it
	var wall_tmpl := _find_first_blocked_tile_template(map)
	if wall_tmpl.is_empty():
		push_warning("MapGenerator: couldn't find ANY tile with custom_data 'blocked' to use as walls.")
		return false

	var exit_tmpl := _find_first_custom_tile_template(map, exit_custom_key)
	if exit_tmpl.is_empty():
		push_warning("MapGenerator: couldn't find an 'exit' tile template. Player.gd expects one.")
		return false

	var landmark_tmps := _find_all_custom_tile_templates(map, landmark_custom_key)

	# Decide origin
	var origin := origin_cell
	if center_room_on_player:
		var player := get_node_or_null(player_path) as Node2D
		if player != null:
			var local_pos: Vector2 = map.to_local(player.global_position)
			var half: float = float(tile_size_px) * 0.5
			var player_cell: Vector2i = map.local_to_map(local_pos + Vector2(half, half))
			origin = player_cell - Vector2i(int(w / 2), int(h / 2))

	# Try until connected
	for _try in range(reroll_attempts):
		var blocked := _make_blocked_grid(w, h) # borders blocked
		_sprinkle_rocks(blocked, w, h, rock_count, rng)

		if _all_floors_connected(blocked, w, h):
			_paint_map(map, origin, blocked, w, h, wall_tmpl)

			# Put required templates back so Player.gd can do its normal logic
			var exit_cell := origin + Vector2i(w - 2, h - 2) # inside border
			_place_template_tile(map, exit_cell, exit_tmpl)

			if not landmark_tmps.is_empty():
				_place_landmark_templates(map, origin, w, h, landmark_tmps)

			# IMPORTANT: force player to spawn inside the room
			_force_player_spawn_inside(map, origin, w, h)

			return true

	push_warning("MapGenerator: failed to generate a connected room after %d rerolls." % reroll_attempts)
	return false

# ----------------------------
# Player spawn fix
# ----------------------------
func _force_player_spawn_inside(map: TileMapLayer, origin: Vector2i, w: int, h: int) -> void:
	var player := get_node_or_null(player_path) as Node2D
	if player == null:
		return

	# Pick a safe interior floor tile (center-ish), never on the border
	var sx: int = clampi(int(w / 2), 1, w - 2)
	var sy: int = clampi(int(h / 2), 1, h - 2)
	var spawn_cell: Vector2i = origin + Vector2i(sx, sy)

	# Teleport
	player.global_position = map.to_global(map.map_to_local(spawn_cell))

	# Also set grid_pos if the Player script has it (so logic matches position immediately)
	# Player.gd uses grid_pos for movement/turn logic. :contentReference[oaicite:1]{index=1}
	if player.has_method("set"):
		player.set("grid_pos", spawn_cell)

# ----------------------------
# Blocked grid
# ----------------------------
func _make_blocked_grid(w: int, h: int) -> Array[PackedByteArray]:
	var rows: Array[PackedByteArray] = []
	rows.resize(h)

	for y in range(h):
		var row := PackedByteArray()
		row.resize(w)
		for x in range(w):
			var is_border := (x == 0 or y == 0 or x == w - 1 or y == h - 1)
			row[x] = 1 if is_border else 0
		rows[y] = row

	return rows

func _sprinkle_rocks(blocked: Array[PackedByteArray], w: int, h: int, count: int, rng: RandomNumberGenerator) -> void:
	if count <= 0:
		return

	var placed := 0
	var attempts := count * 12
	while placed < count and attempts > 0:
		attempts -= 1
		var x := rng.randi_range(1, w - 2)
		var y := rng.randi_range(1, h - 2)
		if blocked[y][x] == 0:
			blocked[y][x] = 1
			placed += 1

# ----------------------------
# Connectivity check (flood fill)
# ----------------------------
func _all_floors_connected(blocked: Array[PackedByteArray], w: int, h: int) -> bool:
	var total_floor := 0
	var start := Vector2i(-1, -1)

	for y in range(h):
		for x in range(w):
			if blocked[y][x] == 0:
				total_floor += 1
				if start.x == -1:
					start = Vector2i(x, y)

	if total_floor == 0:
		return false

	var visited: Array[PackedByteArray] = []
	visited.resize(h)
	for y in range(h):
		var row := PackedByteArray()
		row.resize(w)
		visited[y] = row

	var q: Array[Vector2i] = [start]
	visited[start.y][start.x] = 1

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	var qi := 0
	var reached := 0

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

	for y in range(h):
		for x in range(w):
			var cell := origin + Vector2i(x, y)
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
	var spots: Array[Vector2i] = [
		origin + Vector2i(2, 2),
		origin + Vector2i(w - 3, 2),
		origin + Vector2i(2, h - 3),
		origin + Vector2i(w - 3, h - 3),
	]

	var n: int = mini(spots.size(), tmps.size())
	for i in range(n):
		_place_template_tile(map, spots[i], tmps[i])
