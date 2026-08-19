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


static func texture(kind: CardSymbol.Kind, display_px: float = 24.0) -> Texture2D:
	var px := maxi(16, int(round(display_px * RASTER_PAD)))
	var key := "%d_%d" % [int(kind), px]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex := _rasterize(kind, px)
	_tex_cache[key] = tex
	return tex


static func _rasterize(kind: CardSymbol.Kind, px: int) -> Texture2D:
	var path: String = PATHS.get(kind, PATHS[CardSymbol.Kind.HEAT])
	if not _svg_text.has(path):
		_svg_text[path] = FileAccess.get_file_as_string(path)
	var svg: String = _svg_text[path]
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(px) / SVG_NATIVE)
	if err != OK or img.is_empty():
		push_warning("CardSymbolVisual: SVG raster failed for %s (%s)" % [path, error_string(err)])
		return PlaceholderTexture2D.new()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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
