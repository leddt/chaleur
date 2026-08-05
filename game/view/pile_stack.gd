class_name PileStack
extends Control

## A draw or discard pile drawn as physical cardboard seen on edge: the stack's
## thickness is the card count. A thinning deck becomes visible without reading a
## number, which is how it reads on a real table.

@export var title: String = "":
	set(v):
		title = v
		queue_redraw()

@export var count: int = 0:
	set(v):
		count = maxi(0, v)
		queue_redraw()

## Cards above this many stop adding visible layers; the stack would otherwise
## grow past the panel and stop being comparable at a glance.
const MAX_LAYERS := 14
const LAYER_STEP := 2.0
const CARD_RATIO := 1.42


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(84, 96)


func _draw() -> void:
	var font := get_theme_default_font()
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var label_h := 14.0
	var avail_h := size.y - label_h - 4.0
	# Room for the deepest layer's edge has to come out of the card height.
	var card_h := minf(avail_h - float(MAX_LAYERS) * LAYER_STEP, size.x * CARD_RATIO)
	card_h = maxf(24.0, card_h)
	var card_w := card_h / CARD_RATIO
	var layers := mini(count, MAX_LAYERS)

	var origin := Vector2((size.x - card_w) * 0.5, label_h + 4.0)

	if count == 0:
		# An empty pile is a printed outline, not a missing element.
		var slot := Rect2(origin, Vector2(card_w, card_h))
		draw_rect(slot, Palette.INK)
		_draw_dashed_border(slot, Palette.SMOKE * Color(1, 1, 1, 0.5))
	else:
		# Deepest layer first and lowest, so the edges peek out *below* the top
		# card. Drawing it the other way round stacks the pile upside down.
		for i in layers:
			var depth := layers - 1 - i
			var top_layer := depth == 0
			var r := Rect2(
				origin + Vector2(0, float(depth) * LAYER_STEP), Vector2(card_w, card_h)
			)
			draw_rect(r, Palette.CARDBOARD if top_layer else Palette.CARDBOARD_DARK)
			draw_rect(r, Palette.INK * Color(1, 1, 1, 0.55), false, 1.0)
		_draw_count(font, origin, card_w, card_h)

	if font != null and title != "":
		var extent := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		draw_string(
			font, Vector2((size.x - extent.x) * 0.5, 11.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.SMOKE
		)


func _draw_count(font: Font, origin: Vector2, card_w: float, card_h: float) -> void:
	if font == null:
		return
	var text := str(count)
	var font_size := int(minf(card_w * 0.5, 22.0))
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# Centred on the top card, which sits at the origin.
	var center := origin + Vector2(card_w * 0.5, card_h * 0.5)
	draw_string(
		font, center + Vector2(-extent.x * 0.5, extent.y * 0.34), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.INK
	)


func _draw_dashed_border(r: Rect2, col: Color) -> void:
	var dash := 5.0
	var x := r.position.x
	while x < r.end.x:
		var x2 := minf(x + dash, r.end.x)
		draw_line(Vector2(x, r.position.y), Vector2(x2, r.position.y), col, 1.0)
		draw_line(Vector2(x, r.end.y), Vector2(x2, r.end.y), col, 1.0)
		x += dash * 2.0
	var y := r.position.y
	while y < r.end.y:
		var y2 := minf(y + dash, r.end.y)
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x, y2), col, 1.0)
		draw_line(Vector2(r.end.x, y), Vector2(r.end.x, y2), col, 1.0)
		y += dash * 2.0
