class_name PlayersHud
extends HBoxContainer

## Header chips in this round's turn order. P1/P2 labels follow live race place.

var _chips: Dictionary = {} ## player_id -> Control


func refresh(engine: HeatGameEngine, local_player_id: int = -1) -> void:
	if engine == null:
		_clear_chips()
		return
	var pending := engine.pending_actor_ids()
	var seen: Dictionary = {}
	var index := 0
	for p in engine.round_order():
		seen[p.id] = true
		var chip := _chips.get(p.id) as Control
		if chip == null or not is_instance_valid(chip):
			chip = _build_chip(engine, p, engine.race_place(p.id), pending, local_player_id)
			_chips[p.id] = chip
			add_child(chip)
		else:
			_update_chip(chip, engine, p, engine.race_place(p.id), pending, local_player_id)
		move_child(chip, index)
		index += 1
	var stale: Array = []
	for id in _chips.keys():
		if not seen.has(id):
			stale.append(id)
	for id in stale:
		var old: Control = _chips[id]
		_chips.erase(id)
		if is_instance_valid(old):
			old.queue_free()


func _clear_chips() -> void:
	for id in _chips.keys():
		var chip: Control = _chips[id]
		if is_instance_valid(chip):
			chip.queue_free()
	_chips.clear()
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

	var _clip: Control
	var _front: Label
	var _back: Label
	var _place := 0
	var _tween: Tween

	func setup(seat: Color) -> void:
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
		_clip.clip_contents = true
		_clip.custom_minimum_size = PLATE_SIZE
		_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_clip.resized.connect(_sync_rest_layout)
		add_child(_clip)
		_front = _make_label()
		_back = _make_label()
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
		_slide("P%d" % from, to_text, place > from)

	func _make_label() -> Label:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var display := ThemeBuilder.display_font()
		if display != null:
			label.add_theme_font_override("font", display)
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Palette.CARDBOARD)
		return label

	func _plate_size() -> Vector2:
		var sz := _clip.size if _clip != null else Vector2.ZERO
		if sz.x < 1.0 or sz.y < 1.0:
			return PLATE_SIZE
		return sz

	func _sync_rest_layout() -> void:
		if _is_sliding():
			return
		var sz := _plate_size()
		_front.size = sz
		_front.position = Vector2.ZERO
		_back.size = sz
		_back.position = Vector2.ZERO

	func _snap(text: String) -> void:
		_kill()
		_front.text = text
		_back.visible = false
		_sync_rest_layout()

	func _slide(from_text: String, to_text: String, worse: bool) -> void:
		_kill()
		var sz := _plate_size()
		_front.text = from_text
		_back.text = to_text
		_front.size = sz
		_back.size = sz
		_front.position = Vector2.ZERO
		_back.position = Vector2(0.0, sz.y if worse else -sz.y)
		_back.visible = true
		var delta := -sz.y if worse else sz.y
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.set_parallel(true)
		_tween.tween_property(_front, "position:y", delta, SLIDE_SEC)
		_tween.tween_property(_back, "position:y", 0.0, SLIDE_SEC)
		_tween.set_parallel(false)
		_tween.tween_callback(_finish_slide)

	func _finish_slide() -> void:
		_front.text = _back.text
		_back.visible = false
		_kill()
		_sync_rest_layout()

	func _is_sliding() -> bool:
		return _tween != null and is_instance_valid(_tween) and _tween.is_running()

	func _kill() -> void:
		if _tween != null and is_instance_valid(_tween):
			_tween.kill()
		_tween = null
