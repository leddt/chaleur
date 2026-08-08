extends Control

const ShadedLabelScn := preload("res://ui/kit/shaded_label.gd")
const FLAME_SHADER := preload("res://shaders/flame_text.gdshader")
const CHROME_SHADER := preload("res://shaders/chrome_text.gdshader")
const GRAIN_SHADER := preload("res://shaders/paper_grain.gdshader")

const TITLE_SIZE := 96
const SUBTITLE_SIZE := 28


func _ready() -> void:
	theme = ThemeBuilder.build()
	_apply_background()
	_build_brand_labels()
	_apply_actions()
	_build_kerb()
	_build_grain_overlay()


func _apply_background() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = Palette.ASPHALT


func _build_brand_labels() -> void:
	var brand := get_node("Margin/Row/Brand") as VBoxContainer
	brand.add_theme_constant_override("separation", 0)

	var title: ShadedLabel = ShadedLabelScn.new()
	title.name = "Title"
	title.text = "CHALEUR"
	title.font_size = TITLE_SIZE
	title.pad_left = 56
	title.pad_top = 80
	title.pad_right = 32
	title.pad_bottom = 6
	title.set_font(ThemeBuilder.display_font())
	title.set_shader_material(_flame_material())
	brand.add_child(title)

	var subtitle: ShadedLabel = ShadedLabelScn.new()
	subtitle.name = "Subtitle"
	subtitle.text = "pédale su'l'coin d'la yeule".to_upper()
	subtitle.font_size = SUBTITLE_SIZE
	subtitle.pad_left = title.pad_left
	subtitle.pad_right = title.pad_right
	subtitle.pad_top = 2
	subtitle.pad_bottom = 12
	subtitle.set_font(ThemeBuilder.display_font())
	subtitle.set_shader_material(_chrome_material())
	brand.add_child(subtitle)

	await _align_subtitle_width(title, subtitle)


func _align_subtitle_width(title: ShadedLabel, subtitle: ShadedLabel) -> void:
	# Laisse le titre finir son raster avant de mesurer l'encre des lettres
	# (seuil haut pour ignorer les langues de feu).
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var ink := title.get_ink_rect(0.55)
	var target_w := ink.size.x
	var target_left := ink.position.x
	if target_w <= 1.0:
		target_w = title.get_glyph_size().x
		target_left = float(title.pad_left)
	subtitle.pad_left = int(round(target_left))
	subtitle.pad_right = maxi(
		8, int(round(title.custom_minimum_size.x - target_left - target_w))
	)
	await subtitle.fit_glyph_width(target_w)
	# Affine : aligne le bord gauche d'encre du sous-titre sur celui du titre,
	# puis corrige le scale pour coller aussi le bord droit.
	await get_tree().process_frame
	var sub_ink := subtitle.get_ink_rect(0.25)
	if sub_ink.size.x > 1.0:
		var dx := int(round(target_left - sub_ink.position.x))
		if dx != 0:
			subtitle.pad_left = maxi(0, subtitle.pad_left + dx)
			await subtitle._force_refresh()
			sub_ink = subtitle.get_ink_rect(0.25)
		if sub_ink.size.x > 1.0 and absf(sub_ink.size.x - target_w) > 0.5:
			var sx := subtitle._display.scale.x * (target_w / sub_ink.size.x)
			subtitle._display.scale = Vector2(sx, 1.0)
			subtitle._lock_glyph_width = target_w
			subtitle.custom_minimum_size.x = (
				float(subtitle.pad_left) + target_w + float(subtitle.pad_right)
			)


func _apply_actions() -> void:
	%PlayButton.theme_type_variation = &"Primary"


func _flame_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	mat.set_shader_parameter("flame_core", Vector3(1.0, 0.98, 0.55))
	mat.set_shader_parameter("flame_mid", Vector3(1.0, 0.38, 0.0))
	mat.set_shader_parameter("flame_tip", Vector3(1.0, 0.06, 0.0))
	mat.set_shader_parameter("flame_height", 72.0)
	mat.set_shader_parameter("lean", 0.72)
	mat.set_shader_parameter("rise_speed", 3.0)
	mat.set_shader_parameter("intensity", 1.55)
	return mat


func _chrome_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CHROME_SHADER
	mat.set_shader_parameter("metal_dark", Vector3(0.34, 0.36, 0.4))
	mat.set_shader_parameter("metal_mid", Vector3(0.62, 0.64, 0.68))
	mat.set_shader_parameter("metal_light", Vector3(0.88, 0.9, 0.93))
	mat.set_shader_parameter("env_tint", Vector3(0.42, 0.55, 0.66))
	mat.set_shader_parameter("gloss", 0.52)
	mat.set_shader_parameter("emboss_width", 2.1)
	mat.set_shader_parameter("emboss_strength", 0.55)
	return mat


func _build_kerb() -> void:
	var kerb := Kerb.new()
	kerb.set_anchors_preset(Control.PRESET_TOP_WIDE)
	kerb.offset_bottom = 10
	kerb.stripe_width = 22.0
	kerb.slant = 14.0
	kerb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(kerb)
	move_child(kerb, 1)
	kerb.animate(40.0)


func _build_grain_overlay() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GRAIN_SHADER
	var overlay := ColorRect.new()
	overlay.material = mat
	overlay.color = Color.WHITE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/local_race_setup.tscn")


func _on_lobby_pressed() -> void:
	Game.set_mode(Game.Mode.LOCAL)
	get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _on_spline_track_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/spline_track_picker.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
