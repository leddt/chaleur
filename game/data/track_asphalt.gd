class_name TrackAsphalt
extends RefCounted

## Couleurs d'asphalte d'une piste.
## Document JSON sous `colors.asphalt`:
##   { base, grain_dark, grain_light, grain_locked }

const DEFAULT_BASE := Color(0.28, 0.29, 0.31, 1.0)
const DEFAULT_DARK := Color(0.24, 0.25, 0.26, 1.0)
const DEFAULT_LIGHT := Color(0.31, 0.32, 0.34, 1.0)
const DEFAULT_LOCKED := true

const DARKEN_AMOUNT := 0.14
const LIGHTEN_AMOUNT := 0.055
const EDGE_DARKEN := 0.35


static func derive_dark(base: Color) -> Color:
	var c := base.darkened(DARKEN_AMOUNT)
	c.a = 1.0
	return c


static func derive_light(base: Color) -> Color:
	var c := base.lightened(LIGHTEN_AMOUNT)
	c.a = 1.0
	return c


static func derive_edge(base: Color) -> Color:
	var c := base.darkened(EDGE_DARKEN)
	c.a = 1.0
	return c


static func colors_dict(data: Dictionary) -> Dictionary:
	var raw: Variant = data.get("colors", {})
	return raw if raw is Dictionary else {}


static func from_document(data: Dictionary) -> Dictionary:
	var colors := colors_dict(data)
	var asphalt_raw: Variant = colors.get("asphalt", {})
	var asphalt: Dictionary = asphalt_raw if asphalt_raw is Dictionary else {}
	# Legacy flat keys (pré-"colors") si présents.
	if asphalt.is_empty() and data.has("asphalt_color"):
		asphalt = {
			"base": data.get("asphalt_color"),
			"grain_dark": data.get("asphalt_grain_dark"),
			"grain_light": data.get("asphalt_grain_light"),
			"grain_locked": data.get("asphalt_grain_locked", DEFAULT_LOCKED),
		}
	var base := color_from_variant(asphalt.get("base", DEFAULT_BASE), DEFAULT_BASE)
	var locked := bool(asphalt.get("grain_locked", DEFAULT_LOCKED))
	var dark := color_from_variant(asphalt.get("grain_dark", DEFAULT_DARK), DEFAULT_DARK)
	var light := color_from_variant(asphalt.get("grain_light", DEFAULT_LIGHT), DEFAULT_LIGHT)
	if locked:
		dark = derive_dark(base)
		light = derive_light(base)
	return {
		"base": base,
		"dark": dark,
		"light": light,
		"locked": locked,
	}


static func to_colors_document(settings: Dictionary) -> Dictionary:
	## Bloc `colors` à fusionner dans le document piste.
	var base: Color = settings.get("base", DEFAULT_BASE)
	var locked := bool(settings.get("locked", DEFAULT_LOCKED))
	var dark: Color = settings.get("dark", DEFAULT_DARK)
	var light: Color = settings.get("light", DEFAULT_LIGHT)
	if locked:
		dark = derive_dark(base)
		light = derive_light(base)
	return {
		"asphalt": {
			"base": color_to_array(base),
			"grain_dark": color_to_array(dark),
			"grain_light": color_to_array(light),
			"grain_locked": locked,
		},
	}


static func color_to_array(c: Color) -> Array:
	return [snappedf(c.r, 0.0001), snappedf(c.g, 0.0001), snappedf(c.b, 0.0001)]


static func color_from_variant(value: Variant, fallback: Color) -> Color:
	if value is Color:
		var c := value as Color
		c.a = 1.0
		return c
	if value is Array and value.size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]), 1.0)
	if value is PackedFloat32Array and value.size() >= 3:
		return Color(value[0], value[1], value[2], 1.0)
	if value is String:
		var parsed := Color(str(value))
		parsed.a = 1.0
		return parsed
	return fallback
