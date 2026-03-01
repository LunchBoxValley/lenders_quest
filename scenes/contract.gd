extends Node2D

@export var label_path: NodePath
@export var next_scene: PackedScene

@export var input_delay_sec: float = 0.20

# Contract offers
@export var loan_a: int = 20
@export var interest_a: float = 0.05
@export var cut_a: float = 0.05

@export var loan_b: int = 40
@export var interest_b: float = 0.08
@export var cut_b: float = 0.08

@export var loan_c: int = 80
@export var interest_c: float = 0.12
@export var cut_c: float = 0.10

# Shop items (simple fixed costs)
@export var sword_cost: int = 10
@export var boots_cost: int = 10
@export var potion_cost: int = 10

enum Page { CONTRACT, SHOP }
var _page: Page = Page.CONTRACT

var _label: Label
var _ready_time: float = 0.0
var _can_input: bool = false


func _ready() -> void:
	_ready_time = Time.get_ticks_msec() / 1000.0
	_label = get_node_or_null(label_path) as Label
	_page = Page.CONTRACT
	_refresh_text()


func _process(_delta: float) -> void:
	if _can_input:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	if (now - _ready_time) >= input_delay_sec:
		_can_input = true


func _unhandled_input(event: InputEvent) -> void:
	if not _can_input:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var keycode: Key = (event as InputEventKey).keycode

		if _page == Page.CONTRACT:
			if keycode == KEY_A:
				_pick_contract(loan_a, interest_a, cut_a)
			elif keycode == KEY_B:
				_pick_contract(loan_b, interest_b, cut_b)
			elif keycode == KEY_C:
				_pick_contract(loan_c, interest_c, cut_c)

		elif _page == Page.SHOP:
			# Allow top row numbers AND keypad numbers
			if keycode == KEY_1 or keycode == KEY_KP_1:
				_pick_item(1)
			elif keycode == KEY_2 or keycode == KEY_KP_2:
				_pick_item(2)
			elif keycode == KEY_3 or keycode == KEY_KP_3:
				_pick_item(3)


func _pick_contract(loan_amount: int, interest_rate: float, cut_rate: float) -> void:
	GameManager.set_contract(loan_amount, interest_rate, cut_rate)

	# Move to shop page
	_page = Page.SHOP
	_refresh_text()


func _pick_item(item_id: int) -> void:
	GameManager.set_shop_item(item_id)

	if next_scene != null:
		get_tree().change_scene_to_packed(next_scene)


func _refresh_text() -> void:
	if _label == null:
		return

	if _page == Page.CONTRACT:
		var ia: int = int(round(interest_a * 100.0))
		var ib: int = int(round(interest_b * 100.0))
		var ic: int = int(round(interest_c * 100.0))

		var ca: int = int(round(cut_a * 100.0))
		var cb: int = int(round(cut_b * 100.0))
		var cc: int = int(round(cut_c * 100.0))

		var text: String = ""
		text += "DET KING'S CONTRACT\n"
		text += "(press A, B, or C)\n\n"
		text += "A) Loan %d  | Interest %d%%  | Cut %d%%\n" % [loan_a, ia, ca]
		text += "B) Loan %d  | Interest %d%%  | Cut %d%%\n" % [loan_b, ib, cb]
		text += "C) Loan %d  | Interest %d%%  | Cut %d%%\n\n" % [loan_c, ic, cc]
		text += "Fine print: screaming is acceptance."
		_label.text = text
	else:
		var text2: String = ""
		text2 += "DET KING'S SHOP\n"
		text2 += "(choose ONE item: 1 / 2 / 3)\n\n"
		text2 += "You have CASH: %d\n\n" % GameManager.cash
		text2 += "1) Sword   (+1 damage)      cost %d\n" % sword_cost
		text2 += "2) Boots   (-1 spike damage) cost %d\n" % boots_cost
		text2 += "3) Potion  (heal +3 once)    cost %d\n\n" % potion_cost
		text2 += "DetKing: \"Invest wisely. Or don't.\"\n"
		_label.text = text2
