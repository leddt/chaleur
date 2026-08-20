class_name DeckFactory
extends RefCounted


static func build_starter_draw(
	player_id: int, stress_count: int, include_starter_upgrades: bool = true
) -> Array[HeatCard]:
	var cards: Array[HeatCard] = []
	for speed in [1, 2, 3, 4]:
		for copy in 3:
			cards.append(
				CardCatalog.make_card("p%d_spd_%d_%d" % [player_id, speed, copy], "speed_%d" % speed)
			)
	if include_starter_upgrades:
		cards.append(CardCatalog.make_card("p%d_upg_0" % player_id, "starter_speed_0"))
		cards.append(CardCatalog.make_card("p%d_upg_5" % player_id, "starter_speed_5"))
		cards.append(CardCatalog.make_card("p%d_upg_heat" % player_id, "starter_heat"))
	for s in stress_count:
		cards.append(CardCatalog.make_card("p%d_stress_%d" % [player_id, s], "stress"))
	return cards


static func build_engine_heat(player_id: int, heat_count: int) -> Array[HeatCard]:
	var cards: Array[HeatCard] = []
	for h in heat_count:
		cards.append(CardCatalog.make_card("p%d_heat_%d" % [player_id, h], "heat"))
	return cards


static func build_stress_reserve(count: int = 40) -> CardPile:
	var pile := CardPile.new()
	for i in count:
		pile.add(CardCatalog.make_card("reserve_stress_%d" % i, "stress"))
	return pile
