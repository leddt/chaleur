class_name ThemeBuilder
extends RefCounted

## Construit le Theme complet du jeu en code. Aucun fichier .theme a maintenir.
##
## Usage :
##   var t := ThemeBuilder.build()
##   get_tree().root.theme = t          # applique a tout le jeu
##
## Polices : FontFile embarques dans res://fonts/ (Archivo Black + Barlow Condensed).

const DISPLAY_FONT_PATH := "res://fonts/ArchivoBlack-Regular.ttf"
const BODY_FONT_PATH := "res://fonts/BarlowCondensed-Medium.ttf"

# Echelle typographique. Un seul ratio, applique partout.
const SIZE_HUGE := 76
const SIZE_XL := 34
const SIZE_L := 22
const SIZE_M := 16
const SIZE_S := 13
const SIZE_XS := 11


static func display_font() -> Font:
	return load(DISPLAY_FONT_PATH) as Font


static func body_font() -> Font:
	return load(BODY_FONT_PATH) as Font

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
	_setup_option_buttons(t, body)
	_setup_item_lists(t, body)
	_setup_scroll(t)
	_setup_rich_text(t, body)
	_setup_tooltips(t, body)
	_setup_separators(t)
	_setup_dialogs(t, body)
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
	_setup_primary_strip_button(t, body)
	_setup_compact_button(t, body)
	_setup_symbol_action_button(t, body)
	_setup_color_picker_button(t)


## Pastilles de couleur : peu de marge pour maximiser la surface de swatch.
static func _setup_color_picker_button(t: Theme) -> void:
	t.set_stylebox("normal", "ColorPickerButton", _color_picker_button_box(Color(0, 0, 0, 0), Palette.SMOKE))
	t.set_stylebox("hover", "ColorPickerButton", _color_picker_button_box(Color(0, 0, 0, 0), Palette.MUSTARD))
	t.set_stylebox("pressed", "ColorPickerButton", _color_picker_button_box(Palette.MUSTARD, Palette.MUSTARD))
	t.set_stylebox("disabled", "ColorPickerButton", _color_picker_button_box(Color(0, 0, 0, 0), Palette.INK))
	t.set_stylebox("focus", "ColorPickerButton", _color_picker_button_box(Color(0, 0, 0, 0), Palette.CARDBOARD))


static func _color_picker_button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := _button_box(fill, border)
	sb.set_content_margin_all(2)
	return sb


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
	t.set_color("icon_normal_color", "Compact", Palette.CARDBOARD)
	t.set_color("icon_hover_color", "Compact", Palette.MUSTARD)
	t.set_color("icon_pressed_color", "Compact", Palette.INK)
	t.set_color("icon_disabled_color", "Compact", Palette.SMOKE)
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


static func _primary_strip_box(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := _button_box(fill, border)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## Icônes de réaction / règlement : fond carton pour que les SVG restent lisibles.
static func _setup_symbol_action_button(t: Theme, body: Font) -> void:
	t.add_type("SymbolAction")
	t.set_type_variation("SymbolAction", "Button")
	t.set_font("font", "SymbolAction", body)
	t.set_font_size("font_size", "SymbolAction", SIZE_S)
	t.set_color("font_color", "SymbolAction", Palette.INK)
	t.set_color("font_hover_color", "SymbolAction", Palette.INK)
	t.set_color("font_pressed_color", "SymbolAction", Palette.INK)
	t.set_color("font_disabled_color", "SymbolAction", Palette.SMOKE)
	t.set_stylebox("normal", "SymbolAction", _symbol_action_box(Palette.CARDBOARD, Palette.INK))
	t.set_stylebox(
		"hover", "SymbolAction", _symbol_action_box(Palette.CARDBOARD, Palette.MUSTARD)
	)
	t.set_stylebox("pressed", "SymbolAction", _symbol_action_box(Palette.MUSTARD, Palette.INK))
	t.set_stylebox(
		"disabled", "SymbolAction", _symbol_action_box(Palette.CARDBOARD_DARK, Palette.SMOKE)
	)
	t.set_stylebox("focus", "SymbolAction", _symbol_action_box(Palette.CARDBOARD, Palette.CARDBOARD))


static func _symbol_action_box(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := _button_box(fill, border)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
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


## Primary plus bas, pour le bandeau cockpit (Terminer sous la grille 2×2).
static func _setup_primary_strip_button(t: Theme, body: Font) -> void:
	t.add_type("PrimaryStrip")
	t.set_type_variation("PrimaryStrip", "Button")
	t.set_font("font", "PrimaryStrip", body)
	t.set_font_size("font_size", "PrimaryStrip", SIZE_M)
	t.set_color("font_color", "PrimaryStrip", Palette.INK)
	t.set_color("font_hover_color", "PrimaryStrip", Palette.INK)
	t.set_color("font_pressed_color", "PrimaryStrip", Palette.CARDBOARD)
	t.set_color("font_disabled_color", "PrimaryStrip", Palette.SMOKE)
	t.set_stylebox("normal", "PrimaryStrip", _primary_strip_box(Palette.MUSTARD, Palette.MUSTARD))
	t.set_stylebox(
		"hover",
		"PrimaryStrip",
		_primary_strip_box(Palette.MUSTARD.lightened(0.12), Palette.CARDBOARD)
	)
	t.set_stylebox("pressed", "PrimaryStrip", _primary_strip_box(Palette.RACE_RED, Palette.RACE_RED))
	t.set_stylebox("disabled", "PrimaryStrip", _primary_strip_box(Palette.INK, Palette.SMOKE))
	t.set_stylebox("focus", "PrimaryStrip", _primary_strip_box(Color(0, 0, 0, 0), Palette.CARDBOARD))


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
	t.set_color("selection_color", "LineEdit", Palette.MUSTARD * Color(1, 1, 1, 0.35))
	t.set_color("font_selected_color", "LineEdit", Palette.INK)
	t.set_stylebox("normal", "LineEdit", _field_box(false))
	t.set_stylebox("focus", "LineEdit", _field_box(true))
	t.set_stylebox("read_only", "LineEdit", _field_box(false, true))

	t.set_font("font", "SpinBox", body)
	t.set_font_size("font_size", "SpinBox", SIZE_S)
	t.set_color("font_color", "SpinBox", Palette.CARDBOARD)
	t.set_icon("updown", "SpinBox", _spin_updown(Palette.CARDBOARD))


## Puits enfoncé : distinct des boutons en contour (fond transparent + bord 2 px).
static func _field_box(focused: bool, read_only: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.INK if not read_only else Palette.INK.darkened(0.12)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	# Ombre interne en haut/gauche : ça se lit comme un creux, pas comme un bouton.
	sb.border_color = Palette.MUSTARD if focused else Color(0, 0, 0, 0.72)
	sb.border_width_top = 2
	sb.border_width_left = 2
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	if focused:
		sb.border_width_right = 2
		sb.border_width_bottom = 2
	return sb


static func _spin_updown(color: Color) -> Texture2D:
	var img := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Top: increment (apex up). Bottom: decrement (apex down).
	for i in 4:
		var x0 := 3 - i
		var x1 := 4 + i
		for x in range(maxi(x0, 0), mini(x1, 7) + 1):
			img.set_pixel(x, 2 + i, color)
			img.set_pixel(x, 13 - i, color)
	return ImageTexture.create_from_image(img)


static func _setup_option_buttons(t: Theme, body: Font) -> void:
	t.set_font("font", "OptionButton", body)
	t.set_font_size("font_size", "OptionButton", SIZE_S)
	t.set_color("font_color", "OptionButton", Palette.CARDBOARD)
	t.set_color("font_hover_color", "OptionButton", Palette.MUSTARD)
	t.set_color("font_pressed_color", "OptionButton", Palette.INK)
	t.set_color("font_disabled_color", "OptionButton", Palette.SMOKE)
	t.set_stylebox("normal", "OptionButton", _compact_button_box(Color(0, 0, 0, 0), Palette.SMOKE))
	t.set_stylebox("hover", "OptionButton", _compact_button_box(Color(0, 0, 0, 0), Palette.MUSTARD))
	t.set_stylebox("pressed", "OptionButton", _compact_button_box(Palette.MUSTARD, Palette.MUSTARD))
	t.set_stylebox("disabled", "OptionButton", _compact_button_box(Color(0, 0, 0, 0), Palette.INK))
	t.set_stylebox("focus", "OptionButton", _compact_button_box(Color(0, 0, 0, 0), Palette.CARDBOARD))
	t.set_icon("arrow", "OptionButton", _option_arrow(Palette.CARDBOARD))

	t.add_type("CompactOption")
	t.set_type_variation("CompactOption", "OptionButton")
	t.set_font("font", "CompactOption", body)
	t.set_font_size("font_size", "CompactOption", SIZE_S)
	t.set_stylebox("normal", "CompactOption", _compact_button_box(Color(0, 0, 0, 0), Palette.SMOKE))
	t.set_stylebox("hover", "CompactOption", _compact_button_box(Color(0, 0, 0, 0), Palette.MUSTARD))
	t.set_stylebox("pressed", "CompactOption", _compact_button_box(Palette.MUSTARD, Palette.MUSTARD))
	t.set_stylebox("disabled", "CompactOption", _compact_button_box(Color(0, 0, 0, 0), Palette.INK))
	t.set_stylebox("focus", "CompactOption", _compact_button_box(Color(0, 0, 0, 0), Palette.CARDBOARD))

	t.set_font("font", "PopupMenu", body)
	t.set_font_size("font_size", "PopupMenu", SIZE_S)
	t.set_color("font_color", "PopupMenu", Palette.CARDBOARD)
	t.set_color("font_hover_color", "PopupMenu", Palette.MUSTARD)
	t.set_color("font_accelerator_color", "PopupMenu", Palette.SMOKE)
	t.set_color("font_separator_color", "PopupMenu", Palette.SMOKE)
	var menu_panel := StyleBoxFlat.new()
	menu_panel.bg_color = Palette.INK
	menu_panel.border_color = Palette.SMOKE
	menu_panel.set_border_width_all(1)
	menu_panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PopupMenu", menu_panel)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Palette.ASPHALT
	hover.border_color = Palette.MUSTARD
	hover.border_width_left = 2
	hover.set_content_margin_all(4)
	t.set_stylebox("hover", "PopupMenu", hover)
	t.set_stylebox("labeled_separator_left", "PopupMenu", StyleBoxEmpty.new())
	t.set_stylebox("labeled_separator_right", "PopupMenu", StyleBoxEmpty.new())


static func _option_arrow(color: Color) -> Texture2D:
	var img := Image.create(10, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 5:
		for x in range(y, 10 - y):
			img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


static func _setup_item_lists(t: Theme, body: Font) -> void:
	t.set_font("font", "ItemList", body)
	t.set_font_size("font_size", "ItemList", SIZE_S)
	t.set_color("font_color", "ItemList", Palette.CARDBOARD)
	t.set_color("font_hovered_color", "ItemList", Palette.MUSTARD)
	t.set_color("font_selected_color", "ItemList", Palette.INK)
	t.set_constant("v_separation", "ItemList", 4)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Palette.ASPHALT
	panel.border_color = Palette.SMOKE
	panel.set_border_width_all(1)
	panel.set_content_margin_all(6)
	t.set_stylebox("panel", "ItemList", panel)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Palette.MUSTARD
	selected.set_corner_radius_all(2)
	t.set_stylebox("selected", "ItemList", selected)
	t.set_stylebox("selected_focus", "ItemList", selected)
	var hovered := StyleBoxFlat.new()
	hovered.bg_color = Color(Palette.MUSTARD.r, Palette.MUSTARD.g, Palette.MUSTARD.b, 0.18)
	t.set_stylebox("hovered", "ItemList", hovered)
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ItemList", _compact_button_box(Color(0, 0, 0, 0), Palette.CARDBOARD))


static func _setup_scroll(t: Theme) -> void:
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Palette.SMOKE
	grabber.set_corner_radius_all(2)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	var scroll := StyleBoxFlat.new()
	scroll.bg_color = Palette.INK
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "HScrollBar", grabber)
	t.set_stylebox("scroll", "HScrollBar", scroll)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())


static func _setup_rich_text(t: Theme, body: Font) -> void:
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font_size("normal_font_size", "RichTextLabel", SIZE_S)
	t.set_color("default_color", "RichTextLabel", Palette.CARDBOARD)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())


static func _setup_tooltips(t: Theme, body: Font) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Palette.INK
	panel.border_color = Palette.SMOKE
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(3)
	panel.set_content_margin_all(10)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 6
	t.set_stylebox("panel", "TooltipPanel", panel)
	t.set_font("font", "TooltipLabel", body)
	t.set_font_size("font_size", "TooltipLabel", SIZE_S)
	t.set_color("font_color", "TooltipLabel", Palette.CARDBOARD)


static func _setup_separators(t: Theme) -> void:
	var sep := StyleBoxFlat.new()
	sep.bg_color = Palette.SMOKE
	sep.content_margin_top = 1
	sep.content_margin_bottom = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "VSeparator", sep)


static func _setup_dialogs(t: Theme, body: Font) -> void:
	t.set_font("title_font", "Window", display_font())
	t.set_font_size("title_font_size", "Window", SIZE_M)
	t.set_color("title_color", "Window", Palette.CARDBOARD)
	t.set_color("title_outline_modulate", "Window", Palette.INK)
	t.set_constant("title_height", "Window", 36)
	t.set_constant("title_outline_size", "Window", 0)
	t.set_constant("close_h_offset", "Window", 22)
	t.set_constant("close_v_offset", "Window", 18)

	var chrome := StyleBoxFlat.new()
	chrome.bg_color = Palette.INK
	chrome.border_color = Palette.SMOKE
	chrome.set_border_width_all(2)
	chrome.set_corner_radius_all(4)
	chrome.content_margin_left = 12
	chrome.content_margin_right = 12
	chrome.content_margin_top = 12
	chrome.content_margin_bottom = 12
	chrome.expand_margin_top = 36
	chrome.shadow_color = Color(0, 0, 0, 0.45)
	chrome.shadow_size = 10
	chrome.shadow_offset = Vector2(0, 4)
	t.set_stylebox("embedded_border", "Window", chrome)
	t.set_stylebox("embedded_unfocused_border", "Window", chrome)
	t.set_stylebox("panel", "Window", chrome)

	var body_panel := StyleBoxFlat.new()
	body_panel.bg_color = Palette.INK
	body_panel.border_color = Palette.SMOKE
	body_panel.set_border_width_all(2)
	body_panel.set_corner_radius_all(4)
	# The title is drawn above the panel rect; expand the fill so it is not see-through.
	body_panel.expand_margin_top = 36
	body_panel.content_margin_left = 16
	body_panel.content_margin_right = 16
	body_panel.content_margin_top = 12
	body_panel.content_margin_bottom = 16
	t.set_stylebox("panel", "AcceptDialog", body_panel)
	t.set_font("font", "AcceptDialog", body)
	t.set_font_size("font_size", "AcceptDialog", SIZE_M)


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
