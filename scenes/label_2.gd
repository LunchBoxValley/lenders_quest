extends Label

@export var blink_period: float = 0.8

func _process(_delta: float) -> void:
	var t: float = fmod(Time.get_ticks_msec() / 1000.0, blink_period)
	visible = (t < blink_period * 0.5)
