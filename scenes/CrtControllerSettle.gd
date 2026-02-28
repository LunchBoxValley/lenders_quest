extends CanvasLayer

@export var crt_path: NodePath
var _enabled: bool = true

func _ready() -> void:
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_crt"):
		_enabled = not _enabled
		_apply()
		print("CRT:", "ON" if _enabled else "OFF")

func _apply() -> void:
	var crt := get_node_or_null(crt_path) as CanvasItem
	if crt != null:
		crt.visible = _enabled
