extends GutTest

var _temp_paths: Array[String] = []


func after_each() -> void:
	for path in _temp_paths:
		SplineTrackFile.delete_document(path)
	_temp_paths.clear()


func _temp_path(file_name: String) -> String:
	var path := "%s/%s" % [SplineTrackFile.USER_DIR, file_name]
	_temp_paths.append(path)
	return path


func _sample_document() -> Dictionary:
	return {
		"version": SplineTrackFile.VERSION,
		"name": "Bind Test",
		"spline": TrackSpline.make_default_triangle(Vector2(400, 300), 140.0).to_dict(),
		"segmentation": {
			"algorithm": TrackSegmenter.Algorithm.INNER_UNIFORM,
			"car_length": 40.0,
			"target_space_len": 40.0,
		},
		"start_space": 3,
		"corners": [
			{"space": 5, "speed_limit": 4, "outside": true, "offset": [0.0, 0.0]},
			{"space": 10, "speed_limit": 3, "outside": false, "offset": [0.0, 0.0]},
		],
		"sector_flip_race_line": [{"key": 5}],
	}


func test_bind_to_heat_track_reindexes_from_start() -> void:
	var path := _temp_path("_test_bind_heat.json")
	var data := _sample_document()
	assert_eq(SplineTrackFile.save_document(path, data), OK)
	var bind := SplineTrackBind.from_path(path)
	assert_ne(bind, null)
	var track := bind.to_heat_track(2)
	assert_eq(track.laps, 2)
	assert_eq(track.space_count, bind.space_count())
	assert_eq(track.spot_count(0), 2)
	assert_true(track.start_behind_finish_line)
	assert_ne(track.spline_bind, null)
	# Geometric corner 5 → playable from_space = posmod(5 - 3, n)
	var play_from := bind.geom_to_play(5)
	var found := false
	for c in track.corners:
		if c.from_space == play_from and c.speed_limit == 4:
			found = true
	assert_true(found, "corner at geom 5 should map to play %d" % play_from)


func test_sample_at_returns_heading() -> void:
	var bind := SplineTrackBind.from_document(_sample_document())
	assert_ne(bind, null)
	var sample := bind.sample_at(0.0, 0.0)
	assert_true(sample.has("pos"))
	assert_true(sample.has("heading"))
	assert_gt((sample.heading as Vector2).length(), 0.01)


func test_state_codec_preserves_spline_document() -> void:
	var path := _temp_path("_test_bind_codec.json")
	var data := _sample_document()
	assert_eq(SplineTrackFile.save_document(path, data), OK)
	var track := HeatTrack.from_id(path, 1)
	assert_ne(track, null)
	var engine := HeatGameEngine.new()
	engine.setup(["A", "B"], track, 3)
	var snap := StateCodec.encode(engine, -1)
	var restored := StateCodec.decode(snap)
	assert_ne(restored.track.spline_bind, null)
	assert_eq(restored.track.space_count, track.space_count)
	assert_eq(str(restored.track.spline_bind.document.get("name", "")), "Bind Test")
