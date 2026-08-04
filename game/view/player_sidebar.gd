class_name PlayerSidebar
extends VBoxContainer

## Heat / gear / piles readout and gear selector for the acting viewer.

const GEAR_ACTIVE := Color(0.45, 1.0, 0.45)
const GEAR_NORMAL := Color(0.85, 0.88, 0.9)

@onready var _corner_dist: Label = %CornerDistLabel
@onready var _heat_value: Label = %HeatValue
@onready var _draw_value: Label = %DrawValue
@onready var _discard_value: Label = %DiscardValue

var _gear_buttons: Array[Button] = []
var _gear_player: PlayerState = null
var chosen_gear: int = 1
var _gear_editable: bool = false


func _ready() -> void:
	_gear_buttons = [
		%Gear1Button as Button,
		%Gear2Button as Button,
		%Gear3Button as Button,
		%Gear4Button as Button,
	]
	for i in range(_gear_buttons.size()):
		var gear := i + 1
		_gear_buttons[i].pressed.connect(_on_gear_pressed.bind(gear))


func is_gear_editable() -> bool:
	return _gear_editable


func reset_gear_choice() -> void:
	chosen_gear = -1


func ensure_chosen_gear(player: PlayerState) -> void:
	if chosen_gear < 1 or chosen_gear > 4 or absi(chosen_gear - player.gear) > 2:
		chosen_gear = player.gear


func set_empty() -> void:
	_corner_dist.text = "Distance: —"
	_heat_value.text = "—"
	_draw_value.text = "—"
	_discard_value.text = "—"
	chosen_gear = 1
	set_gear_editable(false)


func refresh(engine: HeatGameEngine, viewer: PlayerState) -> void:
	if engine == null or viewer == null:
		set_empty()
		return
	if viewer.finished:
		_corner_dist.text = "Distance: —"
	else:
		var landmark := engine.track.next_landmark(viewer.progress)
		match str(landmark.get("kind", "none")):
			"finish":
				_corner_dist.text = "Distance à l'arrivée: %d" % int(landmark["distance"])
			"corner":
				_corner_dist.text = "Distance au prochain virage: %d" % int(landmark["distance"])
			_:
				_corner_dist.text = "Distance: —"
	_heat_value.text = str(viewer.engine_heat())
	_draw_value.text = str(viewer.draw_pile.size())
	_discard_value.text = str(viewer.discard.size())
	if not _gear_editable:
		chosen_gear = viewer.gear
		set_gear_editable(false, viewer)
	else:
		_sync_gear_buttons()


func set_gear_editable(editable: bool, player: PlayerState = null) -> void:
	_gear_editable = editable
	_gear_player = player
	for i in range(_gear_buttons.size()):
		var gear := i + 1
		var btn := _gear_buttons[i]
		var delta := 0 if player == null else absi(gear - player.gear)
		btn.disabled = not editable or player == null or delta > 2
		if editable and player != null and delta == 2:
			btn.text = "Gear %d (1 Heat)" % gear
		else:
			btn.text = "Gear %d" % gear
	_sync_gear_buttons()


func _on_gear_pressed(gear: int) -> void:
	if not _gear_editable:
		_sync_gear_buttons()
		return
	if _gear_player == null:
		return
	if absi(gear - _gear_player.gear) > 2:
		_sync_gear_buttons()
		return
	chosen_gear = gear
	_sync_gear_buttons()


func _sync_gear_buttons() -> void:
	var shown := chosen_gear
	if shown < 1:
		shown = _gear_player.gear if _gear_player != null else 1
	for i in range(_gear_buttons.size()):
		var btn := _gear_buttons[i]
		var on := (i + 1) == shown
		btn.set_pressed_no_signal(on)
		_apply_gear_button_color(btn, GEAR_ACTIVE if on else GEAR_NORMAL)


func _apply_gear_button_color(btn: Button, color: Color) -> void:
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_pressed_color", color)
	btn.add_theme_color_override("font_hover_color", color)
	btn.add_theme_color_override("font_hover_pressed_color", color)
	btn.add_theme_color_override("font_focus_color", color)
	btn.add_theme_color_override("font_disabled_color", color)
