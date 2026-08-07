class_name ThemeBuilder
extends RefCounted

## Construit le Theme complet du jeu en code. Aucun fichier .theme a maintenir.
##
## Usage :
##   var t := ThemeBuilder.build()
##   get_tree().root.theme = t          # applique a tout le jeu
##
## Les polices passent par SystemFont : si "Archivo Black" n'est pas installee,
## Godot descend automatiquement dans la liste. Pour figer le rendu sur toutes
## les machines, telecharge les .ttf depuis Google Fonts, mets-les dans
## res://fonts/ et remplace _display() / _body() par des FontFile charges.

const DISPLAY_NAMES := ["Archivo Black", "Anton", "Oswald", "Impact", "Arial Black"]
const BODY_NAMES := ["Barlow Condensed", "Roboto Condensed", "Oswald", "Arial Narrow", "Arial"]

# Echelle typographique. Un seul ratio, applique partout.
const SIZE_HUGE := 76
const SIZE_XL := 34
const SIZE_L := 22
const SIZE_M := 16
const SIZE_S := 13
const SIZE_XS := 11


static func display_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(DISPLAY_NAMES)
	f.font_weight = 900
	return f


static func body_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(BODY_NAMES)
	f.font_weight = 500
	return f


static func build() -> Theme:
	var t := Theme.new()
	var body := body_font()
	var display := display_font()

	t.default_font = body
	t.default_font_size = SIZE_M

	_setup_labels(t, body, display)
	_setup_buttons(t, body)
	_setup_checkboxes(t, body)
	_setup_sliders(t)
	_setup_spinboxes(t, body)
	_setup_panels(t)
	_setup_binnacle(t)
	return t


static func _setup_labels(t: Theme, body: Font, display: Font) -> void:
	# Label de base
	t.set_color("font_color", "Label", Palette.CARDBOARD)

	# Variations. Utilise-les avec label.theme_type_variation = "TitleLabel"
	for entry in [
		["TitleLabel", display, SIZE_XL, Palette.CARDBOARD],
		["BigNumber", display, SIZE_HUGE, Palette.INK],
		["Eyebrow", body, SIZE_XS, Palette.SMOKE],
		["Caption", body, SIZE_S, Palette.SMOKE],
		["Stat", display, SIZE_L, Palette.MUSTARD],
	]:
		var name: String = entry[0]
		t.add_type(name)
		t.set_type_variation(name, "Label")
		t.set_font("font", name, entry[1])
		t.set_font_size("font_size", name, entry[2])
		t.set_color("font_color", name, entry[3])

	# L'eyebrow est en majuscules espacees : c'est le seul "ornement" typo du jeu.
	t.set_constant("line_spacing", "Eyebrow", 2)


static func _setup_buttons(t: Theme, body: Font) -> void:
	t.set_font("font", "Button", body)
	t.set_font_size("font_size", "Button", SIZE_M)
	t.set_color("font_color", "Button", Palette.CARDBOARD)
	t.set_color("font_hover_color", "Button", Palette.MUSTARD)
	t.set_color("font_pressed_color", "Button", Palette.INK)
	t.set_color("font_disabled_color", "Button", Palette.SMOKE)

	t.set_stylebox("normal", "Button", _button_box(Color(0, 0, 0, 0), Palette.SMOKE))
	t.set_stylebox("hover", "Button", _button_box(Color(0, 0, 0, 0), Palette.MUSTARD))
	t.set_stylebox("pressed", "Button", _button_box(Palette.MUSTARD, Palette.MUSTARD))
	t.set_stylebox("disabled", "Button", _button_box(Color(0, 0, 0, 0), Palette.INK))
	# Focus visible au clavier : non negociable.
	t.set_stylebox("focus", "Button", _button_box(Color(0, 0, 0, 0), Palette.CARDBOARD))

	_setup_card_button(t, body)
	_setup_primary_button(t, body)
	_setup_compact_button(t, body)


## Bandeau étroit pour les sélecteurs de mode / panneau éditeur.
static func _setup_compact_button(t: Theme, body: Font) -> void:
	t.add_type("Compact")
	t.set_type_variation("Compact", "Button")
	t.set_font("font", "Compact", body)
	t.set_font_size("font_size", "Compact", SIZE_S)
	t.set_color("font_color", "Compact", Palette.CARDBOARD)
	t.set_color("font_hover_color", "Compact", Palette.MUSTARD)
	t.set_color("font_pressed_color", "Compact", Palette.INK)
	t.set_color("font_disabled_color", "Compact", Palette.SMOKE)
	t.set_stylebox("normal", "Compact", _compact_button_box(Color(0, 0, 0, 0), Palette.SMOKE))
	t.set_stylebox("hover", "Compact", _compact_button_box(Color(0, 0, 0, 0), Palette.MUSTARD))
	t.set_stylebox("pressed", "Compact", _compact_button_box(Palette.MUSTARD, Palette.MUSTARD))
	t.set_stylebox("disabled", "Compact", _compact_button_box(Color(0, 0, 0, 0), Palette.INK))
	t.set_stylebox("focus", "Compact", _compact_button_box(Color(0, 0, 0, 0), Palette.CARDBOARD))


static func _compact_button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := _button_box(fill, border)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## L'action principale d'une phase. Un bouton plein au milieu de boutons en
## contour : la hierarchie se lit sans avoir a lire les libelles.
static func _setup_primary_button(t: Theme, body: Font) -> void:
	t.add_type("Primary")
	t.set_type_variation("Primary", "Button")
	t.set_font("font", "Primary", body)
	t.set_font_size("font_size", "Primary", SIZE_L)
	t.set_color("font_color", "Primary", Palette.INK)
	t.set_color("font_hover_color", "Primary", Palette.INK)
	t.set_color("font_pressed_color", "Primary", Palette.CARDBOARD)
	t.set_color("font_disabled_color", "Primary", Palette.SMOKE)

	t.set_stylebox("normal", "Primary", _button_box(Palette.MUSTARD, Palette.MUSTARD))
	t.set_stylebox(
		"hover", "Primary", _button_box(Palette.MUSTARD.lightened(0.12), Palette.CARDBOARD)
	)
	t.set_stylebox("pressed", "Primary", _button_box(Palette.RACE_RED, Palette.RACE_RED))
	t.set_stylebox("disabled", "Primary", _button_box(Palette.INK, Palette.SMOKE))
	t.set_stylebox("focus", "Primary", _button_box(Color(0, 0, 0, 0), Palette.CARDBOARD))


## Les cartes de la main sont des boutons, mais elles portent leur propre taille :
## les marges du bouton standard les feraient deborder de la bande du cockpit.
static func _setup_card_button(t: Theme, body: Font) -> void:
	t.add_type("CardButton")
	t.set_type_variation("CardButton", "Button")
	t.set_font("font", "CardButton", body)
	t.set_font_size("font_size", "CardButton", SIZE_L)
	t.set_color("font_color", "CardButton", Palette.INK)
	t.set_color("font_hover_color", "CardButton", Palette.INK)
	t.set_color("font_pressed_color", "CardButton", Palette.INK)
	t.set_color("font_disabled_color", "CardButton", Palette.SMOKE)

	t.set_stylebox("normal", "CardButton", _card_button_box(Palette.CARDBOARD, Palette.INK, 0))
	t.set_stylebox("hover", "CardButton", _card_button_box(Palette.CARDBOARD, Palette.MUSTARD, 2))
	t.set_stylebox("pressed", "CardButton", _card_button_box(Palette.CARDBOARD, Palette.MUSTARD, 3))
	t.set_stylebox("disabled", "CardButton", _card_button_box(Palette.CARDBOARD_DARK, Palette.SMOKE, 0))
	t.set_stylebox("focus", "CardButton", _card_button_box(Color(0, 0, 0, 0), Palette.CARDBOARD, 2))


static func _card_button_box(face: Color, accent: Color, border: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = face
	sb.border_color = accent
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func _setup_checkboxes(t: Theme, body: Font) -> void:
	t.set_font("font", "CheckBox", body)
	t.set_font_size("font_size", "CheckBox", SIZE_S)
	t.set_color("font_color", "CheckBox", Palette.CARDBOARD)
	t.set_color("font_hover_color", "CheckBox", Palette.MUSTARD)
	t.set_color("font_pressed_color", "CheckBox", Palette.MUSTARD)
	t.set_color("font_disabled_color", "CheckBox", Palette.SMOKE)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", _compact_button_box(Color(0, 0, 0, 0), Palette.CARDBOARD))
	t.set_icon("unchecked", "CheckBox", _check_icon(false, Palette.SMOKE))
	t.set_icon("checked", "CheckBox", _check_icon(true, Palette.MUSTARD))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, Palette.INK))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true, Palette.SMOKE))
	t.set_icon("radio_unchecked", "CheckBox", _radio_icon(false, Palette.SMOKE))
	t.set_icon("radio_checked", "CheckBox", _radio_icon(true, Palette.MUSTARD))
	t.set_icon("radio_unchecked_disabled", "CheckBox", _radio_icon(false, Palette.INK))
	t.set_icon("radio_checked_disabled", "CheckBox", _radio_icon(true, Palette.SMOKE))


static func _check_icon(checked: bool, accent: Color) -> Texture2D:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(2, size - 2):
		for x in range(2, size - 2):
			var edge := x == 2 or y == 2 or x == size - 3 or y == size - 3
			if edge:
				img.set_pixel(x, y, accent)
			elif checked:
				img.set_pixel(x, y, accent)
	if checked:
		for y in range(5, 11):
			for x in range(5, 11):
				img.set_pixel(x, y, Palette.INK)
	return ImageTexture.create_from_image(img)


static func _radio_icon(checked: bool, accent: Color) -> Texture2D:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(7.5, 7.5)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d >= 5.2 and d <= 6.6:
				img.set_pixel(x, y, accent)
			elif checked and d <= 3.2:
				img.set_pixel(x, y, accent)
	return ImageTexture.create_from_image(img)


static func _setup_sliders(t: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.INK
	track.set_corner_radius_all(2)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	track.border_color = Palette.SMOKE
	track.set_border_width_all(1)
	t.set_stylebox("slider", "HSlider", track)
	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = Color(0, 0, 0, 0)
	t.set_stylebox("grabber_area", "HSlider", grabber_area)
	t.set_stylebox("grabber_area_highlight", "HSlider", grabber_area)
	t.set_icon("grabber", "HSlider", _slider_grabber(Palette.CARDBOARD))
	t.set_icon("grabber_highlight", "HSlider", _slider_grabber(Palette.MUSTARD))
	t.set_icon("grabber_disabled", "HSlider", _slider_grabber(Palette.SMOKE))


static func _slider_grabber(color: Color) -> Texture2D:
	var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(1, 15):
		for x in range(1, 11):
			img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


static func _setup_spinboxes(t: Theme, body: Font) -> void:
	t.set_font("font", "LineEdit", body)
	t.set_font_size("font_size", "LineEdit", SIZE_S)
	t.set_color("font_color", "LineEdit", Palette.CARDBOARD)
	t.set_color("font_placeholder_color", "LineEdit", Palette.SMOKE)
	t.set_color("caret_color", "LineEdit", Palette.MUSTARD)
	var field := StyleBoxFlat.new()
	field.bg_color = Palette.ASPHALT
	field.border_color = Palette.SMOKE
	field.set_border_width_all(1)
	field.set_corner_radius_all(2)
	field.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", field)
	var focus := field.duplicate() as StyleBoxFlat
	focus.border_color = Palette.CARDBOARD
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit", field)


## La casquette du tableau de bord : une seule masse sombre, un bord superieur
## clair qui attrape la lumiere et une ombre portee dessous. C'est ce bord biseaute
## qui fait lire l'ensemble comme une planche de bord plutot que comme des panneaux.
static func _setup_binnacle(t: Theme) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.INK
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.border_color = Palette.SMOKE * Color(1, 1, 1, 0.7)
	sb.border_width_top = 3
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	t.add_type("Binnacle")
	t.set_type_variation("Binnacle", "PanelContainer")
	t.set_stylebox("panel", "Binnacle", sb)

	# Les instruments encastres : un creux, pas une boite posee par-dessus.
	var inset := StyleBoxFlat.new()
	inset.bg_color = Palette.ASPHALT
	inset.set_corner_radius_all(6)
	inset.border_color = Color(0, 0, 0, 0.6)
	inset.border_width_top = 2
	inset.border_width_left = 1
	inset.border_width_right = 1
	inset.set_content_margin_all(8)
	t.add_type("Instrument")
	t.set_type_variation("Instrument", "PanelContainer")
	t.set_stylebox("panel", "Instrument", inset)


static func _setup_panels(t: Theme) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.INK
	sb.set_corner_radius_all(3)
	sb.border_color = Palette.SMOKE
	sb.border_width_top = 2
	sb.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", sb)


## La StyleBox d'une carte. Le rayon des coins et l'ombre suffisent a donner
## l'impression d'un objet pose sur une table.
static func card_box(face: Color, accent: Color, raised: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = face
	sb.set_corner_radius_all(6)
	sb.border_color = accent
	sb.border_width_left = 3
	sb.shadow_color = Color(0, 0, 0, 0.55 if raised else 0.35)
	sb.shadow_size = 18 if raised else 8
	sb.shadow_offset = Vector2(0, 10 if raised else 4)
	return sb
