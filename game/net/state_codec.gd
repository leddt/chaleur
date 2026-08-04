class_name StateCodec
extends RefCounted

## Encode/decode HeatGameEngine for listen-server snapshots.
## viewer_player_id >= 0 hides other players' exact hands (count only).


static func encode(engine: HeatGameEngine, viewer_player_id: int = -1) -> Dictionary:
	var players: Array = []
	for p in engine.players:
		players.append(_encode_player(p, viewer_player_id))
	return {
		"track": _encode_track(engine.track),
		"phase": int(engine.phase),
		"turn_step": int(engine.turn_step),
		"turn_order": engine.turn_order.duplicate(),
		"turn_index": engine.turn_index,
		"started_player_count": engine.started_player_count,
		"next_finish_rank": engine.next_finish_rank,
		"event_log": engine.event_log.duplicate(),
		"players": players,
		"stress_reserve": _encode_pile(engine.stress_reserve),
		"rng_state": engine.rng.state,
	}


static func decode(data: Dictionary) -> HeatGameEngine:
	var engine := HeatGameEngine.new()
	engine.track = _decode_track(data.get("track", {}))
	engine.phase = data.get("phase", 0) as HeatGameEngine.Phase
	engine.turn_step = data.get("turn_step", 0) as HeatGameEngine.TurnStep
	engine.turn_order.clear()
	for id in data.get("turn_order", []):
		engine.turn_order.append(int(id))
	engine.turn_index = int(data.get("turn_index", 0))
	engine.started_player_count = int(data.get("started_player_count", 0))
	engine.next_finish_rank = int(data.get("next_finish_rank", 1))
	engine.event_log.clear()
	for line in data.get("event_log", []):
		engine.event_log.append(str(line))
	engine.players.clear()
	for pdata in data.get("players", []):
		engine.players.append(_decode_player(pdata))
	engine.stress_reserve = _decode_pile(data.get("stress_reserve", []))
	engine.rng.state = int(data.get("rng_state", 0))
	return engine


static func _encode_track(track: HeatTrack) -> Dictionary:
	var corners: Array = []
	for c in track.corners:
		corners.append({"from_space": c.from_space, "speed_limit": c.speed_limit, "id": c.id})
	return {
		"id": track.id,
		"space_count": track.space_count,
		"spots": track.spots.duplicate(),
		"corners": corners,
		"laps": track.laps,
		"start_heat": track.start_heat,
		"start_stress": track.start_stress,
		"start_behind_finish_line": track.start_behind_finish_line,
		"start_max_per_space": track.start_max_per_space,
	}


static func _decode_track(data: Dictionary) -> HeatTrack:
	var track := HeatTrack.new()
	track.id = str(data.get("id", "usa_simplified"))
	track.space_count = int(data.get("space_count", 24))
	track.spots.clear()
	for s in data.get("spots", []):
		track.spots.append(int(s))
	track.corners.clear()
	for c in data.get("corners", []):
		track.corners.append(HeatCorner.new(int(c.get("from_space", 0)), int(c.get("speed_limit", 0)), str(c.get("id", ""))))
	track.laps = int(data.get("laps", 1))
	track.start_heat = int(data.get("start_heat", 6))
	track.start_stress = int(data.get("start_stress", 3))
	track.start_behind_finish_line = bool(data.get("start_behind_finish_line", false))
	track.start_max_per_space = int(data.get("start_max_per_space", 2))
	return track


static func _encode_player(p: PlayerState, viewer_player_id: int) -> Dictionary:
	var show_hand := viewer_player_id < 0 or viewer_player_id == p.id
	var show_pending := show_hand
	return {
		"id": p.id,
		"display_name": p.display_name,
		"gear": p.gear,
		"progress": p.progress,
		"spot": p.spot,
		"finished": p.finished,
		"finish_rank": p.finish_rank,
		"draw_pile": _encode_pile(p.draw_pile) if show_hand else [],
		"hand": _encode_pile(p.hand) if show_hand else [],
		"hand_count": p.hand.size(),
		"hand_hidden": not show_hand,
		"play_area": _encode_pile(p.play_area),
		"discard": _encode_pile(p.discard),
		"engine": _encode_pile(p.engine),
		"gear_locked": p.gear_locked,
		"pending_gear": p.pending_gear if show_pending else -1,
		"cards_locked": p.cards_locked,
		"skipped_move": p.skipped_move,
		"round_speed": p.round_speed,
		"corners_crossed": p.corners_crossed.duplicate(),
		"has_adrenaline": p.has_adrenaline,
		"boost_used": p.boost_used,
		"turn_complete": p.turn_complete,
	}


static func _decode_player(data: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.id = int(data.get("id", 0))
	p.display_name = str(data.get("display_name", "?"))
	p.gear = int(data.get("gear", 1))
	p.progress = int(data.get("progress", 0))
	p.spot = int(data.get("spot", 0))
	p.finished = bool(data.get("finished", false))
	p.finish_rank = int(data.get("finish_rank", -1))
	p.draw_pile = _decode_pile(data.get("draw_pile", []))
	p.hand = _decode_pile(data.get("hand", []))
	if bool(data.get("hand_hidden", false)) and p.hand.is_empty():
		# Placeholder backs so UI can show count without revealing cards.
		for i in int(data.get("hand_count", 0)):
			p.hand.add(HeatCard.new("hidden_%d_%d" % [p.id, i], HeatCard.Kind.SPEED, 0))
	p.play_area = _decode_pile(data.get("play_area", []))
	p.discard = _decode_pile(data.get("discard", []))
	p.engine = _decode_pile(data.get("engine", []))
	p.gear_locked = bool(data.get("gear_locked", false))
	p.pending_gear = int(data.get("pending_gear", -1))
	p.cards_locked = bool(data.get("cards_locked", false))
	p.skipped_move = bool(data.get("skipped_move", false))
	p.round_speed = int(data.get("round_speed", 0))
	p.corners_crossed.clear()
	for c in data.get("corners_crossed", []):
		p.corners_crossed.append(str(c))
	p.has_adrenaline = bool(data.get("has_adrenaline", false))
	p.boost_used = bool(data.get("boost_used", false))
	p.turn_complete = bool(data.get("turn_complete", false))
	return p


static func _encode_pile(pile: CardPile) -> Array:
	var out: Array = []
	for card in pile.cards:
		out.append({"id": card.id, "kind": int(card.kind), "speed_value": card.speed_value})
	return out


static func _decode_pile(data: Array) -> CardPile:
	var pile := CardPile.new()
	for c in data:
		pile.add(HeatCard.new(str(c.get("id", "")), c.get("kind", 0) as HeatCard.Kind, int(c.get("speed_value", 0))))
	return pile
