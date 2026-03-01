extends Node2D

@export var capture_time: float = 0.10   # how long we record the tip path
@export var fade_time: float = 0.12      # how long we fade out
@export var max_points: int = 12         # how smooth the arc is
@export var base_width: float = 3.0
@export var base_color: Color = Color(1, 1, 1, 0.8)

@onready var line: Line2D = $Line2D

var _tip: Node2D
var _t: float = 0.0
var _phase: int = 0 # 0=capture, 1=fade


func start(tip_node: Node2D) -> void:
	_tip = tip_node
	_t = 0.0
	_phase = 0

	line.clear_points()
	line.width = base_width
	line.default_color = base_color


func _process(delta: float) -> void:
	if _tip == null:
		queue_free()
		return

	if _phase == 0:
		_t += delta

		# Add point at sword tip (converted into this node's local space)
		var p_local: Vector2 = to_local(_tip.global_position)
		line.add_point(p_local)

		# Keep recent points only
		while line.get_point_count() > max_points:
			line.remove_point(0)

		if _t >= capture_time:
			_phase = 1
			_t = 0.0

	elif _phase == 1:
		_t += delta
		var a: float = 1.0 - (_t / max(0.001, fade_time))
		a = clamp(a, 0.0, 1.0)

		var c := base_color
		c.a = base_color.a * a
		line.default_color = c
		line.width = base_width * a

		if a <= 0.0:
			queue_free()
