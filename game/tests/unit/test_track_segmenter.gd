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
