extends Node

## Persistent dynamic-music playback. Scenes request semantic contexts; this
## node alone owns playback position, synchronized streams and transitions.

signal music_muted_changed(muted: bool)

const SETTINGS_PATH := "user://chaleur_settings.cfg"
const DEFAULT_SONG := &"coop"
const SILENCE_DB := -80.0
const LIBRARY: DynamicMusicLibrary = preload("res://data/music/library.tres")

var music_muted: bool = false
var current_song_id: StringName
var current_context: StringName

var _players: Array[AudioStreamPlayer] = []
var _sync_streams: Array[AudioStreamSynchronized] = []
var _songs: Array[DynamicMusicSong] = []
var _active_deck: int = -1
var _mix_tween: Tween
var _deck_tween: Tween


func _ready() -> void:
	for deck in 2:
		var player := AudioStreamPlayer.new()
		player.name = "MusicDeck%d" % (deck + 1)
		player.bus = &"Music"
		add_child(player)
		_players.append(player)
		_sync_streams.append(null)
		_songs.append(null)
	_load_music_muted()
	request(DEFAULT_SONG, &"menu", false)


## Select a song and context atomically. Re-requesting the active song only
## changes its mix and deliberately preserves the playback position.
func request(song_id: StringName, context: StringName, transition: bool = true) -> void:
	if song_id == current_song_id and _active_deck >= 0:
		set_context(context, transition)
		return
	var song := LIBRARY.find_song(song_id)
	if song == null:
		push_error("Music: unknown song %s" % song_id)
		return
	var errors := song.validation_errors()
	if not errors.is_empty():
		push_error("Music: invalid song %s: %s" % [song_id, "; ".join(errors)])
		return
	_start_song(song, context, transition)


func set_context(context: StringName, transition: bool = true) -> void:
	if _active_deck < 0:
		request(DEFAULT_SONG, context, transition)
		return
	if context == current_context:
		return
	var song := _songs[_active_deck]
	var mix := song.find_mix(context)
	if mix == null:
		push_warning("Music: song %s has no %s mix; using %s" % [song.id, context, song.default_context])
		context = song.default_context
		mix = song.find_mix(context)
	if mix == null:
		return
	current_context = context
	_apply_mix(_active_deck, mix, transition)


func set_music_muted(muted: bool) -> void:
	if music_muted == muted:
		_apply_music_mute()
		return
	music_muted = muted
	_save_music_muted()
	_apply_music_mute()
	music_muted_changed.emit(muted)


func _start_song(song: DynamicMusicSong, context: StringName, transition: bool) -> void:
	_kill_mix_tween()
	_kill_deck_tween()
	var next_deck := 0 if _active_deck < 0 else 1 - _active_deck
	var player := _players[next_deck]
	player.stop()

	var synchronized := AudioStreamSynchronized.new()
	synchronized.stream_count = song.stems.size()
	for index in song.stems.size():
		var stream := song.stems[index].stream.duplicate(true) as AudioStream
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		synchronized.set_sync_stream(index, stream)
	_sync_streams[next_deck] = synchronized
	_songs[next_deck] = song
	player.stream = synchronized

	var mix := song.find_mix(context)
	if mix == null:
		context = song.default_context
		mix = song.find_mix(context)
	_set_mix_immediately(next_deck, mix)

	var previous_deck := _active_deck
	_active_deck = next_deck
	current_song_id = song.id
	current_context = context
	player.volume_db = SILENCE_DB if transition else 0.0
	player.play()
	if not transition:
		if previous_deck >= 0:
			_players[previous_deck].stop()
		return

	var duration := song.default_transition_seconds
	_deck_tween = create_tween().set_parallel(true)
	_deck_tween.tween_property(player, "volume_db", 0.0, duration)
	if previous_deck >= 0:
		var previous_player := _players[previous_deck]
		_deck_tween.tween_property(previous_player, "volume_db", SILENCE_DB, duration)
		_deck_tween.chain().tween_callback(previous_player.stop)


func _apply_mix(deck: int, mix: DynamicMusicMix, transition: bool) -> void:
	_kill_mix_tween()
	var synchronized := _sync_streams[deck]
	var song := _songs[deck]
	var targets := _target_volumes(song, mix)
	if not transition:
		for index in targets.size():
			synchronized.set_sync_stream_volume(index, targets[index])
		return
	var starts := PackedFloat32Array()
	for index in targets.size():
		starts.append(synchronized.get_sync_stream_volume(index))
	var duration := (
		mix.transition_seconds
		if mix.transition_seconds >= 0.0
		else song.default_transition_seconds
	)
	_mix_tween = create_tween()
	_mix_tween.tween_method(
		_interpolate_mix.bind(synchronized, starts, targets),
		0.0,
		1.0,
		duration,
	)


func _set_mix_immediately(deck: int, mix: DynamicMusicMix) -> void:
	if mix == null:
		return
	var targets := _target_volumes(_songs[deck], mix)
	for index in targets.size():
		_sync_streams[deck].set_sync_stream_volume(index, targets[index])


func _target_volumes(song: DynamicMusicSong, mix: DynamicMusicMix) -> PackedFloat32Array:
	var targets := PackedFloat32Array()
	for stem in song.stems:
		var level := mix.level_for(stem.id)
		targets.append(SILENCE_DB if is_zero_approx(level) else stem.trim_db + linear_to_db(level))
	return targets


func _interpolate_mix(
	weight: float,
	synchronized: AudioStreamSynchronized,
	starts: PackedFloat32Array,
	targets: PackedFloat32Array,
) -> void:
	for index in targets.size():
		synchronized.set_sync_stream_volume(index, lerpf(starts[index], targets[index], weight))


func _load_music_muted() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_muted = bool(cfg.get_value("audio", "music_muted", false))
	_apply_music_mute()


func _save_music_muted() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music_muted", music_muted)
	cfg.save(SETTINGS_PATH)


func _apply_music_mute() -> void:
	var bus_index := AudioServer.get_bus_index(&"Music")
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, music_muted)


func _kill_mix_tween() -> void:
	if _mix_tween != null:
		_mix_tween.kill()
		_mix_tween = null


func _kill_deck_tween() -> void:
	if _deck_tween != null:
		_deck_tween.kill()
		_deck_tween = null
