extends GutTest


func test_double_shift_costs_one_heat() -> void:
	var engine := HeatTestHelpers.make_engine(2, 1)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 6)
	var r := engine.shift_gear(0, 3)
	assert_true(r.ok, r.error)
	# Gear stays secret until everyone has locked.
	assert_eq(p.gear, 1)
	assert_eq(p.pending_gear, 3)
	assert_eq(p.engine_heat(), 6)
	assert_true(engine.shift_gear(1, 1).ok)
	assert_eq(p.gear, 3)
	assert_eq(p.pending_gear, -1)
	assert_eq(p.engine_heat(), 5)


func test_double_shift_illegal_without_heat() -> void:
	var engine := HeatTestHelpers.make_engine(2, 1)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 0)
	var r := engine.shift_gear(0, 3)
	assert_false(r.ok)
	assert_eq(p.gear, 1)
	assert_eq(p.pending_gear, -1)


func test_shift_logs_only_after_everyone_locks() -> void:
	var engine := HeatTestHelpers.make_engine(2, 1)
	assert_true(engine.shift_gear(0, 2).ok)
	for line in engine.event_log:
		assert_false("shifts to gear" in line, line)
	assert_true(engine.shift_gear(1, 1).ok)
	var shift_lines := 0
	for line in engine.event_log:
		if "shifts to gear" in line:
			shift_lines += 1
	assert_eq(shift_lines, 2)
	assert_eq(engine.phase, HeatGameEngine.Phase.PLAY_CARDS)


func test_stress_resolved_before_react_step() -> void:
	var engine := HeatTestHelpers.make_engine(1, 99)
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	var p0 := engine.players[0]
	p0.hand.clear()
	p0.hand.add(HeatCard.new("stress_t", HeatCard.Kind.STRESS, 0))
	p0.draw_pile.clear()
	p0.discard.clear()
	p0.draw_pile.add(HeatCard.new("flip_spd", HeatCard.Kind.SPEED, 4))
	assert_true(engine.play_cards(0, ["stress_t"]).ok)
	assert_eq(engine.phase, HeatGameEngine.Phase.PLAYER_TURN)
	assert_eq(engine.turn_step, HeatGameEngine.TurnStep.REACT)
	assert_eq(p0.round_speed, 4)
	assert_true(p0.play_area.has_id("flip_spd"))


func test_boost_increases_corner_speed_slipstream_does_not() -> void:
	var engine := HeatTestHelpers.make_engine(2, 7)
	var p := engine.players[0]
	var other := engine.players[1]
	HeatTestHelpers.ensure_engine_heat(p, 6)
	p.progress = 5
	p.spot = 0
	other.progress = 6
	other.spot = 0
	p.gear = 3
	other.gear = 1
	p.gear_locked = true
	other.gear_locked = true
	engine.phase = HeatGameEngine.Phase.PLAY_CARDS
	assert_true(HeatTestHelpers.play_speeds(engine, 0, [3, 1, 1]))
	assert_true(HeatTestHelpers.play_speeds(engine, 1, [1]))
	# Restart turns with P0 first after automatic begin
	p.corners_crossed.clear()
	p.progress = 5
	p.round_speed = 0
	p.play_area.clear()
	p.play_area.add(HeatCard.new("s3", HeatCard.Kind.SPEED, 3))
	p.skipped_move = false
	p.draw_pile.clear()
	p.draw_pile.add(HeatCard.new("boost_spd", HeatCard.Kind.SPEED, 2))
	HeatTestHelpers.ensure_engine_heat(p, 6)
	engine.debug_begin_turns([0, 1] as Array[int])
	assert_eq(engine.turn_step, HeatGameEngine.TurnStep.REACT)
	assert_eq(p.round_speed, 3)
	assert_true(engine.react(0, 0, true, false).ok)
	assert_eq(p.round_speed, 5)
	var speed_after_boost := p.round_speed
	# Slipstream must not change round_speed used for corners.
	if engine.turn_step == HeatGameEngine.TurnStep.SLIPSTREAM:
		assert_true(engine.slipstream(0, true).ok)
		assert_eq(p.round_speed, speed_after_boost)
	# Boost (1 Heat) + corner excess for speed 5 vs limit 4 (1 Heat)
	assert_eq(p.engine_heat(), 4)


func test_corner_excess_causes_spin_out() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 1)
	p.progress = 5
	p.spot = 0
	p.gear = 1
	p.gear_locked = true
	engine.phase = HeatGameEngine.Phase.PLAY_CARDS
	assert_true(HeatTestHelpers.play_speeds(engine, 0, [6]))
	assert_eq(engine.turn_step, HeatGameEngine.TurnStep.REACT)
	assert_true(engine.react(0, 0, false, false).ok)
	if engine.turn_step == HeatGameEngine.TurnStep.SLIPSTREAM:
		assert_true(engine.slipstream(0, false).ok)
	assert_eq(p.engine_heat(), 0)
	assert_eq(p.gear, 1)
	assert_gte(p.hand.count_kind(HeatCard.Kind.STRESS), 1)
	assert_lte(p.progress, 5)


func test_multiple_corners_same_turn() -> void:
	var engine := HeatTestHelpers.make_engine(1, 2)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 10)
	p.progress = 5
	p.gear = 1
	p.gear_locked = true
	engine.phase = HeatGameEngine.Phase.PLAY_CARDS
	assert_true(HeatTestHelpers.play_speeds(engine, 0, [8]))
	var heat_before := p.engine_heat()
	assert_true(engine.react(0, 0, false, false).ok)
	if engine.turn_step == HeatGameEngine.TurnStep.SLIPSTREAM:
		assert_true(engine.slipstream(0, false).ok)
	assert_eq(p.engine_heat(), heat_before - 7)


func test_blocking_lands_on_previous_free_space() -> void:
	var engine := HeatTestHelpers.make_engine(2, 4)
	var mover := engine.players[0]
	var blocker := engine.players[1]
	blocker.progress = 8
	blocker.spot = 0
	mover.progress = 7
	mover.spot = 0
	engine._move_player(mover, 1, false)
	assert_eq(mover.progress, 7)
	var blocked := false
	for line in engine.event_log:
		if line.contains("blocked"):
			blocked = true
	assert_true(blocked)


func test_adrenaline_last_and_two_last_with_five_cars() -> void:
	var engine := HeatTestHelpers.make_engine(5, 5)
	for i in engine.players.size():
		engine.players[i].progress = 10 - i
		engine.players[i].spot = 0
		engine.players[i].gear = 1
		engine.players[i].gear_locked = true
	engine.phase = HeatGameEngine.Phase.PLAY_CARDS
	for i in 5:
		assert_true(HeatTestHelpers.play_speeds(engine, i, [1]))
	var with_ad := 0
	for p in engine.players:
		if p.has_adrenaline:
			with_ad += 1
	assert_eq(with_ad, 2)

	var e2 := HeatTestHelpers.make_engine(2, 5)
	assert_true(HeatTestHelpers.shift_all(e2, 1))
	assert_true(HeatTestHelpers.play_speeds(e2, 0, [1]))
	assert_true(HeatTestHelpers.play_speeds(e2, 1, [1]))
	var ad2 := 0
	for p in e2.players:
		if p.has_adrenaline:
			ad2 += 1
	assert_eq(ad2, 1)


func test_cooldown_gear_values() -> void:
	var p := PlayerState.new()
	p.gear = 1
	assert_eq(p.cooldown_from_gear(), 3)
	p.gear = 2
	assert_eq(p.cooldown_from_gear(), 1)
	p.gear = 3
	assert_eq(p.cooldown_from_gear(), 0)


func test_boost_requires_heat() -> void:
	var engine := HeatTestHelpers.make_engine(1, 8)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 0)
	p.gear = 4
	p.gear_locked = true
	engine.phase = HeatGameEngine.Phase.PLAY_CARDS
	assert_true(HeatTestHelpers.play_speeds(engine, 0, [1, 1, 1, 1]))
	assert_eq(engine.turn_step, HeatGameEngine.TurnStep.REACT)
	var r := engine.react(0, 0, true, false)
	assert_false(r.ok)


func test_replenish_to_seven_and_recycle_discard() -> void:
	var engine := HeatTestHelpers.make_engine(1, 11)
	var p := engine.players[0]
	p.gear = 1
	p.gear_locked = true
	engine.phase = HeatGameEngine.Phase.PLAY_CARDS
	p.hand.clear()
	p.draw_pile.clear()
	p.discard.clear()
	for i in 3:
		p.discard.add(HeatCard.new("d%d" % i, HeatCard.Kind.SPEED, 1))
	# Need 4 more in discard/draw to reach 7 after replenish (play area card also discarded)
	for i in 4:
		p.discard.add(HeatCard.new("e%d" % i, HeatCard.Kind.SPEED, 1))
	p.hand.add(HeatCard.new("only", HeatCard.Kind.SPEED, 2))
	assert_true(engine.play_cards(0, ["only"]).ok)
	assert_true(engine.react(0, 0, false, false).ok)
	if engine.turn_step == HeatGameEngine.TurnStep.SLIPSTREAM:
		assert_true(engine.slipstream(0, false).ok)
	assert_true(engine.discard_cards(0, []).ok)
	assert_eq(p.hand.size(), 7)


func test_same_round_finish_ranked_by_distance() -> void:
	var track := HeatTrack.usa_simplified(1)
	track.space_count = 10
	track.spots = [6, 2, 2, 2, 2, 2, 2, 2, 2, 2] as Array[int]
	track.corners.clear()
	track.laps = 1
	var engine := HeatGameEngine.new()
	engine.setup(["Alice", "Bob"], track, 1)
	var alice := engine.players[0]
	var bob := engine.players[1]
	# Alice moves second but ends further past the line than Bob.
	bob.progress = 8
	alice.progress = 7
	bob.spot = 0
	alice.spot = 1
	bob.gear = 1
	alice.gear = 1
	bob.gear_locked = true
	alice.gear_locked = true
	engine.phase = HeatGameEngine.Phase.PLAY_CARDS
	assert_true(HeatTestHelpers.play_speeds(engine, 0, [5])) # Alice -> 12
	assert_true(HeatTestHelpers.play_speeds(engine, 1, [3])) # Bob -> 11
	# Bob is ahead so acts first; both will finish this round.
	assert_true(engine.react(bob.id, 0, false, false).ok)
	if engine.turn_step == HeatGameEngine.TurnStep.DISCARD:
		assert_true(engine.discard_cards(bob.id, []).ok)
	# Alice's turn may already be at REACT after Bob advanced.
	while not alice.finished and engine.phase == HeatGameEngine.Phase.PLAYER_TURN:
		var ap := engine.active_player()
		assert_not_null(ap)
		assert_eq(ap.id, alice.id)
		match engine.turn_step:
			HeatGameEngine.TurnStep.REACT:
				assert_true(engine.react(alice.id, 0, false, false).ok)
			HeatGameEngine.TurnStep.SLIPSTREAM:
				assert_true(engine.slipstream(alice.id, false).ok)
			HeatGameEngine.TurnStep.DISCARD:
				assert_true(engine.discard_cards(alice.id, []).ok)
			_:
				fail_test("Unexpected step %s" % str(engine.turn_step))
				return
	assert_true(bob.finished)
	assert_true(alice.finished)
	var order := engine.ranking()
	assert_eq(order.size(), 2)
	# Alice progressed further (12 > 11) so she ranks #1 despite moving second.
	assert_eq(order[0].id, alice.id)
	assert_eq(order[0].finish_rank, 1)
	assert_eq(order[1].id, bob.id)
	assert_eq(order[1].finish_rank, 2)


func test_first_finisher_still_pending_then_others_continue() -> void:
	var track := HeatTrack.usa_simplified(1)
	track.space_count = 10
	track.spots = [6, 2, 2, 2, 2, 2, 2, 2, 2, 2] as Array[int]
	track.corners.clear()
	track.laps = 1
	var engine := HeatGameEngine.new()
	engine.setup(["Alice", "Bob"], track, 1)
	var alice := engine.players[0]
	var bob := engine.players[1]
	# Bob is ahead and will cross finish; Alice stays behind.
	bob.progress = 8
	bob.spot = 0
	alice.progress = 2
	alice.spot = 1
	alice.gear = 1
	bob.gear = 1
	alice.gear_locked = true
	bob.gear_locked = true
	engine.phase = HeatGameEngine.Phase.PLAY_CARDS
	assert_true(HeatTestHelpers.play_speeds(engine, 0, [1]))
	assert_true(HeatTestHelpers.play_speeds(engine, 1, [3]))
	# Bob should move first and finish; still must be pending for React.
	assert_true(bob.finished)
	assert_false(alice.finished)
	assert_false(engine.is_race_over())
	var pending := engine.pending_actor_ids()
	assert_eq(pending.size(), 1)
	assert_eq(pending[0], bob.id)
	assert_eq(engine.turn_step, HeatGameEngine.TurnStep.REACT)
	assert_true(engine.react(bob.id, 0, false, false).ok)
	# Alice must still get her turn this round (or a later round) — race not over.
	assert_false(engine.is_race_over())
	assert_false(alice.finished)
	pending = engine.pending_actor_ids()
	assert_false(pending.is_empty())
	assert_eq(pending[0], alice.id)


func test_short_race_can_finish() -> void:
	var track := HeatTrack.usa_simplified(1)
	track.space_count = 5
	track.spots = [6, 2, 2, 2, 2] as Array[int]
	track.corners.clear()
	track.laps = 1
	var engine := HeatGameEngine.new()
	engine.setup(["A", "B"], track, 1)
	var guard := 0
	while not engine.is_race_over() and guard < 60:
		guard += 1
		match engine.phase:
			HeatGameEngine.Phase.SHIFT_GEARS:
				for p in engine.players:
					if not p.finished and not p.gear_locked:
						var target := mini(4, p.gear + 1)
						engine.shift_gear(p.id, target)
			HeatGameEngine.Phase.PLAY_CARDS:
				for p in engine.players:
					if p.finished or p.cards_locked:
						continue
					var ids: Array[String] = []
					for card in p.hand.cards:
						if card.is_playable() and ids.size() < p.gear:
							ids.append(card.id)
					engine.play_cards(p.id, ids)
			HeatGameEngine.Phase.PLAYER_TURN:
				var ap := engine.active_player()
				if ap == null:
					break
				match engine.turn_step:
					HeatGameEngine.TurnStep.REACT:
						engine.react(ap.id, 0, false, false)
					HeatGameEngine.TurnStep.SLIPSTREAM:
						engine.slipstream(ap.id, false)
					HeatGameEngine.TurnStep.DISCARD:
						engine.discard_cards(ap.id, [])
					_:
						fail_test("Stuck on step %s" % str(engine.turn_step))
						return
			_:
				break
	assert_true(engine.is_race_over(), "Race did not finish.\n%s" % engine.dump_state())
	assert_eq(engine.ranking().size(), 2)


func test_track1_starts_behind_line_two_per_space() -> void:
	var engine := HeatGameEngine.new()
	engine.setup(["A", "B", "C", "D"], HeatTrack.track1(1), 1)
	assert_true(engine.track.start_behind_finish_line)
	assert_eq(engine.track.space_count, 69)
	# Front row (closest to line): progress -1 → space 68
	assert_eq(engine.players[0].progress, -1)
	assert_eq(engine.players[1].progress, -1)
	assert_eq(engine.track.space_of_progress(-1), 68)
	assert_eq(engine.players[0].spot, 0)
	assert_eq(engine.players[1].spot, 1)
	# Second row: progress -2 → space 67
	assert_eq(engine.players[2].progress, -2)
	assert_eq(engine.players[3].progress, -2)
	assert_eq(engine.track.space_of_progress(-2), 67)
	assert_ne(engine.players[0].progress, engine.players[2].progress)
