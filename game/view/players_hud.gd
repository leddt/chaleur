class_name PlayersHud
extends HBoxContainer

## Header row of per-player status chips.


func refresh(engine: HeatGameEngine, local_player_id: int = -1) -> void:
	for child in get_children():
		child.queue_free()
	if engine == null:
		return
	var pending := engine.pending_actor_ids()
	for p in engine.players:
		var row := Label.new()
		var mark := _ready_mark(engine, p, pending)
		var fin := ""
		if p.finished:
			fin = " FIN#%d" % p.finish_rank if p.finish_rank > 0 else " FIN"
		var you := " (toi)" if local_player_id >= 0 and p.id == local_player_id else ""
		row.text = "%s %s%s | G%d H%d P%d%s" % [
			mark,
			p.display_name,
			you,
			p.gear,
			p.engine_heat(),
			p.progress,
			fin,
		]
		row.add_theme_color_override("font_color", PlayerPalette.color_for(p.id))
		row.add_theme_font_size_override("font_size", 13)
		add_child(row)


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
