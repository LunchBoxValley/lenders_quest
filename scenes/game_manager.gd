extends Node

@export var player_path: NodePath
@export var label_path: NodePath

# Core pressure numbers (tiny prototype defaults)
@export var starting_debt: int = 0
@export var interest_per_turn: int = 1

var turn_count: int = 0
var debt: int = 0

var _player: Node
var _label: Label


func _ready() -> void:
	debt = starting_debt

	_player = get_node_or_null(player_path)
	_label = get_node_or_null(label_path) as Label

	if _player != null and _player.has_signal("turn_taken"):
		_player.connect("turn_taken", Callable(self, "_on_player_turn_taken"))

	_update_hud()


func _on_player_turn_taken(_player_grid_pos: Vector2i) -> void:
	turn_count += 1
	debt += interest_per_turn
	_update_hud()


func _update_hud() -> void:
	if _label == null:
		return

	# Keep it simple: white text, no color styling yet
	_label.text = "DEBT: %d\nTURN: %d" % [debt, turn_count]
