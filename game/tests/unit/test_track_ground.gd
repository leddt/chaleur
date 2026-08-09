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


func test_attach_adds_ground_and_cloud_overlay() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var ground := TrackGround.attach(host, TrackGround.THEME_GRASS)
	assert_ne(ground, null)
	assert_eq(ground.name, "TrackGround")
	assert_true(ground.show_behind_parent)
	var clouds := host.get_node_or_null("CloudShadows") as ColorRect
	assert_ne(clouds, null)
	assert_eq(clouds.z_index, TrackGround.CLOUD_OVERLAY_Z)
	assert_eq(clouds.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var mat := clouds.material as ShaderMaterial
	assert_ne(mat, null)
	assert_eq(mat.shader, TrackGround.CLOUD_SHADER)
	# Idempotent.
	var ground2 := TrackGround.attach(host, TrackGround.THEME_SAND)
	assert_eq(ground2, ground)
	assert_eq(host.get_node("CloudShadows"), clouds)


func test_set_view_updates_ground_and_clouds() -> void:
	var host := Control.new()
	add_child_autofree(host)
	TrackGround.attach(host, TrackGround.THEME_GRASS)
	var pan := Vector2(40.0, -12.5)
	var zoom := 2.5
	TrackGround.set_view(host, pan, zoom)
	for node_name in ["TrackGround", "CloudShadows"]:
		var mat := (host.get_node(node_name) as ColorRect).material as ShaderMaterial
		assert_ne(mat, null)
		assert_eq(mat.get_shader_parameter("view_pan"), pan)
		assert_eq(mat.get_shader_parameter("view_zoom"), zoom)
	TrackGround.set_view(host, Vector2.ZERO, 0.0)
	var clamped: float = (host.get_node("TrackGround") as ColorRect).material.get_shader_parameter("view_zoom")
	assert_gt(clamped, 0.0)
