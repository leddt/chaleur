extends GutTest


func test_unique_loop_drops_closing_duplicate() -> void:
	var baked := PackedVector2Array([
		Vector2(0, 0),
		Vector2(10, 0),
		Vector2(10, 10),
		Vector2(0, 10),
		Vector2(0, 0),
	])
	var pts := SplineTrackPainter.unique_loop_points(baked)
	assert_eq(pts.size(), 4)
	assert_eq(pts[0], Vector2(0, 0))
	assert_eq(pts[3], Vector2(0, 10))


func test_fit_transform_keeps_centerline_inside_viewport() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2(400, 300), 120.0)
	var baked := SplineTrackPainter.bake_spline(spline)
	var world := SplineTrackPainter.bounds(baked, SplineTrackPainter.HALF_WIDTH)
	var viewport := Rect2(0, 0, 300, 260)
	var xform := SplineTrackPainter.fit_transform(world, viewport, 18.0)
	assert_gt(xform.get_scale().x, 0.1)
	for p in baked:
		var local: Vector2 = xform * p
		assert_true(
			viewport.grow(1.0).has_point(local),
			"point %s should map inside viewport" % local
		)


func test_bake_rejects_empty_spline() -> void:
	var empty := TrackSpline.new()
	assert_eq(SplineTrackPainter.bake_spline(empty).size(), 0)


func test_game_options_include_race_overlays() -> void:
	var o := SplineTrackPainter.game_options()
	assert_true(o.asphalt)
	assert_true(o.race_line)
	assert_true(o.spaces)
	assert_true(o.centerline)
	assert_true(o.start_grid)
	assert_true(o.speed_limits)


func test_preview_options_omit_race_overlays() -> void:
	var o := SplineTrackPainter.preview_options()
	assert_true(o.asphalt)
	assert_true(o.race_line)
	assert_true(o.start_line)
	assert_true(o.corner_lines)
	assert_false(o.spaces)
	assert_false(o.centerline)
	assert_false(o.speed_limits)
	assert_false(o.start_grid)


func test_asphalt_shader_material_configured() -> void:
	var mat := SplineTrackPainter._asphalt_mat()
	assert_true(mat != null)
	assert_true(mat.shader != null)
	assert_gt(SplineTrackPainter.ASPHALT_GRAIN_WORLD, 0.0)
	assert_eq(mat.get_shader_parameter("grain_world"), SplineTrackPainter.ASPHALT_GRAIN_WORLD)


func test_context_stores_striped_kerb_sides() -> void:
	var ctx := SplineTrackPainter.Context.new()
	ctx.kerbs = {
		0: {"inside": true, "outside": false},
		1: {"inside": false, "outside": true},
		2: {"inside": true, "outside": true},
	}
	assert_eq(ctx.kerbs.size(), 3)
	assert_true(bool(ctx.kerbs[0].get("inside", false)))
	assert_false(bool(ctx.kerbs[0].get("outside", true)))
	assert_false(bool(ctx.kerbs[1].get("inside", true)))
	assert_true(bool(ctx.kerbs[1].get("outside", false)))
	assert_gt(SplineTrackPainter.KERB_THICKNESS, 0.0)
	assert_gt(SplineTrackPainter.KERB_STRIPE_LEN, 0.0)
	assert_gt(
		SplineTrackPainter.RACE_LINE_EDGE_WIDTH,
		SplineTrackPainter.KERB_THICKNESS,
		"race line must overhang past striped kerbs"
	)
