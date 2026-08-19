@tool
class_name Card
extends Control

## Une carte de jeu, construite a partir d'un CardData. Aucune image :
## StyleBoxFlat pour le carton, Label pour les chiffres, CardSymbolIcon pour les symboles.
##
## Consequences pratiques :
##  - le texte reste net a toutes les resolutions
##  - changer une valeur d'equilibrage = changer une donnee, pas rouvrir Inkscape
##  - le survol, la selection et le retournement sont des animations, pas des sprites

signal clicked(card: Card)
signal symbol_activated(kind: CardSymbol.Kind)
signal speed_picked(speed: int)

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
var _speed_pick: GridContainer
var _title: Label
var _center_icon: TextureRect
var _effect: Label
var _kerb: Kerb
var _symbols_host: CenterContainer
var _symbols_stack: VBoxContainer
var _mandatory_row: HBoxContainer
var _optional_row: HBoxContainer
## kind int -> "inert" | "clickable" | "resolved"
var _symbol_states: Dictionary = {}
var _speed_override := -1
var _speed_pick_options: PackedInt32Array = PackedInt32Array()
var _speed_pick_enabled := false


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

	_big.offset_left = pad
	_big.offset_right = -pad
	_big.offset_bottom = -(kerb_h + effect_h + roundf(6.0 * s))
	_fit_big_font(s, pad)
	_layout_speed_pick(s, pad, kerb_h, effect_h)
	_layout_center_icon(s, pad, kerb_h, effect_h)

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
	var icon_px := maxf(16.0, roundf(24.0 * s))
	var row_sep := maxi(2, int(round(4.0 * s)))
	_layout_symbols(icon_px, row_sep)
	if _symbols_stack != null:
		_symbols_stack.add_theme_constant_override("separation", maxi(2, int(round(4.0 * s))))
	var title_h := roundf(24.0 * s)
	var row_h := icon_px + roundf(4.0 * s)
	var row_count := _symbol_row_count()
	var stack_h := row_h * float(row_count)
	if row_count > 1:
		stack_h += roundf(4.0 * s)
	if _speed_pick_active():
		# Symbols sit on the kerb, below the speed grid.
		_symbols_host.offset_top = card_size.y - kerb_h - effect_h - stack_h - roundf(2.0 * s)
		_symbols_host.offset_bottom = _symbols_host.offset_top + stack_h
	else:
		var big_bottom := card_size.y - kerb_h - effect_h - roundf(6.0 * s)
		var big_center_y := (title_h + big_bottom) * 0.5
		_symbols_host.offset_top = big_center_y + roundf(18.0 * s)
		_symbols_host.offset_bottom = _symbols_host.offset_top + stack_h
	queue_redraw()


func _fit_big_font(s: float, pad: float) -> void:
	var max_size := maxi(18, int(round(76.0 * s)))
	var min_size := maxi(10, int(round(16.0 * s)))
	var font := _big.get_theme_font("font")
	if font == null:
		font = ThemeBuilder.display_font()
	var max_w := maxf(8.0, card_size.x - pad * 2.0)
	var size := max_size
	while size > min_size:
		var w := font.get_string_size(_big.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if w <= max_w:
			break
		size -= 1
	_big.add_theme_font_size_override("font_size", size)


func _layout_center_icon(s: float, pad: float, kerb_h: float, effect_h: float) -> void:
	if _center_icon == null:
		return
	var show := face_up and data != null and data.shows_heat_center()
	_center_icon.visible = show
	if not show:
		return
	var icon_px := maxf(36.0, roundf(72.0 * s))
	_center_icon.texture = CardSymbolVisual.texture(CardSymbol.Kind.HEAT, icon_px)
	_center_icon.modulate = data.ink()
	var top := roundf(28.0 * s)
	var bottom := kerb_h + effect_h + roundf(6.0 * s)
	_center_icon.offset_left = pad
	_center_icon.offset_right = -pad
	_center_icon.offset_top = top
	_center_icon.offset_bottom = -bottom


func _layout_symbols(icon_px: float, separation: int) -> void:
	if _mandatory_row == null:
		return
	for row in [_mandatory_row, _optional_row]:
		row.add_theme_constant_override("separation", separation)
		for child in row.get_children():
			if child is CardSymbolIcon:
				child.set_icon_size(icon_px)


func _build() -> void:
	_title = Label.new()
	_title.theme_type_variation = "Eyebrow"
	add_child(_title)

	_big = Label.new()
	_big.theme_type_variation = "BigNumber"
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big.clip_text = true
	_big.anchor_right = 1.0
	_big.anchor_bottom = 1.0
	add_child(_big)

	_speed_pick = GridContainer.new()
	_speed_pick.columns = 2
	_speed_pick.visible = false
	_speed_pick.anchor_right = 1.0
	_speed_pick.anchor_bottom = 1.0
	_speed_pick.mouse_filter = Control.MOUSE_FILTER_STOP
	_speed_pick.z_index = 3
	add_child(_speed_pick)

	_center_icon = TextureRect.new()
	_center_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_center_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_center_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_center_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_icon.anchor_right = 1.0
	_center_icon.anchor_bottom = 1.0
	_center_icon.visible = false
	add_child(_center_icon)

	_symbols_host = CenterContainer.new()
	_symbols_host.anchor_left = 0.0
	_symbols_host.anchor_right = 1.0
	_symbols_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_symbols_host)

	_symbols_stack = VBoxContainer.new()
	_symbols_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	_symbols_stack.add_theme_constant_override("separation", 4)
	_symbols_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_symbols_host.add_child(_symbols_stack)

	_mandatory_row = HBoxContainer.new()
	_mandatory_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_mandatory_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_symbols_stack.add_child(_mandatory_row)

	_optional_row = HBoxContainer.new()
	_optional_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_optional_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_symbols_stack.add_child(_optional_row)

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
	var show_pick := _speed_pick_active()
	_big.visible = visible_face and data != null and not data.shows_heat_center() and not show_pick
	if _speed_pick != null:
		_speed_pick.visible = show_pick
	_effect.visible = visible_face
	_kerb.visible = visible_face

	if visible_face:
		_title.text = data.title
		_big.text = str(_speed_override) if _speed_override >= 0 else data.big_text()
		_effect.text = data.effect
		var ink := data.ink()
		_title.add_theme_color_override("font_color", ink * Color(1, 1, 1, 0.6))
		_big.add_theme_color_override("font_color", ink)
		_effect.add_theme_color_override("font_color", ink * Color(1, 1, 1, 0.7))
		_kerb.color_a = data.accent()
		_kerb.color_b = data.face()

	_rebuild_symbols()
	# La presence d'un texte d'effet change la hauteur reservee au gros chiffre.
	_apply_size()
	queue_redraw()


func set_symbol_states(states: Dictionary) -> void:
	_symbol_states = states
	_apply_symbol_states()


func set_resolved_speed(speed: int) -> void:
	_speed_override = speed
	_speed_pick_enabled = false
	_refresh()


func set_speed_pick(options: PackedInt32Array, enabled: bool) -> void:
	_speed_pick_options = options
	_speed_pick_enabled = enabled and options.size() > 1
	_rebuild_speed_pick()
	_refresh()


func _speed_pick_active() -> bool:
	return face_up and _speed_pick_enabled and _speed_pick_options.size() > 1


func _rebuild_speed_pick() -> void:
	if _speed_pick == null:
		return
	for child in _speed_pick.get_children():
		child.queue_free()
	if not _speed_pick_enabled:
		return
	for v in _speed_pick_options:
		var btn := Button.new()
		btn.text = str(v)
		btn.clip_text = false
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_override("font", ThemeBuilder.display_font())
		btn.add_theme_color_override("font_color", Palette.INK)
		btn.add_theme_color_override("font_hover_color", Palette.INK)
		btn.add_theme_color_override("font_pressed_color", Palette.INK)
		btn.add_theme_color_override("font_focus_color", Palette.INK)
		btn.add_theme_stylebox_override("normal", _speed_pick_box(Palette.CARDBOARD_DARK, Palette.INK))
		btn.add_theme_stylebox_override("hover", _speed_pick_box(Palette.CARDBOARD, Palette.MUSTARD))
		btn.add_theme_stylebox_override("pressed", _speed_pick_box(Palette.MUSTARD, Palette.INK))
		btn.add_theme_stylebox_override("focus", _speed_pick_box(Palette.CARDBOARD_DARK, Palette.INK))
		var speed := v
		btn.pressed.connect(func() -> void:
			speed_picked.emit(speed)
		)
		_speed_pick.add_child(btn)


func _layout_speed_pick(s: float, pad: float, kerb_h: float, effect_h: float) -> void:
	if _speed_pick == null:
		return
	if not _speed_pick_active():
		return
	var n := _speed_pick_options.size()
	var rows := maxi(1, int(ceili(float(n) / 2.0)))
	var gap := maxf(4.0, roundf(6.0 * s))
	_speed_pick.add_theme_constant_override("h_separation", int(gap))
	_speed_pick.add_theme_constant_override("v_separation", int(gap))
	var title_h := roundf(24.0 * s)
	var symbol_reserve := 0.0
	if _symbol_row_count() > 0:
		symbol_reserve = maxf(16.0, roundf(24.0 * s)) + roundf(6.0 * s)
	var bottom := kerb_h + (effect_h if _effect.visible else 0.0) + symbol_reserve + roundf(4.0 * s)
	var avail_w := card_size.x - pad * 2.0
	var avail_h := card_size.y - title_h - bottom
	var side := minf((avail_w - gap) * 0.5, (avail_h - gap * float(rows - 1)) / float(rows))
	side = maxf(22.0, floorf(side))
	var font_px := maxi(12, int(round(side * 0.48)))
	for child in _speed_pick.get_children():
		if child is Button:
			var btn := child as Button
			btn.custom_minimum_size = Vector2(side, side)
			btn.size = Vector2(side, side)
			btn.add_theme_font_size_override("font_size", font_px)
	var grid_w := side * 2.0 + gap
	var grid_h := side * float(rows) + gap * float(rows - 1)
	var left := (card_size.x - grid_w) * 0.5
	_speed_pick.offset_left = left
	_speed_pick.offset_right = -(card_size.x - left - grid_w)
	_speed_pick.offset_top = title_h + maxf(0.0, (avail_h - grid_h) * 0.5)
	_speed_pick.offset_bottom = -(card_size.y - _speed_pick.offset_top - grid_h)


func _speed_pick_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.content_margin_left = 2
	box.content_margin_right = 2
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


func _rebuild_symbols() -> void:
	if _mandatory_row == null:
		return
	for child in _mandatory_row.get_children():
		child.queue_free()
	for child in _optional_row.get_children():
		child.queue_free()
	if data == null or not face_up:
		_symbols_host.visible = false
		return
	var split_m := _mandatory_symbol_entries()
	var split_o := _optional_symbol_entries()
	var has_any: bool = not split_m.is_empty() or not split_o.is_empty()
	_symbols_host.visible = has_any
	if not has_any:
		return
	var s := card_size.y / SIZE_DEFAULT.y
	var icon_px := maxf(16.0, roundf(24.0 * s))
	_populate_symbol_row(_mandatory_row, split_m, icon_px)
	_populate_symbol_row(_optional_row, split_o, icon_px)
	_mandatory_row.visible = not split_m.is_empty()
	_optional_row.visible = not split_o.is_empty()


func _populate_symbol_row(row: HBoxContainer, entries: Array[CardSymbol], icon_px: float) -> void:
	for entry in entries:
		var icon := CardSymbolIcon.new()
		icon.setup(entry.kind, entry.count)
		icon.activated.connect(_on_symbol_activated)
		row.add_child(icon)
		icon.set_icon_size(icon_px)
	_apply_symbol_states()


func _on_symbol_activated(kind: CardSymbol.Kind) -> void:
	symbol_activated.emit(kind)


func _apply_symbol_states() -> void:
	for row in [_mandatory_row, _optional_row]:
		if row == null:
			continue
		for child in row.get_children():
			if child is CardSymbolIcon:
				var st := str(_symbol_states.get(int(child.kind()), CardSymbolIcon.STATE_INERT))
				child.set_interaction_state(st)


func _mandatory_symbol_entries() -> Array[CardSymbol]:
	var out: Array[CardSymbol] = []
	for entry in _all_symbol_entries():
		if CardSymbol.is_mandatory(entry.kind):
			out.append(entry)
	return out


func _optional_symbol_entries() -> Array[CardSymbol]:
	var out: Array[CardSymbol] = []
	for entry in _all_symbol_entries():
		if not CardSymbol.is_mandatory(entry.kind):
			out.append(entry)
	return out


func _symbol_row_count() -> int:
	if data == null or not face_up:
		return 0
	var n := 0
	if not _mandatory_symbol_entries().is_empty():
		n += 1
	if not _optional_symbol_entries().is_empty():
		n += 1
	return n


func _all_symbol_entries() -> Array[CardSymbol]:
	var out: Array[CardSymbol] = []
	if data.shows_heat_center():
		return out
	for entry in data.symbol_entries:
		out.append(entry)
	return out


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if data == null:
		return

	if face_up:
		var box := ThemeBuilder.card_box(data.face(), data.accent(), _hovered or selected)
		box.draw(get_canvas_item(), r)
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


func _draw_chevron(center: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(-s, s * 0.5),
		center + Vector2(0, -s * 0.5),
		center + Vector2(s, s * 0.5),
	])
	draw_polyline(pts, col, maxf(2.0, s * 0.22), true)


# --- Interaction ---

func _gui_input(event: InputEvent) -> void:
	if dimmed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)


func _notification(what: int) -> void:
	if dimmed:
		return
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		sync_pointer_hover()


## Appelé aussi par les icônes : un enfant STOP vole le hover du parent.
func sync_pointer_hover() -> void:
	if _hover_sync_queued:
		return
	_hover_sync_queued = true
	call_deferred("_apply_pointer_hover")


func _apply_pointer_hover() -> void:
	_hover_sync_queued = false
	if not is_inside_tree() or dimmed:
		return
	var over := _pointer_is_on_self()
	if not over and _hovered and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		over = true
	if _hovered == over:
		return
	_hovered = over
	z_index = 10 if over else 0
	_lift(over)


func _pointer_is_on_self() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if _is_self_or_descendant(hovered):
		return true
	var other := _card_ancestor(hovered)
	if other != null and other != self:
		return false
	# Tooltip / popup : garder le hover si le curseur est encore sur la carte.
	return _hovered and _contains_pointer()


func _contains_pointer() -> bool:
	var local := get_global_transform().affine_inverse() * get_global_mouse_position()
	return Rect2(Vector2.ZERO, size).has_point(local)


func _is_self_or_descendant(node: Node) -> bool:
	while node != null:
		if node == self:
			return true
		node = node.get_parent()
	return false


func _card_ancestor(node: Node) -> Card:
	while node != null:
		if node is Card:
			return node
		node = node.get_parent()
	return null


var _rest_offset := 0.0
var _lift_tween: Tween
var _hover_sync_queued := false

func _lift(up: bool) -> void:
	queue_redraw()
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	var target := _rest_offset - (18.0 if up else 0.0)
	_lift_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_lift_tween.tween_property(self, "position:y", target, 0.14)


## Enregistre la position de repos (a appeler apres avoir place la carte).
func set_rest_y(y: float) -> void:
	_rest_offset = y
	if _hovered:
		position.y = y - 18.0
	else:
		position.y = y


## Retourne la carte avec un scale sur X. Aucune texture de verso necessaire.
func flip() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale:x", 0.0, 0.12)
	tween.tween_callback(func() -> void: face_up = not face_up)
	tween.tween_property(self, "scale:x", 1.0, 0.12)
