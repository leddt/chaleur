extends GutTest


func test_normalize_known_and_fallback() -> void:
	assert_eq(TrackGround.normalize("grass"), TrackGround.THEME_GRASS)
	assert_eq(TrackGround.normalize("DIRT"), TrackGround.THEME_DIRT)
	assert_eq(TrackGround.normalize("sand"), TrackGround.THEME_SAND)
	assert_eq(TrackGround.normalize("snow"), TrackGround.THEME_SNOW)
	assert_eq(TrackGround.normalize("ROCK"), TrackGround.THEME_ROCK)
	assert_eq(TrackGround.normalize(""), TrackGround.DEFAULT_THEME)
	assert_eq(TrackGround.normalize("lava"), TrackGround.DEFAULT_THEME)


func test_from_document_reads_ground_theme() -> void:
	assert_eq(TrackGround.from_document({}), TrackGround.DEFAULT_THEME)
	assert_eq(
		TrackGround.from_document({"ground_theme": "sand"}),
		TrackGround.THEME_SAND
	)
	assert_eq(
		TrackGround.from_document({"ground_theme": "snow"}),
		TrackGround.THEME_SNOW
	)


func test_make_material_sets_shader_params() -> void:
	var mat := TrackGround.make_material(TrackGround.THEME_DIRT)
	assert_ne(mat, null)
	assert_ne(mat.shader, null)
	var base: Variant = mat.get_shader_parameter("base_color")
	assert_true(base is Color)
	TrackGround.apply(mat, TrackGround.THEME_SAND)
	var sand_base: Color = mat.get_shader_parameter("base_color")
	assert_gt(sand_base.r, 0.5)
	TrackGround.apply(mat, TrackGround.THEME_ROCK)
	var rock_base: Color = mat.get_shader_parameter("base_color")
	assert_lt(rock_base.r, 0.6)


func test_display_names_are_french() -> void:
	assert_eq(TrackGround.display_name(TrackGround.THEME_GRASS), "Gazon")
	assert_eq(TrackGround.display_name(TrackGround.THEME_DIRT), "Terre")
	assert_eq(TrackGround.display_name(TrackGround.THEME_SAND), "Sable")
	assert_eq(TrackGround.display_name(TrackGround.THEME_SNOW), "Neige")
	assert_eq(TrackGround.display_name(TrackGround.THEME_ROCK), "Roche")
