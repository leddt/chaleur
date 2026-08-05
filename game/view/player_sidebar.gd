class_name PlayerSidebar
extends VBoxContainer

## Heat / gear / piles readout and gear selector for the acting viewer.

@onready var _corner_board: CornerBoard = %CornerBoard
@onready var _heat_dial: ReserveDial = %HeatDial
@onready var _draw_stack: PileStack = %DrawStack
@onready var _discard_stack: PileStack = %DiscardStack
@onready var _gate: GearGate = %GearGate

var _gear_player: PlayerState = null
var chosen_gear: int = 1
var _gear_editable: bool = false


func _ready() -> void:
	_gate.gear_chosen.connect(_on_gear_pressed)


func is_gear_editable() -> bool:
	return _gear_editable


func reset_gear_choice() -> void:
	chosen_gear = -1


func ensure_chosen_gear(player: PlayerState) -> void:
	if chosen_gear < 1 or chosen_gear > 4 or absi(chosen_gear - player.gear) > 2:
		chosen_gear = player.gear


func set_empty() -> void:
	_corner_board.kind = CornerBoard.Kind.NONE
	_corner_board.distance = -1
	_heat_dial.value = 0
	_draw_stack.count = 0
	_discard_stack.count = 0
	chosen_gear = 1
	set_gear_editable(false)


func refresh(engine: HeatGameEngine, viewer: PlayerState) -> void:
	if engine == null or viewer == null:
		set_empty()
		return
	_refresh_corner_board(engine, viewer)
	# The dial shows what is left to spend, so the needle falls into the red as
	# the reserve empties.
	_heat_dial.max_value = maxi(1, engine.track.start_heat)
	_heat_dial.value = viewer.engine_heat()
	_draw_stack.count = viewer.draw_pile.size()
	_discard_stack.count = viewer.discard.size()
	if not _gear_editable:
		chosen_gear = viewer.gear
		set_gear_editable(false, viewer)
	else:
		_sync_gate()


func set_gear_editable(editable: bool, player: PlayerState = null) -> void:
	_gear_editable = editable
	_gear_player = player
	_gate.editable = editable and player != null
	if player != null:
		_gate.current_gear = player.gear
	_sync_gate()


func _on_gear_pressed(gear: int) -> void:
	if not _gear_editable:
		_sync_gate()
		return
	if _gear_player == null:
		return
	if absi(gear - _gear_player.gear) > 2:
		_sync_gate()
		return
	chosen_gear = gear
	_sync_gate()


func _refresh_corner_board(engine: HeatGameEngine, viewer: PlayerState) -> void:
	if viewer.finished:
		_corner_board.kind = CornerBoard.Kind.NONE
		_corner_board.distance = -1
		return
	var landmark := engine.track.next_landmark(viewer.progress)
	var distance := int(landmark.get("distance", -1))
	match str(landmark.get("kind", "none")):
		"finish":
			_corner_board.kind = CornerBoard.Kind.FINISH
			_corner_board.distance = distance
			_corner_board.speed_limit = 0
		"corner":
			_corner_board.kind = CornerBoard.Kind.CORNER
			_corner_board.distance = distance
			var corner := engine.track.next_corner(viewer.progress)
			_corner_board.speed_limit = corner.speed_limit if corner != null else 0
		_:
			_corner_board.kind = CornerBoard.Kind.NONE
			_corner_board.distance = -1


## Mirrors the pending choice onto the lever; the knob keeps showing the engaged gear.
func _sync_gate() -> void:
	var shown := chosen_gear
	if shown < 1:
		shown = _gear_player.gear if _gear_player != null else 1
	_gate.chosen_gear = shown
