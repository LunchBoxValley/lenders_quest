extends Node

@export var player_path: NodePath
@export var debt_label_path: NodePath

func _ready() -> void:
	var player := get_node_or_null(player_path)
	var label := get_node_or_null(debt_label_path) as Label

	if player != null:
		GameManager.bind_player(player)

	if label != null:
		GameManager.bind_debt_label(label)
