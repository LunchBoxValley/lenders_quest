extends Node

@export var player_path: NodePath
@export var debt_label_path: NodePath
@export var toast_label_path: NodePath = ^"Hud/ToastLabel"

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

# --- Lightweight spawn roles (future-safe for bigger map types) ---
@export var enemy_spawn_roles_enabled: bool = true
@export var enemy_treasure_pressure_count: int = 1
@export var enemy_flanker_count: int = 1
@export var enemy_treasure_pressure_bonus_per_tile: int = 14
@export var enemy_treasure_pressure_falloff_tiles: int = 6
@export var enemy_flanker_far_player_bonus_per_tile: int = 7
@export var enemy_flanker_objective_distance_bonus_per_tile: int = 2

# --- Treasure found response (small prototype-safe escalation) ---
@export var treasure_found_role_response_enabled: bool = true
@export var treasure_pressure_extra_turns_after_treasure: int = 2
@export var flanker_extra_turns_after_treasure: int = 1
@export var neutral_extra_turns_after_treasure: int = 1

@export var treasure_found_spawn_reinforcements: bool = true
@export var treasure_found_bonus_spawn_count: int = 1
@export var treasure_found_min_total_enemies: int = 3
@export var treasure_found_max_total_enemies: int = 5
@export var debug_print_treasure_response_summary: bool = false

# --- Turn feel / juice ---
@export var enemy_step_delay_sec: float = 0.03  # set to 0.3 if you want slower “click…click…click…”

# --- Enemy spawn readability / juice ---
@export var enemy_spawn_delay_sec: float = 0.75
@export var enemy_spawn_fx_enabled: bool = true
@export var enemy_spawn_fx_scene: PackedScene
@export var enemy_spawn_fx_duration_sec: float = 0.95
@export var enemy_spawn_fx_puff_count: int = 8
@export var enemy_spawn_fx_reveal_delay_sec: float = 0.35
@export var enemy_spawn_fx_spread_radius_px: float = 14.0

# --- Treasure escape phase signal / readability ---
@export var treasure_phase_toasts_enabled: bool = true
@export var treasure_found_banner_text: String = "TREASURE FOUND!"
@export var debt_collectors_banner_text: String = "Debt Collectors: Clocked In!"
@export var escape_banner_text: String = "ESCAPE TO THE EXIT!"
@export var treasure_phase_toast_hold_sec: float = 0.72
@export var show_escape_banner_after_treasure_sequence: bool = true

enum SpawnRole {
	NEUTRAL,
	TREASURE_PRESSURE,
	FLANKER,
}

class SpawnPuffFx extends Node2D:
	var duration: float = 0.95
	var puff_count: int = 8
	var spread_radius_px: float = 14.0
	var elapsed: float = 0.0
	var circles: Array[Dictionary] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	func setup(duration_sec: float, count: int, spread_radius: float) -> void:
		duration = duration_sec
		if duration < 0.05:
			duration = 0.05
		puff_count = maxi(1, count)
		spread_radius_px = spread_radius
		if spread_radius_px < 2.0:
			spread_radius_px = 2.0
		elapsed = 0.0
		circles.clear()

		rng.randomize()

		for _i in range(puff_count):
			var angle: float = rng.randf_range(0.0, TAU)
			var start_dist: float = rng.randf_range(0.0, spread_radius_px * 0.35)
			var start_offset: Vector2 = Vector2.RIGHT.rotated(angle) * start_dist
			var drift_dir: Vector2 = Vector2.RIGHT.rotated(angle + rng.randf_range(-0.8, 0.8))
			var drift_speed: float = rng.randf_range(spread_radius_px * 0.55, spread_radius_px * 1.2)
			var start_radius: float = rng.randf_range(3.0, 6.5)
			var end_radius: float = start_radius * rng.randf_range(1.6, 2.25)
			var alpha: float = rng.randf_range(0.42, 0.72)

			circles.append({
				"start_offset": start_offset,
				"drift_dir": drift_dir,
				"drift_speed": drift_speed,
				"start_radius": start_radius,
				"end_radius": end_radius,
				"alpha": alpha,
			})

		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		elapsed += delta
		if elapsed >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = 0.0
		if duration > 0.0:
			t = clampf(elapsed / duration, 0.0, 1.0)

		for item in circles:
			var start_offset: Vector2 = item["start_offset"]
			var drift_dir: Vector2 = item["drift_dir"]
			var drift_speed: float = item["drift_speed"]
			var start_radius: float = item["start_radius"]
			var end_radius: float = item["end_radius"]
			var alpha: float = item["alpha"]

			var rise: Vector2 = Vector2(0.0, -spread_radius_px * 0.55 * t)
			var drift: Vector2 = drift_dir * drift_speed * t
			var draw_pos: Vector2 = start_offset + rise + drift
			var radius: float = lerpf(start_radius, end_radius, t)
			var draw_alpha: float = alpha * (1.0 - t)

			draw_circle(draw_pos, radius, Color(0.75, 0.75, 0.78, draw_alpha))



var _player: Node
var _enemy_phase_running: bool = false
var _treasure_found_handled: bool = false
var _runtime_enemy_spawn_serial: int = 0
var _toast_label: Label
var _main_toast_token: int = 0


func _ready() -> void:
	randomize()

	_player = get_node_or_null(player_path)

	var label: Label = get_node_or_null(debt_label_path) as Label
	_toast_label = get_node_or_null(toast_label_path) as Label

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


func _show_phase_toast(message: String) -> void:
	if not treasure_phase_toasts_enabled:
		return
	if message.strip_edges().is_empty():
		return

	if _player != null and _player.has_method("_show_toast"):
		await _player._show_toast(message, treasure_phase_toast_hold_sec)
		return

	if _toast_label == null:
		return

	_main_toast_token += 1
	var my_token: int = _main_toast_token
	_toast_label.text = message
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(treasure_phase_toast_hold_sec).timeout
	if my_token == _main_toast_token and _toast_label != null:
		_toast_label.text = ""


func _on_player_turn_taken(player_grid_pos: Vector2i) -> void:
	if _enemy_phase_running:
		return
	_enemy_phase_running = true

	# Lock player input while enemies move (prevents “double turns”)
	if _player != null and _player.has_method("set_turn_locked"):
		_player.set_turn_locked(true)

	if GameManager.has_treasure and not _treasure_found_handled:
		await _handle_treasure_found_response(player_grid_pos)

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



func _set_enemy_canvas_visible(enemy: Node, is_visible: bool) -> void:
	var canvas: CanvasItem = enemy as CanvasItem
	if canvas != null:
		canvas.visible = is_visible


func _queue_temp_node_cleanup(node: Node, delay_sec: float) -> void:
	if node == null or not is_instance_valid(node):
		return

	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = delay_sec
	if timer.wait_time < 0.05:
		timer.wait_time = 0.05
	add_child(timer)

	var c := Callable(self, "_on_temp_cleanup_timer_timeout").bind(node, timer)
	timer.timeout.connect(c)
	timer.start()


func _on_temp_cleanup_timer_timeout(node: Node, timer: Timer) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	if timer != null and is_instance_valid(timer):
		timer.queue_free()


func _play_enemy_spawn_fx_at(world_pos: Vector2) -> void:
	if not enemy_spawn_fx_enabled:
		return

	if enemy_spawn_fx_scene != null:
		var fx: Node = enemy_spawn_fx_scene.instantiate()
		add_child(fx)

		var fx_2d: Node2D = fx as Node2D
		if fx_2d != null:
			fx_2d.top_level = true
			fx_2d.global_position = world_pos
			fx_2d.z_index = 100

		if fx.has_method("restart"):
			fx.call("restart")
		elif fx.has_method("play"):
			fx.call("play")

		_queue_temp_node_cleanup(fx, enemy_spawn_fx_duration_sec)
		return

	var puff: SpawnPuffFx = SpawnPuffFx.new()
	add_child(puff)
	puff.top_level = true
	puff.global_position = world_pos
	puff.z_index = 100
	puff.setup(enemy_spawn_fx_duration_sec, enemy_spawn_fx_puff_count, enemy_spawn_fx_spread_radius_px)


func _run_spawn_reveal_sequence(enemy: Node) -> void:
	var tree := get_tree()
	if tree == null:
		_set_enemy_canvas_visible(enemy, true)
		return

	if not enemy_spawn_fx_enabled:
		_set_enemy_canvas_visible(enemy, true)
		if enemy_spawn_delay_sec > 0.0:
			await tree.create_timer(enemy_spawn_delay_sec).timeout
		return

	var enemy_2d: Node2D = enemy as Node2D
	if enemy_2d == null:
		_set_enemy_canvas_visible(enemy, true)
		if enemy_spawn_delay_sec > 0.0:
			await tree.create_timer(enemy_spawn_delay_sec).timeout
		return

	var reveal_delay: float = enemy_spawn_fx_reveal_delay_sec
	if reveal_delay < 0.0:
		reveal_delay = 0.0

	_set_enemy_canvas_visible(enemy, false)
	_play_enemy_spawn_fx_at(enemy_2d.global_position)

	if reveal_delay > 0.0:
		await tree.create_timer(reveal_delay).timeout

	_set_enemy_canvas_visible(enemy, true)

	var remaining_delay: float = enemy_spawn_delay_sec - reveal_delay
	if remaining_delay > 0.0:
		await tree.create_timer(remaining_delay).timeout

func _handle_treasure_found_response(_player_grid_pos: Vector2i) -> void:
	_treasure_found_handled = true

	await _show_phase_toast(treasure_found_banner_text)

	if treasure_found_role_response_enabled:
		_apply_post_treasure_enemy_tuning()

	var spawned_count: int = 0
	if treasure_found_spawn_reinforcements and _player != null:
		spawned_count = await _spawn_treasure_found_reinforcements(_player)

	if spawned_count > 0:
		await _show_phase_toast(debt_collectors_banner_text)

	if show_escape_banner_after_treasure_sequence:
		await _show_phase_toast(escape_banner_text)

	if debug_print_treasure_response_summary:
		print("Treasure response: alive=%d spawned=%d" % [_get_alive_enemy_count(), spawned_count])


func _get_alive_enemy_count() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var count: int = 0
	for e in tree.get_nodes_in_group("enemies"):
		if e != null and is_instance_valid(e):
			count += 1
	return count


func _extra_turns_for_spawn_role_name(role_name: String) -> int:
	match role_name:
		"treasure_pressure":
			return maxi(0, treasure_pressure_extra_turns_after_treasure)
		"flanker":
			return maxi(0, flanker_extra_turns_after_treasure)
		_:
			return maxi(0, neutral_extra_turns_after_treasure)


func _apply_post_treasure_enemy_tuning() -> void:
	var tree := get_tree()
	if tree == null:
		return

	var enemies: Array = tree.get_nodes_in_group("enemies")
	enemies.sort_custom(func(a, b): return String(a.name) < String(b.name))

	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue

		var role_name: String = "neutral"
		if e.has_meta("spawn_role"):
			role_name = String(e.get_meta("spawn_role"))

		e.set("extra_turns_when_player_has_treasure", _extra_turns_for_spawn_role_name(role_name))
		e.set_meta("post_treasure_alerted", true)


func _spawn_treasure_found_reinforcements(player: Node) -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	if enemy_scene == null:
		push_warning("Main.gd: enemy_scene is NOT set. Cannot spawn treasure-found reinforcements.")
		return 0

	var alive_now: int = _get_alive_enemy_count()
	var needed_for_floor: int = maxi(0, treasure_found_min_total_enemies - alive_now)
	var spawn_count: int = maxi(maxi(0, treasure_found_bonus_spawn_count), needed_for_floor)

	if treasure_found_max_total_enemies > 0:
		var room_left: int = maxi(0, treasure_found_max_total_enemies - alive_now)
		spawn_count = mini(spawn_count, room_left)

	if spawn_count <= 0:
		return 0

	var spawned: Array = []
	for _i in range(spawn_count):
		var inst: Node = enemy_scene.instantiate()
		add_child(inst)
		_runtime_enemy_spawn_serial += 1
		inst.name = "EnemySpawned_%d" % _runtime_enemy_spawn_serial
		if inst is Node2D:
			(inst as Node2D).global_position = Vector2.ZERO
		inst.set_meta("spawn_fx_pending", true)
		spawned.append(inst)

	await tree.process_frame

	var roles: Array[int] = _build_enemy_spawn_roles(spawned.size())
	await _place_enemy_batch(player, spawned, roles)

	if treasure_found_role_response_enabled:
		for inst in spawned:
			if inst == null or not is_instance_valid(inst):
				continue
			var role_name: String = "neutral"
			if inst.has_meta("spawn_role"):
				role_name = String(inst.get_meta("spawn_role"))
			inst.set("extra_turns_when_player_has_treasure", _extra_turns_for_spawn_role_name(role_name))
			inst.set_meta("spawned_after_treasure_found", true)

	if debug_print_treasure_response_summary:
		var parts: Array[String] = []
		for inst2 in spawned:
			if inst2 == null or not is_instance_valid(inst2):
				continue
			var pos_text: String = "?"
			if inst2.has_method("get_grid_pos"):
				pos_text = str(inst2.get_grid_pos())
			parts.append("%s[%s] @ %s" % [String(inst2.name), String(inst2.get_meta("spawn_role", "neutral")), pos_text])
		if not parts.is_empty():
			print("Treasure reinforcements: %s" % " | ".join(parts))

	return spawned.size()


func _build_skip_enemy_lookup(enemies: Array) -> Dictionary:
	var lookup: Dictionary = {}
	for e in enemies:
		lookup[e] = true
	return lookup


func _collect_used_enemy_cells(skip_lookup: Dictionary) -> Dictionary:
	var tree := get_tree()
	var used: Dictionary = {}
	if tree == null:
		return used

	var current: Array = tree.get_nodes_in_group("enemies")
	for e in current:
		if e == null or not is_instance_valid(e):
			continue
		if skip_lookup.has(e):
			continue
		if not e.has_method("get_grid_pos"):
			continue
		var pos: Vector2i = e.get_grid_pos()
		used[pos] = true

	return used


func _place_enemy_batch(player: Node, enemies: Array, roles: Array[int]) -> void:
	var tree := get_tree()
	if tree == null:
		return

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

	var skip_lookup: Dictionary = _build_skip_enemy_lookup(enemies)
	var used: Dictionary = _collect_used_enemy_cells(skip_lookup)
	var summary_parts: Array[String] = []

	for i in range(enemies.size()):
		var e: Node = enemies[i]
		if e == null or not is_instance_valid(e):
			continue
		if not e.has_method("set_grid_pos"):
			continue

		var role: int = SpawnRole.NEUTRAL
		if i < roles.size():
			role = roles[i]

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
			pick = _pick_best_enemy_spawn_cell(legal, role, player_pos, exit_pos, treasure_pos, landmark_pos, used, rng)
		else:
			var fallback: Array[Vector2i] = []
			for c2 in candidates:
				if used.has(c2):
					continue
				var dp2: int = _manhattan(c2, player_pos)
				if dp2 >= enemy_min_dist_from_player:
					fallback.append(c2)

			if not fallback.is_empty():
				pick = _pick_best_enemy_spawn_cell(fallback, role, player_pos, exit_pos, treasure_pos, landmark_pos, used, rng)
			else:
				pick = candidates[rng.randi_range(0, candidates.size() - 1)]

		used[pick] = true
		e.set_grid_pos(pick)
		e.set_meta("spawn_role", _spawn_role_name(role))

		var use_spawn_fx: bool = bool(e.get_meta("spawn_fx_pending", false))
		if use_spawn_fx:
			await _run_spawn_reveal_sequence(e)
			e.set_meta("spawn_fx_pending", false)
		else:
			_set_enemy_canvas_visible(e, true)

		if debug_print_enemy_spawn_summary:
			var dp_pick: int = _manhattan(pick, player_pos)
			var line: String = "%s[%s] @ %s dp=%d" % [String(e.name), _spawn_role_name(role), str(pick), dp_pick]
			if _is_valid_run_cell(treasure_pos):
				line += " dt=%d" % _manhattan(pick, treasure_pos)
			if _is_valid_run_cell(exit_pos):
				line += " de=%d" % _manhattan(pick, exit_pos)
			if _is_valid_run_cell(landmark_pos):
				line += " dl=%d" % _manhattan(pick, landmark_pos)
			summary_parts.append(line)

	if debug_print_enemy_spawn_summary and not summary_parts.is_empty():
		print("Enemy spawn summary: %s" % " | ".join(summary_parts))

# ----------------------------
# Spawn + place enemies at run start
# ----------------------------
func _ensure_spawn_and_place_enemies() -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Wait 1 frame so any pre-placed enemies run _ready() and join "enemies"
	await tree.process_frame

	if _player != null and _player.has_method("set_turn_locked"):
		_player.set_turn_locked(true)

	_ensure_enemy_count()

	# Wait 1 frame so newly spawned enemies also join "enemies"
	await tree.process_frame

	if randomize_start_enemies and _player != null:
		await _reposition_start_enemies(_player)

	if _player != null and _player.has_method("set_turn_locked"):
		_player.set_turn_locked(false)


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
	for _i in range(to_make):
		var inst: Node = enemy_scene.instantiate()
		add_child(inst)
		_runtime_enemy_spawn_serial += 1
		inst.name = "EnemySpawned_%d" % _runtime_enemy_spawn_serial
		if inst is Node2D:
			(inst as Node2D).global_position = Vector2.ZERO
		inst.set_meta("spawn_fx_pending", true)


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


func _closeness_to_min_edge_score(dist: int, min_dist: int, max_falloff_tiles: int, per_tile: int) -> int:
	if dist < min_dist:
		return 0
	var extra: int = dist - min_dist
	var closeness: int = maxi(0, max_falloff_tiles - extra)
	return closeness * per_tile


func _role_score(
	cell: Vector2i,
	role: int,
	player_pos: Vector2i,
	exit_pos: Vector2i,
	treasure_pos: Vector2i,
	landmark_pos: Vector2i
) -> int:
	var score: int = 0

	match role:
		SpawnRole.TREASURE_PRESSURE:
			if _is_valid_run_cell(treasure_pos):
				var dt: int = _manhattan(cell, treasure_pos)
				score += _closeness_to_min_edge_score(
					dt,
					enemy_min_dist_from_treasure,
					enemy_treasure_pressure_falloff_tiles,
					enemy_treasure_pressure_bonus_per_tile
				)
			if _is_valid_run_cell(exit_pos):
				var de: int = _manhattan(cell, exit_pos)
				score += mini(de, 4) * enemy_flanker_objective_distance_bonus_per_tile

		SpawnRole.FLANKER:
			var dp: int = _manhattan(cell, player_pos)
			score += mini(maxi(0, dp - enemy_min_dist_from_player), 6) * enemy_flanker_far_player_bonus_per_tile

			if _is_valid_run_cell(treasure_pos):
				var dt2: int = _manhattan(cell, treasure_pos)
				score += mini(dt2, 6) * enemy_flanker_objective_distance_bonus_per_tile

			if _is_valid_run_cell(exit_pos):
				var de2: int = _manhattan(cell, exit_pos)
				score += mini(de2, 6) * enemy_flanker_objective_distance_bonus_per_tile

			if _is_valid_run_cell(landmark_pos):
				var dl: int = _manhattan(cell, landmark_pos)
				score += mini(dl, 4) * enemy_flanker_objective_distance_bonus_per_tile

		_:
			pass

	return score


func _score_enemy_spawn_cell(
	cell: Vector2i,
	role: int,
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

	score += _role_score(cell, role, player_pos, exit_pos, treasure_pos, landmark_pos)

	return score


func _pick_best_enemy_spawn_cell(
	candidates: Array[Vector2i],
	role: int,
	player_pos: Vector2i,
	exit_pos: Vector2i,
	treasure_pos: Vector2i,
	landmark_pos: Vector2i,
	used: Dictionary,
	rng: RandomNumberGenerator
) -> Vector2i:
	var scored: Array[Dictionary] = []

	for c in candidates:
		var score: int = _score_enemy_spawn_cell(c, role, player_pos, exit_pos, treasure_pos, landmark_pos, used)
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


func _build_enemy_spawn_roles(enemy_count: int) -> Array[int]:
	var roles: Array[int] = []

	if not enemy_spawn_roles_enabled:
		for _i in range(enemy_count):
			roles.append(SpawnRole.NEUTRAL)
		return roles

	for _i in range(enemy_treasure_pressure_count):
		if roles.size() >= enemy_count:
			break
		roles.append(SpawnRole.TREASURE_PRESSURE)

	for _i in range(enemy_flanker_count):
		if roles.size() >= enemy_count:
			break
		roles.append(SpawnRole.FLANKER)

	while roles.size() < enemy_count:
		roles.append(SpawnRole.NEUTRAL)

	return roles


func _spawn_role_name(role: int) -> String:
	match role:
		SpawnRole.TREASURE_PRESSURE:
			return "treasure_pressure"
		SpawnRole.FLANKER:
			return "flanker"
		_:
			return "neutral"


func _reposition_start_enemies(player: Node) -> void:
	var tree := get_tree()
	if tree == null:
		return

	var enemies: Array = tree.get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	enemies.sort_custom(func(a, b): return String(a.name) < String(b.name))

	var roles: Array[int] = _build_enemy_spawn_roles(enemies.size())
	await _place_enemy_batch(player, enemies, roles)
