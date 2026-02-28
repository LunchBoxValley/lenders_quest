extends Node

@export var interest_per_turn: int = 1

# Tutorial treasure range (tune later)
@export var treasure_min_value: int = 60
@export var treasure_max_value: int = 120

# Contract terms
var contract_loan: int = 0
var contract_interest: float = 0.0
var contract_cut: float = 0.0

# Run state
var turn_count: int = 0
var debt: int = 0

# Treasure state
var has_treasure: bool = false
var treasure_value: int = 0

var _player: Node
var _label: Label


func bind_player(player: Node) -> void:
	if _player != null and _player.has_signal("turn_taken"):
		var c := Callable(self, "_on_player_turn_taken")
		if _player.is_connected("turn_taken", c):
			_player.disconnect("turn_taken", c)

	_player = player

	if _player != null and _player.has_signal("turn_taken"):
		var c2 := Callable(self, "_on_player_turn_taken")
		if not _player.is_connected("turn_taken", c2):
			_player.connect("turn_taken", c2)


func bind_debt_label(label: Label) -> void:
	_label = label
	_update_hud()


func set_contract(loan_amount: int, interest_rate: float, cut_rate: float) -> void:
	contract_loan = loan_amount
	contract_interest = interest_rate
	contract_cut = cut_rate

	turn_count = 0
	debt = loan_amount
	has_treasure = false
	treasure_value = 0

	_update_hud()


func roll_treasure_value() -> int:
	var lo: int = min(treasure_min_value, treasure_max_value)
	var hi: int = max(treasure_min_value, treasure_max_value)
	return randi_range(lo, hi)


func found_treasure(value: int) -> void:
	if has_treasure:
		return
	has_treasure = true
	treasure_value = max(0, value)
	_update_hud()


func compute_settlement() -> Dictionary:
	# DetKing takes a cut of the treasure (rounded UP, because… DetKing).
	var cut_amt: int = int(ceil(float(treasure_value) * contract_cut))
	var net: int = treasure_value - debt - cut_amt

	var ok: bool = has_treasure and (net >= 0)

	return {
		"treasure": treasure_value,
		"debt": debt,
		"cut_amt": cut_amt,
		"net": net,
		"ok": ok,
		"rate_pct": int(round(contract_interest * 100.0)),
		"cut_pct": int(round(contract_cut * 100.0)),
		"turns": turn_count
	}


func _on_player_turn_taken(_player_grid_pos: Vector2i) -> void:
	turn_count += 1

	# Interest tick (percent of debt, at least 1)
	if contract_interest <= 0.0:
		debt += interest_per_turn
	else:
		var interest: int = int(ceil(float(debt) * contract_interest))
		interest = maxi(1, interest)
		debt += interest

	_update_hud()


func _update_hud() -> void:
	if _label == null:
		return

	var interest_pct: int = int(round(contract_interest * 100.0))
	var cut_pct: int = int(round(contract_cut * 100.0))

	var t_text: String = "--"
	if has_treasure:
		t_text = str(treasure_value)

	_label.text = "DEBT: %d\nTURN: %d\nRATE: %d%%  CUT: %d%%\nTREASURE: %s" % [
		debt, turn_count, interest_pct, cut_pct, t_text
	]
