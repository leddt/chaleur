class_name DeckFactory
extends RefCounted


static func build_starter_draw(player_id: int, stress_count: int) -> Array[HeatCard]:
	var cards: Array[HeatCard] = []
	var n := 0
	for speed in [1, 2, 3, 4]:
		for copy in 3:
			n += 1
			cards.append(HeatCard.new("p%d_spd_%d_%d" % [player_id, speed, copy], HeatCard.Kind.SPEED, speed))
	for upgrade_speed in [1, 2, 3]:
		n += 1
		cards.append(HeatCard.new("p%d_upg_%d" % [player_id, upgrade_speed], HeatCard.Kind.UPGRADE, upgrade_speed))
	for s in stress_count:
		cards.append(HeatCard.new("p%d_stress_%d" % [player_id, s], HeatCard.Kind.STRESS, 0))
	return cards


static func build_engine_heat(player_id: int, heat_count: int) -> Array[HeatCard]:
	var cards: Array[HeatCard] = []
	for h in heat_count:
		cards.append(HeatCard.new("p%d_heat_%d" % [player_id, h], HeatCard.Kind.HEAT, 0))
	return cards


static func build_stress_reserve(count: int = 40) -> CardPile:
	var pile := CardPile.new()
	for i in count:
		pile.add(HeatCard.new("reserve_stress_%d" % i, HeatCard.Kind.STRESS, 0))
	return pile
