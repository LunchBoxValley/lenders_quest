extends Node2D

@export var next_scene: PackedScene

@export var start_delay_sec: float = 0.15
var _ready_time: float = 0.0
var _can_start: bool = false


func _ready() -> void:
	_ready_time = Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	# Tiny delay so the same key used to run the game doesn't instantly skip.
	var now: float = Time.get_ticks_msec() / 1000.0
	if not _can_start and (now - _ready_time) >= start_delay_sec:
		_can_start = true


func _unhandled_input(event: InputEvent) -> void:
	if not _can_start:
		return

	# Any key, any button, any click
	if event is InputEventKey and event.pressed and not event.echo:
		_go_next()
	elif event is InputEventMouseButton and event.pressed:
		_go_next()
	elif event is InputEventJoypadButton and event.pressed:
		_go_next()


func _go_next() -> void:
	if next_scene == null:
		return

	# Optional tiny click feedback later; keep simple now.
	get_tree().change_scene_to_packed(next_scene)
