extends Node

## Global session state (not the rules PlayerState / engine internals).

enum Mode { NONE, LOCAL, HOST, CLIENT }

var mode: Mode = Mode.NONE
var engine: HeatGameEngine = null
## Seat index in engine.players for this machine (online or hotseat active seat).
var local_player_id: int = 0


func set_mode(new_mode: Mode) -> void:
	mode = new_mode


func is_online() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT


func start_local_race(
	player_names: Array[String] = [],
	laps: int = 1,
	race_seed: int = 0,
	track_id: String = "",
	options: RaceOptions = null,
) -> bool:
	mode = Mode.LOCAL
	if player_names.is_empty():
		player_names = ["Alice", "Bob"]
	var track: HeatTrack = null
	if not track_id.is_empty():
		track = HeatTrack.from_id(track_id, laps)
	else:
		track = HeatTrack.default_track(laps)
	if track == null or track.spline_bind == null:
		push_error("Game.start_local_race: no playable spline track")
		return false
	engine = HeatGameEngine.new()
	var seed := race_seed if race_seed != 0 else int(Time.get_unix_time_from_system())
	engine.setup(player_names, track, seed, options)
	local_player_id = 0
	return true


func race_scene_path() -> String:
	if engine != null and engine.phase == HeatGameEngine.Phase.GARAGE_DRAFT:
		return "res://ui/garage_draft.tscn"
	return "res://view/board.tscn"


func clear_race() -> void:
	engine = null
	if mode != Mode.HOST and mode != Mode.CLIENT:
		mode = Mode.NONE
	local_player_id = 0
