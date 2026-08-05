extends GutTest


func _params(algo: int, car_len: float = 36.0) -> TrackSegmenter.Params:
	var p := TrackSegmenter.Params.new()
	p.algorithm = algo
	p.car_length = car_len
	p.target_space_len = car_len
	p.road_half_width = 28.0
	p.min_spaces = 8
	p.max_spaces = 180
	return p


func test_all_algorithms_produce_closed_spaces() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2(400, 300), 160.0)
	for algo in [
		TrackSegmenter.Algorithm.CENTER_UNIFORM,
		TrackSegmenter.Algorithm.INNER_UNIFORM,
		TrackSegmenter.Algorithm.ADAPTIVE_INNER,
	]:
		var result := TrackSegmenter.segment(spline, _params(algo))
		assert_gte(result.space_count(), 8, "algo %s" % algo)
		assert_lte(result.space_count(), 180, "algo %s" % algo)
		assert_gt(result.total_length, 100.0)
		for fr in result.frontiers:
			var f: TrackSegmenter.Frontier = fr
			assert_ne(f.spot_inner, f.spot_outer)
			assert_gt(f.center.distance_to(f.spot_inner), 1.0)


func test_shorter_car_length_yields_more_spaces() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 200.0)
	var coarse := TrackSegmenter.segment(
		spline, _params(TrackSegmenter.Algorithm.INNER_UNIFORM, 60.0)
	)
	var fine := TrackSegmenter.segment(
		spline, _params(TrackSegmenter.Algorithm.INNER_UNIFORM, 24.0)
	)
	assert_gt(fine.space_count(), coarse.space_count())


func test_inner_spots_lie_toward_centroid() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2(200, 200), 120.0)
	var result := TrackSegmenter.segment(
		spline, _params(TrackSegmenter.Algorithm.CENTER_UNIFORM, 40.0)
	)
	var centroid := Vector2.ZERO
	for i in 3:
		centroid += spline.get_point(i).position
	centroid /= 3.0
	var fr: TrackSegmenter.Frontier = result.frontiers[0]
	var d_inner := fr.spot_inner.distance_to(centroid)
	var d_outer := fr.spot_outer.distance_to(centroid)
	assert_lt(d_inner, d_outer, "race line should be closer to track center")


func test_empty_spline_returns_empty_result() -> void:
	var spline := TrackSpline.new()
	var result := TrackSegmenter.segment(spline, _params(TrackSegmenter.Algorithm.CENTER_UNIFORM))
	assert_eq(result.space_count(), 0)


func test_space_ribbon_follows_curve_without_bowtie() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2.ZERO, 80.0)
	# Pinch one point so curvature is sharp near a space.
	spline.set_point_position(0, Vector2(0, -40))
	var result := TrackSegmenter.segment(
		spline, _params(TrackSegmenter.Algorithm.INNER_UNIFORM, 30.0)
	)
	assert_gte(result.space_count(), 8)
	assert_false(result.samples.is_empty())
	var ribbon := result.space_ribbon(0, 28.0)
	assert_gte(ribbon.size(), 6)
	# Hit-test near the first frontier center should resolve a space.
	var fr: TrackSegmenter.Frontier = result.frontiers[0]
	var hit := result.space_at_world(fr.center, 28.0)
	assert_gte(hit, 0)


func test_slot_poses_keep_outer_outside_in_tight_bend() -> void:
	var spline := TrackSpline.make_default_triangle(Vector2(200, 200), 120.0)
	spline.set_point_position(0, Vector2(200, 160))
	var result := TrackSegmenter.segment(
		spline, _params(TrackSegmenter.Algorithm.INNER_UNIFORM, 28.0)
	)
	assert_gte(result.space_count(), 8)
	var centroid := Vector2(200, 200)
	# Find the space whose mid is closest to the pinched vertex (tightest bend).
	var best_i := 0
	var best_d := INF
	for i in result.space_count():
		var poses_i: Array = result.space_slot_poses(i, 28.0, 0.45)
		var mid: Vector2 = poses_i[0].pos.lerp(poses_i[1].pos, 0.5)
		var d := mid.distance_squared_to(Vector2(200, 160))
		if d < best_d:
			best_d = d
			best_i = i
	var poses: Array = result.space_slot_poses(best_i, 28.0, 0.45)
	var inner: Vector2 = poses[0].pos
	var outer: Vector2 = poses[1].pos
	assert_lt(inner.distance_to(centroid), outer.distance_to(centroid))
	# Both cars should sit away from the centerline-ish mid chord of the two spots.
	var sep := inner.distance_to(outer)
	assert_gt(sep, 20.0, "inner/outer should stay laterally separated (got %s)" % sep)
