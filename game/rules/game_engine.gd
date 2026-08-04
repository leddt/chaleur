class_name HeatGameEngine
extends RefCounted

enum Phase {
	SETUP,
	SHIFT_GEARS,
	PLAY_CARDS,
	PLAYER_TURN,
	RACE_OVER,
}

enum TurnStep {
	REVEAL_MOVE,
	REACT,
	SLIPSTREAM,
	CHECK_CORNER,
	DISCARD,
	REPLENISH,
}

var track: HeatTrack
var players: Array[PlayerState] = []
var stress_reserve: CardPile = CardPile.new()
var rng := RandomNumberGenerator.new()
var event_log: Array[String] = []

var phase: Phase = Phase.SETUP
var turn_step: TurnStep = TurnStep.REVEAL_MOVE
var turn_order: Array[int] = []
var turn_index: int = 0
var started_player_count: int = 0
var next_finish_rank: int = 1


func setup(player_names: Array[String], p_track: HeatTrack, seed: int = 1) -> void:
	track = p_track
	rng.seed = seed
	players.clear()
	event_log.clear()
	stress_reserve = DeckFactory.build_stress_reserve()
	started_player_count = player_names.size()
	next_finish_rank = 1
	for i in player_names.size():
		var p := PlayerState.new()
		p.id = i
		p.display_name = player_names[i]
		p.gear = 1
		p.progress = 0
		p.spot = i % track.spot_count(0)
		p.draw_pile.add_many(DeckFactory.build_starter_draw(i, track.start_stress))
		p.draw_pile.shuffle(rng)
		p.engine.add_many(DeckFactory.build_engine_heat(i, track.start_heat))
		_draw_up_to(p, 7)
		players.append(p)
	_assign_unique_start_spots()
	phase = Phase.SHIFT_GEARS
	_log("Race setup on %s (%d laps), seed=%d" % [track.id, track.laps, seed])


func active_player() -> PlayerState:
	if phase != Phase.PLAYER_TURN or turn_order.is_empty():
		return null
	return players[turn_order[turn_index]]


## Players who still need to act in the current simultaneous/turn phase (UI helper).
func pending_actor_ids() -> Array[int]:
	var ids: Array[int] = []
	match phase:
		Phase.SHIFT_GEARS:
			for p in players:
				if not p.finished and not p.gear_locked:
					ids.append(p.id)
		Phase.PLAY_CARDS:
			for p in players:
				if not p.finished and not p.cards_locked:
					ids.append(p.id)
		Phase.PLAYER_TURN:
			# Still include a player who just crossed the finish line — they must
			# complete React (and skip to replenish). Excluding them softlocks the UI
			# and prevents later cars from taking the rest of the round / race.
			var ap := active_player()
			if ap != null:
				ids.append(ap.id)
		_:
			pass
	return ids


func is_slipstream_available() -> bool:
	return phase == Phase.PLAYER_TURN and turn_step == TurnStep.SLIPSTREAM



func dump_state() -> String:
	var lines: PackedStringArray = []
	lines.append("phase=%s turn_step=%s" % [str(phase), str(turn_step)])
	for p in players:
		lines.append(
			(
				"%s gear=%d prog=%d spot=%d heat=%d hand=%d finished=%s"
				% [p.display_name, p.gear, p.progress, p.spot, p.engine_heat(), p.hand.size(), str(p.finished)]
			)
		)
	return "\n".join(lines)


# --- Public actions ---------------------------------------------------------

func shift_gear(player_id: int, target_gear: int) -> ActionResult:
	if phase != Phase.SHIFT_GEARS:
		return ActionResult.fail("Not in SHIFT_GEARS phase")
	var p := _player(player_id)
	if p == null or p.finished:
		return ActionResult.fail("Invalid player")
	if p.gear_locked:
		return ActionResult.fail("Gear already locked")
	if target_gear < 1 or target_gear > 4:
		return ActionResult.fail("Gear must be 1-4")
	var delta := absi(target_gear - p.gear)
	if delta > 2:
		return ActionResult.fail("Cannot shift more than 2 gears")
	if delta == 2 and p.engine_heat() < 1:
		return ActionResult.fail("Not enough Heat to shift 2 gears")
	# Apply and announce only once everyone has locked (simultaneous reveal).
	p.pending_gear = target_gear
	p.gear_locked = true
	_try_advance_from_shift()
	return ActionResult.success()


func play_cards(player_id: int, card_ids: Array[String]) -> ActionResult:
	if phase != Phase.PLAY_CARDS:
		return ActionResult.fail("Not in PLAY_CARDS phase")
	var p := _player(player_id)
	if p == null or p.finished:
		return ActionResult.fail("Invalid player")
	if p.cards_locked:
		return ActionResult.fail("Cards already locked")

	var playable := p.playable_in_hand()
	var required := p.gear
	var cluttered := playable.size() < required

	if cluttered:
		var expected := playable.size() + (required - playable.size())
		if card_ids.size() != expected:
			return ActionResult.fail("Cluttered hand: play all playable plus Heat fillers")
		for cid in card_ids:
			var card := p.hand.get_by_id(cid)
			if card == null:
				return ActionResult.fail("Card not in hand: %s" % cid)
		var heat_fillers := 0
		for cid in card_ids:
			var card := p.hand.get_by_id(cid)
			if card.kind == HeatCard.Kind.HEAT:
				heat_fillers += 1
			elif not card.is_playable():
				return ActionResult.fail("Unplayable card")
		if heat_fillers != required - playable.size():
			return ActionResult.fail("Wrong number of Heat fillers")
		for card in playable:
			if card.id not in card_ids:
				return ActionResult.fail("Must play all playable cards when cluttered")
		p.skipped_move = true
	else:
		if card_ids.size() != required:
			return ActionResult.fail("Must play exactly %d cards" % required)
		for cid in card_ids:
			var card := p.hand.get_by_id(cid)
			if card == null:
				return ActionResult.fail("Card not in hand: %s" % cid)
			if not card.is_playable():
				return ActionResult.fail("Cannot play Heat from hand")

	for cid in card_ids:
		var card := p.hand.remove_id(cid)
		p.play_area.add(card)

	p.cards_locked = true
	_log("%s plays %d card(s)%s" % [p.display_name, card_ids.size(), " (cluttered)" if p.skipped_move else ""])
	_try_advance_from_play()
	return ActionResult.success()


func react(player_id: int, cooldown: int, boost: bool, adrenaline_speed: bool) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.REACT:
		return ActionResult.fail("Not in REACT step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")

	var max_cd := p.cooldown_from_gear()
	if p.has_adrenaline:
		max_cd += 1
	if cooldown < 0 or cooldown > max_cd:
		return ActionResult.fail("Invalid cooldown amount")
	if cooldown > p.hand.count_kind(HeatCard.Kind.HEAT):
		return ActionResult.fail("Not enough Heat in hand to cooldown")
	if boost:
		if not p.can_boost_from_gear():
			return ActionResult.fail("Boost not available in this gear")
		if p.engine_heat() < 1:
			return ActionResult.fail("Not enough Heat to boost")
	if adrenaline_speed and not p.has_adrenaline:
		return ActionResult.fail("No adrenaline")

	# Apply cooldown
	for _i in cooldown:
		var heat := _take_heat_from_hand(p)
		if heat:
			p.engine.add(heat)
	if cooldown > 0:
		_log("%s cools down %d" % [p.display_name, cooldown])

	# Adrenaline speed and boost may be ordered either way; apply adrenaline first then boost by default.
	if adrenaline_speed:
		p.round_speed += 1
		_move_player(p, 1, false)
		_log("%s uses adrenaline +1 speed" % p.display_name)

	if boost:
		_pay_heat(p, 1)
		var speed_card := _flip_until_speed(p)
		if speed_card == null:
			return ActionResult.fail("Boost failed: no Speed card available")
		p.play_area.add(speed_card)
		p.round_speed += speed_card.speed_value
		p.boost_used = true
		_move_player(p, speed_card.speed_value, false)
		_log("%s boosts for +%d" % [p.display_name, speed_card.speed_value])

	_check_finish(p)
	turn_step = TurnStep.SLIPSTREAM
	if not _slipstream_eligible(p):
		return _auto_skip_slipstream(p)
	return ActionResult.success()


func slipstream(player_id: int, use: bool) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.SLIPSTREAM:
		return ActionResult.fail("Not in SLIPSTREAM step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	if use:
		if not _slipstream_eligible(p):
			return ActionResult.fail("Slipstream not eligible")
		_move_player(p, 2, true)
		_log("%s slipstreams +2" % p.display_name)
		_check_finish(p)
	return _after_slipstream(p)


func discard_cards(player_id: int, card_ids: Array[String]) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.DISCARD:
		return ActionResult.fail("Not in DISCARD step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	for cid in card_ids:
		var card := p.hand.get_by_id(cid)
		if card == null:
			return ActionResult.fail("Card not in hand")
		if card.kind == HeatCard.Kind.HEAT or card.kind == HeatCard.Kind.STRESS:
			return ActionResult.fail("Cannot discard Heat or Stress")
		# Starting upgrades also cannot be discarded per p.6 note ("even the Upgrade ones") for Stress/Heat —
		# the note says: never discard Stress or Heat (even the Upgrade ones) — meaning upgrade variants of those.
		# Speed/Upgrade speed cards may be discarded.
	for cid in card_ids:
		var card := p.hand.remove_id(cid)
		p.discard.add(card)
	if not card_ids.is_empty():
		_log("%s discards %d card(s)" % [p.display_name, card_ids.size()])
	return _replenish_and_advance(p)


# --- Internals --------------------------------------------------------------

func _player(player_id: int) -> PlayerState:
	for p in players:
		if p.id == player_id:
			return p
	return null


func _log(line: String) -> void:
	event_log.append(line)


func _assign_unique_start_spots() -> void:
	if track.start_behind_finish_line:
		# Behind the start/finish line: last spaces of the final sector.
		# progress -1 => space (n-1), -2 => (n-2), … ; max 2 cars per space.
		var per_space := maxi(1, track.start_max_per_space)
		for i in players.size():
			var row := int(i / per_space)
			var spot := i % per_space
			players[i].progress = -(row + 1)
			var space := track.space_of_progress(players[i].progress)
			var cap := track.spot_count(space)
			players[i].spot = mini(spot, maxi(cap - 1, 0))
		return
	var max_spots := track.spot_count(0)
	for i in players.size():
		players[i].progress = 0
		players[i].spot = i % maxi(max_spots, 1)


func _draw_up_to(p: PlayerState, target: int) -> void:
	while p.hand.size() < target:
		if p.draw_pile.is_empty():
			if p.discard.is_empty():
				break
			p.draw_pile.add_many(p.discard.cards)
			p.discard.clear()
			p.draw_pile.shuffle(rng)
		var card := p.draw_pile.draw_top()
		if card == null:
			break
		p.hand.add(card)


func _pay_heat(p: PlayerState, amount: int) -> bool:
	if p.engine_heat() < amount:
		return false
	for _i in amount:
		var heat := _take_heat_from_engine(p)
		if heat == null:
			return false
		p.discard.add(heat)
	return true


func _take_heat_from_engine(p: PlayerState) -> HeatCard:
	for i in p.engine.cards.size():
		if p.engine.cards[i].kind == HeatCard.Kind.HEAT:
			return p.engine.remove_at(i)
	return null


func _take_heat_from_hand(p: PlayerState) -> HeatCard:
	for i in p.hand.cards.size():
		if p.hand.cards[i].kind == HeatCard.Kind.HEAT:
			return p.hand.remove_at(i)
	return null


func _try_advance_from_shift() -> void:
	for p in players:
		if not p.finished and not p.gear_locked:
			return
	_reveal_locked_gears()
	phase = Phase.PLAY_CARDS
	_log("All gears locked — play cards")


func _reveal_locked_gears() -> void:
	for p in players:
		if p.finished or p.pending_gear < 1:
			continue
		var from_gear := p.gear
		var target := p.pending_gear
		var delta := absi(target - from_gear)
		if delta == 2:
			if not _pay_heat(p, 1):
				# Validated at lock time; still guard state consistency.
				push_warning("Missing Heat for double shift on reveal for %s" % p.display_name)
			else:
				_log("%s pays 1 Heat for double shift" % p.display_name)
		p.gear = target
		p.pending_gear = -1
		_log("%s shifts to gear %d" % [p.display_name, p.gear])


func _try_advance_from_play() -> void:
	for p in players:
		if not p.finished and not p.cards_locked:
			return
	_begin_turn_order()


func _begin_turn_order() -> void:
	turn_order.clear()
	var active: Array[PlayerState] = []
	for p in players:
		if not p.finished:
			active.append(p)
	active.sort_custom(func(a: PlayerState, b: PlayerState) -> bool:
		if a.progress != b.progress:
			return a.progress > b.progress
		return a.spot < b.spot
	)
	for p in active:
		turn_order.append(p.id)
	# Adrenaline for last / last two based on started count
	var adrenaline_ids: Array[int] = []
	if not turn_order.is_empty():
		adrenaline_ids.append(turn_order[turn_order.size() - 1])
		if started_player_count >= 5 and turn_order.size() >= 2:
			adrenaline_ids.append(turn_order[turn_order.size() - 2])
	for p in players:
		p.has_adrenaline = p.id in adrenaline_ids
	turn_index = 0
	phase = Phase.PLAYER_TURN
	_start_current_turn()


func _start_current_turn() -> void:
	while turn_index < turn_order.size() and players[turn_order[turn_index]].finished:
		turn_index += 1
	if turn_index >= turn_order.size():
		_end_round()
		return
	var p := active_player()
	turn_step = TurnStep.REVEAL_MOVE
	_resolve_reveal_and_move(p)


func _resolve_reveal_and_move(p: PlayerState) -> void:
	if p.skipped_move:
		_log("%s cluttered — no move, gear to 1" % p.display_name)
		p.gear = 1
		for card in p.play_area.cards:
			p.discard.add(card)
		p.play_area.clear()
		turn_step = TurnStep.REPLENISH
		_replenish_and_advance(p)
		return

	# Resolve each Stress by flipping until a Speed card (p. 5).
	for card in p.play_area.cards.duplicate():
		if card.kind != HeatCard.Kind.STRESS:
			continue
		var speed_card := _flip_until_speed(p)
		if speed_card:
			p.play_area.add(speed_card)
			_log("%s resolves Stress -> Speed %d" % [p.display_name, speed_card.speed_value])

	p.round_speed = 0
	for card in p.play_area.cards:
		p.round_speed += card.speed_value

	_move_player(p, p.round_speed, false)
	_log("%s reveals speed %d and moves" % [p.display_name, p.round_speed])
	_check_finish(p)

	turn_step = TurnStep.REACT


func _flip_until_speed(p: PlayerState) -> HeatCard:
	for _i in 1000:
		if p.draw_pile.is_empty():
			if p.discard.is_empty():
				return null
			p.draw_pile.add_many(p.discard.cards)
			p.discard.clear()
			p.draw_pile.shuffle(rng)
		var card := p.draw_pile.draw_top()
		if card == null:
			return null
		if card.is_speed_card():
			return card
		p.discard.add(card)
	return null


func _move_player(p: PlayerState, spaces: int, is_slipstream: bool) -> void:
	if spaces <= 0:
		return
	# Slipstream cannot be used across / after the finish line (rules p. 7).
	if is_slipstream and (p.finished or p.progress >= track.finish_progress()):
		return
	for _i in spaces:
		var already_past_finish := p.progress >= track.finish_progress()
		var from_space := track.space_of_progress(p.progress)
		var corner := track.corner_after(from_space)
		p.progress += 1
		# Corner limits only apply before crossing the finish line.
		if corner != null and not already_past_finish and p.progress < track.finish_progress():
			p.corners_crossed.append(corner.id)
		elif corner != null and not already_past_finish and p.progress >= track.finish_progress():
			# Crossing the finish on this step: ignore that corner and any beyond.
			pass

	# Resolve landing spot / blocking (also past finish for same-space tiebreak).
	_place_on_space(p)


func _place_on_space(p: PlayerState) -> void:
	var space := track.space_of_progress(p.progress)
	var free_spot := _first_free_spot(space, p.id)
	if free_spot >= 0:
		p.spot = free_spot
		return
	# Past the finish line: never bounce backward (keep overshoot for ranking).
	if p.progress >= track.finish_progress():
		p.spot = 0
		return
	# Blocked: step back to first space with a free spot (may go behind start line).
	var guard := track.space_count + players.size() + 4
	while guard > 0:
		guard -= 1
		p.progress -= 1
		space = track.space_of_progress(p.progress)
		free_spot = _first_free_spot(space, p.id)
		if free_spot >= 0:
			p.spot = free_spot
			_log("%s blocked — lands at progress %d spot %d" % [p.display_name, p.progress, p.spot])
			return


func _first_free_spot(space: int, except_player_id: int) -> int:
	var capacity := track.spot_count(space)
	var occupied: Dictionary = {}
	for other in players:
		if other.id == except_player_id:
			continue
		# Finished cars stay on track until end of round — they still occupy spots.
		if track.space_of_progress(other.progress) == space:
			occupied[other.spot] = true
	for spot in capacity:
		if not occupied.has(spot):
			return spot
	return -1


func _check_finish(p: PlayerState) -> void:
	if p.finished:
		return
	if p.progress >= track.finish_progress():
		p.finished = true
		# Rank is assigned at end of round among same-round finishers by distance.
		p.finish_rank = -1
		_log("%s crossed the finish line (progress %d, spot %d)" % [p.display_name, p.progress, p.spot])


func _slipstream_eligible(p: PlayerState) -> bool:
	if p.finished:
		return false
	# After crossing finish on last lap, slipstream not allowed
	if p.progress >= track.finish_progress():
		return false
	var space := track.space_of_progress(p.progress)
	for other in players:
		if other.id == p.id or other.finished:
			continue
		var ospace := track.space_of_progress(other.progress)
		if ospace == space:
			return true
		# Behind another car: other is exactly 1+ spaces ahead on same stretch — "in a Space behind a car"
		if other.progress > p.progress and other.progress - p.progress <= 2:
			# Landed behind (other ahead within immediate vicinity) — rules: end next to OR in a space behind
			if other.progress == p.progress + 1:
				return true
	return false


func _auto_skip_slipstream(p: PlayerState) -> ActionResult:
	return _after_slipstream(p)


func _after_slipstream(p: PlayerState) -> ActionResult:
	turn_step = TurnStep.CHECK_CORNER
	_resolve_corners(p)
	if p.finished:
		return _replenish_and_advance(p)
	turn_step = TurnStep.DISCARD
	return ActionResult.success()


func _resolve_corners(p: PlayerState) -> void:
	# After the finish line, corner limits are disregarded (rules p. 7).
	if p.finished:
		p.corners_crossed.clear()
		return
	var crossings := p.corners_crossed.duplicate()
	p.corners_crossed.clear()
	for corner_id in crossings:
		var corner := _corner_by_id(corner_id)
		if corner == null:
			continue
		var excess := p.round_speed - corner.speed_limit
		if excess <= 0:
			_log("%s clears corner %s (speed %d <= %d)" % [p.display_name, corner_id, p.round_speed, corner.speed_limit])
			continue
		var available := p.engine_heat()
		if available >= excess:
			_pay_heat(p, excess)
			_log("%s pays %d Heat at corner %s" % [p.display_name, excess, corner_id])
		else:
			if available > 0:
				_pay_heat(p, available)
			_spin_out(p, corner)
			break


func _corner_by_id(corner_id: String) -> HeatCorner:
	for corner in track.corners:
		if corner.id == corner_id:
			return corner
	return null


func _spin_out(p: PlayerState, corner: HeatCorner) -> void:
	# Move back to first available space before the corner line (corner.from_space).
	var target_space := corner.from_space
	# Find progress on current lap at target_space, not past finish
	var lap := track.lap_of_progress(maxi(p.progress - 1, 0))
	p.progress = lap * track.space_count + target_space
	_place_on_space(p)
	var stress_n := 1 if p.gear <= 2 else 2
	for _i in stress_n:
		var s := stress_reserve.draw_top()
		if s:
			p.hand.add(s)
	p.gear = 1
	_log("%s spins out at %s — gear 1, +%d Stress" % [p.display_name, corner.id, stress_n])


func _replenish_and_advance(p: PlayerState) -> ActionResult:
	turn_step = TurnStep.REPLENISH
	for card in p.play_area.cards:
		p.discard.add(card)
	p.play_area.clear()
	_draw_up_to(p, 7)
	p.turn_complete = true
	_log("%s replenishes hand (%d)" % [p.display_name, p.hand.size()])
	turn_index += 1
	if turn_index >= turn_order.size():
		_end_round()
	else:
		_start_current_turn()
	return ActionResult.success()


func _end_round() -> void:
	_assign_finish_ranks_for_round()
	var remaining := 0
	for p in players:
		if not p.finished:
			remaining += 1
		p.reset_round_flags()
	if remaining == 0:
		phase = Phase.RACE_OVER
		_log("Race over")
		return
	phase = Phase.SHIFT_GEARS
	_log("New round — shift gears")


## Same-round finishers: furthest progress wins; race-line spot is tiebreaker (p. 7).
func _assign_finish_ranks_for_round() -> void:
	var batch: Array[PlayerState] = []
	for p in players:
		if p.finished and p.finish_rank < 0:
			batch.append(p)
	if batch.is_empty():
		return
	batch.sort_custom(func(a: PlayerState, b: PlayerState) -> bool:
		if a.progress != b.progress:
			return a.progress > b.progress
		return a.spot < b.spot
	)
	for p in batch:
		p.finish_rank = next_finish_rank
		next_finish_rank += 1
		_log("%s placed #%d (progress %d, spot %d)" % [p.display_name, p.finish_rank, p.progress, p.spot])


## Test/debug helper: start PLAYER_TURN with an explicit order after cards are locked.
func debug_begin_turns(order: Array[int]) -> void:
	turn_order = order.duplicate()
	turn_index = 0
	phase = Phase.PLAYER_TURN
	for p in players:
		p.has_adrenaline = false
	if started_player_count >= 5 and turn_order.size() >= 2:
		players[turn_order[turn_order.size() - 1]].has_adrenaline = true
		players[turn_order[turn_order.size() - 2]].has_adrenaline = true
	elif not turn_order.is_empty():
		players[turn_order[turn_order.size() - 1]].has_adrenaline = true
	_start_current_turn()


func is_race_over() -> bool:
	return phase == Phase.RACE_OVER


func ranking() -> Array[PlayerState]:
	# Ensure late callers (e.g. finish overlay mid-last-round) see final order.
	_assign_finish_ranks_for_round()
	var finished_players: Array[PlayerState] = []
	for p in players:
		if p.finished:
			finished_players.append(p)
	finished_players.sort_custom(func(a: PlayerState, b: PlayerState) -> bool:
		if a.finish_rank == b.finish_rank:
			if a.progress != b.progress:
				return a.progress > b.progress
			return a.spot < b.spot
		if a.finish_rank < 0:
			return false
		if b.finish_rank < 0:
			return true
		return a.finish_rank < b.finish_rank
	)
	return finished_players
