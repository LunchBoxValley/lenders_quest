extends Node2D

@export var label_path: NodePath
@export var next_scene_file: String = "res://scenes/title.tscn"
@export var input_delay_sec: float = 0.25

var _label: Label
var _start_ms: int = 0
var _armed: bool = false
var _was_down: bool = false
var _keys: Array[int] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

	_label = get_node_or_null(label_path) as Label
	if _label == null:
		_label = get_node_or_null("HUD/ResultLabel") as Label

	_build_key_list()
	_refresh()

	_start_ms = Time.get_ticks_msec()
	_armed = false
	_was_down = _any_key_down()


func _process(_delta: float) -> void:
	if not _armed:
		var now_ms: int = Time.get_ticks_msec()
		if float(now_ms - _start_ms) / 1000.0 >= input_delay_sec:
			_armed = true
		return

	var down: bool = _any_key_down()
	if down and not _was_down:
		_go_next()
	_was_down = down


func _any_key_down() -> bool:
	for k in _keys:
		if Input.is_key_pressed(k):
			return true
	return false


func _build_key_list() -> void:
	_keys.clear()
	_keys.append(KEY_UP)
	_keys.append(KEY_DOWN)
	_keys.append(KEY_LEFT)
	_keys.append(KEY_RIGHT)
	_keys.append(KEY_SPACE)
	_keys.append(KEY_ENTER)
	_keys.append(KEY_KP_ENTER)
	_keys.append(KEY_ESCAPE)
	_keys.append(KEY_TAB)
	_keys.append(KEY_BACKSPACE)

	for k in range(KEY_0, KEY_9 + 1):
		_keys.append(k)
	for k in range(KEY_A, KEY_Z + 1):
		_keys.append(k)
	for k in range(KEY_F1, KEY_F12 + 1):
		_keys.append(k)


func _refresh() -> void:
	if _label == null:
		return

	var s: Dictionary = GameManager.compute_settlement()

	var reason: String = str(s.get("death_reason", "none"))
	var has_treasure: bool = bool(s.get("has_treasure", false))
	var ok: bool = bool(s.get("ok", false))

	var debt: int = int(s.get("debt", 0))
	var treasure: int = int(s.get("treasure", 0))
	var cut_amt: int = int(s.get("cut_amt", 0))
	var cut_pct: int = int(s.get("cut_pct", 0))
	var net: int = int(s.get("net", -debt))
	var turns: int = int(s.get("turns", 0))

	var text: String = ""

	if reason == "hp":
		text += "YOU DIED.\n"
		text += "\nTREASURE: %s\n" % (str(treasure) if has_treasure else "--")
		text += "DEBT:     %d\n" % debt
		text += "----------------\n"
		text += "NET:      %d\n" % net
		text += "\nTurns: %d\n" % turns
		text += "\nDetKing: \"Medical debt is still debt.\""
	elif not has_treasure:
		text += "YOU FLEE EMPTY-HANDED!\n"
		text += "\nTREASURE: --\n"
		text += "DEBT:     %d\n" % debt
		text += "----------------\n"
		text += "NET:      %d\n" % net
		text += "\nTurns: %d\n" % turns
		text += "\nDetKing: \"No treasure? Then YOU'LL DO.\""
	else:
		text += "YOU ESCAPE!\n" if ok else "DEBTOR'S DUNGEON.\n"
		text += "\nTREASURE: %d\n" % treasure
		text += "DEBT:     %d\n" % debt
		text += "CUT (%d%%): %d\n" % [cut_pct, cut_amt]
		text += "----------------\n"
		text += "NET:      %d\n" % net
		text += "\nTurns: %d\n" % turns
		text += "\nDetKing: \"A fair deal! (for me.)\"" if ok else "\nDetKing: \"Terms were clear. The chains are too.\""

	text += "\n\nPress any key..."
	_label.text = text


func _go_next() -> void:
	if next_scene_file == "":
		if _label != null:
			_label.text += "\n\n[ERROR] next_scene_file not set."
		return

	get_tree().call_deferred("change_scene_to_file", next_scene_file)
