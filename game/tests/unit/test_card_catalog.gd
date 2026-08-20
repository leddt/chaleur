extends GutTest


func test_catalog_loads_core_definitions() -> void:
	assert_true(CardCatalog.has("speed_1"))
	assert_true(CardCatalog.has("starter_speed_0"))
	assert_true(CardCatalog.has("starter_speed_5"))
	assert_true(CardCatalog.has("starter_heat"))
	assert_true(CardCatalog.has("upg_01_4wd"))
	assert_true(CardCatalog.has("upg_24_gas_pedal"))


func test_starter_draw_composition() -> void:
	var cards := DeckFactory.build_starter_draw(0, 3)
	var counts: Dictionary = {}
	for card in cards:
		counts[card.def_id] = int(counts.get(card.def_id, 0)) + 1
	assert_eq(counts.get("speed_1", 0), 3)
	assert_eq(counts.get("speed_2", 0), 3)
	assert_eq(counts.get("speed_3", 0), 3)
	assert_eq(counts.get("speed_4", 0), 3)
	assert_eq(counts.get("starter_speed_0", 0), 1)
	assert_eq(counts.get("starter_speed_5", 0), 1)
	assert_eq(counts.get("starter_heat", 0), 1)
	assert_eq(counts.get("stress", 0), 3)
	assert_eq(cards.size(), 18)


func test_starter_speed_5_contributes_to_reveal() -> void:
	var engine := HeatTestHelpers.make_engine(1, 42)
	var p := engine.players[0]
	p.hand.clear()
	p.hand.add(HeatTestHelpers.card("upg5", "starter_speed_5"))
	assert_true(HeatTestHelpers.shift_all(engine, 1))
	assert_true(engine.play_cards(0, ["upg5"]).ok)
	assert_eq(p.round_speed, 5)


func test_starter_heat_behaves_like_heat() -> void:
	var card := HeatTestHelpers.card("h_upg", "starter_heat")
	assert_eq(card.kind, HeatCard.Kind.HEAT)
	assert_false(card.can_discard())
	assert_false(card.is_playable())
	assert_false(card.contributes_speed_when_played())


func test_track_reads_start_heat_and_stress_from_document() -> void:
	var data := {
		"version": SplineTrackFile.VERSION,
		"name": "Heat Stress Test",
		"spline": TrackSpline.make_default_triangle(Vector2(400, 300), 140.0).to_dict(),
		"start_heat": 4,
		"start_stress": 2,
	}
	var track := HeatTrack.from_document(data, 1)
	assert_ne(track, null)
	assert_eq(track.start_heat, 4)
	assert_eq(track.start_stress, 2)


func test_state_codec_round_trips_def_id() -> void:
	var engine := HeatTestHelpers.make_engine(2, 7)
	var snap := StateCodec.encode(engine, -1)
	var restored := StateCodec.decode(snap)
	for i in engine.players.size():
		assert_eq(restored.players[i].draw_pile.size(), engine.players[i].draw_pile.size())
		if not engine.players[i].draw_pile.is_empty():
			assert_eq(
				restored.players[i].draw_pile.cards[0].def_id,
				engine.players[i].draw_pile.cards[0].def_id
			)
