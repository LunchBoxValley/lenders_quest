extends Camera2D

@export var default_shake_strength: float = 2.0
@export var default_shake_frames: int = 2

var _base_pos: Vector2
var _frames_left: int = 0
var _strength: float = 0.0

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
	_base_pos = position

func _process(_delta: float) -> void:
	if _frames_left > 0:
		position = _base_pos + Vector2(
			randf_range(-_strength, _strength),
			randf_range(-_strength, _strength)
		)
		_frames_left -= 1
		if _frames_left == 0:
			position = _base_pos
