extends Node

# Fallback if no contract chosen yet (should rarely happen)
@export var interest_per_turn: int = 1

# Contract terms chosen on Contract screen
var contract_loan: int = 0
var contract_interest: float = 0.0
var contract_cut: float = 0.0

var turn_count: int = 0
var debt: int = 0

var _player: Node
var _label: Label


func bind_player(player: Node) -> void:
	# Disconnect previous, if any
	if _player != null and _player.has_signal("turn_taken"):
		var c := Callable(self, "_on_player_turn_taken")
		if _player.is_connected("turn_taken", c):
			_player.disconnect("turn_taken", c)

	_player = player

	# Connect new
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

	# Loan becomes starting debt (simple + clear)
	turn_count = 0
	debt = loan_amount
	_update_hud()


func reset_run() -> void:
	turn_count = 0
	debt = contract_loan
	_update_hud()


func _on_player_turn_taken(_player_grid_pos: Vector2i) -> void:
	turn_count += 1

	# NEW: real interest tick based on current debt and contract rate
	if contract_interest <= 0.0:
		debt += interest_per_turn
	else:
		var interest: int = int(ceil(float(debt) * contract_interest))
		interest = maxi(1, interest) # always at least 1 per turn
		debt += interest

	_update_hud()


func _update_hud() -> void:
	if _label == null:
		return

	var interest_pct: int = int(round(contract_interest * 100.0))
	var cut_pct: int = int(round(contract_cut * 100.0))

	_label.text = "DEBT: %d\nTURN: %d\nRATE: %d%%  CUT: %d%%" % [debt, turn_count, interest_pct, cut_pct]
