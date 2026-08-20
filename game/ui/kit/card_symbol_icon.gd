class_name CardSymbolIcon
extends Control

## One card symbol: tinted SVG icon, optional count, rich tooltip on hover.

signal activated(kind: CardSymbol.Kind)

const DEFAULT_ICON_SIZE := 22.0
const STATE_INERT := "inert"
const STATE_CLICKABLE := "clickable"
const STATE_RESOLVED := "resolved"

var _kind: CardSymbol.Kind = CardSymbol.Kind.HEAT
var _count: int = 1
var _extra: Dictionary = {}
var _tooltip_bbcode: String = ""
var _icon_px: float = DEFAULT_ICON_SIZE
var force_hide_count := false
var _state: String = STATE_INERT

var _icon: TextureRect
var _count_label: Label
var _check: TextureRect


func kind() -> CardSymbol.Kind:
	return _kind


func _ready() -> void:
	if _icon == null:
		_build()
	_sync_tooltip()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		var card := _owning_card()
		if card != null:
			card.sync_pointer_hover()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _state == STATE_CLICKABLE:
			activated.emit(_kind)
			accept_event()
			return
		var card := _owning_card()
		if card != null:
			card._gui_input(event)


func _owning_card() -> Card:
	var node := get_parent()
	while node != null:
		if node is Card:
			return node
		node = node.get_parent()
	return null


func setup(p_kind: CardSymbol.Kind, p_count: int = 1, extra: Dictionary = {}) -> void:
	_kind = p_kind
	_count = p_count
	_extra = extra
	var sym := CardSymbol.make(p_kind, p_count)
	_tooltip_bbcode = sym.tooltip_bbcode(extra)
	_sync_tooltip()
	if _icon == null:
		_build()
	else:
		_apply_visual()


func set_icon_size(pixels: float) -> void:
	_icon_px = pixels
	custom_minimum_size = Vector2(pixels * 1.6, pixels)
	if _icon != null:
		_apply_visual()


func set_count_color(color: Color) -> void:
	if _count_label != null:
		_count_label.add_theme_color_override(&"font_color", color)


func set_interaction_state(state: String) -> void:
	_state = state
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if state == STATE_CLICKABLE else Control.CURSOR_ARROW
	)
	_apply_visual()


func _build() -> void:
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_count_label = Label.new()
	_count_label.theme_type_variation = &"Caption"
	_count_label.add_theme_color_override(&"font_color", Palette.INK)
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	_check = TextureRect.new()
	_check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_check.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check.visible = false
	add_child(_check)

	_apply_visual()


func _apply_visual() -> void:
	if _icon == null:
		return
	_icon.texture = CardSymbolVisual.texture(_kind, _icon_px)
	_icon.material = null
	var tint := CardSymbolVisual.tint(_kind)
	if _state == STATE_RESOLVED:
		_icon.modulate = Color(tint.r, tint.g, tint.b, 0.35)
	else:
		_icon.modulate = tint
	var show_n := CardSymbol.shows_count(_kind) and not force_hide_count
	_count_label.visible = show_n
	if show_n:
		if _kind == CardSymbol.Kind.ADJUST_SPEED_LIMIT and _count >= 0:
			_count_label.text = "+%d" % _count
		else:
			_count_label.text = str(_count)
		_count_label.modulate.a = 0.35 if _state == STATE_RESOLVED else 1.0
	_apply_layout(_icon_px)
	_apply_check()


func _apply_check() -> void:
	if _check == null:
		return
	var show_check := _state == STATE_RESOLVED
	_check.visible = show_check
	if not show_check:
		return
	var check_px := maxf(10.0, _icon_px * 0.72)
	_check.texture = CardSymbolVisual.check_texture(check_px)
	_check.modulate = CardSymbolVisual.CHECK_GREEN
	_check.size = Vector2(check_px, check_px)
	_check.position = Vector2((_icon_px - check_px) * 0.5, (_icon_px - check_px) * 0.5)


func _apply_layout(icon_px: float) -> void:
	_icon.custom_minimum_size = Vector2(icon_px, icon_px)
	_icon.size = Vector2(icon_px, icon_px)
	_icon.position = Vector2.ZERO
	if _count_label.visible:
		var fs := maxi(10, int(round(icon_px * 0.5)))
		if icon_px >= 40.0:
			_count_label.add_theme_font_override("font", ThemeBuilder.display_font())
		_count_label.add_theme_font_size_override("font_size", fs)
		var font := _count_label.get_theme_font("font")
		if font == null:
			font = ThemeBuilder.display_font()
		var count_w := font.get_string_size(_count_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		count_w = maxf(count_w + 2.0, icon_px * 0.35)
		_count_label.position = Vector2(icon_px + 2.0, 0.0)
		_count_label.size = Vector2(count_w, icon_px)
		custom_minimum_size = Vector2(icon_px + count_w, icon_px)
	else:
		custom_minimum_size = Vector2(icon_px, icon_px)
	size = custom_minimum_size
	_apply_check()


func _make_custom_tooltip(_tooltip: String) -> Object:
	if tooltip_text.is_empty() or _tooltip_bbcode.strip_edges().is_empty():
		return null
	return CardSymbolTooltip.make_control(_tooltip_bbcode)


func _sync_tooltip() -> void:
	tooltip_text = " " if not _tooltip_bbcode.strip_edges().is_empty() else ""
