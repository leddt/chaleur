extends Control

const FLAME_SHADER := preload("res://shaders/flame_text.gdshader")
const CHROME_SHADER := preload("res://shaders/chrome_text.gdshader")

const NARROW_WIDTH := 900.0


func _ready() -> void:
	_apply_background()
	_style_brand()
	_apply_actions()
	_start_kerb()
	resized.connect(_adapt_layout)
	_adapt_layout()


func _apply_background() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = Palette.ASPHALT


func _style_brand() -> void:
	var title := %Title as ShadedLabel
	title.set_font(ThemeBuilder.display_font())
	title.set_shader_material(_flame_material())
	var subtitle := %Subtitle as ShadedLabel
	subtitle.set_font(ThemeBuilder.display_font())
	subtitle.set_shader_material(_chrome_material())
	_align_subtitle_width(title, subtitle)


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


func _start_kerb() -> void:
	var kerb := get_node_or_null("Kerb") as Kerb
	if kerb != null:
		kerb.animate(40.0)


func _adapt_layout() -> void:
	var row := %Row as BoxContainer
	if row == null:
		return
	row.vertical = size.x < NARROW_WIDTH


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


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/local_race_setup.tscn")


func _on_lobby_pressed() -> void:
	Game.set_mode(Game.Mode.LOCAL)
	get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _on_spline_track_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/spline_track_picker.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
