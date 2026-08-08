class_name TrackGround
extends RefCounted

## Presets de fond de plateau pour les pistes.
## Champ JSON: "ground_theme".

const THEME_GRASS := "grass"
const THEME_DIRT := "dirt"
const THEME_SAND := "sand"
const THEME_SNOW := "snow"
const THEME_ROCK := "rock"
const DEFAULT_THEME := THEME_GRASS

const SHADER := preload("res://shaders/track_ground.gdshader")

const _THEME_ORDER: Array[String] = [
	THEME_GRASS, THEME_DIRT, THEME_SAND, THEME_SNOW, THEME_ROCK,
]


static func theme_ids() -> Array[String]:
	return _THEME_ORDER.duplicate()


static func normalize(theme_id: String) -> String:
	var id := theme_id.strip_edges().to_lower()
	if id in _THEME_ORDER:
		return id
	return DEFAULT_THEME


static func from_document(data: Dictionary) -> String:
	return normalize(str(data.get("ground_theme", DEFAULT_THEME)))


static func display_name(theme_id: String) -> String:
	match normalize(theme_id):
		THEME_DIRT:
			return "Terre"
		THEME_SAND:
			return "Sable"
		THEME_SNOW:
			return "Neige"
		THEME_ROCK:
			return "Roche"
		_:
			return "Gazon"


static func make_material(theme_id: String = DEFAULT_THEME) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	apply(mat, theme_id)
	return mat


static func apply(material: ShaderMaterial, theme_id: String) -> void:
	if material == null:
		return
	if material.shader == null:
		material.shader = SHADER
	var p := _preset(normalize(theme_id))
	material.set_shader_parameter("base_color", p.base)
	material.set_shader_parameter("accent_color", p.accent)
	material.set_shader_parameter("vein_color", p.vein)
	material.set_shader_parameter("pattern_scale", p.scale)
	material.set_shader_parameter("contrast", p.contrast)
	material.set_shader_parameter("vein_strength", p.vein_strength)
	material.set_shader_parameter("grit_amount", p.grit)


static func attach(parent: Control, theme_id: String = DEFAULT_THEME) -> ColorRect:
	## Crée ou réutilise un ColorRect plein panneau sous le tracé.
	if parent == null:
		return null
	var rect := parent.get_node_or_null("TrackGround") as ColorRect
	if rect == null:
		rect = ColorRect.new()
		rect.name = "TrackGround"
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.show_behind_parent = true
		rect.color = Color.WHITE
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.material = make_material(theme_id)
		parent.add_child(rect)
		parent.move_child(rect, 0)
	else:
		rect.show_behind_parent = true
		var mat := rect.material as ShaderMaterial
		if mat == null:
			mat = make_material(theme_id)
			rect.material = mat
		else:
			apply(mat, theme_id)
	return rect


static func _preset(theme_id: String) -> Dictionary:
	match theme_id:
		THEME_DIRT:
			return {
				"base": Color(0.34, 0.26, 0.20),
				"accent": Color(0.46, 0.36, 0.27),
				"vein": Color(0.22, 0.16, 0.12),
				"scale": 16.0,
				"contrast": 0.58,
				"vein_strength": 0.45,
				"grit": 0.35,
			}
		THEME_SAND:
			return {
				"base": Color(0.78, 0.70, 0.52),
				"accent": Color(0.88, 0.81, 0.62),
				"vein": Color(0.62, 0.52, 0.36),
				"scale": 12.0,
				"contrast": 0.42,
				"vein_strength": 0.28,
				"grit": 0.55,
			}
		THEME_SNOW:
			return {
				"base": Color(0.86, 0.89, 0.92),
				"accent": Color(0.96, 0.97, 0.98),
				"vein": Color(0.68, 0.74, 0.80),
				"scale": 11.0,
				"contrast": 0.35,
				"vein_strength": 0.22,
				"grit": 0.12,
			}
		THEME_ROCK:
			return {
				"base": Color(0.38, 0.38, 0.40),
				"accent": Color(0.52, 0.51, 0.50),
				"vein": Color(0.24, 0.23, 0.22),
				"scale": 18.0,
				"contrast": 0.68,
				"vein_strength": 0.55,
				"grit": 0.48,
			}
		_:
			# Vert anglais dérivé de Palette.team(3), assombri pour lire l'asphalte.
			return {
				"base": Color(0.16, 0.28, 0.20),
				"accent": Color(0.28, 0.42, 0.30),
				"vein": Color(0.10, 0.18, 0.13),
				"scale": 14.0,
				"contrast": 0.55,
				"vein_strength": 0.38,
				"grit": 0.18,
			}
