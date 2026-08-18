extends GutTest

var _temp_paths: Array[String] = []


func after_each() -> void:
	for path in _temp_paths:
		assert_eq(SplineTrackFile.delete_document(path), OK, "cleanup %s" % path)
		assert_false(FileAccess.file_exists(path), "temp track should be deleted: %s" % path)
	_temp_paths.clear()


func _temp_path(file_name: String) -> String:
	var path := "%s/%s" % [SplineTrackFile.USER_DIR, file_name]
	_temp_paths.append(path)
	return path


func test_slugify_basic() -> void:
	assert_eq(SplineTrackFile.slugify("Mon Circuit"), "mon_circuit")
	assert_eq(SplineTrackFile.slugify("  A--B  "), "a_b")


func test_slugify_empty_fallback() -> void:
	var slug := SplineTrackFile.slugify("   ")
	assert_true(slug.begins_with("trace_"), slug)


func test_save_and_load_roundtrip() -> void:
	var path := _temp_path("_test_spline_save.json")
	var data := {
		"version": SplineTrackFile.VERSION,
		"name": "Test",
		"ground_theme": "sand",
		"spline": TrackSpline.make_default_triangle().to_dict(),
		"segmentation": {"algorithm": 1, "car_length": 36.0, "target_space_len": 36.0},
		"start_space": 2,
		"start_heat": 4,
		"start_stress": 1,
		"corners": [{"space": 4, "speed_limit": 3, "outside": true, "offset": [1.0, 2.0]}],
		"kerbs": [{"space": 4, "inside": true, "outside": false}],
		"sector_flip_race_line": [{"key": 4}],
	}
	assert_eq(SplineTrackFile.save_document(path, data), OK)
	var loaded := SplineTrackFile.load_document(path)
	assert_eq(str(loaded.get("name", "")), "Test")
	assert_eq(int(loaded.get("start_space", -1)), 2)
	assert_eq(int(loaded.get("start_heat", -1)), 4)
	assert_eq(int(loaded.get("start_stress", -1)), 1)
	assert_eq(str(loaded.get("ground_theme", "")), "sand")
	var corners: Array = loaded.get("corners", [])
	assert_eq(corners.size(), 1)
	var kerbs: Array = loaded.get("kerbs", [])
	assert_eq(kerbs.size(), 1)
	assert_true(bool(kerbs[0].get("inside", false)))
	assert_false(bool(kerbs[0].get("outside", true)))


func test_list_entries_includes_saved() -> void:
	var path := _temp_path("_test_list_entry.json")
	var data := {
		"version": SplineTrackFile.VERSION,
		"name": "ZZ List Entry",
		"spline": TrackSpline.make_default_triangle().to_dict(),
	}
	assert_eq(SplineTrackFile.save_document(path, data), OK)
	var found := false
	for entry in SplineTrackFile.list_entries():
		if str(entry.get("path", "")) == path:
			found = true
			assert_eq(str(entry.get("name", "")), "ZZ List Entry")
			assert_false(bool(entry.get("builtin", true)))
			break
	assert_true(found, "saved track should appear in list")


func test_path_for_name_builtin_vs_user() -> void:
	assert_eq(
		SplineTrackFile.path_for_name("Oval", false),
		"%s/oval.json" % SplineTrackFile.USER_DIR
	)
	assert_eq(
		SplineTrackFile.path_for_name("Oval", true),
		"%s/oval.json" % SplineTrackFile.BUILTIN_DIR
	)
	assert_true(SplineTrackFile.is_builtin_path(SplineTrackFile.path_for_name("Oval", true)))
	assert_true(SplineTrackFile.is_user_path(SplineTrackFile.path_for_name("Oval", false)))


func test_list_entries_skips_invalid_json() -> void:
	var path := _temp_path("_test_invalid_layout.json")
	assert_eq(SplineTrackFile.save_document(path, {
		"author_corners": [],
		"centerline": {"closed": true, "points": []},
	}), OK)
	for entry in SplineTrackFile.list_entries():
		assert_ne(str(entry.get("path", "")), path)
	assert_false(SplineTrackFile.is_valid_document(SplineTrackFile.load_document(path)))
