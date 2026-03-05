extends Node

@export var player_path: NodePath
@export var debt_label_path: NodePath

# ------------------------------------------------
# Enemy start placement rules (fairness)
# ------------------------------------------------
@export var randomize_start_enemies: bool = true
@export var enemy_spawn_attempts: int = 200

@export var enemy_min_dist_from_player: int = 6
@export var enemy_max_dist_from_player: int = 999

@export var enemy_min_dist_from_exit: int = 4
@export var enemy_max_dist_from_exit: int = 999

@export var enemy_min_dist_from_treasure: int = 4
@export var enemy_max_dist_from_treasure: int = 999


func _ready() -> void:
	var player: Node = get_node_or_null(player_path)
	var label: Label = get_node_or_null(debt_label_path) as Label

	if player != null:
		GameManager.bind_player(player)

	if label != null:
		GameManager.bind_debt_label(label)

	# Reposition any pre-placed enemies so they don't spawn unfairly close
	if randomize_start_enemies and player != null:
		call_deferred("_reposition_start_enemies", player)


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _reposition_start_enemies(player: Node) -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Require player helper methods from patched player.gd
	if not player.has_method("get_grid_pos"):
		return
	if not player.has_method("get_walkable_floor_candidates"):
		return

	var player_pos: Vector2i = player.get_grid_pos()

	var exit_pos: Vector2i = Vector2i(999999, 999999)
	if player.has_method("get_run_exit_pos"):
		exit_pos = player.get_run_exit_pos()

	var treasure_pos: Vector2i = Vector2i(999999, 999999)
	if player.has_method("get_run_treasure_pos"):
		treasure_pos = player.get_run_treasure_pos()

	# Candidates from player (already excludes blocked/hazard/door/exit/treasure/landmark and the player tile)
	var candidates: Array[Vector2i] = player.get_walkable_floor_candidates(true)
	if candidates.is_empty():
		return

	var enemies: Array = tree.get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	var used: Dictionary = {} # Vector2i -> bool

	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue

		# We only reposition enemies that support set_grid_pos (patched enemy.gd includes it)
		if not e.has_method("set_grid_pos"):
			continue

		# Build legal list for THIS enemy
		var legal: Array[Vector2i] = []
		for c in candidates:
			if used.has(c):
				continue

			var dp: int = _manhattan(c, player_pos)
			if dp < enemy_min_dist_from_player or dp > enemy_max_dist_from_player:
				continue

			if exit_pos.x < 900000:
				var de: int = _manhattan(c, exit_pos)
				if de < enemy_min_dist_from_exit or de > enemy_max_dist_from_exit:
					continue

			if treasure_pos.x < 900000:
				var dt: int = _manhattan(c, treasure_pos)
				if dt < enemy_min_dist_from_treasure or dt > enemy_max_dist_from_treasure:
					continue

			legal.append(c)

		var pick: Vector2i = Vector2i(999999, 999999)

		if not legal.is_empty():
			pick = legal[randi() % legal.size()]
		else:
			# Fallback: at least satisfy min distance from player
			var fallback: Array[Vector2i] = []
			for c2 in candidates:
				if used.has(c2):
					continue
				var dp2: int = _manhattan(c2, player_pos)
				if dp2 >= enemy_min_dist_from_player:
					fallback.append(c2)

			if not fallback.is_empty():
				pick = fallback[randi() % fallback.size()]
			else:
				pick = candidates[randi() % candidates.size()]

		used[pick] = true
		e.set_grid_pos(pick)
