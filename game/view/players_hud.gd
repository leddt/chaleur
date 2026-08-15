class_name PlayersHud
extends HBoxContainer

## Header chips in this round's turn order. P1/P2 labels follow live race place.

const REORDER_SEC := 0.64

var _slots: Dictionary = {} ## player_id -> slot Control
var _order_ids: Array[int] = []
var _reorder_gen := 0


func refresh(engine: HeatGameEngine, local_player_id: int = -1) -> void:
	if engine == null:
		_clear_chips()
		return
	clip_contents = false
	var pending := engine.pending_actor_ids()
	var old_visual: Dictionary = {}
	for id in _slots.keys():
		var slot: Control = _slots[id]
		var chip: Control = slot.get_meta("chip")
		if is_instance_valid(chip):
			old_visual[id] = chip.global_position
	var seen: Dictionary = {}
	var new_order: Array[int] = []
	var index := 0
	for p in engine.round_order():
		seen[p.id] = true
		new_order.append(p.id)
		var slot := _slots.get(p.id) as Control
		if slot == null or not is_instance_valid(slot):
			var chip := _build_chip(engine, p, engine.race_place(p.id), pending, local_player_id)
			slot = _wrap_slot(chip)
			_slots[p.id] = slot
			add_child(slot)
		else:
			_update_chip(slot.get_meta("chip"), engine, p, engine.race_place(p.id), pending, local_player_id)
		move_child(slot, index)
		index += 1
	var stale: Array = []
	for id in _slots.keys():
		if not seen.has(id):
			stale.append(id)
	for id in stale:
		var old: Control = _slots[id]
		_slots.erase(id)
		if is_instance_valid(old):
			old.queue_free()
	var order_changed := not _ids_equal(_order_ids, new_order)
	_order_ids = new_order
	if order_changed and not old_visual.is_empty():
		_queue_reorder(old_visual)


func _wrap_slot(chip: Control) -> Control:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.set_meta("chip", chip)
	chip.resized.connect(func() -> void: _fit_slot(slot, chip))
	slot.add_child(chip)
	_fit_slot(slot, chip)
	return slot


func _fit_slot(slot: Control, chip: Control) -> void:
	if not is_instance_valid(slot) or not is_instance_valid(chip):
		return
	var ms := chip.get_combined_minimum_size()
	if chip.size.x > ms.x:
		ms.x = chip.size.x
	if chip.size.y > ms.y:
		ms.y = chip.size.y
	slot.custom_minimum_size = ms


func _ids_equal(a: Array[int], b: Array[int]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _queue_reorder(old_visual: Dictionary) -> void:
	_reorder_gen += 1
	var gen := _reorder_gen
	_play_reorder.call_deferred(old_visual, gen)


func _play_reorder(old_visual: Dictionary, gen: int) -> void:
	if gen != _reorder_gen:
		return
	for id in _slots.keys():
		if not old_visual.has(id):
			continue
		var slot: Control = _slots[id]
		if not is_instance_valid(slot):
			continue
		var chip: Control = slot.get_meta("chip")
		if not is_instance_valid(chip):
			continue
		var dest := slot.global_position
		var start: Vector2 = old_visual[id]
		var delta := start - dest
		_kill_move_tween(chip)
		if delta.length() < 0.5:
			chip.position = Vector2.ZERO
			continue
		chip.position = delta
		chip.z_index = 2
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		chip.set_meta("move_tween", tw)
		tw.tween_property(chip, "position", Vector2.ZERO, REORDER_SEC)
		tw.tween_callback(
			func() -> void:
				if is_instance_valid(chip):
					chip.z_index = 0
		)


func _kill_move_tween(chip: Control) -> void:
	if not chip.has_meta("move_tween"):
		return
	var tw: Tween = chip.get_meta("move_tween")
	if tw != null and is_instance_valid(tw):
		tw.kill()
	chip.remove_meta("move_tween")


func _clear_chips() -> void:
	_reorder_gen += 1
	_order_ids.clear()
	for id in _slots.keys():
		var slot: Control = _slots[id]
		if is_instance_valid(slot):
			slot.queue_free()
	_slots.clear()
	for child in get_children():
		child.queue_free()


func _build_chip(
	engine: HeatGameEngine,
	p: PlayerState,
	place: int,
	pending: Array[int],
	local_player_id: int,
) -> Control:
	var seat := PlayerPalette.color_for(p.id)
	var acting := _is_acting(engine, p, pending)

	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 0)

	var reel := PlaceReel.new()
	reel.setup(seat)
	chip.add_child(reel)
	reel.set_place(place, false)

	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", _body_style(seat, acting))
	chip.add_child(body)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	body.add_child(col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 5)
	col.add_child(name_row)

	var mark := Label.new()
	mark.add_theme_font_size_override("font_size", 12)
	name_row.add_child(mark)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", seat)
	name_row.add_child(name_label)

	var stats := Label.new()
	stats.theme_type_variation = "Eyebrow"
	col.add_child(stats)

	chip.set_meta("reel", reel)
	chip.set_meta("body", body)
	chip.set_meta("mark", mark)
	chip.set_meta("name", name_label)
	chip.set_meta("stats", stats)
	_fill_chip(chip, engine, p, place, pending, local_player_id, false)
	return chip


func _update_chip(
	chip: Control,
	engine: HeatGameEngine,
	p: PlayerState,
	place: int,
	pending: Array[int],
	local_player_id: int,
) -> void:
	_fill_chip(chip, engine, p, place, pending, local_player_id, true)


func _fill_chip(
	chip: Control,
	engine: HeatGameEngine,
	p: PlayerState,
	place: int,
	pending: Array[int],
	local_player_id: int,
	animate_place: bool,
) -> void:
	var seat := PlayerPalette.color_for(p.id)
	var acting := _is_acting(engine, p, pending)
	var body: PanelContainer = chip.get_meta("body")
	body.add_theme_stylebox_override("panel", _body_style(seat, acting))
	var mark: Label = chip.get_meta("mark")
	mark.text = _ready_mark(engine, p, pending)
	mark.add_theme_color_override("font_color", seat if acting else Palette.SMOKE)
	var name_label: Label = chip.get_meta("name")
	name_label.text = p.display_name
	if local_player_id >= 0 and p.id == local_player_id:
		name_label.text += " (toi)"
	var stats: Label = chip.get_meta("stats")
	stats.text = _stats_text(p)
	var reel: PlaceReel = chip.get_meta("reel")
	reel.set_place(place, animate_place)


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
		clip_contents = false
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = seat
		sb.corner_radius_top_left = 4
		sb.corner_radius_bottom_left = 4
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		add_theme_stylebox_override("panel", sb)
		_clip = Control.new()
		_clip.clip_contents = false
		_clip.custom_minimum_size = PLATE_SIZE
		_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_clip.resized.connect(_sync_rest_layout)
		add_child(_clip)
		_front = _make_place_label()
		_back = _make_place_label()
		_clip.add_child(_front)
		_clip.add_child(_back)
		_back.visible = false
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
		var plate := _plate_size()
		var glyph := label.get_glyph_size()
		if glyph.x < 1.0 or glyph.y < 1.0:
			glyph = Vector2(20.0, 18.0)
		return Vector2(
			(plate.x - glyph.x) * 0.5 - float(label.pad_left),
			(plate.y - glyph.y) * 0.5 - float(label.pad_top)
		)

	func _sync_rest_layout() -> void:
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
