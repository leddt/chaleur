extends GutTest


func test_derive_grain_from_base() -> void:
	var base := TrackAsphalt.DEFAULT_BASE
	var dark := TrackAsphalt.derive_dark(base)
	var light := TrackAsphalt.derive_light(base)
	assert_lt(dark.r, base.r)
	assert_gt(light.r, base.r)
	assert_eq(dark.a, 1.0)
	assert_eq(light.a, 1.0)


func test_from_document_defaults_and_locked() -> void:
	var def := TrackAsphalt.from_document({})
	assert_eq(def.base, TrackAsphalt.DEFAULT_BASE)
	assert_true(def.locked)
	assert_eq(def.dark, TrackAsphalt.derive_dark(TrackAsphalt.DEFAULT_BASE))
	assert_eq(def.light, TrackAsphalt.derive_light(TrackAsphalt.DEFAULT_BASE))


func test_from_document_reads_colors_asphalt() -> void:
	var data := {
		"colors": {
			"asphalt": {
				"base": [0.5, 0.1, 0.1],
				"grain_dark": [0.1, 0.0, 0.0],
				"grain_light": [0.9, 0.4, 0.4],
				"grain_locked": false,
			},
		},
	}
	var s := TrackAsphalt.from_document(data)
	assert_false(s.locked)
	assert_eq(s.base, Color(0.5, 0.1, 0.1, 1.0))
	assert_eq(s.dark, Color(0.1, 0.0, 0.0, 1.0))
	assert_eq(s.light, Color(0.9, 0.4, 0.4, 1.0))


func test_from_document_legacy_flat_keys() -> void:
	var data := {
		"asphalt_color": [0.2, 0.3, 0.4],
		"asphalt_grain_locked": true,
	}
	var s := TrackAsphalt.from_document(data)
	assert_eq(s.base, Color(0.2, 0.3, 0.4, 1.0))
	assert_true(s.locked)
	assert_eq(s.dark, TrackAsphalt.derive_dark(s.base))


func test_to_colors_document_rederive_when_locked() -> void:
	var base := Color(0.4, 0.4, 0.45, 1.0)
	var colors := TrackAsphalt.to_colors_document({
		"base": base,
		"dark": Color.BLACK,
		"light": Color.WHITE,
		"locked": true,
	})
	var asphalt: Dictionary = colors.asphalt
	assert_true(asphalt.grain_locked)
	assert_eq(asphalt.base, TrackAsphalt.color_to_array(base))
	assert_eq(asphalt.grain_dark, TrackAsphalt.color_to_array(TrackAsphalt.derive_dark(base)))
	assert_eq(asphalt.grain_light, TrackAsphalt.color_to_array(TrackAsphalt.derive_light(base)))
