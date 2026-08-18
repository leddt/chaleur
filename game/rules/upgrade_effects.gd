class_name UpgradeEffects
extends RefCounted

## Garage upgrade resolution: mandatory at reveal, optionals during React.


static func apply_reveal(engine: HeatGameEngine, p: PlayerState) -> void:
	p.pending_symbols.clear()
	p.refresh_card_ids.clear()
	p.accelerate_used = false
	p.plus_symbols_used = 0
	p.speed_limit_adjust = 0
	p.slipstream_bonus = 0
	p.cooldown_bonus = 0
	# Stress: flip until speed (counts as + for Accelerate). Do not move yet.
	for card in p.play_area.cards.duplicate():
		if card.kind != HeatCard.Kind.STRESS:
			continue
		p.plus_symbols_used += 1
		var speed_card := engine._flip_until_speed(p)
		if speed_card:
			p.play_area.add(speed_card)
			engine._log("%s resolves Stress -> Speed %d" % [p.display_name, speed_card.speed_value])
	var surviving: Array[HeatCard] = []
	for card in p.play_area.cards.duplicate():
		if card.kind == HeatCard.Kind.STRESS:
			surviving.append(card)
			continue
		var kept := _apply_mandatory(engine, p, card)
		if kept == null:
			var fallback := engine._flip_until_speed(p)
			if fallback:
				surviving.append(fallback)
				engine._log(
					"%s heat-fallback -> Speed %d" % [p.display_name, fallback.speed_value]
				)
			continue
		surviving.append(card)
		_queue_optionals(p, card)
	p.play_area.clear()
	p.play_area.add_many(surviving)


static func apply_direct_play(engine: HeatGameEngine, p: PlayerState, card: HeatCard) -> bool:
	var kept := _apply_mandatory(engine, p, card)
	if kept == null:
		var fallback := engine._flip_until_speed(p)
		if fallback:
			p.play_area.add(fallback)
			p.round_speed += fallback.speed_value
			engine._move_player(p, fallback.speed_value, false)
			engine._check_finish(p)
			engine._log(
				"%s Direct Play heat-fallback -> Speed %d" % [p.display_name, fallback.speed_value]
			)
		return false
	p.play_area.add(card)
	_queue_optionals(p, card)
	if card.contributes_speed_when_played():
		p.round_speed += card.speed_value
		engine._move_player(p, card.speed_value, false)
		engine._check_finish(p)
		engine._log("%s Direct Play %s +%d" % [p.display_name, card.def_id, card.speed_value])
	else:
		engine._log("%s Direct Play %s" % [p.display_name, card.def_id])
	return true


static func _apply_mandatory(engine: HeatGameEngine, p: PlayerState, card: HeatCard) -> HeatCard:
	var def := CardCatalog.get_def(card.def_id)
	for s in def.symbols:
		if not CardSymbol.is_mandatory(s.kind):
			continue
		match s.kind:
			CardSymbol.Kind.HEAT:
				if not engine._pay_heat(p, s.count):
					engine._log(
						"%s cannot pay Heat for %s — discard and flip" % [p.display_name, card.def_id]
					)
					p.discard.add(card)
					return null
				engine._log("%s pays %d Heat for %s" % [p.display_name, s.count, card.def_id])
			CardSymbol.Kind.SCRAP:
				_scrap(engine, p, s.count)
				engine._log("%s scraps %d" % [p.display_name, s.count])
			CardSymbol.Kind.ADJUST_SPEED_LIMIT:
				p.speed_limit_adjust += s.count
				engine._log("%s adjust speed limit %+d" % [p.display_name, s.count])
	return card


static func _queue_optionals(p: PlayerState, card: HeatCard) -> void:
	var def := CardCatalog.get_def(card.def_id)
	for s in def.symbols:
		if CardSymbol.is_mandatory(s.kind) or s.kind == CardSymbol.Kind.DIRECT_PLAY:
			continue
		if s.kind == CardSymbol.Kind.COOLDOWN:
			p.cooldown_bonus += maxi(1, s.count)
			continue
		if s.kind == CardSymbol.Kind.PLUS:
			for i in maxi(1, s.count):
				p.pending_symbols.append(
					{"card_id": card.id, "kind": int(s.kind), "count": 1, "uid": "%s_plus_%d" % [card.id, i]}
				)
			continue
		p.pending_symbols.append(
			{"card_id": card.id, "kind": int(s.kind), "count": s.count, "uid": "%s_%d" % [card.id, int(s.kind)]}
		)


static func _scrap(engine: HeatGameEngine, p: PlayerState, n: int) -> void:
	for _i in n:
		if p.draw_pile.is_empty():
			if p.discard.is_empty():
				return
			p.draw_pile.add_many(p.discard.cards)
			p.discard.clear()
			p.draw_pile.shuffle(engine.rng)
		var top := p.draw_pile.draw_top()
		if top:
			p.discard.add(top)


static func use_symbol(
	engine: HeatGameEngine, p: PlayerState, uid: String, payload: Dictionary = {}
) -> ActionResult:
	var idx := _index_of(p, uid)
	if idx < 0:
		return ActionResult.fail("Unknown upgrade symbol")
	var entry: Dictionary = p.pending_symbols[idx]
	var kind := entry.get("kind", 0) as CardSymbol.Kind
	var count := int(entry.get("count", 1))
	var card_id := str(entry.get("card_id", ""))
	match kind:
		CardSymbol.Kind.PLUS:
			var flipped := engine._flip_until_speed(p)
			if flipped == null:
				return ActionResult.fail("No speed card to flip")
			p.play_area.add(flipped)
			p.round_speed += flipped.speed_value
			p.plus_symbols_used += 1
			engine._move_player(p, flipped.speed_value, false)
			engine._check_finish(p)
			engine._log("%s + -> Speed %d" % [p.display_name, flipped.speed_value])
		CardSymbol.Kind.SLIPSTREAM_BOOST:
			p.slipstream_bonus += count
			engine._log("%s slipstream boost +%d" % [p.display_name, count])
		CardSymbol.Kind.REDUCE_STRESS:
			var n := 0
			var wanted := count
			var ids: Array = payload.get("card_ids", [])
			if ids.is_empty():
				for card in p.hand.cards.duplicate():
					if n >= wanted:
						break
					if card.kind == HeatCard.Kind.STRESS:
						p.hand.remove_id(card.id)
						p.discard.add(card)
						n += 1
			else:
				for cid in ids:
					if n >= wanted:
						break
					var card := p.hand.get_by_id(str(cid))
					if card == null or card.kind != HeatCard.Kind.STRESS:
						return ActionResult.fail("Not a Stress card")
					p.hand.remove_id(str(cid))
					p.discard.add(card)
					n += 1
			engine._log("%s reduces stress %d" % [p.display_name, n])
		CardSymbol.Kind.SALVAGE:
			var salvage_ids: Array = payload.get("card_ids", [])
			if salvage_ids.size() > count:
				return ActionResult.fail("Too many salvage cards")
			for cid in salvage_ids:
				var card := p.discard.remove_id(str(cid))
				if card == null:
					return ActionResult.fail("Card not in discard")
				p.draw_pile.add(card)
			p.draw_pile.shuffle(engine.rng)
			engine._log("%s salvages %d" % [p.display_name, salvage_ids.size()])
		CardSymbol.Kind.REFRESH:
			if card_id not in p.refresh_card_ids:
				p.refresh_card_ids.append(card_id)
			engine._log("%s refresh %s" % [p.display_name, card_id])
		CardSymbol.Kind.ACCELERATE:
			if p.accelerate_used:
				return ActionResult.fail("Accelerate already used")
			p.accelerate_used = true
			var bonus := p.plus_symbols_used
			p.round_speed += bonus
			engine._move_player(p, bonus, false)
			engine._check_finish(p)
			engine._log("%s accelerate +%d" % [p.display_name, bonus])
		_:
			return ActionResult.fail("Symbol not usable")
	p.pending_symbols.remove_at(idx)
	return ActionResult.success()


static func _index_of(p: PlayerState, uid: String) -> int:
	for i in p.pending_symbols.size():
		if str(p.pending_symbols[i].get("uid", "")) == uid:
			return i
	return -1


static func queue_direct_play_from_hand(p: PlayerState) -> void:
	for card in p.hand.cards:
		var def := CardCatalog.get_def(card.def_id)
		if def.has_symbol(CardSymbol.Kind.DIRECT_PLAY):
			p.pending_symbols.append(
				{
					"card_id": card.id,
					"kind": int(CardSymbol.Kind.DIRECT_PLAY),
					"count": 1,
					"uid": "%s_direct" % card.id,
				}
			)
