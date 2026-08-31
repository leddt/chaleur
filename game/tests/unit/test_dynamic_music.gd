extends GutTest


func test_coop_song_configuration_is_valid() -> void:
	var song := load("res://data/music/coop.tres") as DynamicMusicSong

	assert_not_null(song)
	assert_eq(song.stems.size(), 5)
	assert_eq(song.mixes.size(), 9)
	assert_true(song.validation_errors().is_empty(), "; ".join(song.validation_errors()))


func test_all_coop_stems_share_the_same_loop_length() -> void:
	var song := load("res://data/music/coop.tres") as DynamicMusicSong
	var expected := song.stems[0].stream.get_length()

	for stem in song.stems:
		assert_almost_eq(stem.stream.get_length(), expected, 0.01, str(stem.id))


func test_changing_context_preserves_the_active_playback_deck() -> void:
	Music.request(&"coop", &"menu", false)
	var active_deck: int = Music.get("_active_deck")
	var player: AudioStreamPlayer = Music.get("_players")[active_deck]

	Music.set_context(&"race_active", false)

	assert_eq(Music.get("_active_deck"), active_deck)
	assert_same(Music.get("_players")[active_deck], player)
	assert_true(player.playing)
	assert_eq(Music.current_context, &"race_active")


func test_race_context_resolves_local_active_and_waiting_states() -> void:
	var engine := HeatTestHelpers.make_engine(2, 1)

	assert_eq(
		MusicContextResolver.for_race(engine, true, 0),
		&"race_active",
	)
	engine.shift_gear(0, 2)
	assert_eq(
		MusicContextResolver.for_race(engine, true, 0),
		&"race_waiting",
	)


func test_hotseat_handoff_uses_waiting_mix() -> void:
	var engine := HeatTestHelpers.make_engine(2, 1)

	assert_eq(
		MusicContextResolver.for_race(engine, false, 0, true),
		&"race_waiting",
	)
