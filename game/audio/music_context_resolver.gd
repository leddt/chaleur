class_name MusicContextResolver
extends RefCounted

## Translate game/presentation state into stable context names understood by songs.


static func for_race(
	engine: HeatGameEngine,
	online: bool,
	local_player_id: int,
	hotseat_handoff: bool = false,
) -> StringName:
	if engine == null:
		return &"lobby"
	if engine.is_race_over():
		return &"finish"
	var pending := engine.pending_actor_ids()
	if pending.is_empty():
		return &"race_resolution"
	if online and local_player_id not in pending:
		return &"race_waiting"
	if not online and hotseat_handoff:
		return &"race_waiting"
	return &"race_active"


static func for_garage(engine: HeatGameEngine, online: bool, local_player_id: int) -> StringName:
	if engine == null:
		return &"lobby"
	if not online:
		return &"garage_active"
	return (
		&"garage_active"
		if local_player_id in engine.pending_actor_ids()
		else &"garage_waiting"
	)
