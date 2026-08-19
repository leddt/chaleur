class_name CardSymbolVisual
extends RefCounted

## Icon paths and tint colors for card symbols. Adjust SYMBOL_LIGHT / SLIPSTREAM_GREEN / tint() here.
## Textures are rasterized from SVG at the display size so edges stay anti-aliased.

const SLIPSTREAM_GREEN := Color(0.263, 0.435, 0.294)
## Icônes « blanc » sur carton — ajuster ici (Palette.INK si trop pâle).
const SYMBOL_LIGHT := Palette.INK
const SVG_NATIVE := 256.0
## Extra pixels for viewport stretch / HiDPI. 2× then LINEAR looks cleaner than 1×.
const RASTER_PAD := 2.0

const CHECK_PATH := "res://ui/kit/icons/ph-check-fat-fill.svg"
const CHECK_GREEN := Color(0.22, 0.64, 0.34)

const PATHS := {
	CardSymbol.Kind.HEAT: "res://ui/kit/icons/ph-fire-duotone.svg",
	CardSymbol.Kind.SCRAP: "res://ui/kit/icons/ph-trash-simple-duotone.svg",
	CardSymbol.Kind.ADJUST_SPEED_LIMIT: "res://ui/kit/icons/ph-speedometer-duotone.svg",
	CardSymbol.Kind.COOLDOWN: "res://ui/kit/icons/ph-thermometer-simple-duotone.svg",
	CardSymbol.Kind.SLIPSTREAM_BOOST: "res://ui/kit/icons/ph-wind-duotone.svg",
	CardSymbol.Kind.REDUCE_STRESS: "res://ui/kit/icons/ph-caret-double-down-duotone.svg",
	CardSymbol.Kind.REFRESH: "res://ui/kit/icons/ph-arrow-clockwise-duotone.svg",
	CardSymbol.Kind.SALVAGE: "res://ui/kit/icons/ph-wrench-duotone.svg",
	CardSymbol.Kind.DIRECT_PLAY: "res://ui/kit/icons/ph-hand-deposit-duotone.svg",
	CardSymbol.Kind.ACCELERATE: "res://ui/kit/icons/ph-caret-circle-double-up-duotone.svg",
	CardSymbol.Kind.PLUS: "res://ui/kit/icons/ph-plus-square-duotone.svg",
}

static var _svg_text: Dictionary = {}
static var _tex_cache: Dictionary = {}

## `load()` so the exporter packs the imported textures. FileAccess on the .svg
## source works in the editor; exported builds only have the .ctex.
const _PACKED: Array[Texture2D] = [
	preload("res://ui/kit/icons/ph-check-fat-fill.svg"),
	preload("res://ui/kit/icons/ph-fire-duotone.svg"),
	preload("res://ui/kit/icons/ph-trash-simple-duotone.svg"),
	preload("res://ui/kit/icons/ph-speedometer-duotone.svg"),
	preload("res://ui/kit/icons/ph-thermometer-simple-duotone.svg"),
	preload("res://ui/kit/icons/ph-wind-duotone.svg"),
	preload("res://ui/kit/icons/ph-caret-double-down-duotone.svg"),
	preload("res://ui/kit/icons/ph-arrow-clockwise-duotone.svg"),
	preload("res://ui/kit/icons/ph-wrench-duotone.svg"),
	preload("res://ui/kit/icons/ph-hand-deposit-duotone.svg"),
	preload("res://ui/kit/icons/ph-caret-circle-double-up-duotone.svg"),
	preload("res://ui/kit/icons/ph-plus-square-duotone.svg"),
]


static func texture(kind: CardSymbol.Kind, display_px: float = 24.0) -> Texture2D:
	var path: String = PATHS.get(kind, PATHS[CardSymbol.Kind.HEAT])
	return _texture_at(path, display_px)


static func check_texture(display_px: float = 24.0) -> Texture2D:
	return _texture_at(CHECK_PATH, display_px)


static func _texture_at(path: String, display_px: float) -> Texture2D:
	var px := maxi(16, int(round(display_px * RASTER_PAD)))
	var key := "%s_%d" % [path, px]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex := _rasterize_path(path, px)
	_tex_cache[key] = tex
	return tex


static func _rasterize_path(path: String, px: int) -> Texture2D:
	if not _svg_text.has(path):
		_svg_text[path] = FileAccess.get_file_as_string(path)
	var svg: String = str(_svg_text[path])
	if not svg.is_empty():
		var img := Image.new()
		var err := img.load_svg_from_string(svg, float(px) / SVG_NATIVE)
		if err == OK and not img.is_empty():
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	var imported := load(path) as Texture2D
	if imported != null:
		return imported
	push_warning("CardSymbolVisual: SVG raster failed for %s" % path)
	return PlaceholderTexture2D.new()


static func tint(kind: CardSymbol.Kind) -> Color:
	match kind:
		CardSymbol.Kind.HEAT:
			return Palette.RACE_RED
		CardSymbol.Kind.SCRAP:
			return Palette.SMOKE
		CardSymbol.Kind.ADJUST_SPEED_LIMIT:
			return SYMBOL_LIGHT
		CardSymbol.Kind.COOLDOWN:
			return Palette.FUEL_BLUE
		CardSymbol.Kind.SLIPSTREAM_BOOST:
			return SLIPSTREAM_GREEN
		CardSymbol.Kind.REDUCE_STRESS:
			return Palette.MUSTARD
		CardSymbol.Kind.REFRESH, CardSymbol.Kind.SALVAGE, CardSymbol.Kind.DIRECT_PLAY:
			return SYMBOL_LIGHT
		CardSymbol.Kind.ACCELERATE, CardSymbol.Kind.PLUS:
			return SYMBOL_LIGHT
		_:
			return SYMBOL_LIGHT
