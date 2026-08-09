class_name SplineTrackPainter
extends RefCounted

## Single source of truth for drawing a spline track (asphalt → game overlays).
## Extracted from the spline editor look; preview / editor / board share this API.

const HALF_WIDTH := 28.0
const BAKE_INTERVAL := 8.0
const CORNER_BADGE_RADIUS := 11.0
const CORNER_BADGE_GAP := 18.0
const START_GRID_SPACES := 5
const OUTER_SPOT_ALONG_OFFSET := 4.0

const ASPHALT_COLOR := Color(0.28, 0.29, 0.31, 1.0)
const ASPHALT_EDGE_COLOR := Color(0.18, 0.19, 0.21, 1.0)
## World units per grain pixel (shader).
const ASPHALT_GRAIN_WORLD := 1.15
const ASPHALT_GRAIN_DARK := Color(0.24, 0.25, 0.26, 1.0)
const ASPHALT_GRAIN_LIGHT := Color(0.31, 0.32, 0.34, 1.0)
const ASPHALT_SHADER := preload("res://shaders/asphalt_grain.gdshader")
const RACE_LINE_EDGE_COLOR := Color(0.58, 0.59, 0.62, 1.0)
## Red/cream vibeurs along geometric inside/outside edges (per-space).
const KERB_THICKNESS := 5.5
const KERB_STRIPE_LEN := 9.0
const KERB_SLANT := 3.5
const KERB_COLOR_A := Palette.RACE_RED
const KERB_COLOR_B := Palette.CARDBOARD
## Pale race-side edge; must exceed KERB_THICKNESS so a lip stays visible past vibeurs.
const RACE_LINE_OVERHANG := 1.75
const RACE_LINE_EDGE_WIDTH := KERB_THICKNESS + RACE_LINE_OVERHANG
const ASPHALT_OUTER_EDGE_WIDTH := 1.5
const CENTERLINE_COLOR := Color(0.95, 0.95, 0.97, 1.0)
const CENTERLINE_WIDTH := 2.0
const SPACE_EDGE_COLOR := Color(0.05, 0.05, 0.06, 0.95)
const START_LINE_COLOR := Color(0.9, 0.15, 0.12, 1.0)
const CORNER_LINE_COLOR := Color(0.2, 0.85, 0.35, 1.0)
const START_GRID_MARKER_COLOR := Color(0.95, 0.95, 0.98, 0.6)


## Which layers to paint. Asphalt alone is the base in-game road body.
class Options:
	extends RefCounted

	var asphalt: bool = true
	## Pale race-side kerb + thin dark outer kerb (uses seg samples + flips).
	var race_line: bool = false
	var centerline: bool = false
	## Ordinary space separators (excludes start / corner exits when those flags are on).
	var spaces: bool = false
	var start_line: bool = false
	var corner_lines: bool = false
	var speed_limits: bool = false
	var space_numbers: bool = false
	var start_grid: bool = false


## Track data needed beyond the centerline polyline.
class Context:
	extends RefCounted

	var half_width: float = HALF_WIDTH
	var spot_inset: float = 0.45
	var seg: TrackSegmenter.Result
	var start_space: int = 0
	## space_index -> {speed_limit, outside, offset: Vector2}
	var corners: Dictionary = {}
	## space_index -> {inside: bool, outside: bool} (geometric loop sides)
	var kerbs: Dictionary = {}
	## (space: int) -> bool
	var race_line_flipped: Callable = func(_space: int) -> bool: return false
	var font: Font


static func default_options() -> Options:
	return Options.new()


static func game_options() -> Options:
	var o := Options.new()
	o.asphalt = true
	o.race_line = true
	o.centerline = true
	o.spaces = true
	o.start_line = true
	o.corner_lines = true
	o.speed_limits = true
	o.start_grid = true
	return o


## Lighter look for track pickers (no case grid / badges / starting pads).
static func preview_options() -> Options:
	var o := Options.new()
	o.asphalt = true
	o.race_line = true
	o.start_line = true
	o.corner_lines = true
	return o


static func editor_roadmap_options(hide_space_numbers: bool = false) -> Options:
	var o := Options.new()
	o.asphalt = true
	o.race_line = true
	o.centerline = true
	o.spaces = true
	o.start_line = true
	o.corner_lines = true
	o.speed_limits = true
	o.space_numbers = not hide_space_numbers
	o.start_grid = true
	return o


static func bake_spline(spline: TrackSpline, bake_interval: float = BAKE_INTERVAL) -> PackedVector2Array:
	if spline == null or spline.point_count() < TrackSpline.MIN_POINTS:
		return PackedVector2Array()
	return spline.baked_points(bake_interval)


static func unique_loop_points(baked: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if baked.is_empty():
		return pts
	pts.append(baked[0])
	for i in range(1, baked.size()):
		if baked[i].distance_squared_to(pts[pts.size() - 1]) > 0.25:
			pts.append(baked[i])
	if pts.size() >= 2 and pts[0].distance_squared_to(pts[pts.size() - 1]) <= 0.25:
		pts.resize(pts.size() - 1)
	return pts


static func bounds(points: PackedVector2Array, half_width: float = HALF_WIDTH) -> Rect2:
	var pts := unique_loop_points(points)
	if pts.is_empty():
		return Rect2()
	var min_v := pts[0]
	var max_v := pts[0]
	for i in range(1, pts.size()):
		min_v = min_v.min(pts[i])
		max_v = max_v.max(pts[i])
	var rect := Rect2(min_v, max_v - min_v).grow(half_width)
	if rect.size.x < 1.0:
		rect.size.x = 1.0
	if rect.size.y < 1.0:
		rect.size.y = 1.0
	return rect


static func fit_transform(world_rect: Rect2, viewport: Rect2, padding: float = 16.0) -> Transform2D:
	if world_rect.size.x < 0.001 or world_rect.size.y < 0.001:
		return Transform2D.IDENTITY
	var inner := viewport.grow(-padding)
	if inner.size.x < 1.0 or inner.size.y < 1.0:
		inner = viewport
	var scale := minf(inner.size.x / world_rect.size.x, inner.size.y / world_rect.size.y)
	var scaled := world_rect.size * scale
	var origin := inner.position + (inner.size - scaled) * 0.5 - world_rect.position * scale
	var xform := Transform2D.IDENTITY.scaled(Vector2(scale, scale))
	xform.origin = origin
	return xform


## Lightweight Node2D used as an ordered paint layer under a host canvas.
class PaintLayer:
	extends Node2D

	var _paint: Callable = Callable()

	func set_paint(cb: Callable) -> void:
		_paint = cb
		queue_redraw()

	func clear_paint() -> void:
		_paint = Callable()
		queue_redraw()

	func _draw() -> void:
		if _paint.is_valid():
			_paint.call()


static var _asphalt_material: ShaderMaterial


## Pan only — no redraw. Geometry is already zoom-baked; PaintRoot.scale stays 1.
static func set_view_pan(host: CanvasItem, pan: Vector2) -> void:
	var node := host as Node
	if node == null:
		return
	var root := node.get_node_or_null("_PaintRoot") as Node2D
	if root == null:
		return
	root.position = pan
	root.scale = Vector2.ONE


## @deprecated Prefer set_view_pan for pan; zoom requires a full draw().
static func set_view_xform(host: CanvasItem, xform: Transform2D) -> void:
	set_view_pan(host, xform.origin)


static func draw(
	canvas: CanvasItem,
	baked: PackedVector2Array,
	ctx: Context,
	opts: Options = null,
	xform: Transform2D = Transform2D.IDENTITY,
	after_asphalt: Callable = Callable(),
	after_road: Callable = Callable(),
) -> void:
	if canvas == null or ctx == null:
		return
	var options := opts if opts != null else default_options()
	var layers := _ensure_paint_layers(canvas)
	## Bake zoom into geometry for crisp AA; pan via PaintRoot.position only.
	var zoom := maxf(absf(xform.get_scale().x), 0.0001)
	set_view_pan(canvas, xform.origin)
	_sync_asphalt_material(layers.asphalt, zoom)
	var zoom_xform := Transform2D(0.0, Vector2(zoom, zoom), 0.0, Vector2.ZERO)

	var under: PaintLayer = layers.under
	var asphalt: PaintLayer = layers.asphalt
	var over: PaintLayer = layers.over
	var top: PaintLayer = layers.top
	var badges: PaintLayer = layers.badges

	if options.race_line:
		under.set_paint(func() -> void: _draw_race_line_kerbs(under, ctx, zoom_xform))
	else:
		under.clear_paint()

	if options.asphalt:
		asphalt.set_paint(
			func() -> void: _draw_asphalt_band(asphalt, baked, ctx.half_width, zoom_xform)
		)
	else:
		asphalt.clear_paint()

	over.set_paint(
		func() -> void:
			if options.asphalt:
				_draw_striped_kerbs(over, ctx, zoom_xform)
			if after_asphalt.is_valid():
				after_asphalt.call(over)
			if options.centerline:
				_draw_centerline(over, baked, zoom_xform)
			if (
				options.spaces
				or options.start_line
				or options.corner_lines
				or options.space_numbers
				or options.start_grid
			):
				_draw_space_overlays(over, ctx, options, zoom_xform)
	)

	if after_road.is_valid():
		top.set_paint(func() -> void: after_road.call(top))
	else:
		top.clear_paint()

	if options.speed_limits:
		badges.set_paint(
			func() -> void: _draw_speed_limit_badges(badges, ctx, zoom_xform)
		)
	else:
		badges.clear_paint()


static func _asphalt_mat() -> ShaderMaterial:
	if _asphalt_material == null:
		_asphalt_material = ShaderMaterial.new()
		_asphalt_material.shader = ASPHALT_SHADER
		_asphalt_material.set_shader_parameter("base_color", ASPHALT_COLOR)
		_asphalt_material.set_shader_parameter("dark_color", ASPHALT_GRAIN_DARK)
		_asphalt_material.set_shader_parameter("light_color", ASPHALT_GRAIN_LIGHT)
		_asphalt_material.set_shader_parameter("grain_world", ASPHALT_GRAIN_WORLD)
		_asphalt_material.set_shader_parameter("view_zoom", 1.0)
	return _asphalt_material


static func _sync_asphalt_material(asphalt_layer: CanvasItem, view_zoom: float = 1.0) -> void:
	var mat := _asphalt_mat()
	mat.set_shader_parameter("grain_world", ASPHALT_GRAIN_WORLD)
	mat.set_shader_parameter("base_color", ASPHALT_COLOR)
	mat.set_shader_parameter("dark_color", ASPHALT_GRAIN_DARK)
	mat.set_shader_parameter("light_color", ASPHALT_GRAIN_LIGHT)
	mat.set_shader_parameter("view_zoom", maxf(view_zoom, 0.0001))
	asphalt_layer.material = mat


static func _ensure_paint_layers(host: CanvasItem) -> Dictionary:
	var node := host as Node
	assert(node != null, "SplineTrackPainter.draw host must be a Node")
	var root := node.get_node_or_null("_PaintRoot") as Node2D
	if root == null:
		root = Node2D.new()
		root.name = "_PaintRoot"
		root.z_index = 1
		node.add_child(root)
	var under := _take_paint_layer(node, root, "_PaintUnder", 0)
	var asphalt := _take_paint_layer(node, root, "_PaintAsphalt", 1)
	var over := _take_paint_layer(node, root, "_PaintOver", 2)
	var top := _take_paint_layer(node, root, "_PaintTop", 3)
	var badges := _take_paint_layer(node, root, "_PaintBadges", TrackGround.SPEED_BADGE_Z, false)
	return {
		"root": root,
		"under": under,
		"asphalt": asphalt,
		"over": over,
		"top": top,
		"badges": badges,
	}


static func _take_paint_layer(
	host: Node,
	root: Node2D,
	layer_name: String,
	z: int,
	z_relative: bool = true,
) -> PaintLayer:
	var layer := root.get_node_or_null(layer_name) as PaintLayer
	if layer == null:
		layer = host.get_node_or_null(layer_name) as PaintLayer
		if layer != null:
			layer.reparent(root)
		else:
			layer = PaintLayer.new()
			layer.name = layer_name
			root.add_child(layer)
	layer.z_as_relative = z_relative
	layer.z_index = z
	return layer


static func clear_paint_layers(host: CanvasItem) -> void:
	var node := host as Node
	if node == null:
		return
	var root := node.get_node_or_null("_PaintRoot") as Node2D
	if root == null:
		return
	for name in ["_PaintUnder", "_PaintAsphalt", "_PaintOver", "_PaintTop", "_PaintBadges"]:
		var layer := root.get_node_or_null(name) as PaintLayer
		if layer != null:
			layer.clear_paint()


static func corner_badge_natural(
	frontier: TrackSegmenter.Frontier,
	outside: bool,
	half_width: float = HALF_WIDTH,
) -> Vector2:
	var lateral := half_width + CORNER_BADGE_GAP
	if outside:
		return frontier.center - frontier.inside_normal * lateral
	return frontier.center + frontier.inside_normal * lateral


static func corner_badge_center(ctx: Context, space: int, frontier: Variant = null) -> Vector2:
	if ctx == null or ctx.seg == null or ctx.seg.space_count() == 0:
		return Vector2.ZERO
	if frontier == null:
		var exit_i := posmod(space + 1, ctx.seg.space_count())
		frontier = ctx.seg.frontiers[exit_i]
	var outside := true
	var offset := Vector2.ZERO
	var entry: Variant = ctx.corners.get(space)
	if entry is Dictionary:
		outside = bool(entry.get("outside", true))
		var off_v: Variant = entry.get("offset", Vector2.ZERO)
		if off_v is Vector2:
			offset = off_v
	return corner_badge_natural(frontier as TrackSegmenter.Frontier, outside, ctx.half_width) + offset


static func display_space_number(ctx: Context, space_index: int) -> int:
	if ctx == null or ctx.seg == null or ctx.seg.space_count() == 0:
		return space_index + 1
	var n := ctx.seg.space_count()
	return posmod(space_index - ctx.start_space, n) + 1


static func _scale_of(xform: Transform2D) -> float:
	return absf(xform.get_scale().x)


static func _tx(xform: Transform2D, p: Vector2) -> Vector2:
	return xform * p


static func _sw(xform: Transform2D, w: float) -> float:
	return w * _scale_of(xform)


static func _closed_loop(pts: PackedVector2Array) -> PackedVector2Array:
	var loop := PackedVector2Array()
	loop.resize(pts.size() + 1)
	for i in pts.size():
		loop[i] = pts[i]
	loop[pts.size()] = pts[0]
	return loop


static func _draw_asphalt_band(
	canvas: CanvasItem,
	baked: PackedVector2Array,
	half_width: float,
	xform: Transform2D,
) -> void:
	var pts := unique_loop_points(baked)
	if pts.size() < 3:
		return
	var local := PackedVector2Array()
	local.resize(pts.size())
	for i in pts.size():
		local[i] = _tx(xform, pts[i])
	var radius := _sw(xform, half_width)
	## Solid stroke; pixel grain comes from the asphalt layer shader.
	for i in local.size():
		canvas.draw_circle(local[i], radius, ASPHALT_COLOR)
	canvas.draw_polyline(_closed_loop(local), ASPHALT_COLOR, radius * 2.0, true)


static func _draw_centerline(canvas: CanvasItem, baked: PackedVector2Array, xform: Transform2D) -> void:
	var pts := unique_loop_points(baked)
	if pts.size() < 3:
		return
	var local := PackedVector2Array()
	local.resize(pts.size())
	for i in pts.size():
		local[i] = _tx(xform, pts[i])
	canvas.draw_polyline(_closed_loop(local), CENTERLINE_COLOR, maxf(1.0, _sw(xform, CENTERLINE_WIDTH)), true)


static func _draw_race_line_kerbs(canvas: CanvasItem, ctx: Context, xform: Transform2D) -> void:
	if ctx.seg == null or ctx.seg.samples.is_empty():
		return
	var half := ctx.half_width
	var race_half := RACE_LINE_EDGE_WIDTH * 0.5
	var outer_half := ASPHALT_OUTER_EDGE_WIDTH * 0.5
	var race_run := PackedVector2Array()
	var outer_run := PackedVector2Array()
	var prev_flipped := false
	var have_prev := false
	for s in ctx.seg.samples:
		var inside: Vector2 = s.inside
		if inside.length_squared() < 0.0001:
			inside = Vector2.UP
		else:
			inside = inside.normalized()
		var space := ctx.seg.space_index_at_offset(float(s.cum))
		var flipped := bool(ctx.race_line_flipped.call(space))
		if have_prev and flipped != prev_flipped:
			_stroke_edge_run(canvas, race_run, RACE_LINE_EDGE_COLOR, _sw(xform, RACE_LINE_EDGE_WIDTH))
			_stroke_edge_run(canvas, outer_run, ASPHALT_EDGE_COLOR, _sw(xform, ASPHALT_OUTER_EDGE_WIDTH))
			race_run = PackedVector2Array()
			outer_run = PackedVector2Array()
		have_prev = true
		prev_flipped = flipped
		var race_n := -inside if flipped else inside
		var center: Vector2 = s.pos
		race_run.append(_tx(xform, center + race_n * (half + race_half)))
		outer_run.append(_tx(xform, center - race_n * (half + outer_half)))
	_stroke_edge_run(canvas, race_run, RACE_LINE_EDGE_COLOR, _sw(xform, RACE_LINE_EDGE_WIDTH))
	_stroke_edge_run(canvas, outer_run, ASPHALT_EDGE_COLOR, _sw(xform, ASPHALT_OUTER_EDGE_WIDTH))


static func _stroke_edge_run(canvas: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var r := width * 0.5
	for i in pts.size():
		canvas.draw_circle(pts[i], r, color)
	canvas.draw_polyline(pts, color, width, true)


static func _kerb_sides(ctx: Context, space: int) -> Vector2i:
	var entry: Variant = ctx.kerbs.get(space)
	if not entry is Dictionary:
		return Vector2i.ZERO
	var d: Dictionary = entry
	return Vector2i(
		1 if bool(d.get("inside", false)) else 0,
		1 if bool(d.get("outside", false)) else 0
	)


## Red/cream strips along geometric inside and/or outside asphalt edges.
static func _draw_striped_kerbs(canvas: CanvasItem, ctx: Context, xform: Transform2D) -> void:
	if ctx.seg == null or ctx.seg.samples.is_empty() or ctx.kerbs.is_empty():
		return
	var half := ctx.half_width
	var inner_edge := PackedVector2Array()
	var inner_out := PackedVector2Array()
	var outer_edge := PackedVector2Array()
	var outer_out := PackedVector2Array()
	var prev_sides := Vector2i(-1, -1)
	var have_prev := false
	for s in ctx.seg.samples:
		var inside: Vector2 = s.inside
		if inside.length_squared() < 0.0001:
			inside = Vector2.UP
		else:
			inside = inside.normalized()
		var space := ctx.seg.space_index_at_offset(float(s.cum))
		var sides := _kerb_sides(ctx, space)
		if have_prev and sides != prev_sides:
			if prev_sides.x != 0:
				_stroke_striped_kerb_run(canvas, inner_edge, inner_out, xform)
			if prev_sides.y != 0:
				_stroke_striped_kerb_run(canvas, outer_edge, outer_out, xform)
			inner_edge = PackedVector2Array()
			inner_out = PackedVector2Array()
			outer_edge = PackedVector2Array()
			outer_out = PackedVector2Array()
		have_prev = true
		prev_sides = sides
		var center: Vector2 = s.pos
		if sides.x != 0:
			inner_edge.append(center + inside * half)
			inner_out.append(inside)
		if sides.y != 0:
			outer_edge.append(center - inside * half)
			outer_out.append(-inside)
	if prev_sides.x != 0:
		_stroke_striped_kerb_run(canvas, inner_edge, inner_out, xform)
	if prev_sides.y != 0:
		_stroke_striped_kerb_run(canvas, outer_edge, outer_out, xform)


## `edge` = asphalt lip; `outward` = unit normals pointing away from the road.
static func _stroke_striped_kerb_run(
	canvas: CanvasItem,
	edge: PackedVector2Array,
	outward: PackedVector2Array,
	xform: Transform2D,
) -> void:
	var n := edge.size()
	if n < 2 or outward.size() != n:
		return
	var cum := PackedFloat32Array()
	cum.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + edge[i].distance_to(edge[i - 1])
	var total := cum[n - 1]
	if total < 0.5:
		return
	var thick := KERB_THICKNESS
	var slant := KERB_SLANT
	var t := 0.0
	var stripe_i := 0
	while t < total - 0.001:
		var t1 := minf(t + KERB_STRIPE_LEN, total)
		var a0 := _sample_along_edge(edge, outward, cum, t)
		var a1 := _sample_along_edge(edge, outward, cum, t1)
		var tang0 := _tangent_along_edge(edge, cum, t)
		var tang1 := _tangent_along_edge(edge, cum, t1)
		var b0: Vector2 = a0.pos + a0.out * thick + tang0 * slant
		var b1: Vector2 = a1.pos + a1.out * thick + tang1 * slant
		var poly := PackedVector2Array([
			_tx(xform, a0.pos),
			_tx(xform, a1.pos),
			_tx(xform, b1),
			_tx(xform, b0),
		])
		var col := KERB_COLOR_A if stripe_i % 2 == 0 else KERB_COLOR_B
		canvas.draw_colored_polygon(poly, col)
		t = t1
		stripe_i += 1


static func _sample_along_edge(
	edge: PackedVector2Array,
	outward: PackedVector2Array,
	cum: PackedFloat32Array,
	dist: float,
) -> Dictionary:
	var n := edge.size()
	if dist <= 0.0:
		return {"pos": edge[0], "out": outward[0]}
	if dist >= cum[n - 1]:
		return {"pos": edge[n - 1], "out": outward[n - 1]}
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= dist:
			lo = mid
		else:
			hi = mid
	var span := cum[hi] - cum[lo]
	var u := 0.0 if span < 0.0001 else (dist - cum[lo]) / span
	var out_n: Vector2 = (outward[lo] as Vector2).lerp(outward[hi] as Vector2, u)
	if out_n.length_squared() < 0.0001:
		out_n = outward[lo]
	else:
		out_n = out_n.normalized()
	return {
		"pos": (edge[lo] as Vector2).lerp(edge[hi] as Vector2, u),
		"out": out_n,
	}


static func _tangent_along_edge(edge: PackedVector2Array, cum: PackedFloat32Array, dist: float) -> Vector2:
	var n := edge.size()
	if n < 2:
		return Vector2.RIGHT
	var lo := 0
	var hi := n - 1
	if dist <= 0.0:
		hi = 1
		lo = 0
	elif dist >= cum[n - 1]:
		lo = n - 2
		hi = n - 1
	else:
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if cum[mid] <= dist:
				lo = mid
			else:
				hi = mid
	var tang: Vector2 = edge[hi] - edge[lo]
	if tang.length_squared() < 0.0001:
		return Vector2.RIGHT
	return tang.normalized()


static func _draw_space_overlays(canvas: CanvasItem, ctx: Context, opts: Options, xform: Transform2D) -> void:
	if ctx.seg == null or ctx.seg.space_count() < 2:
		return
	var n := ctx.seg.space_count()
	var font := ctx.font if ctx.font != null else ThemeDB.fallback_font
	for i in n:
		var a: TrackSegmenter.Frontier = ctx.seg.frontiers[i]
		var inner_edge := _tx(xform, a.center + a.inside_normal * ctx.half_width)
		var outer_edge := _tx(xform, a.center - a.inside_normal * ctx.half_width)
		var is_start_line := i == ctx.start_space
		var space_before := posmod(i - 1, n)
		var is_corner_exit := ctx.corners.has(space_before)
		var draw_line := false
		var col := SPACE_EDGE_COLOR
		var width := 2.0
		if is_start_line and opts.start_line:
			col = START_LINE_COLOR
			width = 3.5
			draw_line = true
		elif is_corner_exit and opts.corner_lines:
			col = CORNER_LINE_COLOR
			width = 3.5
			draw_line = true
		elif opts.spaces:
			draw_line = true
		if draw_line:
			canvas.draw_line(inner_edge, outer_edge, col, _sw(xform, width), true)
		if opts.space_numbers:
			var b: TrackSegmenter.Frontier = ctx.seg.frontiers[(i + 1) % n]
			var label_pos := _tx(
				xform,
				a.center.lerp(b.center, 0.35) + a.inside_normal * 10.0
			)
			canvas.draw_string(
				font,
				label_pos,
				str(display_space_number(ctx, i)),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				maxi(1, int(round(_sw(xform, 11.0)))),
				Color(1, 1, 1, 0.7)
			)
	if opts.start_grid:
		_draw_start_grid(canvas, ctx, xform)


static func _draw_speed_limit_badges(canvas: CanvasItem, ctx: Context, xform: Transform2D) -> void:
	if ctx.seg == null or ctx.seg.space_count() < 2:
		return
	var n := ctx.seg.space_count()
	var font := ctx.font if ctx.font != null else ThemeDB.fallback_font
	for i in n:
		var space_before := posmod(i - 1, n)
		if not ctx.corners.has(space_before):
			continue
		var a: TrackSegmenter.Frontier = ctx.seg.frontiers[i]
		var badge_c := _tx(xform, corner_badge_center(ctx, space_before, a))
		_draw_corner_limit_badge(canvas, font, badge_c, _corner_speed(ctx, space_before), xform)


static func _corner_speed(ctx: Context, space: int) -> int:
	var entry: Variant = ctx.corners.get(space)
	if entry is Dictionary:
		return int(entry.get("speed_limit", 0))
	return int(entry) if entry != null else 0


static func _draw_corner_limit_badge(
	canvas: CanvasItem,
	font: Font,
	center: Vector2,
	limit: int,
	xform: Transform2D,
) -> void:
	var r := _sw(xform, CORNER_BADGE_RADIUS)
	var font_size := maxi(8, int(round(_sw(xform, 12.0))))
	canvas.draw_circle(center, r, Color.WHITE, true, -1.0, true)
	canvas.draw_arc(center, maxf(1.0, r - _sw(xform, 1.5)), 0.0, TAU, 28, CORNER_LINE_COLOR, _sw(xform, 2.5), true)
	var text := str(limit)
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# draw_string uses the baseline. Center the line box (ascent above, descent below).
	var baseline := center.y + (
		font.get_ascent(font_size) - font.get_descent(font_size)
	) * 0.5
	canvas.draw_string(
		font,
		Vector2(center.x - extent.x * 0.5, baseline),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.BLACK
	)


static func _draw_start_grid(canvas: CanvasItem, ctx: Context, xform: Transform2D) -> void:
	var n := ctx.seg.space_count()
	var rows := mini(START_GRID_SPACES, n)
	var lateral := ctx.half_width * ctx.spot_inset
	for row in rows:
		var space := posmod(ctx.start_space - 1 - row, n)
		var exit_i := posmod(space + 1, n)
		var fr: TrackSegmenter.Frontier = ctx.seg.frontiers[exit_i]
		var fwd := fr.tangent
		if fwd.length_squared() < 0.0001:
			continue
		fwd = fwd.normalized()
		var flipped := bool(ctx.race_line_flipped.call(space))
		var race_side := fr.inside_normal if not flipped else -fr.inside_normal
		_draw_start_grid_marker(canvas, _tx(xform, fr.center - fwd * 4.0 + race_side * lateral), fwd, xform)
		_draw_start_grid_marker(
			canvas,
			_tx(xform, fr.center - fwd * (4.0 + OUTER_SPOT_ALONG_OFFSET) - race_side * lateral),
			fwd,
			xform
		)


static func _draw_start_grid_marker(
	canvas: CanvasItem,
	center: Vector2,
	heading: Vector2,
	xform: Transform2D,
) -> void:
	var fwd := heading.normalized()
	# Basis stays in world-tangent space; lengths are scaled for the viewport.
	var right := Vector2(-fwd.y, fwd.x)
	var s := _scale_of(xform)
	var half_w := 8.5 * s
	var arm := 5.0 * s
	var t := 1.0 * s
	var stroke := 2.0 * t
	canvas.draw_line(
		center + right * (-half_w + t),
		center + right * (half_w - t),
		START_GRID_MARKER_COLOR,
		stroke,
		true
	)
	canvas.draw_line(
		center + right * (-half_w) + fwd * (-arm),
		center + right * (-half_w) + fwd * t,
		START_GRID_MARKER_COLOR,
		stroke,
		true
	)
	canvas.draw_line(
		center + right * half_w + fwd * (-arm),
		center + right * half_w + fwd * t,
		START_GRID_MARKER_COLOR,
		stroke,
		true
	)
