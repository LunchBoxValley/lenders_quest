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


func _reposition_start_enemies(player: Node) -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Require helper methods from player.gd
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

	var candidates: Array[Vector2i] = player.get_walkable_floor_candidates(true)
	if candidates.is_empty():
		return

	var enemies: Array = tree.get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	var used: Dictionary = {}

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

			if exit_pos.x < 900000:
				var de: int = _manhattan(c, exit_pos)
				if de < enemy_min_dist_from_exit or de > enemy_max_dist_from_exit:
					continue

			if treasure_pos.x < 900000:
				var dt: int = _manhattan(c, treasure_pos)
				if dt < enemy_min_dist_from_treasure or dt > enemy_max_dist_from_treasure:
					continue

			legal.append(c)

		var pick: Vector2i

		if not legal.is_empty():
			pick = legal[randi() % legal.size()]
		else:
			# fallback: at least far from player
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
