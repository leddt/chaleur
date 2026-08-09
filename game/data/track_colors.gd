class_name TrackColors
extends RefCounted

## Bloc document JSON `colors` : asphalt, ligne de course, vibreurs, marquages.

const DEFAULT_RACE_LINE := Color(0.58, 0.59, 0.62, 1.0)
const DEFAULT_KERB_A := Color(0.753, 0.224, 0.169, 1.0) ## Palette.RACE_RED
const DEFAULT_KERB_B := Color(0.863, 0.827, 0.745, 1.0) ## Palette.CARDBOARD
const DEFAULT_CENTERLINE := Color(0.95, 0.95, 0.97, 1.0)
const DEFAULT_START_LINE := Color(0.9, 0.15, 0.12, 1.0)
const DEFAULT_CORNER_LINE := Color(0.2, 0.85, 0.35, 1.0)
const DEFAULT_SPACE_EDGE := Color(0.05, 0.05, 0.06, 0.95)
## Bornes de feuillage (vert anglais Palette.team(3) éclairci / assombri).
const DEFAULT_VEGETATION_A := Color(0.336, 0.492, 0.374, 1.0)
const DEFAULT_VEGETATION_B := Color(0.216, 0.357, 0.241, 1.0)


static func defaults() -> Dictionary:
	return {
		"asphalt": TrackAsphalt.from_document({}),
		"race_line": DEFAULT_RACE_LINE,
		"kerb_a": DEFAULT_KERB_A,
		"kerb_b": DEFAULT_KERB_B,
		"centerline": DEFAULT_CENTERLINE,
		"start_line": DEFAULT_START_LINE,
		"corner_line": DEFAULT_CORNER_LINE,
		"space_edge": DEFAULT_SPACE_EDGE,
		"vegetation_a": DEFAULT_VEGETATION_A,
		"vegetation_b": DEFAULT_VEGETATION_B,
	}


static func from_document(data: Dictionary) -> Dictionary:
	var colors := TrackAsphalt.colors_dict(data)
	var out := defaults()
	out["asphalt"] = TrackAsphalt.from_document(data)
	out["race_line"] = _color(colors, "race_line", DEFAULT_RACE_LINE)
	out["centerline"] = _color(colors, "centerline", DEFAULT_CENTERLINE)
	out["start_line"] = _color(colors, "start_line", DEFAULT_START_LINE)
	out["corner_line"] = _color(colors, "corner_line", DEFAULT_CORNER_LINE)
	out["space_edge"] = _color(colors, "space_edge", DEFAULT_SPACE_EDGE, true)
	var kerbs_raw: Variant = colors.get("kerbs", {})
	if kerbs_raw is Dictionary:
		var kerbs: Dictionary = kerbs_raw
		out["kerb_a"] = TrackAsphalt.color_from_variant(kerbs.get("a", DEFAULT_KERB_A), DEFAULT_KERB_A)
		out["kerb_b"] = TrackAsphalt.color_from_variant(kerbs.get("b", DEFAULT_KERB_B), DEFAULT_KERB_B)
	var veg_raw: Variant = colors.get("vegetation", {})
	if veg_raw is Dictionary:
		var veg: Dictionary = veg_raw
		out["vegetation_a"] = TrackAsphalt.color_from_variant(
			veg.get("a", DEFAULT_VEGETATION_A), DEFAULT_VEGETATION_A
		)
		out["vegetation_b"] = TrackAsphalt.color_from_variant(
			veg.get("b", DEFAULT_VEGETATION_B), DEFAULT_VEGETATION_B
		)
	return out


static func to_colors_document(settings: Dictionary) -> Dictionary:
	var asphalt: Dictionary = settings.get("asphalt", TrackAsphalt.from_document({}))
	var colors := TrackAsphalt.to_colors_document(asphalt)
	colors["race_line"] = TrackAsphalt.color_to_array(settings.get("race_line", DEFAULT_RACE_LINE) as Color)
	colors["centerline"] = TrackAsphalt.color_to_array(settings.get("centerline", DEFAULT_CENTERLINE) as Color)
	colors["start_line"] = TrackAsphalt.color_to_array(settings.get("start_line", DEFAULT_START_LINE) as Color)
	colors["corner_line"] = TrackAsphalt.color_to_array(settings.get("corner_line", DEFAULT_CORNER_LINE) as Color)
	colors["space_edge"] = _color_to_array_alpha(settings.get("space_edge", DEFAULT_SPACE_EDGE) as Color)
	colors["kerbs"] = {
		"a": TrackAsphalt.color_to_array(settings.get("kerb_a", DEFAULT_KERB_A) as Color),
		"b": TrackAsphalt.color_to_array(settings.get("kerb_b", DEFAULT_KERB_B) as Color),
	}
	colors["vegetation"] = {
		"a": TrackAsphalt.color_to_array(settings.get("vegetation_a", DEFAULT_VEGETATION_A) as Color),
		"b": TrackAsphalt.color_to_array(settings.get("vegetation_b", DEFAULT_VEGETATION_B) as Color),
	}
	return colors


static func _color(
	colors: Dictionary,
	key: String,
	fallback: Color,
	keep_alpha: bool = false,
) -> Color:
	var raw: Variant = colors.get(key, null)
	var c := TrackAsphalt.color_from_variant(raw if raw != null else fallback, fallback)
	if keep_alpha:
		if raw is Array and raw.size() >= 4:
			c.a = float(raw[3])
		elif raw is Color:
			c.a = (raw as Color).a
		else:
			c.a = fallback.a
	return c


static func _color_to_array_alpha(c: Color) -> Array:
	return [
		snappedf(c.r, 0.0001),
		snappedf(c.g, 0.0001),
		snappedf(c.b, 0.0001),
		snappedf(c.a, 0.0001),
	]
