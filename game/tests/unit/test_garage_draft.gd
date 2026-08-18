extends GutTest


func test_catalog_loads_garage_definitions() -> void:
	assert_true(CardCatalog.has("upg_01_4wd"))
	assert_true(CardCatalog.has("upg_17_heat"))
	assert_true(CardCatalog.has("upg_24_gas_pedal"))
	assert_true(CardCatalog.has("upg_48_heat"))
	assert_false(CardCatalog.is_advanced("upg_01_4wd"))
	assert_true(CardCatalog.is_advanced("upg_24_gas_pedal"))


func test_garage_pool_sizes() -> void:
	var basic := GarageDeckFactory.build_pool(true, false)
	var advanced := GarageDeckFactory.build_pool(false, true)
	var both := GarageDeckFactory.build_pool(true, true)
	assert_eq(basic.size(), 17)
	assert_eq(advanced.size(), 31)
	assert_eq(both.size(), 48)


func test_garage_draft_market_size_and_order() -> void:
	var opts := RaceOptions.new()
	opts.garage_enabled = true
	opts.garage_include_basic = true
	opts.garage_quick_start = false
	var engine := HeatTestHelpers.make_engine(2, 11, 1, opts)
	assert_eq(engine.phase, HeatGameEngine.Phase.GARAGE_DRAFT)
	assert_eq(engine.garage_draft_round, 1)
	assert_eq(engine.garage_market.size(), 5)
	assert_eq(engine.grid_order.size(), 2)
	var first_order := engine.garage_pick_order()
	assert_eq(first_order[0], engine.grid_order[1])
	assert_eq(engine.garage_picker_id(), first_order[0])
	var market_ids := engine.garage_market.ids()
	assert_true(engine.pick_garage_card(first_order[0], market_ids[0]).ok)
	assert_true(engine.pick_garage_card(first_order[1], market_ids[1]).ok)
	assert_eq(engine.garage_draft_round, 2)
	assert_eq(engine.garage_market.size(), 5)
	var second := engine.garage_pick_order()
	assert_eq(second[0], engine.grid_order[0])
	var m2 := engine.garage_market.ids()
	assert_true(engine.pick_garage_card(second[0], m2[0]).ok)
	assert_true(engine.pick_garage_card(second[1], m2[1]).ok)
	assert_eq(engine.garage_draft_round, 3)
	var third := engine.garage_pick_order()
	assert_eq(third[0], engine.grid_order[1])
	var m3 := engine.garage_market.ids()
	assert_true(engine.pick_garage_card(third[0], m3[0]).ok)
	assert_true(engine.pick_garage_card(third[1], m3[1]).ok)
	assert_eq(engine.phase, HeatGameEngine.Phase.SHIFT_GEARS)
	assert_eq(engine.players[0].hand.size(), 7)
	assert_eq(engine.players[1].hand.size(), 7)
	assert_eq(engine.players[0].garage_upgrades.size(), 3)
	assert_false(_has_starter_upgrades(engine.players[0]))


func test_garage_quick_start_deals_three() -> void:
	var opts := RaceOptions.new()
	opts.garage_enabled = true
	opts.garage_quick_start = true
	opts.garage_include_basic = true
	var engine := HeatTestHelpers.make_engine(2, 5, 1, opts)
	assert_eq(engine.phase, HeatGameEngine.Phase.SHIFT_GEARS)
	assert_eq(engine.players[0].garage_upgrades.size(), 3)
	assert_eq(engine.players[1].garage_upgrades.size(), 3)
	assert_eq(engine.players[0].hand.size(), 7)
	assert_false(_has_starter_upgrades(engine.players[0]))


func test_garage_draft_codec_roundtrip() -> void:
	var opts := RaceOptions.new()
	opts.garage_enabled = true
	opts.garage_include_basic = true
	var engine := HeatTestHelpers.make_engine(2, 9, 1, opts)
	var snap := StateCodec.encode(engine, -1)
	var restored := StateCodec.decode(snap)
	assert_eq(restored.phase, HeatGameEngine.Phase.GARAGE_DRAFT)
	assert_eq(restored.garage_market.size(), engine.garage_market.size())
	assert_eq(restored.garage_draft_round, 1)
	assert_eq(restored.grid_order, engine.grid_order)
	assert_true(restored.options.garage_enabled)


func _has_starter_upgrades(p: PlayerState) -> bool:
	for pile in [p.draw_pile, p.hand, p.garage_upgrades]:
		for card in pile.cards:
			if card.def_id.begins_with("starter_"):
				return true
	return false
