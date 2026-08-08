extends Node

## Presentation-layer sound effects (not part of the rules engine).

const SETTINGS_PATH := "user://chaleur_settings.cfg"

const _STREAMS := {
	"engine": preload("res://assets/sfx/engine.mp3"),
	"fail": preload("res://assets/sfx/fail.mp3"),
	"finish_line": preload("res://assets/sfx/finish-line.mp3"),
	"podium": preload("res://assets/sfx/podium.mp3"),
	"spinout": preload("res://assets/sfx/spinout.mp3"),
	"button": preload("res://assets/sfx/button.mp3"),
	"boost": preload("res://assets/sfx/boost.mp3"),
	"slipstream": preload("res://assets/sfx/slipstream.mp3"),
	"lever": preload("res://assets/sfx/lever.mp3"),
}

const _RACE_MUSIC := preload("res://assets/loop.ogg")
const _RACE_MUSIC_VOLUME := 0.3
const _FADE_IN_SEC := 2.5
const _FADE_OUT_SEC := 0.35
const _MUTE_DB := -80.0

var music_muted: bool = false

var _players: Dictionary = {} # id -> AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_tween: Tween


func _ready() -> void:
	for id in _STREAMS.keys():
		var player := AudioStreamPlayer.new()
		player.name = "Sfx_%s" % id
		player.stream = _STREAMS[id]
		add_child(player)
		_players[id] = player
	_music = AudioStreamPlayer.new()
	_music.name = "Music_race"
	var stream := _RACE_MUSIC.duplicate() as AudioStreamOggVorbis
	if stream != null:
		stream.loop = true
		_music.stream = stream
	else:
		_music.stream = _RACE_MUSIC
	_music.volume_db = linear_to_db(_RACE_MUSIC_VOLUME)
	add_child(_music)
	_load_music_muted()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_hook_existing_buttons")


func play(id: String) -> void:
	var player: AudioStreamPlayer = _players.get(id) as AudioStreamPlayer
	if player == null or player.stream == null:
		return
	player.play()


func stop(id: String) -> void:
	var player: AudioStreamPlayer = _players.get(id) as AudioStreamPlayer
	if player == null:
		return
	player.stop()


func set_music_muted(muted: bool) -> void:
	if music_muted == muted:
		_apply_music_mute()
		return
	music_muted = muted
	_save_music_muted()
	_apply_music_mute()


## Start (or restart) the in-race loop with a fade-in to ~30% volume.
func start_race_music() -> void:
	stop("podium")
	_kill_music_tween()
	if _music.stream == null:
		return
	_music.play()
	if music_muted:
		_music.volume_db = _MUTE_DB
		return
	_music.volume_db = linear_to_db(0.01)
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", linear_to_db(_RACE_MUSIC_VOLUME), _FADE_IN_SEC)


## Fade out the race loop so podium (or UI) can take over.
func stop_race_music(fade := true) -> void:
	_kill_music_tween()
	if _music == null or not _music.playing:
		return
	if not fade or music_muted:
		_music.stop()
		return
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", linear_to_db(0.01), _FADE_OUT_SEC)
	_music_tween.tween_callback(_music.stop)


## Map authoritative event_log lines to SFX (used when the UI journal advances).
func play_for_log_line(line: String) -> void:
	if "reveals speed" in line and "moves" in line:
		play("engine")
	elif "boosts for" in line or "uses adrenaline" in line:
		play("boost")
	elif "slipstreams" in line:
		play("slipstream")
	elif "All gears locked" in line:
		play("lever")
	elif "cluttered — no move" in line:
		play("fail")
	elif "crossed the finish line" in line:
		play("finish_line")
	elif "spins out at" in line:
		play("spinout")


func _apply_music_mute() -> void:
	_kill_music_tween()
	if _music == null or not _music.playing:
		return
	if music_muted:
		_music.volume_db = _MUTE_DB
	else:
		_music.volume_db = linear_to_db(_RACE_MUSIC_VOLUME)


func _load_music_muted() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	music_muted = bool(cfg.get_value("audio", "music_muted", false))
	_apply_music_mute()


func _save_music_muted() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music_muted", music_muted)
	cfg.save(SETTINGS_PATH)


func _kill_music_tween() -> void:
	if _music_tween != null:
		_music_tween.kill()
		_music_tween = null


func _hook_existing_buttons() -> void:
	_hook_tree(get_tree().root)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node as BaseButton)


func _hook_tree(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node as BaseButton)
	for child in node.get_children():
		_hook_tree(child)


func _hook_button(button: BaseButton) -> void:
	if button.get_meta("_sfx_button_hooked", false):
		return
	button.set_meta("_sfx_button_hooked", true)
	button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play("button")
