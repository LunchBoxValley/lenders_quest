extends Camera2D

# Screen-to-screen camera (Zelda/Isaac style)
# - ROOM: camera locks to a 320x192 “room” and slides when player enters a new room
# - FOLLOW: camera follows player (normal)

# --- Shake (uses Camera2D.offset so it won't break room tweening) ---
@export var default_shake_strength: float = 4.0
@export var default_shake_frames: int = 8

# --- Mode ---
enum CameraMode { FOLLOW, ROOM }
@export var mode: CameraMode = CameraMode.ROOM

# --- ROOM tuning ---
@export var room_width_px: int = 320
@export var room_height_px: int = 192
@export var room_slide_time: float = 0.12

# --- Pixel stability (great with CRT filters) ---
@export var snap_to_whole_pixels: bool = true

var _current_room: Vector2i = Vector2i(999999, 999999)
var _move_tween: Tween

var _shake_frames_left: int = 0
var _shake_strength: float = 0.0


func _ready() -> void:
	randomize()

	# Listen for the player's step signal (your Player emits turn_taken)
	var p: Node = get_parent()
	if p != null and p.has_signal("turn_taken"):
		var cb := Callable(self, "_on_player_turn_taken")
		if not p.is_connected("turn_taken", cb):
			p.connect("turn_taken", cb)

	_apply_mode_immediately()


# ----------------------------
# Public API
# ----------------------------
func set_follow_mode() -> void:
	mode = CameraMode.FOLLOW
	_apply_mode_immediately()

func set_room_mode(room_w: int = -1, room_h: int = -1) -> void:
	if room_w > 0:
		room_width_px = room_w
	if room_h > 0:
		room_height_px = room_h
	mode = CameraMode.ROOM
	_apply_mode_immediately()

func shake(strength: float = -1.0, frames: int = -1) -> void:
	if strength < 0.0:
		strength = default_shake_strength
	if frames < 0:
		frames = default_shake_frames

	_shake_strength = strength
	_shake_frames_left = maxi(1, frames)


# ----------------------------
# Signal hook (player step)
# ----------------------------
func _on_player_turn_taken(_player_grid_pos: Vector2i) -> void:
	if mode == CameraMode.ROOM:
		_update_room_from_player()


# ----------------------------
# Mode setup
# ----------------------------
func _apply_mode_immediately() -> void:
	# Kill motion tween
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	offset = Vector2.ZERO

	if mode == CameraMode.FOLLOW:
		# Let being a child of the Player do the work.
		top_level = false
		position = Vector2.ZERO
		_current_room = Vector2i(999999, 999999)
		return

	# ROOM mode: decouple from player transform
	top_level = true
	_snap_to_room_of_player()


# ----------------------------
# ROOM mode logic
# ----------------------------
func _snap_to_room_of_player() -> void:
	var p: Node2D = get_parent() as Node2D
	if p == null:
		return

	var r: Vector2i = _room_from_world_pos(p.global_position)
	_current_room = r
	global_position = _room_center_world(r)
	_snap_if_needed()

func _update_room_from_player() -> void:
	var p: Node2D = get_parent() as Node2D
	if p == null:
		return

	var r: Vector2i = _room_from_world_pos(p.global_position)
	if r == _current_room:
		return

	_current_room = r
	var target: Vector2 = _room_center_world(r)
	_tween_to_global(target, room_slide_time)

func _room_from_world_pos(world_pos: Vector2) -> Vector2i:
	var rx: int = int(floor(world_pos.x / float(room_width_px)))
	var ry: int = int(floor(world_pos.y / float(room_height_px)))
	return Vector2i(rx, ry)

func _room_center_world(room: Vector2i) -> Vector2:
	var cx: float = float(room.x * room_width_px) + float(room_width_px) * 0.5
	var cy: float = float(room.y * room_height_px) + float(room_height_px) * 0.5
	return Vector2(cx, cy)

func _tween_to_global(target: Vector2, t: float) -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	if snap_to_whole_pixels:
		target = target.round()

	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position", target, t)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)


# ----------------------------
# Per-frame: shake + pixel snap
# ----------------------------
func _process(_delta: float) -> void:
	# Shake uses offset so it won't fight the room slide tween
	if _shake_frames_left > 0:
		offset = Vector2(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength)
		)
		_shake_frames_left -= 1
		if _shake_frames_left == 0:
			offset = Vector2.ZERO
	else:
		offset = Vector2.ZERO

	_snap_if_needed()

func _snap_if_needed() -> void:
	if snap_to_whole_pixels:
		global_position = global_position.round()
