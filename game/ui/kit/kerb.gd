@tool
class_name Kerb
extends Control

## LE motif signature du jeu : la bande de vibreurs (les damiers rouges et creme
## en bordure de piste). On la reutilise partout — bas des cartes, separateurs,
## bordure du plateau, barre de chargement — et c'est elle qui donne au jeu son
## identite visuelle sans qu'aucune image ne soit produite.
##
## Dessinee entierement en code, donc nette a toutes les resolutions et
## recoloriable a la volee.

@export var stripe_width: float = 16.0:
	set(v):
		stripe_width = maxf(2.0, v)
		queue_redraw()

## Inclinaison des bandes en pixels (0 = barres droites).
@export var slant: float = 10.0:
	set(v):
		slant = v
		queue_redraw()

@export var color_a: Color = Palette.RACE_RED:
	set(v):
		color_a = v
		queue_redraw()

@export var color_b: Color = Palette.CARDBOARD:
	set(v):
		color_b = v
		queue_redraw()

## Decalage anime : fais varier ca dans un tween pour donner l'illusion de vitesse.
@export var scroll: float = 0.0:
	set(v):
		scroll = v
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return

	# Le rectangle qui sert de masque.
	var bounds := PackedVector2Array([
		r.position,
		r.position + Vector2(r.size.x, 0),
		r.position + r.size,
		r.position + Vector2(0, r.size.y),
	])

	var period := stripe_width * 2.0
	var start := -absf(slant) - period + fposmod(scroll, period)
	var x := start
	var i := 0
	while x < r.size.x + absf(slant) + period:
		var quad := PackedVector2Array([
			Vector2(x, r.size.y),
			Vector2(x + stripe_width, r.size.y),
			Vector2(x + stripe_width + slant, 0.0),
			Vector2(x + slant, 0.0),
		])
		# On coupe la bande au rectangle plutot que de laisser deborder.
		for piece in Geometry2D.intersect_polygons(quad, bounds):
			if piece.size() < 3:
				continue
			if Geometry2D.triangulate_polygon(piece).is_empty():
				continue
			draw_colored_polygon(piece, color_a if i % 2 == 0 else color_b)
		x += stripe_width
		i += 1


var _scroll_tween: Tween


## Fait defiler la bande en continu. Rendu = sensation de vitesse, gratuit.
func animate(speed_px_per_sec: float = 60.0) -> void:
	if speed_px_per_sec == 0.0:
		return
	stop_animation()
	var period := stripe_width * 2.0
	_scroll_tween = create_tween().set_loops()
	_scroll_tween.tween_method(
		func(v: float) -> void: scroll = v,
		0.0, period, period / absf(speed_px_per_sec)
	)


## Arrete le defilement et remet la bande au repos.
func stop_animation() -> void:
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = null
	scroll = 0.0
