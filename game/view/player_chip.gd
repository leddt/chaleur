class_name PlayerChip
extends HBoxContainer

var _reel
var _body: PanelContainer
var _mark: Label
var _name: Label
var _stats: Label


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_body = $Body
	_mark = $Body/Col/NameRow/Mark
	_name = $Body/Col/NameRow/NameLabel
	_stats = $Body/Col/Stats
	_stats.theme_type_variation = "Eyebrow"
	_reel = PlaceReel.new()
	add_child(_reel)
	move_child(_reel, 0)


func bind_seat(seat: Color) -> void:
	if _reel == null:
		return
	_reel.setup(seat)


func apply(
	engine: HeatGameEngine,
	p: PlayerState,
	place: int,
	pending: Array[int],
	local_player_id: int,
	animate_place: bool,
) -> void:
	var seat := PlayerPalette.color_for(p.id)
	bind_seat(seat)
	var acting := _is_acting(engine, p, pending)
	_body.add_theme_stylebox_override("panel", _body_style(seat, acting))
	_mark.text = _ready_mark(engine, p, pending)
	_mark.add_theme_color_override("font_color", seat if acting else Palette.SMOKE)
	_name.text = p.display_name
	_name.add_theme_color_override("font_color", seat)
	if local_player_id >= 0 and p.id == local_player_id:
		_name.text += " (toi)"
	_stats.text = _stats_text(p)
	_reel.set_place(place, animate_place)


func _body_style(seat: Color, acting: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = seat * Color(1, 1, 1, 0.16) if acting else Color(0, 0, 0, 0.25)
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _stats_text(p: PlayerState) -> String:
	if p.finished:
		return "ARRIVÉ"
	return "R%d · %d HEAT" % [p.gear, p.engine_heat()]


func _is_acting(engine: HeatGameEngine, p: PlayerState, pending: Array[int]) -> bool:
	match engine.phase:
		HeatGameEngine.Phase.SHIFT_GEARS:
			return not p.gear_locked
		HeatGameEngine.Phase.PLAY_CARDS:
			return not p.cards_locked
		HeatGameEngine.Phase.PLAYER_TURN:
			return p.id in pending
		_:
			return false


func _ready_mark(engine: HeatGameEngine, p: PlayerState, pending: Array[int]) -> String:
	match engine.phase:
		HeatGameEngine.Phase.SHIFT_GEARS:
			return "✓" if p.gear_locked else "…"
		HeatGameEngine.Phase.PLAY_CARDS:
			return "✓" if p.cards_locked else "…"
		HeatGameEngine.Phase.PLAYER_TURN:
			return "▶" if p.id in pending else "·"
		_:
			return "·"


class PlaceReel extends PanelContainer:
	const SLIDE_SEC := 0.64
	const PLATE_SIZE := Vector2(32, 22)
	const FLAME_SHADER := preload("res://shaders/flame_text.gdshader")

	var _clip: Control
	var _front: ShadedLabel
	var _back: ShadedLabel
	var _place := 0
	var _tween: Tween
	var _flame_mat: ShaderMaterial

	func setup(seat: Color) -> void:
		if _clip != null:
			var sb := StyleBoxFlat.new()
			sb.bg_color = seat
			sb.corner_radius_top_left = 4
			sb.corner_radius_bottom_left = 4
			sb.set_content_margin_all(0)
			add_theme_stylebox_override("panel", sb)
			return
		clip_contents = false
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		var box := StyleBoxFlat.new()
		box.bg_color = seat
		box.corner_radius_top_left = 4
		box.corner_radius_bottom_left = 4
		box.set_content_margin_all(0)
		add_theme_stylebox_override("panel", box)
		_clip = Control.new()
		_clip.clip_contents = false
		_clip.custom_minimum_size = PLATE_SIZE
		_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(_clip)
		_front = _make_place_label()
		_back = _make_place_label()
		_clip.add_child(_front)
		_clip.add_child(_back)
		_back.visible = false
		_clip.resized.connect(_sync_rest_layout)
		_sync_rest_layout()

	func set_place(place: int, animate: bool) -> void:
		if place == _place:
			return
		var from := _place
		_place = place
		var to_text := "P%d" % place
		if not animate or from <= 0 or not is_inside_tree():
			_snap(to_text)
			return
		_slide("P%d" % from, to_text, from, place > from)

	func _make_place_label() -> ShadedLabel:
		var label := ShadedLabel.new()
		label.font_size = 16
		label.pad_left = 16
		label.pad_right = 10
		label.pad_top = 32
		label.pad_bottom = 8
		label.set_font(ThemeBuilder.display_font())
		return label

	func _style_place(label: ShadedLabel, place: int, flames: bool = true) -> void:
		if flames and place == 1:
			label.modulate = Color.WHITE
			label.set_shader_material(_flame_material())
		else:
			label.set_shader_material(null)
			label.modulate = Palette.CARDBOARD

	func _flame_material() -> ShaderMaterial:
		if _flame_mat == null:
			_flame_mat = ShaderMaterial.new()
			_flame_mat.shader = FLAME_SHADER
			_flame_mat.set_shader_parameter("flame_core", Vector3(1.0, 0.98, 0.55))
			_flame_mat.set_shader_parameter("flame_mid", Vector3(1.0, 0.38, 0.0))
			_flame_mat.set_shader_parameter("flame_tip", Vector3(1.0, 0.06, 0.0))
			_flame_mat.set_shader_parameter("flame_height", 28.0)
			_flame_mat.set_shader_parameter("lean", 0.72)
			_flame_mat.set_shader_parameter("rise_speed", 3.0)
			_flame_mat.set_shader_parameter("intensity", 1.55)
			_flame_mat.set_shader_parameter("burn_glyph", 0.0)
			_flame_mat.set_shader_parameter("glyph_color", Vector3(Palette.CARDBOARD.r, Palette.CARDBOARD.g, Palette.CARDBOARD.b))
		return _flame_mat

	func _plate_size() -> Vector2:
		var sz := _clip.size if _clip != null else Vector2.ZERO
		if sz.x < 1.0 or sz.y < 1.0:
			return PLATE_SIZE
		return sz

	func _rest_pos(label: ShadedLabel) -> Vector2:
		if label == null:
			return Vector2.ZERO
		var plate := _plate_size()
		var glyph := label.get_glyph_size()
		if glyph.x < 1.0 or glyph.y < 1.0:
			glyph = Vector2(20.0, 18.0)
		return Vector2(
			(plate.x - glyph.x) * 0.5 - float(label.pad_left),
			(plate.y - glyph.y) * 0.5 - float(label.pad_top)
		)

	func _sync_rest_layout() -> void:
		if _front == null or _back == null:
			return
		if _is_sliding():
			return
		_front.position = _rest_pos(_front)
		_back.position = _rest_pos(_back)

	func _set_clipping(clipped: bool) -> void:
		clip_contents = clipped
		if _clip != null:
			_clip.clip_contents = clipped

	func _snap(text: String) -> void:
		_kill()
		_set_clipping(false)
		_front.text = text
		_style_place(_front, _place)
		_back.visible = false
		_sync_rest_layout()

	func _slide(from_text: String, to_text: String, from_place: int, worse: bool) -> void:
		_kill()
		_set_clipping(true)
		var rest := _rest_pos(_front)
		var h := _plate_size().y
		_front.text = from_text
		_back.text = to_text
		_style_place(_front, from_place, false)
		_style_place(_back, _place, false)
		_front.position = rest
		_back.position = Vector2(rest.x, rest.y + (h if worse else -h))
		_back.visible = true
		var to_y := rest.y + (-h if worse else h)
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.set_parallel(true)
		_tween.tween_property(_front, "position:y", to_y, SLIDE_SEC)
		_tween.tween_property(_back, "position:y", rest.y, SLIDE_SEC)
		_tween.set_parallel(false)
		_tween.tween_callback(_finish_slide)

	func _finish_slide() -> void:
		_front.text = _back.text
		_style_place(_front, _place)
		_back.visible = false
		_kill()
		_set_clipping(false)
		_sync_rest_layout()

	func _is_sliding() -> bool:
		return _tween != null and is_instance_valid(_tween) and _tween.is_running()

	func _kill() -> void:
		if _tween != null and is_instance_valid(_tween):
			_tween.kill()
		_tween = null
