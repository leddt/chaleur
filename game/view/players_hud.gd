class_name PlayersHud
extends HBoxContainer

## Header row of per-player seat chips.
##
## The previous version packed name, gear, heat, progress and status into one
## string per player ("… Alice | G1 H6 P-1"), which read as noise. Here the seat
## colour and the state mark carry the glanceable part and the numbers sit under
## the name, so a row of chips can be scanned without being read.


func refresh(engine: HeatGameEngine, local_player_id: int = -1) -> void:
	for child in get_children():
		child.queue_free()
	if engine == null:
		return
	var pending := engine.pending_actor_ids()
	for p in engine.players:
		add_child(_build_chip(engine, p, pending, local_player_id))


func _build_chip(
	engine: HeatGameEngine, p: PlayerState, pending: Array[int], local_player_id: int
) -> Control:
	var seat := PlayerPalette.color_for(p.id)
	var acting := _is_acting(engine, p, pending)

	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = seat * Color(1, 1, 1, 0.16) if acting else Color(0, 0, 0, 0.25)
	sb.set_corner_radius_all(4)
	sb.border_color = seat if acting else seat * Color(1, 1, 1, 0.35)
	sb.border_width_left = 4
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	chip.add_child(col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 5)
	col.add_child(name_row)

	var mark := Label.new()
	mark.text = _ready_mark(engine, p, pending)
	mark.add_theme_font_size_override("font_size", 12)
	mark.add_theme_color_override("font_color", seat if acting else Palette.SMOKE)
	name_row.add_child(mark)

	var name_label := Label.new()
	name_label.text = p.display_name
	if local_player_id >= 0 and p.id == local_player_id:
		name_label.text += " (toi)"
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", seat)
	name_row.add_child(name_label)

	var stats := Label.new()
	stats.text = _stats_text(p)
	stats.theme_type_variation = "Eyebrow"
	col.add_child(stats)

	return chip


func _stats_text(p: PlayerState) -> String:
	if p.finished:
		return "ARRIVÉ #%d" % p.finish_rank if p.finish_rank > 0 else "ARRIVÉ"
	# Progress is negative until the car crosses the start line; "CASE -1" means
	# nothing to a player, "GRILLE" does.
	var place := "GRILLE" if p.progress < 0 else "CASE %d" % p.progress
	return "R%d · %d HEAT · %s" % [p.gear, p.engine_heat(), place]


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
