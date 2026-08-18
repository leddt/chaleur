class_name HeatTestHelpers
extends RefCounted


static func make_engine(
	player_count: int = 2, seed: int = 42, laps: int = 1, options: RaceOptions = null
) -> HeatGameEngine:
	var names: Array[String] = []
	for i in player_count:
		names.append("P%d" % i)
	var engine := HeatGameEngine.new()
	engine.setup(names, HeatTrack.for_tests(laps), seed, options)
	return engine


static func card(id: String, def_id: String) -> HeatCard:
	return CardCatalog.make_card(id, def_id)


static func put_speed_in_hand(p: PlayerState, values: Array[int]) -> Array[String]:
	p.hand.clear()
	var ids: Array[String] = []
	for i in values.size():
		var def_id := "speed_%d" % values[i]
		var c := card("%s_test_spd_%d" % [p.display_name, i], def_id)
		p.hand.add(c)
		ids.append(c.id)
	return ids


static func ensure_engine_heat(p: PlayerState, amount: int) -> void:
	p.engine.clear()
	for i in amount:
		p.engine.add(card("%s_h_%d" % [p.display_name, i], "heat"))


static func shift_all(engine: HeatGameEngine, gear: int = 1) -> bool:
	for p in engine.players:
		if p.finished:
			continue
		if not engine.shift_gear(p.id, gear).ok:
			return false
	return true


static func play_speeds(engine: HeatGameEngine, player_id: int, values: Array[int]) -> bool:
	var p := engine.players[player_id]
	var ids := put_speed_in_hand(p, values)
	while p.hand.size() < 7:
		p.hand.add(card("%s_pad_%d" % [p.display_name, p.hand.size()], "speed_1"))
	var play_ids: Array[String] = []
	for i in mini(p.gear, ids.size()):
		play_ids.append(ids[i])
	return engine.play_cards(player_id, play_ids).ok
