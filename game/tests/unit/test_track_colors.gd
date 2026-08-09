extends GutTest


func test_defaults_include_race_line_and_kerbs() -> void:
	var d := TrackColors.defaults()
	assert_eq(d.race_line, TrackColors.DEFAULT_RACE_LINE)
	assert_eq(d.kerb_a, TrackColors.DEFAULT_KERB_A)
	assert_eq(d.kerb_b, TrackColors.DEFAULT_KERB_B)
	assert_true(d.asphalt is Dictionary)


func test_roundtrip_colors_document() -> void:
	var settings := {
		"asphalt": {
			"base": Color(0.3, 0.3, 0.3, 1.0),
			"dark": Color(0.2, 0.2, 0.2, 1.0),
			"light": Color(0.4, 0.4, 0.4, 1.0),
			"locked": false,
		},
		"race_line": Color(0.1, 0.2, 0.9, 1.0),
		"kerb_a": Color(1.0, 0.0, 0.0, 1.0),
		"kerb_b": Color(1.0, 1.0, 0.8, 1.0),
		"centerline": Color(0.9, 0.9, 1.0, 1.0),
		"start_line": Color(1.0, 0.2, 0.1, 1.0),
		"corner_line": Color(0.1, 0.8, 0.2, 1.0),
		"space_edge": Color(0.1, 0.1, 0.1, 0.95),
		"vegetation_a": Color(0.4, 0.6, 0.3, 1.0),
		"vegetation_b": Color(0.1, 0.3, 0.15, 1.0),
	}
	var doc := {"colors": TrackColors.to_colors_document(settings)}
	var loaded := TrackColors.from_document(doc)
	assert_eq(loaded.race_line, Color(0.1, 0.2, 0.9, 1.0))
	assert_eq(loaded.kerb_a, Color(1.0, 0.0, 0.0, 1.0))
	assert_eq(loaded.kerb_b, Color(1.0, 1.0, 0.8, 1.0))
	assert_eq(loaded.centerline, Color(0.9, 0.9, 1.0, 1.0))
	assert_eq(loaded.start_line, Color(1.0, 0.2, 0.1, 1.0))
	assert_eq(loaded.corner_line, Color(0.1, 0.8, 0.2, 1.0))
	assert_eq(loaded.space_edge, Color(0.1, 0.1, 0.1, 0.95))
	assert_eq(loaded.vegetation_a, Color(0.4, 0.6, 0.3, 1.0))
	assert_eq(loaded.vegetation_b, Color(0.1, 0.3, 0.15, 1.0))
	assert_eq(loaded.asphalt.base, Color(0.3, 0.3, 0.3, 1.0))
	assert_false(loaded.asphalt.locked)
