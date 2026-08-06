@tool
class_name Card
extends Control

## Une carte de jeu, construite a partir d'un CardData. Aucune image :
## StyleBoxFlat pour le carton, Label pour les chiffres, _draw pour les symboles.
##
## Consequences pratiques :
##  - le texte reste net a toutes les resolutions
##  - changer une valeur d'equilibrage = changer une donnee, pas rouvrir Inkscape
##  - le survol, la selection et le retournement sont des animations, pas des sprites

signal clicked(card: Card)

const SIZE_DEFAULT := Vector2(150, 220)

@export var data: CardData:
	set(v):
		data = v
		_refresh()

@export var face_up: bool = true:
	set(v):
		face_up = v
		_refresh()

@export var selected: bool = false:
	set(v):
		selected = v
		_refresh()

## Taille de la carte. La main du cockpit en veut des plus petites que l'eventail
## de la demo, donc la taille est une propriete plutot qu'une constante.
@export var card_size: Vector2 = SIZE_DEFAULT:
	set(v):
		card_size = v
		if is_node_ready():
			_apply_size()

## Carte visible mais non jouable dans la phase courante : grisee et inerte.
@export var dimmed: bool = false:
	set(v):
		dimmed = v
		mouse_default_cursor_shape = Control.CURSOR_ARROW if dimmed else Control.CURSOR_POINTING_HAND
		_refresh()

var _hovered := false
var _big: Label
var _title: Label
var _effect: Label
var _kerb: Kerb


func _ready() -> void:
	_apply_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_refresh()


## Toute la mise en page interne est proportionnelle a card_size. Les offsets fixes
## de la premiere version etaient calibres sur 150x220 : a 96x138 le gros chiffre,
## le texte d'effet et le vibreur se chevauchaient et le texte se faisait couper.
func _apply_size() -> void:
	custom_minimum_size = card_size
	size = card_size
	pivot_offset = card_size * Vector2(0.5, 1.0) # pivote depuis le bas : eventail naturel
	if _title == null:
		return

	var s := card_size.y / SIZE_DEFAULT.y
	var pad := roundf(14.0 * s)
	var kerb_h := maxf(6.0, roundf(14.0 * s))
	var has_effect := _effect.text != ""
	var effect_h := roundf(48.0 * s) if has_effect else 0.0

	_title.position = Vector2(pad, roundf(10.0 * s))
	_title.add_theme_font_size_override("font_size", maxi(8, int(round(11.0 * s))))

	_big.offset_bottom = -(kerb_h + effect_h + roundf(6.0 * s))
	_big.add_theme_font_size_override("font_size", maxi(18, int(round(76.0 * s))))

	_effect.offset_left = pad
	_effect.offset_right = -pad
	_effect.offset_top = -(kerb_h + effect_h + roundf(4.0 * s))
	_effect.offset_bottom = -(kerb_h + roundf(4.0 * s))
	_effect.add_theme_font_size_override("font_size", maxi(8, int(round(13.0 * s))))
	_effect.visible = has_effect

	_kerb.offset_top = -kerb_h
	_kerb.offset_left = roundf(6.0 * s)
	_kerb.offset_right = -roundf(6.0 * s)
	_kerb.offset_bottom = -roundf(6.0 * s)
	_kerb.stripe_width = maxf(4.0, roundf(9.0 * s))
	_kerb.slant = maxf(2.0, roundf(6.0 * s))
	queue_redraw()


func _build() -> void:
	_title = Label.new()
	_title.theme_type_variation = "Eyebrow"
	add_child(_title)

	_big = Label.new()
	_big.theme_type_variation = "BigNumber"
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big.anchor_right = 1.0
	_big.anchor_bottom = 1.0
	add_child(_big)

	_effect = Label.new()
	_effect.theme_type_variation = "Caption"
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect.clip_text = true
	_effect.anchor_top = 1.0
	_effect.anchor_right = 1.0
	_effect.anchor_bottom = 1.0
	_effect.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_effect)

	_kerb = Kerb.new()
	_kerb.anchor_top = 1.0
	_kerb.anchor_right = 1.0
	_kerb.anchor_bottom = 1.0
	_kerb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kerb)
	_apply_size()


func _refresh() -> void:
	if not is_node_ready() or data == null:
		return

	var visible_face := face_up
	_title.visible = visible_face
	_big.visible = visible_face
	_effect.visible = visible_face
	_kerb.visible = visible_face

	if visible_face:
		_title.text = data.title
		_big.text = data.big_text()
		_effect.text = data.effect
		var ink := data.ink()
		_title.add_theme_color_override("font_color", ink * Color(1, 1, 1, 0.6))
		_big.add_theme_color_override("font_color", ink)
		_effect.add_theme_color_override("font_color", ink * Color(1, 1, 1, 0.7))
		_kerb.color_a = data.accent()
		_kerb.color_b = data.face()

	# La presence d'un texte d'effet change la hauteur reservee au gros chiffre.
	_apply_size()
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if data == null:
		return

	if face_up:
		var box := ThemeBuilder.card_box(data.face(), data.accent(), _hovered or selected)
		box.draw(get_canvas_item(), r)
		_draw_symbol(data.symbol, data.accent())
	else:
		# Le verso : carton fonce + un seul chevron. Rien de plus.
		var box := ThemeBuilder.card_box(Palette.CARDBOARD_DARK, Palette.INK, _hovered)
		box.draw(get_canvas_item(), r)
		_draw_chevron(r.get_center(), 34.0, Palette.INK * Color(1, 1, 1, 0.35))

	if selected:
		draw_rect(r.grow(3), Palette.MUSTARD, false, 3.0)

	# Le voile passe par-dessus tout le reste : la carte reste lisible, mais elle
	# sort visiblement du jeu.
	if dimmed:
		draw_rect(r, Palette.ASPHALT * Color(1, 1, 1, 0.55))


func _draw_symbol(symbol: String, col: Color) -> void:
	if symbol == "":
		return
	var center := Vector2(size.x - 30, 34)
	match symbol:
		"flame":
			_draw_flame(center, 15.0, col)
		"chevron":
			_draw_chevron(center, 15.0, col)
		"gear":
			_draw_gear(center, 14.0, col)


func _draw_chevron(center: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(-s, s * 0.5),
		center + Vector2(0, -s * 0.5),
		center + Vector2(s, s * 0.5),
	])
	draw_polyline(pts, col, maxf(2.0, s * 0.22), true)


func _draw_flame(center: Vector2, s: float, col: Color) -> void:
	# Une flamme lisible en 8 points. Pas besoin d'illustration.
	var pts := PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(s * 0.45, -s * 0.2),
		center + Vector2(s * 0.55, s * 0.35),
		center + Vector2(s * 0.2, s),
		center + Vector2(-s * 0.2, s),
		center + Vector2(-s * 0.55, s * 0.35),
		center + Vector2(-s * 0.35, -s * 0.15),
		center + Vector2(-s * 0.1, -s * 0.5),
	])
	draw_colored_polygon(pts, col)


func _draw_gear(center: Vector2, s: float, col: Color) -> void:
	var teeth := 8
	var pts := PackedVector2Array()
	for i in teeth * 2:
		var a := TAU * float(i) / float(teeth * 2)
		var rad := s if i % 2 == 0 else s * 0.68
		pts.append(center + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, col)
	draw_circle(center, s * 0.3, data.face() if data else Palette.CARDBOARD)


# --- Interaction ---

func _gui_input(event: InputEvent) -> void:
	if dimmed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)


func _notification(what: int) -> void:
	if dimmed:
		return
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		_lift(true)
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		_lift(false)


var _rest_offset := 0.0

func _lift(up: bool) -> void:
	queue_redraw()
	var target := _rest_offset - (18.0 if up else 0.0)
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", target, 0.14)


## Enregistre la position de repos (a appeler apres avoir place la carte).
func set_rest_y(y: float) -> void:
	_rest_offset = y
	position.y = y


## Retourne la carte avec un scale sur X. Aucune texture de verso necessaire.
func flip() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale:x", 0.0, 0.12)
	tween.tween_callback(func() -> void: face_up = not face_up)
	tween.tween_property(self, "scale:x", 1.0, 0.12)
