class_name CardSymbolIcon
extends Control

## One card symbol: tinted SVG icon, optional count, rich tooltip on hover.

const DEFAULT_ICON_SIZE := 22.0

var _kind: CardSymbol.Kind = CardSymbol.Kind.HEAT
var _count: int = 1
var _extra: Dictionary = {}
var _tooltip_bbcode: String = ""
var _icon_px: float = DEFAULT_ICON_SIZE
var force_hide_count := false

var _icon: TextureRect
var _count_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	if _icon == null:
		_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		var card := _owning_card()
		if card != null:
			card.sync_pointer_hover()


func _gui_input(event: InputEvent) -> void:
	# Clic sur l'icône = clic sur la carte (sélection, etc.).
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
	if _icon == null:
		_build()
	else:
		_apply_visual()


func set_icon_size(pixels: float) -> void:
	_icon_px = pixels
	custom_minimum_size = Vector2(pixels * 1.6, pixels)
	if _icon != null:
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

	_apply_visual()


func _apply_visual() -> void:
	if _icon == null:
		return
	_icon.texture = CardSymbolVisual.texture(_kind, _icon_px)
	_icon.material = null
	_icon.modulate = CardSymbolVisual.tint(_kind)
	var show_n := CardSymbol.shows_count(_kind) and not force_hide_count
	_count_label.visible = show_n
	if show_n:
		if _kind == CardSymbol.Kind.ADJUST_SPEED_LIMIT and _count >= 0:
			_count_label.text = "+%d" % _count
		else:
			_count_label.text = str(_count)
	_apply_layout(_icon_px)


func _apply_layout(icon_px: float) -> void:
	_icon.custom_minimum_size = Vector2(icon_px, icon_px)
	_icon.size = Vector2(icon_px, icon_px)
	_icon.position = Vector2.ZERO
	var count_w := 0.0
	if _count_label.visible:
		count_w = _count_label.get_minimum_size().x + 2.0
		_count_label.position = Vector2(icon_px + 2.0, 0.0)
		_count_label.size = Vector2(count_w, icon_px)
	custom_minimum_size = Vector2(icon_px + count_w, icon_px)
	size = custom_minimum_size


func _make_custom_tooltip(_tooltip: String) -> Object:
	return CardSymbolTooltip.make_control(_tooltip_bbcode)
