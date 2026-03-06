extends Node

@export var player_path: NodePath
@export var debt_label_path: NodePath

# --- Spawn more enemies at run start ---
@export var enemy_scene: PackedScene
@export var start_enemy_count: int = 3

# --- Enemy placement rules (fairness + visibility) ---
@export var randomize_start_enemies: bool = true
@export var enemy_spawn_attempts: int = 200

@export var enemy_min_dist_from_player: int = 6
@export var enemy_max_dist_from_player: int = 14  # keeps them near-ish for room camera

@export var enemy_min_dist_from_exit: int = 4
@export var enemy_max_dist_from_exit: int = 999

@export var enemy_min_dist_from_treasure: int = 4
@export var enemy_max_dist_from_treasure: int = 999

@export var enemy_min_dist_from_landmark: int = 3
@export var enemy_max_dist_from_landmark: int = 999

# --- Enemy placement tuning ---
@export var enemy_spawn_top_pool_size: int = 5
@export var enemy_prefer_spread_bonus_per_tile: int = 7
@export var enemy_prefer_player_band_center_bonus: int = 24
@export var enemy_prefer_objective_buffer_bonus: int = 3
@export var debug_print_enemy_spawn_summary: bool = false

# --- Turn feel / juice ---
@export var enemy_step_delay_sec: float = 0.03  # set to 0.3 if you want slower “click…click…click…”

var _player: Node
var _enemy_phase_running: bool = false


func _ready() -> void:
	randomize()

	_player = get_node_or_null(player_path)

	var label: Label = get_node_or_null(debt_label_path) as Label

	# Bind GameManager (safe if methods exist)
	if _player != null and GameManager.has_method("bind_player"):
		GameManager.bind_player(_player)
	if label != null and GameManager.has_method("bind_debt_label"):
		GameManager.bind_debt_label(label)

	# Ensure enemies exist + placed
	if _player != null:
		call_deferred("_ensure_spawn_and_place_enemies")

	# Listen for player turns so we can run the enemy phase
	if _player != null and _player.has_signal("turn_taken"):
		var c := Callable(self, "_on_player_turn_taken")
		if not _player.is_connected("turn_taken", c):
			_player.connect("turn_taken", c)


func _on_player_turn_taken(player_grid_pos: Vector2i) -> void:
	if _enemy_phase_running:
		return
	_enemy_phase_running = true

	# Lock player input while enemies move (prevents “double turns”)
	if _player != null and _player.has_method("set_turn_locked"):
		_player.set_turn_locked(true)

	await _run_enemy_turns(player_grid_pos)

	if _player != null and _player.has_method("set_turn_locked"):
		_player.set_turn_locked(false)

	_enemy_phase_running = false


func _run_enemy_turns(player_grid_pos: Vector2i) -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Snapshot enemies in a stable order so it feels consistent
	var enemies: Array = tree.get_nodes_in_group("enemies")
	enemies.sort_custom(func(a, b): return String(a.name) < String(b.name))

	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		if not e.has_method("take_turn"):
			continue

		await e.take_turn(player_grid_pos)

		if enemy_step_delay_sec > 0.0:
			await tree.create_timer(enemy_step_delay_sec).timeout


# ----------------------------
# Spawn + place enemies at run start
# ----------------------------
func _ensure_spawn_and_place_enemies() -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Wait 1 frame so any pre-placed enemies run _ready() and join "enemies"
	await tree.process_frame

	_ensure_enemy_count()

	# Wait 1 frame so newly spawned enemies also join "enemies"
	await tree.process_frame

	if randomize_start_enemies and _player != null:
		_reposition_start_enemies(_player)


func _ensure_enemy_count() -> void:
	if start_enemy_count <= 0:
		return

	var tree := get_tree()
	if tree == null:
		return

	var current: Array = tree.get_nodes_in_group("enemies")
	var count: int = current.size()

	if count >= start_enemy_count:
		return

	if enemy_scene == null:
		push_warning("Main.gd: enemy_scene is NOT set. Drag res://scenes/enemy.tscn into the Inspector.")
		return

	var to_make: int = start_enemy_count - count
	for i in range(to_make):
		var inst: Node = enemy_scene.instantiate()
		add_child(inst)
		inst.name = "EnemySpawned_%d" % i
		if inst is Node2D:
			(inst as Node2D).global_position = Vector2.ZERO


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _is_valid_run_cell(cell: Vector2i) -> bool:
	return cell.x <= 900000 and cell.y <= 900000


func _buffer_score(dist: int, min_dist: int, max_dist: int) -> int:
	if max_dist < min_dist:
		return 0

	var score: int = 0
	var extra: int = maxi(0, dist - min_dist)
	score += mini(extra, 6) * enemy_prefer_objective_buffer_bonus

	if max_dist < 999:
		var room_left: int = maxi(0, max_dist - dist)
		score += mini(room_left, 4)

	return score


func _player_band_center_score(dist: int) -> int:
	if enemy_max_dist_from_player <= enemy_min_dist_from_player:
		return 0

	var center: float = (float(enemy_min_dist_from_player) + float(enemy_max_dist_from_player)) * 0.5
	var diff: int = int(round(abs(float(dist) - center)))
	return maxi(0, enemy_prefer_player_band_center_bonus - diff * 6)


func _spread_score(cell: Vector2i, used: Dictionary) -> int:
	var score: int = 0
	for other in used.keys():
		var other_cell: Vector2i = other
		var d: int = _manhattan(cell, other_cell)
		score += mini(d, 6) * enemy_prefer_spread_bonus_per_tile
	return score


func _score_enemy_spawn_cell(
	cell: Vector2i,
	player_pos: Vector2i,
	exit_pos: Vector2i,
	treasure_pos: Vector2i,
	landmark_pos: Vector2i,
	used: Dictionary
) -> int:
	var score: int = 0
	var dp: int = _manhattan(cell, player_pos)
	score += _player_band_center_score(dp)
	score += _spread_score(cell, used)

	if _is_valid_run_cell(exit_pos):
		var de: int = _manhattan(cell, exit_pos)
		score += _buffer_score(de, enemy_min_dist_from_exit, enemy_max_dist_from_exit)

	if _is_valid_run_cell(treasure_pos):
		var dt: int = _manhattan(cell, treasure_pos)
		score += _buffer_score(dt, enemy_min_dist_from_treasure, enemy_max_dist_from_treasure)

	if _is_valid_run_cell(landmark_pos):
		var dl: int = _manhattan(cell, landmark_pos)
		score += _buffer_score(dl, enemy_min_dist_from_landmark, enemy_max_dist_from_landmark)

	return score


func _pick_best_enemy_spawn_cell(
	candidates: Array[Vector2i],
	player_pos: Vector2i,
	exit_pos: Vector2i,
	treasure_pos: Vector2i,
	landmark_pos: Vector2i,
	used: Dictionary,
	rng: RandomNumberGenerator
) -> Vector2i:
	var scored: Array[Dictionary] = []

	for c in candidates:
		var score: int = _score_enemy_spawn_cell(c, player_pos, exit_pos, treasure_pos, landmark_pos, used)
		scored.append({
			"cell": c,
			"score": score,
		})

	if scored.is_empty():
		return Vector2i(999999, 999999)

	scored.shuffle()
	scored.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["score"]) > int(b["score"]))

	var top_count: int = mini(enemy_spawn_top_pool_size, scored.size())
	top_count = maxi(1, top_count)
	var picked: Dictionary = scored[rng.randi_range(0, top_count - 1)]
	return picked["cell"]


func _reposition_start_enemies(player: Node) -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Require helper methods from player.gd
	if not player.has_method("get_grid_pos"):
		return
	if not player.has_method("get_walkable_floor_candidates"):
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	var player_pos: Vector2i = player.get_grid_pos()

	var exit_pos: Vector2i = Vector2i(999999, 999999)
	if player.has_method("get_run_exit_pos"):
		exit_pos = player.get_run_exit_pos()

	var treasure_pos: Vector2i = Vector2i(999999, 999999)
	if player.has_method("get_run_treasure_pos"):
		treasure_pos = player.get_run_treasure_pos()

	var landmark_pos: Vector2i = Vector2i(999999, 999999)
	if player.has_method("get_run_landmark_pos"):
		landmark_pos = player.get_run_landmark_pos()

	var candidates: Array[Vector2i] = player.get_walkable_floor_candidates(true)
	if candidates.is_empty():
		return

	var enemies: Array = tree.get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	var used: Dictionary = {}
	var summary_parts: Array[String] = []

	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		if not e.has_method("set_grid_pos"):
			continue

		var legal: Array[Vector2i] = []
		for c in candidates:
			if used.has(c):
				continue

			var dp: int = _manhattan(c, player_pos)
			if dp < enemy_min_dist_from_player or dp > enemy_max_dist_from_player:
				continue

			if _is_valid_run_cell(exit_pos):
				var de: int = _manhattan(c, exit_pos)
				if de < enemy_min_dist_from_exit or de > enemy_max_dist_from_exit:
					continue

			if _is_valid_run_cell(treasure_pos):
				var dt: int = _manhattan(c, treasure_pos)
				if dt < enemy_min_dist_from_treasure or dt > enemy_max_dist_from_treasure:
					continue

			if _is_valid_run_cell(landmark_pos):
				var dl: int = _manhattan(c, landmark_pos)
				if dl < enemy_min_dist_from_landmark or dl > enemy_max_dist_from_landmark:
					continue

			legal.append(c)

		var pick: Vector2i

		if not legal.is_empty():
			pick = _pick_best_enemy_spawn_cell(legal, player_pos, exit_pos, treasure_pos, landmark_pos, used, rng)
		else:
			# fallback: at least far from player, then still score for spread/objectives
			var fallback: Array[Vector2i] = []
			for c2 in candidates:
				if used.has(c2):
					continue
				var dp2: int = _manhattan(c2, player_pos)
				if dp2 >= enemy_min_dist_from_player:
					fallback.append(c2)

			if not fallback.is_empty():
				pick = _pick_best_enemy_spawn_cell(fallback, player_pos, exit_pos, treasure_pos, landmark_pos, used, rng)
			else:
				pick = candidates[rng.randi_range(0, candidates.size() - 1)]

		used[pick] = true
		e.set_grid_pos(pick)

		if debug_print_enemy_spawn_summary:
			var dp_pick: int = _manhattan(pick, player_pos)
			var line: String = "%s @ %s dp=%d" % [String(e.name), str(pick), dp_pick]
			if _is_valid_run_cell(treasure_pos):
				line += " dt=%d" % _manhattan(pick, treasure_pos)
			if _is_valid_run_cell(exit_pos):
				line += " de=%d" % _manhattan(pick, exit_pos)
			if _is_valid_run_cell(landmark_pos):
				line += " dl=%d" % _manhattan(pick, landmark_pos)
			summary_parts.append(line)

	if debug_print_enemy_spawn_summary and not summary_parts.is_empty():
		print("Enemy spawn summary: %s" % " | ".join(summary_parts))
