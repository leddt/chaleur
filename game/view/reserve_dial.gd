class_name ReserveDial
extends Control

## Engine reserve as a round dial with a needle, the way a fuel or pressure gauge
## reads in a car. The reserve is spent, not accumulated (game_engine.gd), so the
## danger arc sits at the empty end: needle swinging left is bad news.

@export var value: int = 0:
	set(v):
		value = clampi(v, 0, max_value)
		queue_redraw()

@export var max_value: int = 6:
	set(v):
		max_value = maxi(1, v)
		value = clampi(value, 0, max_value)
		queue_redraw()

## Sweep of the dial face, centred on straight up.
const ARC_SPAN := 4.2
## Fraction of the sweep, from the empty end, painted as the danger band.
const DANGER_FRACTION := 0.34

var _pulse: float = 0.0


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(110, 92)
	set_process(true)


func _process(delta: float) -> void:
	# The needle throbs once the reserve drops into the danger band.
	if _ratio() <= DANGER_FRACTION:
		_pulse = fmod(_pulse + delta * 3.0, TAU)
		queue_redraw()
	elif _pulse != 0.0:
		_pulse = 0.0
		queue_redraw()


func _ratio() -> float:
	return float(value) / float(max_value)


func _center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.78)


func _radius() -> float:
	return minf(size.x * 0.42, size.y * 0.62)


## Empty sits on the left of the sweep, full on the right.
func _angle_for(ratio: float) -> float:
	var start := -PI * 0.5 - ARC_SPAN * 0.5
	return start + ARC_SPAN * ratio


func _draw() -> void:
	var r := _radius()
	if r <= 0.0:
		return
	var c := _center()

	draw_circle(c, r + 6.0, Palette.INK)
	draw_arc(c, r + 6.0, 0.0, TAU, 48, Palette.SMOKE * Color(1, 1, 1, 0.5), 1.0, true)

	# Danger band first, so the ticks sit on top of it.
	draw_arc(
		c, r, _angle_for(0.0), _angle_for(DANGER_FRACTION), 20,
		Palette.RACE_RED * Color(1, 1, 1, 0.85), 4.0, true
	)
	draw_arc(
		c, r, _angle_for(DANGER_FRACTION), _angle_for(1.0), 32,
		Palette.SMOKE * Color(1, 1, 1, 0.6), 2.0, true
	)

	for i in max_value + 1:
		var a := _angle_for(float(i) / float(max_value))
		var dir := Vector2(cos(a), sin(a))
		var lit := i <= value
		draw_line(
			c + dir * (r - 7.0), c + dir * r,
			Palette.CARDBOARD if lit else Palette.SMOKE, 2.0, true
		)

	_draw_needle(c, r)
	_draw_window(c, r)


func _draw_needle(c: Vector2, r: float) -> void:
	var a := _angle_for(_ratio())
	var dir := Vector2(cos(a), sin(a))
	var col := Palette.RACE_RED if _ratio() <= DANGER_FRACTION else Palette.CARDBOARD
	if _pulse != 0.0:
		col = col.lerp(Palette.MUSTARD, 0.3 + 0.3 * sin(_pulse))
	# Counterweighted tail, like a real instrument needle.
	draw_line(c - dir * (r * 0.16), c + dir * (r - 10.0), col, 2.5, true)
	draw_circle(c, 4.0, col)


## Small window with the exact figure: a dial reads at a glance, a number decides.
func _draw_window(c: Vector2, r: float) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var text := str(value)
	var font_size := int(r * 0.5)
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box := Rect2(
		c + Vector2(-extent.x * 0.5 - 6.0, -r * 0.42),
		Vector2(extent.x + 12.0, extent.y + 4.0)
	)
	draw_rect(box, Palette.ASPHALT)
	draw_rect(box, Palette.SMOKE * Color(1, 1, 1, 0.6), false, 1.0)
	draw_string(
		font, box.position + Vector2(6.0, extent.y - 1.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.CARDBOARD
	)
