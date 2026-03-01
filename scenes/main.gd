extends Node2D

@export var player_path: NodePath = NodePath("Player")
@export var debt_label_path: NodePath = NodePath("Hud/DebtLabel")

@export var toast_label_path: NodePath = NodePath("Hud/ToastLabel")
@export var collector_toast_delay: float = 1.25
@export var collector_toast_duration: float = 1.10

@export var collector_spawn_path: NodePath = NodePath("CollectorSpawn")
@export var enemy_template_path: NodePath = NodePath("Enemy")

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

var _player: Node = null
var _toast_label: Label = null
var _toast_token: int = 0

var _prev_has_treasure: bool = false
var _collector_spawned: bool = false


func _ready() -> void:
	_player = get_node_or_null(player_path)
	var label := get_node_or_null(debt_label_path) as Label
	_toast_label = get_node_or_null(toast_label_path) as Label

	if _player != null:
		GameManager.bind_player(_player)

		if _player.has_signal("turn_taken"):
			var c := Callable(self, "_on_player_turn_taken")
			if not _player.is_connected("turn_taken", c):
				_player.connect("turn_taken", c)

	if label != null:
		GameManager.bind_debt_label(label)

	_prev_has_treasure = GameManager.has_treasure


func _on_player_turn_taken(_player_grid_pos: Vector2i) -> void:
	if (not _prev_has_treasure) and GameManager.has_treasure:
		_prev_has_treasure = true
		_spawn_collector_once()


func _spawn_collector_once() -> void:
	if _collector_spawned:
		return
	_collector_spawned = true

	var spawn_node := get_node_or_null(collector_spawn_path) as Node2D
	var spawn_pos: Vector2 = Vector2.ZERO

	if spawn_node != null:
		spawn_pos = spawn_node.global_position
	else:
		var template_enemy := get_node_or_null(enemy_template_path) as Node2D
		if template_enemy != null:
			spawn_pos = template_enemy.global_position
		elif _player != null and _player is Node2D:
			spawn_pos = (_player as Node2D).global_position

	var collector := ENEMY_SCENE.instantiate() as Node2D
	collector.name = "Collector"
	collector.global_position = spawn_pos

	# Copy important exported settings from existing Enemy instance (safe property copy)
	var template := get_node_or_null(enemy_template_path)
	if template != null:
		_copy_prop_if_exists(collector, template, &"map_path")
		_copy_prop_if_exists(collector, template, &"player_path")
		_copy_prop_if_exists(collector, template, &"camera_path")
		_copy_prop_if_exists(collector, template, &"step_dust_scene")

	add_child(collector)

	_show_toast_delayed("DetKing: \"Collectors, clock in.\"", collector_toast_delay, collector_toast_duration)


func _has_prop(obj: Object, prop: StringName) -> bool:
	for p in obj.get_property_list():
		if p.name == prop:
			return true
	return false


func _copy_prop_if_exists(dst: Object, src: Object, prop: StringName) -> void:
	if dst == null or src == null:
		return
	if _has_prop(dst, prop) and _has_prop(src, prop):
		dst.set(prop, src.get(prop))


func _show_toast_delayed(text: String, delay_sec: float, duration_sec: float) -> void:
	if _toast_label == null:
		return

	_toast_token += 1
	var my_token := _toast_token
	_call_later(text, delay_sec, duration_sec, my_token)


func _call_later(text: String, delay_sec: float, duration_sec: float, token: int) -> void:
	await get_tree().create_timer(delay_sec).timeout
	if token != _toast_token:
		return
	if _toast_label == null:
		return

	_toast_label.text = text

	await get_tree().create_timer(duration_sec).timeout
	if token != _toast_token:
		return
	if _toast_label == null:
		return

	if _toast_label.text == text:
		_toast_label.text = ""
