class_name TrackDecor
extends RefCounted

## Éléments de décor procéduraux (vue du dessus) pour les pistes.
## Champ JSON: "decorations" → [{ type, position:[x,y], seed, rotation, scale }].

const TYPE_TREE := "tree"
const TYPE_ROCK := "rock"
const DEFAULT_TYPE := TYPE_TREE
## Brush d'éditeur (pas un type sérialisé).
const TOOL_SELECT := "select"

const SELECT_ICON := preload("res://ui/kit/icons/selection.png")

const _TYPE_ORDER: Array[String] = [TYPE_TREE, TYPE_ROCK]

## Rayon de hit-test approximatif (échelle locale, avant marge).
const HIT_PAD := 1.15
const MIN_SCALE := 0.25
const MAX_SCALE := 3.0
const DEFAULT_SCALE := 1.0
## Décalage local de la poignée de rotation au-delà du demi-cadre.
const ROTATE_HANDLE_GAP := 14.0


static func type_ids() -> Array[String]:
	return _TYPE_ORDER.duplicate()


static func normalize(type_id: String) -> String:
	var id := type_id.strip_edges().to_lower()
	if id in _TYPE_ORDER:
		return id
	return DEFAULT_TYPE


static func normalize_brush(brush_id: String) -> String:
	var id := brush_id.strip_edges().to_lower()
	if id == TOOL_SELECT or id in _TYPE_ORDER:
		return id
	return TOOL_SELECT


static func is_place_brush(brush_id: String) -> bool:
	return normalize_brush(brush_id) != TOOL_SELECT


static func from_document(data: Dictionary) -> Array:
	var out: Array = []
	var raw: Variant = data.get("decorations", [])
	if not raw is Array:
		return out
	for item in raw:
		var parsed := parse_item(item)
		if not parsed.is_empty():
			out.append(parsed)
	return out


static func to_document(items: Array) -> Array:
	var out: Array = []
	for item in items:
		var parsed := parse_item(item)
		if parsed.is_empty():
			continue
		var pos: Vector2 = parsed.position
		out.append({
			"type": parsed.type,
			"position": [pos.x, pos.y],
			"seed": int(parsed.seed),
			"rotation": float(parsed.rotation),
			"scale": float(parsed.scale),
		})
	return out


static func parse_item(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var entry: Dictionary = raw
	var type_id := normalize(str(entry.get("type", DEFAULT_TYPE)))
	var pos := Vector2.ZERO
	var pos_v: Variant = entry.get("position", [0.0, 0.0])
	if pos_v is Array and pos_v.size() >= 2:
		pos = Vector2(float(pos_v[0]), float(pos_v[1]))
	elif pos_v is Vector2:
		pos = pos_v
	else:
		return {}
	return {
		"type": type_id,
		"position": pos,
		"seed": int(entry.get("seed", 0)),
		"rotation": float(entry.get("rotation", 0.0)),
		"scale": clamp_scale(float(entry.get("scale", DEFAULT_SCALE))),
	}


static func make_item(type_id: String, position: Vector2, seed: int = -1) -> Dictionary:
	var s := seed if seed >= 0 else int(randi())
	return {
		"type": normalize(type_id),
		"position": position,
		"seed": s,
		"rotation": 0.0,
		"scale": DEFAULT_SCALE,
	}


static func clamp_scale(value: float) -> float:
	return clampf(value, MIN_SCALE, MAX_SCALE)


static func item_xform(item: Dictionary) -> Transform2D:
	var parsed := parse_item(item)
	if parsed.is_empty():
		return Transform2D.IDENTITY
	var scl := float(parsed.scale)
	return Transform2D(float(parsed.rotation), Vector2(scl, scl), 0.0, parsed.position)


static func selection_half(item: Dictionary) -> float:
	var parsed := parse_item(item)
	if parsed.is_empty():
		return 0.0
	return float(params_for(parsed).hit_radius) * HIT_PAD


static func selection_corners(item: Dictionary) -> PackedVector2Array:
	var half := selection_half(item)
	var local := PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	var xf := item_xform(item)
	var out := PackedVector2Array()
	for p in local:
		out.append(xf * p)
	return out


static func rotate_handle_world(item: Dictionary) -> Vector2:
	var half := selection_half(item)
	return item_xform(item) * Vector2(0.0, -half - ROTATE_HANDLE_GAP)


static func hit_index(items: Array, world: Vector2) -> int:
	## Dernier élément touché (dessus de pile).
	for i in range(items.size() - 1, -1, -1):
		var item := parse_item(items[i])
		if item.is_empty():
			continue
		var params := params_for(item)
		var radius: float = float(params.hit_radius) * HIT_PAD
		var local := item_xform(item).affine_inverse() * world
		if local.length_squared() <= radius * radius:
			return i
	return -1


static func draw(canvas: CanvasItem, items: Array, xform: Transform2D = Transform2D.IDENTITY) -> void:
	if canvas == null:
		return
	for raw in items:
		var item := parse_item(raw)
		if item.is_empty():
			continue
		draw_item(canvas, item, xform)


static func draw_item(
	canvas: CanvasItem,
	item: Dictionary,
	xform: Transform2D = Transform2D.IDENTITY,
	alpha: float = 1.0,
) -> void:
	var parsed := parse_item(item)
	if parsed.is_empty() or canvas == null:
		return
	var full := xform * item_xform(parsed)
	var a := clampf(alpha, 0.0, 1.0)
	match str(parsed.type):
		TYPE_ROCK:
			_draw_rock(canvas, params_for(parsed), full, a)
		_:
			_draw_tree(canvas, params_for(parsed), full, a)


static func preview_texture(type_id: String, px: int = 48, seed: int = 1) -> Texture2D:
	## Miniature synchrone pour la palette (pas de SubViewport).
	if normalize_brush(type_id) == TOOL_SELECT:
		return SELECT_ICON
	var size := maxi(px, 16)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var item := make_item(type_id, Vector2(size * 0.5, size * 0.5), seed)
	var params := params_for(item)
	var fit := float(size) * 0.38 / maxf(float(params.hit_radius), 1.0)
	match normalize(type_id):
		TYPE_ROCK:
			_stamp_rock(img, item.position, params, fit)
		_:
			_stamp_tree(img, item.position, params, fit)
	return ImageTexture.create_from_image(img)


## Paramètres procéduraux dérivés du seed — partagés hit-test / dessin / preview.
static func params_for(item: Dictionary) -> Dictionary:
	var parsed := parse_item(item)
	var rng := RandomNumberGenerator.new()
	var seed_v := int(parsed.seed) if not parsed.is_empty() else 0
	rng.seed = seed_v if seed_v != 0 else 1
	match normalize(str(parsed.get("type", DEFAULT_TYPE))):
		TYPE_ROCK:
			return _params_rock(rng)
		_:
			return _params_tree(rng)


static func _params_tree(rng: RandomNumberGenerator) -> Dictionary:
	var canopy_r := rng.randf_range(14.0, 22.0)
	var blob_count := rng.randi_range(4, 6)
	var blobs: Array = []
	for _i in blob_count:
		blobs.append({
			"ang": rng.randf() * TAU,
			"dist": rng.randf_range(0.0, canopy_r * 0.45),
			"radius": canopy_r * rng.randf_range(0.42, 0.72),
			"light": rng.randf_range(-0.08, 0.18),
			"dark": rng.randf_range(0.0, 0.22),
		})
	return {
		"hit_radius": canopy_r,
		"canopy_r": canopy_r,
		"blobs": blobs,
		"trunk_tint": rng.randf_range(-0.05, 0.08),
		"hi_ang": rng.randf() * TAU,
	}


static func _params_rock(rng: RandomNumberGenerator) -> Dictionary:
	var radius := rng.randf_range(11.0, 18.0)
	var n := rng.randi_range(5, 8)
	var rot := rng.randf() * TAU
	var radii: Array = []
	for _i in n:
		radii.append(radius * rng.randf_range(0.62, 1.08))
	return {
		"hit_radius": radius,
		"radius": radius,
		"n": n,
		"rot": rot,
		"radii": radii,
		"base_dark": rng.randf_range(0.05, 0.25),
		"face_light": rng.randf_range(0.04, 0.14),
		"facet_start": rng.randi_range(0, maxi(n - 1, 0)),
	}


static func _rock_verts_from_params(center: Vector2, params: Dictionary) -> PackedVector2Array:
	var n := int(params.n)
	var rot := float(params.rot)
	var radii: Array = params.radii
	var pts := PackedVector2Array()
	for i in n:
		var ang := rot + TAU * float(i) / float(n)
		var r := float(radii[i]) if i < radii.size() else float(params.radius)
		pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	return pts


static func _draw_tree(canvas: CanvasItem, params: Dictionary, xform: Transform2D, alpha: float = 1.0) -> void:
	var canopy_r: float = float(params.canopy_r)
	var base_green := Palette.team(3)
	var shadow := base_green.darkened(0.45)
	shadow.a = 0.55 * alpha
	var s := _sx(xform)
	canvas.draw_circle(xform * Vector2(1.2, 1.6), canopy_r * 0.92 * s, shadow, true, -1.0, true)
	var blobs: Array = params.blobs
	for i in blobs.size():
		var b: Dictionary = blobs[i]
		var br: float = float(b.radius)
		var tint := base_green.lightened(float(b.light)).darkened(float(b.dark))
		if i == 0:
			tint = base_green.darkened(0.12)
		tint.a *= alpha
		var p := Vector2(cos(float(b.ang)), sin(float(b.ang))) * float(b.dist)
		canvas.draw_circle(xform * p, br * s, tint, true, -1.0, true)
	var trunk := Color(0.28, 0.20, 0.14, 1.0).lightened(float(params.trunk_tint))
	trunk.a *= alpha
	canvas.draw_circle(xform * Vector2.ZERO, canopy_r * 0.16 * s, trunk, true, -1.0, true)
	var hi := Vector2(cos(float(params.hi_ang)), sin(float(params.hi_ang))) * canopy_r * 0.28
	var hi_col := base_green.lightened(0.28)
	hi_col.a = 0.55 * alpha
	canvas.draw_circle(xform * hi, canopy_r * 0.22 * s, hi_col, true, -1.0, true)


static func _draw_rock(canvas: CanvasItem, params: Dictionary, xform: Transform2D, alpha: float = 1.0) -> void:
	var verts := _rock_verts_from_params(Vector2.ZERO, params)
	var screen := PackedVector2Array()
	for v in verts:
		screen.append(xform * v)
	var base := Palette.SMOKE.darkened(float(params.base_dark))
	base.a *= alpha
	var edge := base.darkened(0.28)
	edge.a *= alpha
	canvas.draw_colored_polygon(screen, base)
	var inset := PackedVector2Array()
	for v2 in verts:
		inset.append(xform * (v2 * 0.78))
	var face := base.lightened(float(params.face_light))
	face.a *= alpha
	canvas.draw_colored_polygon(inset, face)
	var facet_n := mini(3, verts.size())
	var start := int(params.facet_start) % verts.size()
	var facet := PackedVector2Array()
	facet.append(xform * (verts[start] * 0.15))
	for k in facet_n:
		facet.append(xform * verts[(start + k) % verts.size()])
	var highlight := Palette.CARDBOARD_DARK.darkened(0.15)
	highlight.a = 0.55 * alpha
	if facet.size() >= 3:
		canvas.draw_colored_polygon(facet, highlight)
	if screen.size() >= 2:
		var loop := PackedVector2Array(screen)
		loop.append(screen[0])
		canvas.draw_polyline(loop, edge, maxf(1.0, 1.4 * _sx(xform)), true)


static func _sx(xform: Transform2D) -> float:
	return absf(xform.get_scale().x)


static func _stamp_tree(img: Image, center: Vector2, params: Dictionary, fit: float) -> void:
	var canopy_r: float = float(params.canopy_r) * fit
	var base_green := Palette.team(3)
	_fill_circle(img, center + Vector2(1.0, 1.2) * fit, canopy_r * 0.92, Color(base_green.darkened(0.45), 0.5))
	var blobs: Array = params.blobs
	for i in blobs.size():
		var b: Dictionary = blobs[i]
		var br: float = float(b.radius) * fit
		var tint := base_green.lightened(float(b.light)).darkened(float(b.dark))
		if i == 0:
			tint = base_green.darkened(0.12)
		var p := center + Vector2(cos(float(b.ang)), sin(float(b.ang))) * float(b.dist) * fit
		_fill_circle(img, p, br, tint)
	_fill_circle(img, center, canopy_r * 0.16, Color(0.28, 0.20, 0.14, 1.0))


static func _stamp_rock(img: Image, center: Vector2, params: Dictionary, fit: float) -> void:
	var scaled := params.duplicate(true)
	scaled.radius = float(params.radius) * fit
	var radii: Array = []
	for r in params.radii:
		radii.append(float(r) * fit)
	scaled.radii = radii
	var verts := _rock_verts_from_params(center, scaled)
	var base := Palette.SMOKE.darkened(float(params.base_dark))
	_fill_polygon(img, verts, base)
	var inset := PackedVector2Array()
	for v in verts:
		inset.append(center.lerp(v, 0.78))
	_fill_polygon(img, inset, base.lightened(float(params.face_light)))


static func _fill_circle(img: Image, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.5:
		return
	var r2 := r * r
	var min_x := maxi(0, int(floor(c.x - r)))
	var max_x := mini(img.get_width() - 1, int(ceil(c.x + r)))
	var min_y := maxi(0, int(floor(c.y - r)))
	var max_y := mini(img.get_height() - 1, int(ceil(c.y + r)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5) - c
			if d.length_squared() <= r2:
				img.set_pixel(x, y, col)


static func _fill_polygon(img: Image, verts: PackedVector2Array, col: Color) -> void:
	if verts.size() < 3:
		return
	var min_v := verts[0]
	var max_v := verts[0]
	for v in verts:
		min_v = min_v.min(v)
		max_v = max_v.max(v)
	var min_x := maxi(0, int(floor(min_v.x)))
	var max_x := mini(img.get_width() - 1, int(ceil(max_v.x)))
	var min_y := maxi(0, int(floor(min_v.y)))
	var max_y := mini(img.get_height() - 1, int(ceil(max_v.y)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if Geometry2D.is_point_in_polygon(Vector2(float(x) + 0.5, float(y) + 0.5), verts):
				img.set_pixel(x, y, col)
