extends Node2D

@export var label_path: NodePath
@export var next_scene: PackedScene # usually Title, or Contract

@export var input_delay_sec: float = 0.25

var _label: Label
var _ready_time: float = 0.0
var _can_input: bool = false


func _ready() -> void:
	_ready_time = Time.get_ticks_msec() / 1000.0
	_label = get_node_or_null(label_path) as Label
	_refresh()


func _process(_delta: float) -> void:
	if _can_input:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if (now - _ready_time) >= input_delay_sec:
		_can_input = true


func _unhandled_input(event: InputEvent) -> void:
	if not _can_input:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		_go_next()
	elif event is InputEventMouseButton and event.pressed:
		_go_next()
	elif event is InputEventJoypadButton and event.pressed:
		_go_next()


func _refresh() -> void:
	if _label == null:
		return

	var s: Dictionary = GameManager.compute_settlement()

	var headline: String = ""
	if bool(s["ok"]):
		headline = "YOU ESCAPE!\n"
	else:
		headline = "DEBTOR'S DUNGEON.\n"

	var text: String = ""
	text += headline
	text += "\nTREASURE: %d\n" % int(s["treasure"])
	text += "DEBT:     %d\n" % int(s["debt"])
	text += "CUT (%d%%): %d\n" % [int(s["cut_pct"]), int(s["cut_amt"])]
	text += "----------------\n"
	text += "NET:      %d\n" % int(s["net"])
	text += "\nTurns: %d\n" % int(s["turns"])

	if bool(s["ok"]):
		text += "\nDetKing: \"A fair deal! (for me.)\""
	else:
		text += "\nDetKing: \"Terms were clear. The chains are too.\""

	text += "\n\nPress any key..."

	_label.text = text


func _go_next() -> void:
	if next_scene != null:
		get_tree().change_scene_to_packed(next_scene)
