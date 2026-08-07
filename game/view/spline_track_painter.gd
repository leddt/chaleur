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
const RACE_LINE_EDGE_COLOR := Color(0.58, 0.59, 0.62, 1.0)
const RACE_LINE_EDGE_WIDTH := 5.0
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


static func draw(
	canvas: CanvasItem,
	baked: PackedVector2Array,
	ctx: Context,
	opts: Options = null,
	xform: Transform2D = Transform2D.IDENTITY,
) -> void:
	if canvas == null or ctx == null:
		return
	var options := opts if opts != null else default_options()
	# Kerbs under asphalt (editor look): mitre spikes get covered by the band.
	if options.race_line:
		_draw_race_line_kerbs(canvas, ctx, xform)
	if options.asphalt:
		_draw_asphalt_band(canvas, baked, ctx.half_width, xform)
	if options.centerline:
		_draw_centerline(canvas, baked, xform)
	if (
		options.spaces
		or options.start_line
		or options.corner_lines
		or options.speed_limits
		or options.space_numbers
		or options.start_grid
	):
		_draw_space_overlays(canvas, ctx, options, xform)


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
	_stroke_closed_band(canvas, local, _closed_loop(local), _sw(xform, half_width), ASPHALT_COLOR)


static func _draw_centerline(canvas: CanvasItem, baked: PackedVector2Array, xform: Transform2D) -> void:
	var pts := unique_loop_points(baked)
	if pts.size() < 3:
		return
	var local := PackedVector2Array()
	local.resize(pts.size())
	for i in pts.size():
		local[i] = _tx(xform, pts[i])
	canvas.draw_polyline(_closed_loop(local), CENTERLINE_COLOR, maxf(1.0, _sw(xform, CENTERLINE_WIDTH)), true)


static func _stroke_closed_band(
	canvas: CanvasItem,
	pts: PackedVector2Array,
	loop: PackedVector2Array,
	radius: float,
	color: Color,
) -> void:
	for i in pts.size():
		canvas.draw_circle(pts[i], radius, color)
	canvas.draw_polyline(loop, color, radius * 2.0, true)


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
		if is_corner_exit and opts.speed_limits:
			var badge_c := _tx(xform, corner_badge_center(ctx, space_before, a))
			_draw_corner_limit_badge(canvas, font, badge_c, _corner_speed(ctx, space_before), xform)
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
