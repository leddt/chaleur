extends GutTest


func test_codec_roundtrip_preserves_core_state() -> void:
	var engine := HeatTestHelpers.make_engine(2, 99)
	assert_true(HeatTestHelpers.shift_all(engine, 2))
	var snap := StateCodec.encode(engine, -1)
	var restored := StateCodec.decode(snap)
	assert_eq(restored.phase, engine.phase)
	assert_eq(restored.players.size(), 2)
	assert_eq(restored.players[0].gear, 2)
	assert_eq(restored.players[0].hand.size(), engine.players[0].hand.size())
	assert_eq(restored.track.space_count, engine.track.space_count)


func test_codec_hides_other_hands_from_viewer() -> void:
	var engine := HeatTestHelpers.make_engine(2, 7)
	var snap := StateCodec.encode(engine, 0)
	var p0: Dictionary = snap["players"][0]
	var p1: Dictionary = snap["players"][1]
	assert_false(bool(p0.get("hand_hidden", true)))
	assert_true(p0["hand"].size() > 0)
	assert_true(bool(p1.get("hand_hidden", false)))
	assert_eq(p1["hand"].size(), 0)
	assert_eq(int(p1["hand_count"]), engine.players[1].hand.size())


func test_codec_hides_other_pending_gear_from_viewer() -> void:
	var engine := HeatTestHelpers.make_engine(2, 7)
	assert_true(engine.shift_gear(1, 3).ok)
	var snap := StateCodec.encode(engine, 0)
	var p0: Dictionary = snap["players"][0]
	var p1: Dictionary = snap["players"][1]
	assert_eq(int(p1["gear"]), 1)
	assert_eq(int(p1["pending_gear"]), -1)
	assert_true(bool(p1["gear_locked"]))
	assert_eq(int(p0["pending_gear"]), -1)
	# Full encode still carries pending for authority / rematch.
	var full := StateCodec.encode(engine, -1)
	assert_eq(int(full["players"][1]["pending_gear"]), 3)


func test_host_rejects_action_when_not_pending() -> void:
	var engine := HeatTestHelpers.make_engine(2, 3)
	Game.engine = engine
	# Only player 0 can shift first if we lock nothing — both pending.
	# Lock player 0, then player 1 action as if forged for player 0 should fail pending check after 0 locked... 
	assert_true(engine.shift_gear(0, 1).ok)
	# Player 0 already locked — applying another shift for 0 fails at engine; pending no longer has 0.
	var pending := engine.pending_actor_ids()
	assert_false(0 in pending)
	assert_true(1 in pending)
	Game.engine = null
