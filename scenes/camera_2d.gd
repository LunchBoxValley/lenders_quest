extends Camera2D

@export var default_shake_strength: float = 2.0
@export var default_shake_frames: int = 2

# NEW: makes shake feel like a quick "kick" instead of wobble
@export var shake_decay_power: float = 3.0  # higher = snappier fade-out
@export var snappy_kick_mode: bool = true   # true = kick in one direction (recommended)

var _base_pos: Vector2 = Vector2.ZERO
var _frames_left: int = 0
var _frames_total: int = 0
var _strength: float = 0.0
var _kick_dir: Vector2 = Vector2.RIGHT


func _ready() -> void:
	_base_pos = position
	randomize()


func shake(strength: float = -1.0, frames: int = -1) -> void:
	if strength < 0.0:
		strength = default_shake_strength
	if frames < 0:
		frames = default_shake_frames

	_strength = strength
	_frames_left = maxi(1, frames)
	_frames_total = _frames_left
	_base_pos = position

	# Pick one direction for the whole shake (snappy "kick")
	var d := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if d.length() < 0.001:
		d = Vector2.RIGHT
	_kick_dir = d.normalized()


func _process(_delta: float) -> void:
	if _frames_left <= 0:
		return

	# 1.0 -> 0.0 over time
	var t: float = float(_frames_left) / float(_frames_total)
	# Fast decay makes it snappy
	var amp: float = _strength * pow(t, shake_decay_power)

	if snappy_kick_mode:
		position = _base_pos + (_kick_dir * amp)
	else:
		position = _base_pos + Vector2(
			randf_range(-amp, amp),
			randf_range(-amp, amp)
		)

	_frames_left -= 1
	if _frames_left == 0:
		position = _base_pos
