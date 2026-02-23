extends Node2D

@export var lifetime: float = 0.12
@export var rise_px: float = 3.0
@export var spread_px: float = 3.0

var _age: float = 0.0
var _base: Vector2
var _has_setup: bool = false

func setup(start_global_pos: Vector2) -> void:
	global_position = start_global_pos
	_base = position
	_has_setup = true
	queue_redraw()

func _ready() -> void:
	randomize()
	# If someone forgot to call setup(), fall back to current position safely.
	if not _has_setup:
		_base = position
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var t := _age / lifetime
	position = _base + Vector2(0.0, -rise_px * t)
	queue_redraw()

func _draw() -> void:
	var t := _age / lifetime
	var a := 1.0 - t
	var col := Color(1, 1, 1, a)

	for i in range(3):
		var x := randf_range(-spread_px, spread_px)
		var y := randf_range(-1.0, 1.0)
		draw_rect(Rect2(Vector2(x, y), Vector2(1, 1)), col, true)
