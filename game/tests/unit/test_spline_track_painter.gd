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


func test_game_options_are_asphalt_plus_race_line() -> void:
	var o := SplineTrackPainter.game_options()
	assert_true(o.asphalt)
	assert_true(o.race_line)
	assert_false(o.spaces)
	assert_false(o.centerline)
