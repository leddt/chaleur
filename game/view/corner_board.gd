class_name CornerBoard
extends Control

## Trackside braking board. Real circuits mark the approach to a corner with
## distance boards; this one carries the two numbers a driver actually needs
## before shifting: how far to the corner, and the speed it must be taken at.
##
## The chevrons fill as the corner closes, so proximity registers before the
## number is even read.

enum Kind { NONE, CORNER, FINISH }

const CHEVRONS := 4
## Distance at which the board starts filling in.
const ALERT_RANGE := 8

@export var kind: Kind = Kind.NONE:
	set(v):
		kind = v
		queue_redraw()

@export var distance: int = -1:
	set(v):
		distance = v
		queue_redraw()

## Speed limit of the corner ahead; ignored when the landmark is the finish.
@export var speed_limit: int = 0:
	set(v):
		speed_limit = v
		queue_redraw()


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(0, 62)


func _draw() -> void:
	var font := get_theme_default_font()
	if font == null or size.x <= 0.0:
		return

	if kind == Kind.NONE or distance < 0:
		draw_string(
			font, Vector2(4.0, size.y * 0.6), "—",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.SMOKE
		)
		return

	# Three stacked bands: label, figure, chevrons. Sharing a band is what made the
	# chevrons run under the number.
	var chevron_h := 10.0
	var label_baseline := 12.0
	var figure_top := label_baseline + 3.0
	var figure_h := maxf(20.0, size.y - figure_top - chevron_h - 4.0)

	var label := "PROCHAIN VIRAGE" if kind == Kind.CORNER else "ARRIVÉE"
	draw_string(
		font, Vector2(4.0, label_baseline), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.SMOKE
	)

	var big := str(distance)
	var big_size := int(minf(30.0, figure_h))
	var big_extent := font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size)
	var near := distance <= 2
	var figure_baseline := figure_top + (figure_h + big_extent.y) * 0.5 - 3.0
	draw_string(
		font, Vector2(4.0, figure_baseline), big,
		HORIZONTAL_ALIGNMENT_LEFT, -1, big_size,
		Palette.MUSTARD if near else Palette.CARDBOARD
	)

	var unit := "case" if distance == 1 else "cases"
	draw_string(
		font, Vector2(8.0 + big_extent.x, figure_baseline), unit,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.SMOKE
	)

	if kind == Kind.CORNER and speed_limit > 0:
		_draw_limit_disc(font, figure_top + figure_h * 0.5)
	_draw_chevrons(size.y - chevron_h - 1.0, chevron_h)


## The corner's speed limit, in the red disc used for limits on real signage.
func _draw_limit_disc(font: Font, center_y: float) -> void:
	var r := 17.0
	var c := Vector2(size.x - r - 4.0, center_y)
	draw_circle(c, r, Palette.CARDBOARD)
	draw_arc(c, r - 2.0, 0.0, TAU, 32, Palette.RACE_RED, 4.0, true)
	var text := str(speed_limit)
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	draw_string(
		font, c + Vector2(-extent.x * 0.5, extent.y * 0.34), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Palette.INK
	)


func _draw_chevrons(y: float, h: float) -> void:
	var filled := 0
	if distance <= ALERT_RANGE:
		filled = int(ceil(float(ALERT_RANGE - distance) / float(ALERT_RANGE) * float(CHEVRONS)))
	var w := 13.0
	for i in CHEVRONS:
		var x := 4.0 + float(i) * (w + 4.0)
		var lit := i < filled
		var col := Palette.RACE_RED if lit else Palette.SMOKE * Color(1, 1, 1, 0.45)
		var pts := PackedVector2Array([
			Vector2(x, y + h), Vector2(x + w * 0.5, y), Vector2(x + w, y + h),
		])
		if lit:
			draw_colored_polygon(pts, col)
		else:
			draw_polyline(pts, col, 1.5, true)
