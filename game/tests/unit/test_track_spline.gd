extends GutTest


func test_default_triangle_has_three_auto_points() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2(100, 100), 50.0)
	assert_eq(spline.point_count(), 3)
	for i in 3:
		var cp := spline.get_point(i)
		assert_eq(cp.type, TrackSpline.PointType.AUTO_SMOOTH)
		assert_eq(cp.tension, TrackSpline.DEFAULT_TENSION)


func test_closed_curve2d_repeats_first_point() -> void:
	var spline := TrackSpline.make_default_triangle()
	var curve := spline.to_curve2d()
	# 3 anchors + repeated first point to close (no Curve2D.closed in 4.7).
	assert_eq(curve.point_count, 4)
	assert_eq(curve.get_point_position(0), curve.get_point_position(3))


func test_baked_path_is_non_empty_closed_loop() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 100.0)
	var baked := spline.baked_points()
	assert_gt(baked.size(), 6)
	# First and last baked points of a closed Curve2D should meet closely.
	var gap := baked[0].distance_to(baked[baked.size() - 1])
	assert_lt(gap, 4.0, "closed bake should nearly meet (gap=%s)" % gap)


func test_higher_tension_lengthens_out_handle() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 100.0)
	spline.set_point_type(0, TrackSpline.PointType.TENSION)
	var base_len := spline.get_point(0).position.distance_to(spline.out_handle_world(0))
	spline.set_point_tension(0, 2.0)
	var high_len := spline.get_point(0).position.distance_to(spline.out_handle_world(0))
	assert_gt(high_len, base_len * 1.5)


func test_tension_from_handle_roundtrip() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2(200, 200), 80.0)
	spline.set_point_type(1, TrackSpline.PointType.TENSION)
	spline.set_point_tension(1, 1.5)
	var tip := spline.out_handle_world(1)
	var recovered := spline.tension_from_out_handle(1, tip)
	assert_almost_eq(recovered, 1.5, 0.05)


func test_moving_point_updates_bake() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 60.0)
	var before := spline.baked_points()[0]
	spline.set_point_position(0, Vector2(0, -200))
	var after_curve := spline.to_curve2d()
	assert_eq(after_curve.get_point_position(0), Vector2(0, -200))
	var baked := spline.baked_points()
	assert_ne(before, baked[0])


func test_insert_point_near_curve_grows_count() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 100.0)
	var mid := spline.get_point(0).position.lerp(spline.get_point(1).position, 0.5)
	# Nudge toward the curve bulging outward from the chord.
	var hit: Dictionary = spline.closest_on_curve(mid)
	var idx := spline.insert_point_near(hit.point)
	assert_eq(spline.point_count(), 4)
	assert_gte(idx, 0)
	assert_lte(idx, 3)
	assert_almost_eq(spline.get_point(idx).position.x, float(hit.point.x), 1.0)
	assert_almost_eq(spline.get_point(idx).position.y, float(hit.point.y), 1.0)


func test_remove_point_respects_minimum() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 80.0)
	assert_false(spline.remove_point(0), "cannot go below 3 points")
	assert_eq(spline.point_count(), 3)
	var on_curve: Vector2 = spline.closest_on_curve(Vector2(80, 0)).point
	var inserted := spline.insert_point_near(on_curve)
	assert_gte(inserted, 0)
	assert_eq(spline.point_count(), 4)
	assert_true(spline.remove_point(inserted))
	assert_eq(spline.point_count(), 3)


func test_set_point_type_to_free_bakes_handles() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 100.0)
	spline.set_point_type(0, TrackSpline.PointType.TENSION)
	spline.set_point_tension(0, 1.8)
	var out_before := spline.out_handle_world(0)
	var in_before := spline.in_handle_world(0)
	spline.set_point_type(0, TrackSpline.PointType.FREE)
	assert_eq(spline.get_point(0).type, TrackSpline.PointType.FREE)
	assert_almost_eq(spline.out_handle_world(0).x, out_before.x, 0.01)
	assert_almost_eq(spline.out_handle_world(0).y, out_before.y, 0.01)
	assert_almost_eq(spline.in_handle_world(0).x, in_before.x, 0.01)
	assert_almost_eq(spline.in_handle_world(0).y, in_before.y, 0.01)


func test_free_handles_are_independent() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 100.0)
	spline.set_point_type(1, TrackSpline.PointType.FREE)
	var anchor := spline.get_point(1).position
	spline.set_out_handle_world(1, anchor + Vector2(40, 0))
	spline.set_in_handle_world(1, anchor + Vector2(0, -25))
	assert_almost_eq(spline.get_point(1).out_handle.x, 40.0, 0.01)
	assert_almost_eq(spline.get_point(1).in_handle.y, -25.0, 0.01)
	var curve := spline.to_curve2d()
	assert_eq(curve.get_point_out(1), Vector2(40, 0))
	assert_eq(curve.get_point_in(1), Vector2(0, -25))


func test_auto_smooth_ignores_tension() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 100.0)
	spline.set_point_type(0, TrackSpline.PointType.AUTO_SMOOTH)
	var base := spline.out_handle_world(0)
	spline.set_point_tension(0, 3.0) # no-op for auto
	assert_eq(spline.out_handle_world(0), base)


func test_type_roundtrip_tension_free_tension() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 90.0)
	spline.set_point_type(2, TrackSpline.PointType.TENSION)
	spline.set_point_tension(2, 1.4)
	var t0 := spline.get_point(2).tension
	spline.set_point_type(2, TrackSpline.PointType.FREE)
	spline.set_point_type(2, TrackSpline.PointType.TENSION)
	assert_eq(spline.get_point(2).type, TrackSpline.PointType.TENSION)
	assert_almost_eq(spline.get_point(2).tension, t0, 0.08)


func test_to_dict_from_dict_roundtrip() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2(50, 60), 80.0)
	spline.set_point_type(1, TrackSpline.PointType.FREE)
	spline.set_out_handle_world(1, spline.get_point(1).position + Vector2(12, -8))
	spline.set_in_handle_world(1, spline.get_point(1).position + Vector2(-5, 9))
	var restored := TrackSpline.from_dict(spline.to_dict())
	assert_eq(restored.point_count(), 3)
	assert_eq(restored.get_point(1).type, TrackSpline.PointType.FREE)
	assert_almost_eq(restored.get_point(1).out_handle.x, 12.0, 0.01)
	assert_almost_eq(restored.get_point(1).in_handle.y, 9.0, 0.01)
	assert_almost_eq(restored.get_point(0).position.x, spline.get_point(0).position.x, 0.01)


func test_insert_defaults_to_auto() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 80.0)
	var on_curve: Vector2 = spline.closest_on_curve(Vector2(80, 0)).point
	var idx := spline.insert_point_near(on_curve)
	assert_eq(spline.get_point(idx).type, TrackSpline.PointType.AUTO_SMOOTH)
