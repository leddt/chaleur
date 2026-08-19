class_name HeatGameEngine
extends RefCounted

enum Phase {
	SETUP,
	GARAGE_DRAFT,
	GARAGE_SUMMARY,
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
	SETTLE_HEAT,
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
var options: RaceOptions = RaceOptions.new()
var grid_order: Array[int] = []
var garage_deck: CardPile = CardPile.new()
var garage_market: CardPile = CardPile.new()
var garage_discard: CardPile = CardPile.new()
var garage_draft_round: int = 0
var garage_pick_index: int = 0
var garage_ready: Array[bool] = []
## card_id -> player_id for picks still shown on this round's market.
var garage_claims: Dictionary = {}


func setup(
	player_names: Array[String],
	p_track: HeatTrack,
	seed: int = 1,
	p_options: RaceOptions = null,
) -> void:
	track = p_track
	rng.seed = seed
	options = p_options if p_options != null else RaceOptions.new()
	players.clear()
	event_log.clear()
	grid_order.clear()
	garage_deck.clear()
	garage_market.clear()
	garage_discard.clear()
	garage_draft_round = 0
	garage_pick_index = 0
	garage_ready.clear()
	garage_claims.clear()
	stress_reserve = DeckFactory.build_stress_reserve()
	started_player_count = player_names.size()
	next_finish_rank = 1
	var include_starters := not options.garage_enabled
	for i in player_names.size():
		var p := PlayerState.new()
		p.id = i
		p.display_name = player_names[i]
		p.gear = 1
		p.progress = 0
		p.spot = i % track.spot_count(0)
		p.draw_pile.add_many(
			DeckFactory.build_starter_draw(i, track.start_stress, include_starters)
		)
		p.draw_pile.shuffle(rng)
		p.engine.add_many(DeckFactory.build_engine_heat(i, track.start_heat))
		players.append(p)
	_assign_unique_start_spots()
	_snapshot_round_order()
	if options.garage_enabled:
		_begin_garage()
		return
	for p in players:
		_draw_up_to(p, 7)
	phase = Phase.SHIFT_GEARS
	_log("Race setup on %s (%d laps), seed=%d" % [track.display_name(), track.laps, seed])


func active_player() -> PlayerState:
	if phase != Phase.PLAYER_TURN or turn_order.is_empty():
		return null
	return players[turn_order[turn_index]]


## Players who still need to act in the current simultaneous/turn phase (UI helper).
func pending_actor_ids() -> Array[int]:
	var ids: Array[int] = []
	match phase:
		Phase.GARAGE_DRAFT:
			var picker := garage_picker_id()
			if picker >= 0:
				ids.append(picker)
		Phase.GARAGE_SUMMARY:
			for p in players:
				if not is_garage_ready(p.id):
					ids.append(p.id)
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


func garage_pick_order() -> Array[int]:
	var order: Array[int] = grid_order.duplicate()
	if garage_draft_round != 2:
		order.reverse()
	return order


func garage_picker_id() -> int:
	if phase != Phase.GARAGE_DRAFT:
		return -1
	var order := garage_pick_order()
	if garage_pick_index < 0 or garage_pick_index >= order.size():
		return -1
	return order[garage_pick_index]


func _begin_garage() -> void:
	var pool := GarageDeckFactory.build_pool(
		options.garage_include_basic, options.garage_include_advanced
	)
	for card in pool:
		garage_deck.add(card)
	garage_deck.shuffle(rng)
	_log(
		"Race setup on %s (%d laps), seed=%d — garage" % [track.display_name(), track.laps, rng.seed]
	)
	if options.garage_quick_start:
		_garage_quick_start()
		return
	garage_draft_round = 1
	garage_pick_index = 0
	_deal_garage_market()
	phase = Phase.GARAGE_DRAFT
	_log("Garage draft round 1")


func _garage_quick_start() -> void:
	var remaining: Array[HeatCard] = garage_deck.cards.duplicate()
	garage_deck.clear()
	for p in players:
		var dealt := GarageDeckFactory.deal_random(remaining, rng, 3)
		for card in dealt:
			remaining.erase(card)
			p.garage_upgrades.add(card)
			p.draw_pile.add(card)
		p.draw_pile.shuffle(rng)
		_draw_up_to(p, 7)
		_log("%s quick-start upgrades" % p.display_name)
	phase = Phase.SHIFT_GEARS


func _deal_garage_market() -> void:
	garage_market.clear()
	garage_claims.clear()
	var need := players.size() + 3
	for _i in need:
		var card := garage_deck.draw_top()
		if card == null:
			break
		garage_market.add(card)


func garage_claim_player_id(card_id: String) -> int:
	if not garage_claims.has(card_id):
		return -1
	return int(garage_claims[card_id])


func pick_garage_card(player_id: int, card_id: String) -> ActionResult:
	if phase != Phase.GARAGE_DRAFT:
		return ActionResult.fail("Not in garage draft")
	if player_id != garage_picker_id():
		return ActionResult.fail("Not this player's pick")
	if garage_claim_player_id(card_id) >= 0:
		return ActionResult.fail("Card already drafted")
	var card := garage_market.get_by_id(card_id)
	if card == null:
		return ActionResult.fail("Card not in market")
	var p := _player(player_id)
	if p == null:
		return ActionResult.fail("Invalid player")
	p.garage_upgrades.add(card)
	garage_claims[card_id] = player_id
	_log("%s drafts %s" % [p.display_name, card.def_id])
	garage_pick_index += 1
	return ActionResult.success()


func is_garage_round_complete() -> bool:
	return phase == Phase.GARAGE_DRAFT and garage_pick_index >= players.size()


func advance_garage_round() -> ActionResult:
	if not is_garage_round_complete():
		return ActionResult.fail("Garage round still in progress")
	_advance_garage_round()
	return ActionResult.success()


func _advance_garage_round() -> void:
	for card in garage_market.cards:
		if garage_claim_player_id(card.id) >= 0:
			continue
		garage_discard.add(card)
	garage_market.clear()
	garage_claims.clear()
	if garage_draft_round >= 3:
		_enter_garage_summary()
		return
	garage_draft_round += 1
	garage_pick_index = 0
	_deal_garage_market()
	_log("Garage draft round %d" % garage_draft_round)


func is_garage_ready(player_id: int) -> bool:
	return player_id >= 0 and player_id < garage_ready.size() and garage_ready[player_id]


func ready_garage(player_id: int) -> ActionResult:
	if phase != Phase.GARAGE_SUMMARY:
		return ActionResult.fail("Not in garage summary")
	if player_id < 0 or player_id >= players.size():
		return ActionResult.fail("Invalid player")
	if not is_garage_ready(player_id):
		garage_ready[player_id] = true
		_log("%s is ready" % players[player_id].display_name)
	if _all_garage_ready():
		_begin_race_from_garage()
	return ActionResult.success()


func begin_race_from_garage() -> ActionResult:
	if phase != Phase.GARAGE_SUMMARY:
		return ActionResult.fail("Not in garage summary")
	_begin_race_from_garage()
	return ActionResult.success()


func _all_garage_ready() -> bool:
	if garage_ready.size() != players.size():
		return false
	for v in garage_ready:
		if not v:
			return false
	return true


func _enter_garage_summary() -> void:
	garage_ready.clear()
	for _p in players:
		garage_ready.append(false)
	phase = Phase.GARAGE_SUMMARY
	_log("Garage draft complete — review loadouts")


func _begin_race_from_garage() -> void:
	for p in players:
		for card in p.garage_upgrades.cards:
			p.draw_pile.add(card)
		p.draw_pile.shuffle(rng)
		_draw_up_to(p, 7)
	phase = Phase.SHIFT_GEARS
	_log("Garage draft complete — shift gears")


func use_upgrade_symbol(player_id: int, uid: String, payload: Dictionary = {}) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.REACT:
		return ActionResult.fail("Not in REACT step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	return UpgradeEffects.use_symbol(self, p, uid, payload)


func use_direct_play(player_id: int, card_id: String, speed_choice: int = -1) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.REACT:
		return ActionResult.fail("Not in REACT step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	var card := p.hand.get_by_id(card_id)
	if card == null:
		return ActionResult.fail("Card not in hand")
	var def := CardCatalog.get_def(card.def_id)
	if not def.has_symbol(CardSymbol.Kind.DIRECT_PLAY):
		return ActionResult.fail("Not a Direct Play card")
	if speed_choice >= 0:
		card.chosen_speed = speed_choice
	p.hand.remove_id(card_id)
	# Remove the queued DIRECT_PLAY pending entry if present.
	var left: Array[Dictionary] = []
	for entry in p.pending_symbols:
		if str(entry.get("card_id", "")) == card_id and int(entry.get("kind", -1)) == int(
			CardSymbol.Kind.DIRECT_PLAY
		):
			continue
		left.append(entry)
	p.pending_symbols = left
	UpgradeEffects.apply_direct_play(self, p, card)
	return ActionResult.success()



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


func play_cards(
	player_id: int, card_ids: Array[String], _speed_choices: Dictionary = {}
) -> ActionResult:
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


func use_boost(player_id: int) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.REACT:
		return ActionResult.fail("Not in REACT step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	if p.boost_used:
		return ActionResult.fail("Boost already used")
	if p.engine_heat() < 1:
		return ActionResult.fail("Not enough Heat to boost")
	_pay_heat(p, 1)
	var speed_card := _flip_until_speed(p)
	if speed_card == null:
		return ActionResult.fail("Boost failed: no Speed card available")
	p.play_area.add(speed_card)
	p.round_speed += speed_card.speed_value
	p.boost_used = true
	p.plus_symbols_used += 1
	_move_player(p, speed_card.speed_value, false)
	_log("%s boosts for +%d" % [p.display_name, speed_card.speed_value])
	_check_finish(p)
	return ActionResult.success()


func use_adrenaline(player_id: int) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.REACT:
		return ActionResult.fail("Not in REACT step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	if not p.has_adrenaline:
		return ActionResult.fail("No adrenaline")
	if p.adrenaline_speed_used:
		return ActionResult.fail("Adrenaline already used")
	p.adrenaline_speed_used = true
	p.round_speed += 1
	_move_player(p, 1, false)
	_log("%s uses adrenaline +1 speed" % p.display_name)
	_check_finish(p)
	return ActionResult.success()


func use_cooldown(player_id: int) -> ActionResult:
	if phase != Phase.PLAYER_TURN:
		return ActionResult.fail("Not in player turn")
	if turn_step != TurnStep.REACT and turn_step != TurnStep.SETTLE_HEAT:
		return ActionResult.fail("Cooldown not available now")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	if p.cooldown_remaining() < 1:
		return ActionResult.fail("No cooldown remaining")
	if p.hand.count_kind(HeatCard.Kind.HEAT) < 1:
		return ActionResult.fail("Not enough Heat in hand to cooldown")
	var heat := _take_heat_from_hand(p)
	if heat == null:
		return ActionResult.fail("Not enough Heat in hand to cooldown")
	p.engine.add(heat)
	p.cooldown_used += 1
	_log("%s cools down 1" % p.display_name)
	return ActionResult.success()


func choose_speed(player_id: int, card_id: String, speed: int) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.REACT:
		return ActionResult.fail("Not in REACT step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	var card := p.play_area.get_by_id(card_id)
	if card == null:
		return ActionResult.fail("Card not in play")
	if not card.needs_speed_choice():
		return ActionResult.fail("Speed already chosen")
	var opts := CardCatalog.get_def(card.def_id).resolved_speed_options()
	if opts.find(speed) < 0:
		return ActionResult.fail("Invalid speed option")
	if _card_has_pending_heat_debt(p, card_id):
		return ActionResult.fail("Pay Heat before choosing speed")
	card.chosen_speed = speed
	p.round_speed += speed
	_move_player(p, speed, false)
	_log("%s chooses speed %d on %s" % [p.display_name, speed, card.def_id])
	_check_finish(p)
	return ActionResult.success()


func pay_heat_debt(player_id: int, uid: String) -> ActionResult:
	if phase != Phase.PLAYER_TURN:
		return ActionResult.fail("Not in player turn")
	if turn_step != TurnStep.SETTLE_HEAT and turn_step != TurnStep.REACT:
		return ActionResult.fail("Cannot pay Heat now")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	return UpgradeEffects.pay_heat_debt(self, p, uid)


func finish_settle_heat(player_id: int) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.SETTLE_HEAT:
		return ActionResult.fail("Not in Heat settlement")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	if p.can_pay_any_heat_debt():
		return ActionResult.fail("Must pay Heat you can afford")
	UpgradeEffects.auto_fallback_unpayable_debts(self, p)
	if p.has_pending_heat_debts():
		return ActionResult.fail("Unresolved Heat debts")
	_complete_move_after_settle(p)
	return ActionResult.success()


func finish_react(player_id: int) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.REACT:
		return ActionResult.fail("Not in REACT step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	if p.has_unresolved_speeds():
		return ActionResult.fail("Must choose speed on multi-option cards")
	if p.can_pay_any_heat_debt():
		return ActionResult.fail("Must pay Heat you can afford")
	UpgradeEffects.auto_fallback_unpayable_debts(self, p)
	if p.has_pending_heat_debts():
		return ActionResult.fail("Unresolved Heat debts")
	turn_step = TurnStep.SLIPSTREAM
	if not _slipstream_eligible(p):
		return _auto_skip_slipstream(p)
	return ActionResult.success()


## Legacy name used by UI / net action "react" (= finish React step).
func react(player_id: int) -> ActionResult:
	return finish_react(player_id)


func slipstream(player_id: int, use: bool) -> ActionResult:
	if phase != Phase.PLAYER_TURN or turn_step != TurnStep.SLIPSTREAM:
		return ActionResult.fail("Not in SLIPSTREAM step")
	var p := active_player()
	if p == null or p.id != player_id:
		return ActionResult.fail("Not this player's turn")
	if use:
		if not _slipstream_eligible(p):
			return ActionResult.fail("Slipstream not eligible")
		_move_player(p, 2 + p.slipstream_bonus, true)
		_log("%s slipstreams +%d" % [p.display_name, 2 + p.slipstream_bonus])
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
		if not card.can_discard():
			return ActionResult.fail("Cannot discard this card")
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
	# Shuffle grid order so lobby/seat order (host first) is not the pole.
	var grid: Array[int] = []
	for i in players.size():
		grid.append(i)
	for i in range(grid.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := grid[i]
		grid[i] = grid[j]
		grid[j] = tmp

	grid_order = grid.duplicate()

	if track.start_behind_finish_line:
		# Behind the start/finish line: last spaces of the final sector.
		# progress -1 => space (n-1), -2 => (n-2), … ; max 2 cars per space.
		var per_space := maxi(1, track.start_max_per_space)
		for rank in grid.size():
			var p := players[grid[rank]]
			var row := int(rank / per_space)
			var spot := rank % per_space
			p.progress = -(row + 1)
			var space := track.space_of_progress(p.progress)
			var cap := track.spot_count(space)
			p.spot = mini(spot, maxi(cap - 1, 0))
		return
	var max_spots := track.spot_count(0)
	for rank in grid.size():
		var p := players[grid[rank]]
		p.progress = 0
		p.spot = rank % maxi(max_spots, 1)


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


func _snapshot_round_order() -> void:
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


func _begin_turn_order() -> void:
	# Order was frozen at round start; positions must not reshuffle mid-round.
	if turn_order.is_empty():
		_snapshot_round_order()
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

	UpgradeEffects.apply_reveal(self, p)
	if p.pending_heat_debts.is_empty():
		_complete_move_after_settle(p)
	else:
		turn_step = TurnStep.SETTLE_HEAT


func _complete_move_after_settle(p: PlayerState) -> void:
	UpgradeEffects.resolve_kept_plus(self, p, false)
	p.round_speed = 0
	for card in p.play_area.cards:
		if card.contributes_speed_when_played() and not _card_has_pending_heat_debt(p, card.id):
			p.round_speed += card.speed_value

	_move_player(p, p.round_speed, false)
	_log("%s reveals speed %d and moves" % [p.display_name, p.round_speed])
	_check_finish(p)

	turn_step = TurnStep.REACT
	UpgradeEffects.queue_direct_play_from_hand(p)


func _card_has_pending_heat_debt(p: PlayerState, card_id: String) -> bool:
	for debt in p.pending_heat_debts:
		if str(debt.get("card_id", "")) == card_id:
			return true
	return false


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
		var excess := p.round_speed - (corner.speed_limit + p.speed_limit_adjust)
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
	var refresh: Dictionary = {}
	for cid in p.refresh_card_ids:
		refresh[cid] = true
	for card in p.play_area.cards:
		if refresh.has(card.id):
			p.draw_pile.cards.insert(0, card)
		else:
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
	_snapshot_round_order()
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
	finished_players.sort_custom(_is_ahead)
	return finished_players


## Live order for every car: assigned finish ranks first, then track position
## (progress, then race-line spot). Place is 1-based index in this list.
func race_order() -> Array[PlayerState]:
	var order: Array[PlayerState] = players.duplicate()
	order.sort_custom(_is_ahead)
	return order


func race_place(player_id: int) -> int:
	var i := 0
	for p in race_order():
		i += 1
		if p.id == player_id:
			return i
	return 0


## Badge row for this round: current turn_order, then earlier finishers.
func round_order() -> Array[PlayerState]:
	var seen: Dictionary = {}
	var order: Array[PlayerState] = []
	for id in turn_order:
		if id < 0 or id >= players.size():
			continue
		var p: PlayerState = players[id]
		order.append(p)
		seen[id] = true
	var rest: Array[PlayerState] = []
	for p in players:
		if not seen.has(p.id):
			rest.append(p)
	rest.sort_custom(_is_ahead)
	order.append_array(rest)
	return order


func _is_ahead(a: PlayerState, b: PlayerState) -> bool:
	if a.finish_rank > 0 and b.finish_rank > 0:
		return a.finish_rank < b.finish_rank
	if a.finish_rank > 0:
		return true
	if b.finish_rank > 0:
		return false
	if a.progress != b.progress:
		return a.progress > b.progress
	return a.spot < b.spot
