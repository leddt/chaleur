class_name TrackDecor
extends RefCounted

## Éléments de décor procéduraux (vue du dessus) pour les pistes.
## Champ JSON: "decorations" → [{ type, position:[x,y], seed, rotation, scale[, size] }].
## Les gradins (`bleachers`) utilisent `size:[w,d]` (pas de scale uniforme).

const TYPE_TREE := "tree"
const TYPE_ROCK := "rock"
const TYPE_BLEACHERS := "bleachers"
const DEFAULT_TYPE := TYPE_TREE
## Brush d'éditeur (pas un type sérialisé).
const TOOL_SELECT := "select"

const SELECT_ICON := preload("res://ui/kit/icons/selection.png")
const CROWD_SHADER := preload("res://shaders/crowd_dots.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage_dots.gdshader")
const DISC_SHADER := preload("res://shaders/dot_disc.gdshader")
const CROWD_NODE := "_CrowdDots"
const FOLIAGE_NODE := "_FoliageDots"
const TRUNK_NODE := "_TrunkDots"
## Au-dessus des meshes de décor (4–6) pour cadres et poignées de sélection.
const DECOR_SELECTION_Z := 7

const _TYPE_ORDER: Array[String] = [TYPE_TREE, TYPE_ROCK, TYPE_BLEACHERS]

## Rayon de hit-test approximatif (échelle locale, avant marge).
const HIT_PAD := 1.15
const MIN_SCALE := 0.25
const MAX_SCALE := 3.0
const DEFAULT_SCALE := 1.0
## Décalage local de la poignée de rotation au-delà du demi-cadre.
const ROTATE_HANDLE_GAP := 14.0

## Gradins: profondeur fixe par étage (unités monde locales).
const BLEACHER_TIER_DEPTH := 7.0
const BLEACHER_MIN_WIDTH := 28.0
const BLEACHER_MAX_WIDTH := 480.0
const BLEACHER_MIN_TIERS := 1
const BLEACHER_MAX_TIERS := 14
const BLEACHER_DEFAULT_SIZE := Vector2(84.0, 21.0)


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
		var entry := {
			"type": parsed.type,
			"position": [pos.x, pos.y],
			"seed": int(parsed.seed),
			"rotation": float(parsed.rotation),
			"scale": float(parsed.scale),
		}
		if uses_free_size(str(parsed.type)):
			var sz: Vector2 = parsed.size
			entry["size"] = [sz.x, sz.y]
		out.append(entry)
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
	var parsed := {
		"type": type_id,
		"position": pos,
		"seed": int(entry.get("seed", 0)),
		"rotation": float(entry.get("rotation", 0.0)),
		"scale": clamp_scale(float(entry.get("scale", DEFAULT_SCALE))),
		"size": BLEACHER_DEFAULT_SIZE,
	}
	if uses_free_size(type_id):
		parsed.size = clamp_bleacher_size(_parse_size(entry.get("size", BLEACHER_DEFAULT_SIZE)))
		parsed.scale = DEFAULT_SCALE
	return parsed


static func _parse_size(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw
	if raw is Array and raw.size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return BLEACHER_DEFAULT_SIZE


static func make_item(type_id: String, position: Vector2, item_seed: int = -1) -> Dictionary:
	var s := item_seed if item_seed >= 0 else int(randi())
	var id := normalize(type_id)
	var item := {
		"type": id,
		"position": position,
		"seed": s,
		"rotation": 0.0,
		"scale": DEFAULT_SCALE,
		"size": BLEACHER_DEFAULT_SIZE,
	}
	if uses_free_size(id):
		item.size = BLEACHER_DEFAULT_SIZE
	return item


static func uses_free_size(type_id: String) -> bool:
	return normalize(type_id) == TYPE_BLEACHERS


static func clamp_scale(value: float) -> float:
	return clampf(value, MIN_SCALE, MAX_SCALE)


static func clamp_bleacher_size(size: Vector2) -> Vector2:
	var w := clampf(size.x, BLEACHER_MIN_WIDTH, BLEACHER_MAX_WIDTH)
	var tiers := clampi(
		int(round(size.y / BLEACHER_TIER_DEPTH)),
		BLEACHER_MIN_TIERS,
		BLEACHER_MAX_TIERS
	)
	return Vector2(w, float(tiers) * BLEACHER_TIER_DEPTH)


static func bleacher_tier_count(size: Vector2) -> int:
	var clamped := clamp_bleacher_size(size)
	return clampi(int(round(clamped.y / BLEACHER_TIER_DEPTH)), BLEACHER_MIN_TIERS, BLEACHER_MAX_TIERS)


static func item_xform(item: Dictionary) -> Transform2D:
	var parsed := parse_item(item)
	if parsed.is_empty():
		return Transform2D.IDENTITY
	if uses_free_size(str(parsed.type)):
		return Transform2D(float(parsed.rotation), Vector2.ONE, 0.0, parsed.position)
	var scl := float(parsed.scale)
	return Transform2D(float(parsed.rotation), Vector2(scl, scl), 0.0, parsed.position)


static func selection_half(item: Dictionary) -> float:
	## Demi-côté max du cadre (utile pour un rayon approximatif).
	var extents := selection_extents(item)
	return maxf(extents.x, extents.y)


static func selection_extents(item: Dictionary) -> Vector2:
	## Demi-largeur / demi-profondeur du cadre de sélection (espace local item).
	var parsed := parse_item(item)
	if parsed.is_empty():
		return Vector2.ZERO
	if uses_free_size(str(parsed.type)):
		## Cadre exact (= silhouette) pour un resize W×H précis.
		var sz: Vector2 = parsed.size
		return Vector2(sz.x * 0.5, sz.y * 0.5)
	var r := float(params_for(parsed).hit_radius) * HIT_PAD
	return Vector2(r, r)


static func selection_corners(item: Dictionary) -> PackedVector2Array:
	var half := selection_extents(item)
	var local := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	var xf := item_xform(item)
	var out := PackedVector2Array()
	for p in local:
		out.append(xf * p)
	return out


static func selection_edge_mids(item: Dictionary) -> PackedVector2Array:
	## N, E, S, W — milieu des côtés (espace monde).
	var corners := selection_corners(item)
	if corners.size() < 4:
		return PackedVector2Array()
	return PackedVector2Array([
		corners[0].lerp(corners[1], 0.5),
		corners[1].lerp(corners[2], 0.5),
		corners[2].lerp(corners[3], 0.5),
		corners[3].lerp(corners[0], 0.5),
	])


static func rotate_handle_world(item: Dictionary) -> Vector2:
	var half := selection_extents(item)
	return item_xform(item) * Vector2(0.0, -half.y - ROTATE_HANDLE_GAP)


static func hit_index(items: Array, world: Vector2) -> int:
	## Dernier élément touché (dessus de pile).
	for i in range(items.size() - 1, -1, -1):
		var item := parse_item(items[i])
		if item.is_empty():
			continue
		var local := item_xform(item).affine_inverse() * world
		if uses_free_size(str(item.type)):
			var half := selection_extents(item)
			## Légère marge de pick autour du rectangle.
			if absf(local.x) <= half.x * HIT_PAD and absf(local.y) <= half.y * HIT_PAD:
				return i
			continue
		var params := params_for(item)
		var radius: float = float(params.hit_radius) * HIT_PAD
		if local.length_squared() <= radius * radius:
			return i
	return -1


static func has_bleachers(items: Array) -> bool:
	for raw in items:
		var item := parse_item(raw)
		if str(item.get("type", "")) == TYPE_BLEACHERS:
			return true
	return false


static func draw(
	canvas: CanvasItem,
	items: Array,
	xform: Transform2D = Transform2D.IDENTITY,
	foliage_a: Color = TrackColors.DEFAULT_VEGETATION_A,
	foliage_b: Color = TrackColors.DEFAULT_VEGETATION_B,
) -> void:
	if canvas == null:
		return
	for raw in items:
		var item := parse_item(raw)
		if item.is_empty():
			continue
		draw_item(canvas, item, xform, 1.0, foliage_a, foliage_b, false, false)
	var host := canvas.get_parent() as Node2D
	if host != null:
		sync_foliage_mesh(host, items, xform, foliage_a, foliage_b)
		sync_trunk_mesh(host, items, xform)
		sync_crowd_mesh(host, items, xform)


static func draw_item(
	canvas: CanvasItem,
	item: Dictionary,
	xform: Transform2D = Transform2D.IDENTITY,
	alpha: float = 1.0,
	foliage_a: Color = TrackColors.DEFAULT_VEGETATION_A,
	foliage_b: Color = TrackColors.DEFAULT_VEGETATION_B,
	include_crowd: bool = true,
	include_foliage: bool = true,
) -> void:
	var parsed := parse_item(item)
	if parsed.is_empty() or canvas == null:
		return
	var full := xform * item_xform(parsed)
	var a := clampf(alpha, 0.0, 1.0)
	match str(parsed.type):
		TYPE_ROCK:
			_draw_rock(canvas, params_for(parsed), full, a)
		TYPE_BLEACHERS:
			_draw_bleachers(canvas, params_for(parsed), full, a, include_crowd)
		_:
			_draw_tree(canvas, params_for(parsed), full, a, foliage_a, foliage_b, include_foliage)


static func preview_texture(type_id: String, px: int = 48, item_seed: int = 1) -> Texture2D:
	## Miniature synchrone pour la palette (pas de SubViewport).
	if normalize_brush(type_id) == TOOL_SELECT:
		return SELECT_ICON
	var size := maxi(px, 16)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var item := make_item(type_id, Vector2(size * 0.5, size * 0.5), item_seed)
	var params := params_for(item)
	match normalize(type_id):
		TYPE_ROCK:
			var fit := float(size) * 0.38 / maxf(float(params.hit_radius), 1.0)
			_stamp_rock(img, item.position, params, fit)
		TYPE_BLEACHERS:
			var half := Vector2(float(item.size.x), float(item.size.y)) * 0.5
			var fit_b := float(size) * 0.78 / maxf(maxf(half.x, half.y) * 2.0, 1.0)
			_stamp_bleachers(img, item.position, params, fit_b)
		_:
			var fit_t := float(size) * 0.38 / maxf(float(params.hit_radius), 1.0)
			_stamp_tree(img, item.position, params, fit_t)
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
		TYPE_BLEACHERS:
			return _params_bleachers(rng, parsed)
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
			"phase": rng.randf() * TAU,
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


static func _params_bleachers(rng: RandomNumberGenerator, item: Dictionary) -> Dictionary:
	var sz: Vector2 = item.size if item.has("size") else BLEACHER_DEFAULT_SIZE
	var tiers := bleacher_tier_count(sz)
	var width := float(sz.x)
	var base_tint := rng.randf_range(-0.04, 0.06)
	## Légères teintes par étage (pas d'alternance fixe).
	var tier_shades: Array = []
	for _t in tiers:
		## Delta subtil autour du béton de base (lighten +, darken -).
		tier_shades.append(rng.randf_range(-0.028, 0.032))
	## Spectateurs régénérés selon seed + dimensions (répartition stable pour une taille donnée).
	var spectators: Array = []
	var slot_w := 3.3
	var cols := maxi(2, int(floor(width / slot_w)))
	for t in tiers:
		for c in cols:
			## ~62% d'occupation : foule plus dense, marches encore lisibles.
			if rng.randf() > 0.62:
				continue
			var u := (float(c) + 0.5) / float(cols)
			var x := (u - 0.5) * width * 0.92 + rng.randf_range(-0.7, 0.7)
			var y_tier := -0.5 * float(tiers) + float(t) + 0.5
			var y := y_tier * BLEACHER_TIER_DEPTH + rng.randf_range(-0.9, 0.9)
			spectators.append({
				"x": x,
				"y": y,
				"r": rng.randf_range(0.85, 1.25),
				"shade": rng.randf_range(0.0, 0.22),
				"phase": rng.randf() * TAU,
				"bob": rng.randf_range(0.45, 1.0),
			})
	return {
		"hit_radius": maxf(width, float(tiers) * BLEACHER_TIER_DEPTH) * 0.5,
		"tiers": tiers,
		"width": width,
		"depth": float(tiers) * BLEACHER_TIER_DEPTH,
		"base_tint": base_tint,
		"tier_shades": tier_shades,
		"spectators": spectators,
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


static func _foliage_mix(foliage_a: Color, foliage_b: Color, light: float, dark: float) -> Color:
	## Interpole entre les deux bornes selon le bias clair/sombre du blob.
	var mix := clampf(0.5 + float(light) * 0.9 - float(dark) * 0.9, 0.0, 1.0)
	return foliage_a.lerp(foliage_b, mix)


static func _draw_tree(
	canvas: CanvasItem,
	params: Dictionary,
	xform: Transform2D,
	alpha: float = 1.0,
	foliage_a: Color = TrackColors.DEFAULT_VEGETATION_A,
	foliage_b: Color = TrackColors.DEFAULT_VEGETATION_B,
	include_foliage: bool = true,
) -> void:
	var canopy_r: float = float(params.canopy_r)
	var shadow := foliage_a.lerp(foliage_b, 0.75).darkened(0.35)
	shadow.a = 0.55 * alpha
	var s := _sx(xform)
	canvas.draw_circle(xform * Vector2(1.2, 1.6), canopy_r * 0.92 * s, shadow, true, -1.0, true)
	if include_foliage:
		var blobs: Array = params.blobs
		for i in blobs.size():
			var b: Dictionary = blobs[i]
			var br: float = float(b.radius)
			var tint := _foliage_mix(foliage_a, foliage_b, float(b.light), float(b.dark))
			if i == 0:
				tint = foliage_a.lerp(foliage_b, 0.55)
			tint.a *= alpha
			var p := Vector2(cos(float(b.ang)), sin(float(b.ang))) * float(b.dist)
			canvas.draw_circle(xform * p, br * s, tint, true, -1.0, true)
		var hi := Vector2(cos(float(params.hi_ang)), sin(float(params.hi_ang))) * canopy_r * 0.28
		var hi_col := foliage_a.lerp(foliage_b, 0.15).lightened(0.12)
		hi_col.a = 0.55 * alpha
		canvas.draw_circle(xform * hi, canopy_r * 0.22 * s, hi_col, true, -1.0, true)
	else:
		return
	var trunk := Color(0.28, 0.20, 0.14, 1.0).lightened(float(params.trunk_tint))
	trunk.a *= alpha
	canvas.draw_circle(xform * Vector2.ZERO, canopy_r * 0.16 * s, trunk, true, -1.0, true)


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


static func _bleacher_tint(base: Color, shade: float) -> Color:
	if shade >= 0.0:
		return base.lightened(shade)
	return base.darkened(-shade)


static func _draw_bleachers(
	canvas: CanvasItem,
	params: Dictionary,
	xform: Transform2D,
	alpha: float = 1.0,
	include_crowd: bool = true,
) -> void:
	var tiers := int(params.tiers)
	var width: float = float(params.width)
	var depth: float = float(params.depth)
	var hx := width * 0.5
	var hy := depth * 0.5
	var concrete := Palette.SMOKE.lightened(0.22 + float(params.base_tint))
	concrete.a *= alpha
	var seam := concrete.darkened(0.22)
	seam.a *= alpha
	var rim := Palette.CARDBOARD_DARK.darkened(0.12)
	rim.a *= alpha
	var tier_shades: Array = params.tier_shades
	## Embase globale.
	var base_pts := PackedVector2Array([
		xform * Vector2(-hx, -hy),
		xform * Vector2(hx, -hy),
		xform * Vector2(hx, hy),
		xform * Vector2(-hx, hy),
	])
	canvas.draw_colored_polygon(base_pts, concrete.darkened(0.05))
	## Bandes d'étages (parallèles, profondeur fixe).
	for t in tiers:
		var y0 := -hy + float(t) * BLEACHER_TIER_DEPTH
		var y1 := y0 + BLEACHER_TIER_DEPTH
		var shade := float(tier_shades[t]) if t < tier_shades.size() else 0.0
		var band := _bleacher_tint(concrete, shade)
		band.a *= alpha
		var pts := PackedVector2Array([
			xform * Vector2(-hx + 1.0, y0 + 0.6),
			xform * Vector2(hx - 1.0, y0 + 0.6),
			xform * Vector2(hx - 1.0, y1 - 0.6),
			xform * Vector2(-hx + 1.0, y1 - 0.6),
		])
		canvas.draw_colored_polygon(pts, band)
		## Ligne de marche (arête avant de chaque étage).
		canvas.draw_line(
			xform * Vector2(-hx + 1.0, y1 - 0.6),
			xform * Vector2(hx - 1.0, y1 - 0.6),
			seam,
			maxf(1.0, 1.2 * _sx(xform)),
			true
		)
	## Contour + garde-corps avant (côté +Y).
	var outline := PackedVector2Array(base_pts)
	outline.append(base_pts[0])
	canvas.draw_polyline(outline, rim, maxf(1.2, 1.6 * _sx(xform)), true)
	canvas.draw_line(
		xform * Vector2(-hx, hy),
		xform * Vector2(hx, hy),
		rim.darkened(0.15),
		maxf(1.4, 2.0 * _sx(xform)),
		true
	)
	## Spectateurs CPU (fantôme d'éditeur / repli). La vue piste utilise un MultiMesh GPU.
	if not include_crowd:
		return
	var crowd: Array = params.spectators
	for raw in crowd:
		var s: Dictionary = raw
		var col := Palette.INK.lightened(float(s.shade))
		col.a = 0.82 * alpha
		canvas.draw_circle(
			xform * Vector2(float(s.x), float(s.y)),
			float(s.r) * _sx(xform),
			col,
			true,
			-1.0,
			true
		)


static func _sx(xform: Transform2D) -> float:
	return absf(xform.get_scale().x)


static var _crowd_mesh: ArrayMesh
static var _crowd_mat: ShaderMaterial
static var _crowd_tex: Texture2D


static func _crowd_quad_mesh() -> ArrayMesh:
	if _crowd_mesh != null:
		return _crowd_mesh
	_crowd_mesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0),
		Vector3(-1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0),
		Vector2(0, 1), Vector2(1, 0), Vector2(0, 0),
	])
	_crowd_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _crowd_mesh


static func _crowd_white_tex() -> Texture2D:
	if _crowd_tex != null:
		return _crowd_tex
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_crowd_tex = ImageTexture.create_from_image(img)
	return _crowd_tex


static func sync_crowd_mesh(host: Node2D, items: Array, xform: Transform2D) -> void:
	if host == null:
		return
	var node := host.get_node_or_null(CROWD_NODE) as MultiMeshInstance2D
	if node == null:
		node = MultiMeshInstance2D.new()
		node.name = CROWD_NODE
		node.z_as_relative = true
		node.z_index = 6
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		node.texture = _crowd_white_tex()
		host.add_child(node)
	if _crowd_mat == null:
		_crowd_mat = ShaderMaterial.new()
		_crowd_mat.shader = CROWD_SHADER
	var dots: Array = []
	for raw in items:
		var item := parse_item(raw)
		if str(item.get("type", "")) != TYPE_BLEACHERS:
			continue
		var full := xform * item_xform(item)
		var sx := _sx(full)
		for spec_v in params_for(item).spectators:
			var s: Dictionary = spec_v
			var r_local := maxf(float(s.r), 0.35)
			var bob := float(s.get("bob", 1.0))
			dots.append({
				"pos": full * Vector2(float(s.x), float(s.y)),
				"r": r_local * sx,
				"col": Palette.INK.lightened(float(s.shade)),
				"phase": float(s.get("phase", 0.0)),
				"bob": bob,
				"amp": 0.32 * bob / r_local,
			})
	if dots.is_empty():
		node.visible = false
		if node.multimesh != null:
			node.multimesh.instance_count = 0
		return
	node.visible = true
	var mm := node.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _crowd_quad_mesh()
		node.multimesh = mm
		node.material = _crowd_mat
	mm.instance_count = dots.size()
	for i in dots.size():
		var d: Dictionary = dots[i]
		var r: float = float(d.r)
		var xf := Transform2D(0.0, Vector2(r, r), 0.0, d.pos)
		mm.set_instance_transform_2d(i, xf)
		var col: Color = d.col
		col.a = 0.82
		mm.set_instance_color(i, col)
		mm.set_instance_custom_data(i, Color(float(d.phase), float(d.bob), float(d.amp), 0.0))


static var _foliage_mat: ShaderMaterial
static var _disc_mat: ShaderMaterial


static func sync_foliage_mesh(
	host: Node2D,
	items: Array,
	xform: Transform2D,
	foliage_a: Color,
	foliage_b: Color,
) -> void:
	if _foliage_mat == null:
		_foliage_mat = ShaderMaterial.new()
		_foliage_mat.shader = FOLIAGE_SHADER
	var dots: Array = []
	for raw in items:
		var item := parse_item(raw)
		if str(item.get("type", "")) != TYPE_TREE:
			continue
		var params := params_for(item)
		var full := xform * item_xform(item)
		var sx := _sx(full)
		var canopy_r := float(params.canopy_r)
		var blobs: Array = params.blobs
		for i in blobs.size():
			var b: Dictionary = blobs[i]
			var r_local := maxf(float(b.radius), 0.5)
			var tint := _foliage_mix(foliage_a, foliage_b, float(b.light), float(b.dark))
			if i == 0:
				tint = foliage_a.lerp(foliage_b, 0.55)
			var local := Vector2(cos(float(b.ang)), sin(float(b.ang))) * float(b.dist)
			dots.append({
				"pos": full * local,
				"r": r_local * sx,
				"col": tint,
				"phase": float(b.get("phase", 0.0)),
				"amp": 2.2 / r_local,
			})
		var hi := Vector2(cos(float(params.hi_ang)), sin(float(params.hi_ang))) * canopy_r * 0.28
		var hi_col := foliage_a.lerp(foliage_b, 0.15).lightened(0.12)
		hi_col.a = 0.55
		dots.append({
			"pos": full * hi,
			"r": canopy_r * 0.22 * sx,
			"col": hi_col,
			"phase": float(params.hi_ang),
			"amp": 2.2 / maxf(canopy_r * 0.22, 0.5),
		})
	_apply_dot_multimesh(host, FOLIAGE_NODE, 4, _foliage_mat, dots)


static func sync_trunk_mesh(host: Node2D, items: Array, xform: Transform2D) -> void:
	if _disc_mat == null:
		_disc_mat = ShaderMaterial.new()
		_disc_mat.shader = DISC_SHADER
	var dots: Array = []
	for raw in items:
		var item := parse_item(raw)
		if str(item.get("type", "")) != TYPE_TREE:
			continue
		var params := params_for(item)
		var full := xform * item_xform(item)
		var sx := _sx(full)
		var canopy_r := float(params.canopy_r)
		var trunk := Color(0.28, 0.20, 0.14, 1.0).lightened(float(params.trunk_tint))
		dots.append({
			"pos": full * Vector2.ZERO,
			"r": canopy_r * 0.16 * sx,
			"col": trunk,
			"phase": 0.0,
			"amp": 0.0,
		})
	_apply_dot_multimesh(host, TRUNK_NODE, 5, _disc_mat, dots)


static func _apply_dot_multimesh(
	host: Node2D,
	node_name: String,
	z: int,
	mat: ShaderMaterial,
	dots: Array,
) -> void:
	if host == null:
		return
	var node := host.get_node_or_null(node_name) as MultiMeshInstance2D
	if node == null:
		node = MultiMeshInstance2D.new()
		node.name = node_name
		node.z_as_relative = true
		node.z_index = z
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		node.texture = _crowd_white_tex()
		host.add_child(node)
	if dots.is_empty():
		node.visible = false
		if node.multimesh != null:
			node.multimesh.instance_count = 0
		return
	node.visible = true
	var mm := node.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _crowd_quad_mesh()
		node.multimesh = mm
		node.material = mat
	mm.instance_count = dots.size()
	for i in dots.size():
		var d: Dictionary = dots[i]
		var r: float = float(d.r)
		mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(r, r), 0.0, d.pos))
		var col: Color = d.col
		if col.a >= 0.99:
			col.a = 1.0
		mm.set_instance_color(i, col)
		mm.set_instance_custom_data(i, Color(float(d.get("phase", 0.0)), 0.0, float(d.get("amp", 0.0)), 0.0))


static func _stamp_tree(img: Image, center: Vector2, params: Dictionary, fit: float) -> void:
	var canopy_r: float = float(params.canopy_r) * fit
	var foliage_a := TrackColors.DEFAULT_VEGETATION_A
	var foliage_b := TrackColors.DEFAULT_VEGETATION_B
	_fill_circle(
		img,
		center + Vector2(1.0, 1.2) * fit,
		canopy_r * 0.92,
		Color(foliage_a.lerp(foliage_b, 0.75).darkened(0.35), 0.5)
	)
	var blobs: Array = params.blobs
	for i in blobs.size():
		var b: Dictionary = blobs[i]
		var br: float = float(b.radius) * fit
		var tint := _foliage_mix(foliage_a, foliage_b, float(b.light), float(b.dark))
		if i == 0:
			tint = foliage_a.lerp(foliage_b, 0.55)
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


static func _stamp_bleachers(
	img: Image, center: Vector2, params: Dictionary, fit: float
) -> void:
	var width: float = float(params.width) * fit
	var depth: float = float(params.depth) * fit
	var tiers := int(params.tiers)
	var hx := width * 0.5
	var hy := depth * 0.5
	var concrete := Palette.SMOKE.lightened(0.22 + float(params.base_tint))
	var tier_shades: Array = params.tier_shades
	_fill_polygon(img, PackedVector2Array([
		center + Vector2(-hx, -hy),
		center + Vector2(hx, -hy),
		center + Vector2(hx, hy),
		center + Vector2(-hx, hy),
	]), concrete.darkened(0.05))
	var tier_h := BLEACHER_TIER_DEPTH * fit
	for t in tiers:
		var y0 := -hy + float(t) * tier_h
		var shade := float(tier_shades[t]) if t < tier_shades.size() else 0.0
		var band := _bleacher_tint(concrete, shade)
		_fill_polygon(img, PackedVector2Array([
			center + Vector2(-hx + fit, y0 + 0.4 * fit),
			center + Vector2(hx - fit, y0 + 0.4 * fit),
			center + Vector2(hx - fit, y0 + tier_h - 0.4 * fit),
			center + Vector2(-hx + fit, y0 + tier_h - 0.4 * fit),
		]), band)
	for raw in params.spectators:
		var s: Dictionary = raw
		var pos := center + Vector2(float(s.x), float(s.y)) * fit
		_fill_circle(img, pos, maxf(0.8, float(s.r) * fit), Palette.INK.lightened(float(s.shade)))


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
