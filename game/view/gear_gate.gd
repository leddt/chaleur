class_name GearGate
extends Control

## Sequential shift lever: one slot, gear 1 at the bottom through 4 at the top.
##
## The layout carries the rule instead of explaining it. Travel along the slot is
## the gear delta, and the delta is what the engine charges for (game_engine.gd):
##   1 notch  -> free
##   2 notches -> costs one Heat, so the notch is marked with a flame
##   3 notches -> refused, so the notch is struck out
##
## A linear slot is used rather than a classic H-pattern gate on purpose: in an H,
## 1 -> 3 is a short move but a paid one, so the geometry would contradict the cost.

signal gear_chosen(gear: int)

const GEAR_MIN := 1
const GEAR_MAX := 4
## Shifting this many notches or fewer is free; one more costs a Heat.
const FREE_TRAVEL := 1
const PAID_TRAVEL := 2

const SLOT_WIDTH := 34.0
const NOTCH_RADIUS := 15.0
const HEAT_ICON_PX := 16.0
const HEAT_SHIFT_TOOLTIP := (
	"[b]Heat 1[/b]\nUn changement de deux crans coûte 1 Heat du moteur."
)

@export var current_gear: int = 1:
	set(v):
		current_gear = clampi(v, GEAR_MIN, GEAR_MAX)
		queue_redraw()
		_refresh_heat_tips()

@export var chosen_gear: int = 1:
	set(v):
		chosen_gear = clampi(v, GEAR_MIN, GEAR_MAX)
		queue_redraw()

@export var editable: bool = false:
	set(v):
		editable = v
		# An inert lever stays out of the tab order instead of trapping focus.
		focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
		mouse_default_cursor_shape = \
			Control.CURSOR_POINTING_HAND if editable else Control.CURSOR_ARROW
		if not editable:
			_hover_gear = -1
			if has_focus():
				release_focus()
		queue_redraw()
		_refresh_heat_tips()

var _hover_gear: int = -1


func _ready() -> void:
	# Fallback only: a scene that sets its own size keeps it.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(96, 176)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(_refresh_heat_tips)
	_refresh_heat_tips()


## Notches this many steps away cost a Heat; further away is refused.
func travel_to(gear: int) -> int:
	return absi(gear - current_gear)


func is_reachable(gear: int) -> bool:
	return travel_to(gear) <= PAID_TRAVEL


func costs_heat(gear: int) -> bool:
	return travel_to(gear) == PAID_TRAVEL


# --- Geometry ---

func _notch_center(gear: int) -> Vector2:
	var rows := GEAR_MAX - GEAR_MIN
	var top := NOTCH_RADIUS + 6.0
	var bottom := size.y - NOTCH_RADIUS - 6.0
	# Gear 4 sits at the top: up the slot is faster, like a real sequential lever.
	var t := float(GEAR_MAX - gear) / float(rows)
	return Vector2(size.x * 0.5, lerpf(top, bottom, t))


func _gear_at(point: Vector2) -> int:
	for gear in range(GEAR_MIN, GEAR_MAX + 1):
		if point.distance_to(_notch_center(gear)) <= NOTCH_RADIUS + 4.0:
			return gear
	return -1


# --- Drawing ---

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_slot()
	for gear in range(GEAR_MIN, GEAR_MAX + 1):
		_draw_notch(gear)
	_draw_lever()
	if editable:
		_draw_travel_hints()
	if has_focus() and editable:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.CARDBOARD, false, 2.0)


func _draw_slot() -> void:
	var top := _notch_center(GEAR_MAX)
	var bottom := _notch_center(GEAR_MIN)
	var rail := Rect2(
		Vector2(size.x * 0.5 - SLOT_WIDTH * 0.5, top.y),
		Vector2(SLOT_WIDTH, bottom.y - top.y)
	)
	draw_rect(rail, Palette.INK)
	draw_rect(rail, Color(0, 0, 0, 0.5), false, 2.0)
	# A highlight down the left lip reads as a milled slot rather than a flat box.
	draw_line(
		rail.position + Vector2(1, 0), rail.position + Vector2(1, rail.size.y),
		Palette.SMOKE * Color(1, 1, 1, 0.45), 1.0
	)


func _draw_notch(gear: int) -> void:
	var center := _notch_center(gear)
	var reachable := is_reachable(gear)
	var engaged := gear == current_gear
	var hovered := gear == _hover_gear and editable and reachable

	# Detents are cut into the slot; the numbers live outside it, to the left.
	var half := SLOT_WIDTH * 0.5
	var tick := Palette.SMOKE if reachable else Palette.SMOKE * Color(1, 1, 1, 0.4)
	draw_line(
		center + Vector2(-half, 0), center + Vector2(-half + 5.0, 0), tick, 2.0
	)
	draw_line(
		center + Vector2(half - 5.0, 0), center + Vector2(half, 0), tick, 2.0
	)

	if hovered:
		draw_circle(center, NOTCH_RADIUS * 0.75, Palette.SMOKE * Color(1, 1, 1, 0.35))

	var ink := Palette.CARDBOARD if reachable else Palette.SMOKE
	if engaged:
		ink = Palette.MUSTARD
	_draw_number(center + Vector2(-half - 12.0, 0), gear, ink)

	# The gear currently engaged is ringed, so it stays visible while you move the
	# lever somewhere else.
	if engaged:
		draw_arc(
			center + Vector2(-half - 12.0, 0), 11.0, 0.0, TAU, 24,
			Palette.MUSTARD * Color(1, 1, 1, 0.7), 1.0, true
		)

	if editable and costs_heat(gear):
		_draw_heat_icon(_heat_icon_center(gear), HEAT_ICON_PX)
	elif editable and not reachable:
		_draw_strike(center + Vector2(half + 11.0, 0.0), 5.0, Palette.SMOKE)


## The lever itself: a ball on a shaft, sitting at the gear you have selected.
## Clicking a notch moves the ball there, which is the whole point — the previous
## version highlighted a pill and never read as something you could grab.
func _draw_lever() -> void:
	var ball := _notch_center(chosen_gear)
	var base := Vector2(size.x * 0.5, size.y - 4.0)

	var shaft_col := Palette.SMOKE if editable else Palette.SMOKE * Color(1, 1, 1, 0.5)
	draw_line(base, ball, shaft_col, 5.0, true)
	draw_line(base, ball, Palette.INK * Color(1, 1, 1, 0.6), 2.0, true)

	var r := NOTCH_RADIUS * 0.92
	var body := Palette.MUSTARD if editable else Palette.SMOKE
	draw_circle(ball, r, body)
	draw_arc(ball, r, 0.0, TAU, 32, Palette.INK, 2.0, true)
	# Off-centre highlight: the ball reads as round instead of as a flat disc.
	draw_circle(ball + Vector2(-r * 0.3, -r * 0.35), r * 0.28, Color(1, 1, 1, 0.28))


## Small chevrons above and below the ball: the lever can travel that way.
func _draw_travel_hints() -> void:
	var ball := _notch_center(chosen_gear)
	var r := NOTCH_RADIUS + 8.0
	if chosen_gear < GEAR_MAX and is_reachable(chosen_gear + 1):
		_draw_hint(ball + Vector2(0, -r), -1.0)
	if chosen_gear > GEAR_MIN and is_reachable(chosen_gear - 1):
		_draw_hint(ball + Vector2(0, r), 1.0)


func _draw_hint(at: Vector2, dir: float) -> void:
	var s := 4.0
	draw_polyline(
		PackedVector2Array([
			at + Vector2(-s, s * dir), at, at + Vector2(s, s * dir),
		]),
		Palette.CARDBOARD * Color(1, 1, 1, 0.55), 1.5, true
	)


func _draw_number(center: Vector2, gear: int, col: Color) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := 17
	var text := str(gear)
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var origin := center + Vector2(-extent.x * 0.5, extent.y * 0.32)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _heat_icon_center(gear: int) -> Vector2:
	return _notch_center(gear) + Vector2(SLOT_WIDTH * 0.5 + 11.0, 0.0)


func _refresh_heat_tips() -> void:
	for child in get_children():
		if child is HeatTip:
			child.queue_free()
	if not editable or size.x <= 0.0 or size.y <= 0.0:
		return
	for gear in range(GEAR_MIN, GEAR_MAX + 1):
		if not costs_heat(gear):
			continue
		var tip := HeatTip.new()
		tip.gear = gear
		tip.bbcode = HEAT_SHIFT_TOOLTIP
		var px := HEAT_ICON_PX
		var center := _heat_icon_center(gear)
		tip.position = center - Vector2(px, px) * 0.5
		tip.size = Vector2(px, px)
		add_child(tip)


class HeatTip extends Control:
	var gear: int = 0
	var bbcode: String = ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = " "

	func _make_custom_tooltip(_tooltip: String) -> Object:
		return CardSymbolTooltip.make_control(bbcode)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			var gate := get_parent() as GearGate
			if gate != null and gate.is_reachable(gear):
				gate._select(gear)


func _draw_heat_icon(center: Vector2, px: float) -> void:
	var tex := CardSymbolVisual.texture(CardSymbol.Kind.HEAT, px)
	var rect := Rect2(center - Vector2(px, px) * 0.5, Vector2(px, px))
	draw_texture_rect(tex, rect, false, Palette.RACE_RED)


func _draw_strike(center: Vector2, s: float, col: Color) -> void:
	draw_line(center + Vector2(-s, -s), center + Vector2(s, s), col, 2.0, true)


# --- Interaction ---

func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if event is InputEventMouseMotion:
		var over := _gear_at(event.position)
		if over != _hover_gear:
			_hover_gear = over
			queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		var gear := _gear_at(event.position)
		if gear > 0 and is_reachable(gear):
			_select(gear)
		return
	# Up and down walk the slot the same way the lever does, so the arrow keys are
	# consumed here rather than moving focus out of the gate.
	if event.is_action_pressed("ui_up"):
		_step(1)
		accept_event()
	elif event.is_action_pressed("ui_down"):
		_step(-1)
		accept_event()


func _step(direction: int) -> void:
	var target := chosen_gear + direction
	if target < GEAR_MIN or target > GEAR_MAX or not is_reachable(target):
		return
	_select(target)


func _select(gear: int) -> void:
	if gear == chosen_gear:
		return
	chosen_gear = gear
	gear_chosen.emit(gear)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			if _hover_gear != -1:
				_hover_gear = -1
				queue_redraw()
		NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
			queue_redraw()
