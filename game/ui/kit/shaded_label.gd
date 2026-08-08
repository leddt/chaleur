@tool
class_name ShadedLabel
extends Control

## Label rasterise dans un SubViewport, puis affiche via TextureRect.
## Necessaire pour appliquer un ShaderMaterial qui echantillonne TEXTURE :
## sur un Label nu, Godot 4 n'expose pas ce built-in.

@export var text: String = "":
	set(v):
		if text == v:
			return
		text = v
		_queue_refresh()

@export var font_size: int = 32:
	set(v):
		if font_size == v:
			return
		font_size = v
		_queue_refresh()

@export var letter_spacing: int = 0:
	set(v):
		if letter_spacing == v:
			return
		letter_spacing = v
		_queue_refresh()

var _font: Font
var _pending_material: Material
var _vp: SubViewport
var _label: Label
var _display: TextureRect
var _refresh_queued := false
## Si > 0, le glyphe est force a cette largeur (scale X leger si besoin).
var _lock_glyph_width := -1.0

## Marges autour du glyphe rasterise (gauche, haut, droite, bas) pour laisser
## de la place aux effets qui debordent (flammes, glow…).
@export var pad_left := 20
@export var pad_top := 20
@export var pad_right := 20
@export var pad_bottom := 20


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.handle_input_locally = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color.WHITE)
	_vp.add_child(_label)

	_display = TextureRect.new()
	_display.texture = _vp.get_texture()
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _pending_material != null:
		_display.material = _pending_material
		_pending_material = null
	add_child(_display)

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


func set_font(font: Font) -> void:
	_font = font
	_queue_refresh()


func set_shader_material(mat: Material) -> void:
	if _display != null:
		_display.material = mat
	else:
		_pending_material = mat


func get_ink_rect(alpha_threshold: float = 0.12) -> Rect2:
	## Rectangle du contenu opaque dans le VP (coordonnees locales du Control).
	if _vp == null or _vp.size.x < 1:
		return Rect2()
	var tex := _vp.get_texture()
	if tex == null:
		return Rect2()
	var img := tex.get_image()
	if img == null:
		return Rect2()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var min_x := img.get_width()
	var max_x := -1
	var min_y := img.get_height()
	var max_y := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > alpha_threshold:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2()
	# VP content mape sur le Control : titre = plein, sous-titre = offset + scale.
	if _lock_glyph_width > 0.0:
		var sx := _display.scale.x
		return Rect2(
			_display.position.x + float(min_x) * sx,
			_display.position.y + float(min_y),
			float(max_x - min_x + 1) * sx,
			float(max_y - min_y + 1)
		)
	return Rect2(float(min_x), float(min_y), float(max_x - min_x + 1), float(max_y - min_y + 1))


func get_glyph_size() -> Vector2:
	if _label == null:
		return Vector2.ZERO
	var h := _measure_height()
	if _lock_glyph_width > 0.0:
		return Vector2(_lock_glyph_width, h)
	return Vector2(_drawn_glyph_width(), h)


func _resolved_font() -> Font:
	if _font == null:
		return ThemeBuilder.body_font()
	if letter_spacing == 0:
		return _font
	var variation := FontVariation.new()
	variation.base_font = _font
	variation.spacing_glyph = letter_spacing
	return variation


func _measure_height() -> float:
	return _resolved_font().get_height(font_size)


func _unspaced_width() -> float:
	if text.is_empty():
		return 0.0
	var f := _font if _font != null else ThemeBuilder.body_font()
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _drawn_glyph_width() -> float:
	if text.is_empty():
		return 0.0
	return _resolved_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Ajuste font_size + letter_spacing pour que le glyphe ait exactement target_px
## de large (sans les pads).
func fit_glyph_width(target_px: float) -> void:
	if not is_node_ready():
		await ready
	_lock_glyph_width = -1.0
	letter_spacing = 0
	await _force_refresh()

	while font_size > 10 and _unspaced_width() > target_px + 0.5:
		font_size -= 1
		await _force_refresh()

	var gaps := maxi(text.length() - 1, 1)
	var base := _unspaced_width()
	letter_spacing = maxi(0, int(floor((target_px - base) / float(gaps))))
	_lock_glyph_width = target_px
	await _force_refresh()


func _queue_refresh() -> void:
	if not is_node_ready():
		return
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh")


func _force_refresh() -> void:
	_refresh_queued = false
	await _refresh()


func _refresh() -> void:
	_refresh_queued = false
	if _label == null:
		return

	var active_font := _resolved_font()
	_label.text = text
	_label.add_theme_font_override("font", active_font)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.reset_size()

	var text_h := _measure_height()
	var drawn_w := _drawn_glyph_width()

	if _lock_glyph_width > 0.0:
		# Sous-titre aligne : pads hors VP, scale X vers la largeur cible.
		var glyph_w := _lock_glyph_width
		var vp_w := maxi(1, ceili(drawn_w))
		var vp_h := maxi(1, ceili(text_h))
		_vp.size = Vector2i(vp_w, vp_h)
		_label.position = Vector2.ZERO
		custom_minimum_size = Vector2(
			float(pad_left) + glyph_w + float(pad_right),
			float(pad_top) + text_h + float(pad_bottom)
		)
		_display.position = Vector2(pad_left, pad_top)
		_display.size = Vector2(vp_w, vp_h)
		_display.scale = Vector2(glyph_w / maxf(drawn_w, 1.0), 1.0)
	else:
		# Titre / defaut : pads DANS le VP (place pour flammes, glow…).
		var w := maxi(1, ceili(drawn_w) + pad_left + pad_right)
		var h := maxi(1, ceili(text_h) + pad_top + pad_bottom)
		_vp.size = Vector2i(w, h)
		_label.position = Vector2(pad_left, pad_top)
		custom_minimum_size = Vector2(w, h)
		_display.position = Vector2.ZERO
		_display.size = Vector2(w, h)
		_display.scale = Vector2.ONE

	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	await get_tree().process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
