extends Camera2D

@export var room_width_px: int = 320
@export var room_height_px: int = 192
@export var room_slide_time: float = 0.12

@export var snap_to_whole_pixels: bool = true

# Optional shake
@export var default_shake_strength: float = 2.0
@export var default_shake_frames: int = 2

var _current_room: Vector2i = Vector2i(999999, 999999)
var _move_tween: Tween

var _base_global: Vector2 = Vector2.ZERO
var _frames_left: int = 0
var _strength: float = 0.0


func _ready() -> void:
	# We do NOT want to inherit player movement. This is a room camera.
	top_level = true
	randomize()
	_snap_to_room_of_player()
	_base_global = global_position
	_snap_if_needed()


func _process(_delta: float) -> void:
	# Keep room lock logic in _process so it can't desync with step tweens.
	_update_room_from_player()

	# Shake
	if _frames_left > 0:
		global_position = _base_global + Vector2(
			randf_range(-_strength, _strength),
			randf_range(-_strength, _strength)
		)
		_frames_left -= 1
		if _frames_left == 0:
			global_position = _base_global

	_snap_if_needed()


func shake(strength: float = -1.0, frames: int = -1) -> void:
	if strength < 0.0:
		strength = default_shake_strength
	if frames < 0:
		frames = default_shake_frames

	_strength = strength
	_frames_left = maxi(1, frames)
	_base_global = global_position


func _snap_to_room_of_player() -> void:
	var p: Node = get_parent()
	if p == null:
		return

	var r: Vector2i = _room_from_world_pos(p.global_position)
	_current_room = r
	global_position = _room_center_world(r)
	_base_global = global_position
	_snap_if_needed()


func _update_room_from_player() -> void:
	var p: Node = get_parent()
	if p == null:
		return

	var r: Vector2i = _room_from_world_pos(p.global_position)
	if r == _current_room:
		return

	_current_room = r
	var target: Vector2 = _room_center_world(r)

	# Stop any previous slide.
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	if snap_to_whole_pixels:
		target = target.round()

	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position", target, room_slide_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Keep shake base in sync after move finishes.
	_move_tween.finished.connect(func() -> void:
		_base_global = global_position
		_snap_if_needed()
	)


func _room_from_world_pos(world_pos: Vector2) -> Vector2i:
	var rx: int = int(floor(world_pos.x / float(room_width_px)))
	var ry: int = int(floor(world_pos.y / float(room_height_px)))
	return Vector2i(rx, ry)


func _room_center_world(room: Vector2i) -> Vector2:
	var cx: float = float(room.x * room_width_px) + float(room_width_px) * 0.5
	var cy: float = float(room.y * room_height_px) + float(room_height_px) * 0.5
	return Vector2(cx, cy)


func _snap_if_needed() -> void:
	if snap_to_whole_pixels:
		global_position = global_position.round()
