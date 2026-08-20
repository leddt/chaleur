extends GutTest


func test_mandatory_heat_deferred_until_settle() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 6)
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("brakes", "upg_07_brakes"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["brakes"]).ok)
	assert_eq(engine.turn_step, HeatGameEngine.TurnStep.SETTLE_HEAT)
	assert_eq(p.engine_heat(), 6)
	assert_eq(p.round_speed, 0)
	assert_eq(p.pending_heat_debts.size(), 1)
	assert_true(engine.pay_heat_debt(0, "brakes_heat").ok)
	assert_true(engine.finish_settle_heat(0).ok)
	assert_eq(engine.turn_step, HeatGameEngine.TurnStep.REACT)
	assert_eq(p.engine_heat(), 5)
	assert_eq(p.round_speed, 0)
	assert_false(engine.finish_react(0).ok)
	assert_true(engine.choose_speed(0, "brakes", 2).ok)
	assert_eq(p.round_speed, 2)


func test_heat_fallback_does_not_count_for_accelerate() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 0)
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("brakes", "upg_07_brakes"))
	p.draw_pile.clear()
	p.draw_pile.add(HeatTestHelpers.card("spd", "speed_4"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["brakes"]).ok)
	assert_eq(engine.turn_step, HeatGameEngine.TurnStep.SETTLE_HEAT)
	assert_true(engine.finish_settle_heat(0).ok)
	assert_eq(p.plus_symbols_used, 0)
	assert_eq(p.round_speed, 4)
	var in_discard := false
	for card in p.discard.cards:
		if card.id == "brakes":
			in_discard = true
	assert_true(in_discard)


func test_cooldown_before_mandatory_heat_pay() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 0)
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("brakes", "upg_07_brakes"))
	p.hand.add(HeatTestHelpers.card("h1", "heat"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["brakes"]).ok)
	assert_eq(engine.turn_step, HeatGameEngine.TurnStep.SETTLE_HEAT)
	assert_true(engine.use_cooldown(0).ok)
	assert_eq(p.engine_heat(), 1)
	assert_true(engine.pay_heat_debt(0, "brakes_heat").ok)
	assert_true(engine.finish_settle_heat(0).ok)
	assert_true(engine.choose_speed(0, "brakes", 2).ok)
	assert_eq(p.round_speed, 2)


func test_must_pay_heat_when_affordable() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 2)
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("brakes", "upg_07_brakes"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["brakes"]).ok)
	assert_false(engine.finish_settle_heat(0).ok)
	assert_true(engine.pay_heat_debt(0, "brakes_heat").ok)
	assert_true(engine.finish_settle_heat(0).ok)


func test_multi_speed_chosen_during_react() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 6)
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("spd", "speed_2"))
	p.hand.add(HeatTestHelpers.card("rpm", "upg_31_rpm"))
	while p.hand.size() < 7:
		p.hand.add(HeatTestHelpers.card("pad_%d" % p.hand.size(), "speed_1"))
	assert_true(HeatTestHelpers.shift_all(engine, 2))
	assert_true(engine.play_cards(0, ["spd", "rpm"]).ok)
	assert_true(HeatTestHelpers.finish_settle_heat(engine, 0))
	assert_eq(p.round_speed, 2)
	assert_false(engine.finish_react(0).ok)
	assert_true(engine.choose_speed(0, "rpm", 1).ok)
	assert_eq(p.round_speed, 3)


func test_adjust_speed_limit_applied_at_reveal() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("tyre", "upg_37_tyres"))
	p.draw_pile.clear()
	p.draw_pile.add(HeatTestHelpers.card("a", "speed_1"))
	p.draw_pile.add(HeatTestHelpers.card("b", "speed_1"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["tyre"]).ok)
	assert_eq(p.speed_limit_adjust, 1)


func test_accelerate_all_or_nothing_plus_only() -> void:
	var engine := HeatTestHelpers.make_engine(1, 9)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 6)
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("four", "upg_47_4wd"))
	p.draw_pile.clear()
	p.draw_pile.add(HeatTestHelpers.card("s3", "speed_3"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["four"]).ok)
	assert_true(HeatTestHelpers.finish_settle_heat(engine, 0))
	assert_eq(p.round_speed, 3)
	assert_eq(p.plus_symbols_used, 1)
	assert_true("four" in p.plus_resolved_card_ids)
	var accel_uid := ""
	for entry in p.pending_symbols:
		assert_ne(int(entry.get("kind", -1)), int(CardSymbol.Kind.PLUS))
		if int(entry.get("kind", -1)) == int(CardSymbol.Kind.ACCELERATE):
			accel_uid = str(entry.get("uid", ""))
	assert_ne(accel_uid, "")
	assert_true(engine.use_upgrade_symbol(0, accel_uid).ok)
	assert_true(p.accelerate_used)
	assert_eq(p.round_speed, 4)


func test_direct_play_from_react() -> void:
	var engine := HeatTestHelpers.make_engine(1, 4)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 6)
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("spd", "speed_2"))
	p.hand.add(HeatTestHelpers.card("gas", "upg_24_gas_pedal"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["spd"]).ok)
	assert_true(HeatTestHelpers.finish_settle_heat(engine, 0))
	assert_eq(p.round_speed, 2)
	assert_true(engine.use_direct_play(0, "gas", 1).ok)
	assert_eq(p.round_speed, 3)


func test_direct_play_heat_debt_before_finish_react() -> void:
	var engine := HeatTestHelpers.make_engine(1, 4)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 6)
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("spd", "speed_2"))
	p.hand.add(HeatTestHelpers.card("gas", "upg_27_gas_pedal"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["spd"]).ok)
	assert_true(HeatTestHelpers.finish_settle_heat(engine, 0))
	assert_true(engine.use_direct_play(0, "gas", 4).ok)
	assert_eq(p.pending_heat_debts.size(), 1)
	assert_false(engine.finish_react(0).ok)
	assert_true(engine.pay_heat_debt(0, "gas_heat").ok)
	assert_true(engine.finish_react(0).ok)


func test_direct_play_not_playable_during_play_cards() -> void:
	var engine := HeatTestHelpers.make_engine(1, 4)
	var p := engine.players[0]
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("gas", "upg_24_gas_pedal"))
	p.hand.add(HeatTestHelpers.card("spd", "speed_2"))
	while p.hand.size() < 7:
		p.hand.add(HeatTestHelpers.card("pad_%d" % p.hand.size(), "speed_1"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_false(p.hand.get_by_id("gas").is_playable())
	assert_false(engine.play_cards(0, ["gas"]).ok)
	assert_true(engine.play_cards(0, ["spd"]).ok)


func test_scrap_at_reveal() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("body", "upg_19_bodywork"))
	p.draw_pile.clear()
	p.draw_pile.add(HeatTestHelpers.card("top", "speed_4"))
	p.draw_pile.add(HeatTestHelpers.card("next", "speed_3"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["body"]).ok)
	assert_eq(p.draw_pile.size(), 0)
	assert_eq(p.discard.get_by_id("top") != null, true)
	assert_eq(p.discard.get_by_id("next") != null, true)


func test_refresh_puts_card_on_draw() -> void:
	var engine := HeatTestHelpers.make_engine(1, 11)
	var p := engine.players[0]
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("susp", "upg_34_suspension"))
	while p.hand.size() < 7:
		p.hand.add(HeatTestHelpers.card("pad_%d" % p.hand.size(), "speed_1"))
	p.draw_pile.clear()
	p.draw_pile.add(HeatTestHelpers.card("keep", "speed_2"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["susp"]).ok)
	assert_true(HeatTestHelpers.finish_settle_heat(engine, 0))
	var refresh_uid := ""
	for entry in p.pending_symbols:
		if int(entry.get("kind", -1)) == int(CardSymbol.Kind.REFRESH):
			refresh_uid = str(entry.get("uid", ""))
	assert_ne(refresh_uid, "")
	assert_true(engine.use_upgrade_symbol(0, refresh_uid).ok)
	assert_true(engine.finish_react(0).ok)
	if engine.turn_step == HeatGameEngine.TurnStep.SLIPSTREAM:
		assert_true(engine.slipstream(0, false).ok)
	if engine.turn_step == HeatGameEngine.TurnStep.DISCARD:
		assert_true(engine.discard_cards(0, []).ok)
	assert_eq(p.play_area.size(), 0)
	assert_eq(p.discard.get_by_id("susp"), null)
	assert_true(p.hand.get_by_id("susp") != null or p.draw_pile.get_by_id("susp") != null)


func test_salvage_from_discard() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("fuel", "upg_22_fuel"))
	p.discard.add(HeatTestHelpers.card("old", "speed_4"))
	p.draw_pile.clear()
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["fuel"]).ok)
	assert_true(HeatTestHelpers.finish_settle_heat(engine, 0))
	var salvage_uid := ""
	for entry in p.pending_symbols:
		if int(entry.get("kind", -1)) == int(CardSymbol.Kind.SALVAGE):
			salvage_uid = str(entry.get("uid", ""))
	assert_ne(salvage_uid, "")
	assert_true(engine.use_upgrade_symbol(0, salvage_uid, {"card_ids": ["old"]}).ok)
	assert_eq(p.discard.get_by_id("old"), null)
	assert_eq(p.draw_pile.get_by_id("old") != null, true)


func test_upgrade_cooldown_adds_to_react_quota() -> void:
	var engine := HeatTestHelpers.make_engine(1, 3)
	var p := engine.players[0]
	HeatTestHelpers.ensure_engine_heat(p, 6)
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("cool", "upg_12_cooling"))
	p.hand.add(HeatTestHelpers.card("h1", "heat"))
	p.hand.add(HeatTestHelpers.card("h2", "heat"))
	while p.hand.size() < 7:
		p.hand.add(HeatTestHelpers.card("pad_%d" % p.hand.size(), "speed_1"))
	assert_true(HeatTestHelpers.shift_all(engine, 3))
	assert_eq(p.cooldown_from_gear(), 0)
	assert_true(engine.play_cards(0, ["cool", "pad_3", "pad_4"]).ok)
	assert_true(HeatTestHelpers.finish_settle_heat(engine, 0))
	p.has_adrenaline = false
	assert_eq(p.cooldown_bonus, 2)
	assert_eq(p.max_cooldown(), 2)
	assert_true(engine.use_cooldown(0).ok)
	assert_true(engine.use_cooldown(0).ok)
	assert_false(engine.use_cooldown(0).ok)
	for entry in p.pending_symbols:
		assert_ne(int(entry.get("kind", -1)), int(CardSymbol.Kind.COOLDOWN))


func test_plus_flips_at_reveal() -> void:
	var engine := HeatTestHelpers.make_engine(1, 9)
	var p := engine.players[0]
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("four", "upg_01_4wd"))
	p.draw_pile.clear()
	p.draw_pile.add(HeatTestHelpers.card("s2", "speed_2"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["four"]).ok)
	assert_true(HeatTestHelpers.finish_settle_heat(engine, 0))
	assert_eq(p.plus_symbols_used, 1)
	assert_eq(p.round_speed, 6)
	assert_eq(p.play_area.get_by_id("s2") != null, true)


func test_plus_count_flips_each_at_reveal() -> void:
	var engine := HeatTestHelpers.make_engine(1, 9)
	var p := engine.players[0]
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("four", "upg_02_4wd"))
	p.draw_pile.clear()
	p.draw_pile.add(HeatTestHelpers.card("s1", "speed_1"))
	p.draw_pile.add(HeatTestHelpers.card("s2", "speed_2"))
	p.draw_pile.add(HeatTestHelpers.card("s3", "speed_3"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["four"]).ok)
	assert_true(HeatTestHelpers.finish_settle_heat(engine, 0))
	assert_eq(p.plus_symbols_used, 3)
	assert_eq(p.round_speed, 6)
