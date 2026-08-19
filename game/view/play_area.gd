class_name PlayAreaView
extends Control

## Cards currently in play, same size as the hand, sitting to its right.

signal symbol_activated(card_id: String, kind: CardSymbol.Kind)
signal speed_picked(card_id: String, speed: int)

const CARD_GAP := 10.0

var _cards: Array[Card] = []


func _ready() -> void:
	clip_contents = false
	resized.connect(_layout_row)
	visibility_changed.connect(_layout_row)


func clear_area() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()
	visible = false
	custom_minimum_size.x = 0.0


func set_from_player(p: PlayerState, turn_step: HeatGameEngine.TurnStep) -> void:
	clear_area()
	if p == null or p.play_area.is_empty():
		return
	visible = true
	for heat_card in p.play_area.cards:
		var card := Card.new()
		card.card_size = _card_size()
		card.data = CardCatalog.to_card_data(heat_card.def_id)
		card.set_meta("card_id", heat_card.id)
		var cid := heat_card.id
		card.symbol_activated.connect(func(kind: CardSymbol.Kind) -> void:
			symbol_activated.emit(cid, kind)
		)
		card.speed_picked.connect(func(speed: int) -> void:
			speed_picked.emit(cid, speed)
		)
		add_child(card)
		card.set_symbol_states(_states_for(p, heat_card, turn_step))
		if heat_card.chosen_speed >= 0:
			card.set_resolved_speed(heat_card.chosen_speed)
		elif turn_step == HeatGameEngine.TurnStep.REACT and heat_card.needs_speed_choice():
			card.set_speed_pick(CardCatalog.get_def(heat_card.def_id).resolved_speed_options(), true)
		_cards.append(card)
	_layout_row()
	call_deferred("_layout_row")


func _card_size() -> Vector2:
	var hover_room := 22.0
	var max_h := maxf(72.0, size.y - hover_room)
	var design := CardHandView.CARD_SIZE
	if design.y <= max_h or size.y <= 1.0:
		return design
	return design * (max_h / design.y)


func _layout_row() -> void:
	if _cards.is_empty():
		custom_minimum_size.x = 0.0
		return
	var n := _cards.size()
	var cs := _card_size()
	var gap := CARD_GAP * (cs.x / CardHandView.CARD_SIZE.x)
	var span := float(n) * cs.x + float(n - 1) * gap
	custom_minimum_size.x = span
	var step := cs.x + gap
	if size.x > 1.0 and span > size.x and n > 1:
		step = maxf(cs.x * 0.45, (size.x - cs.x) / float(n - 1))
		span = step * float(n - 1) + cs.x
	var start_x := maxf(0.0, (size.x - span) * 0.5)
	var start_y := size.y - cs.y - 4.0
	if start_y < 0.0:
		start_y = 0.0
	for i in n:
		var card := _cards[i]
		card.card_size = cs
		card.rotation = 0.0
		card.position = Vector2(start_x + float(i) * step, start_y)
		card.set_rest_y(start_y)


static func pending_uid(p: PlayerState, card_id: String, kind: CardSymbol.Kind) -> String:
	if kind == CardSymbol.Kind.HEAT:
		for debt in p.pending_heat_debts:
			if str(debt.get("card_id", "")) == card_id:
				return str(debt.get("uid", ""))
		return ""
	for entry in p.pending_symbols:
		if str(entry.get("card_id", "")) != card_id:
			continue
		if int(entry.get("kind", -1)) != int(kind):
			continue
		return str(entry.get("uid", ""))
	return ""


static func _has_pending(p: PlayerState, card_id: String, kind: CardSymbol.Kind) -> bool:
	return not pending_uid(p, card_id, kind).is_empty()


static func _states_for(
	p: PlayerState, card: HeatCard, turn_step: HeatGameEngine.TurnStep
) -> Dictionary:
	var out := {}
	var settle := turn_step == HeatGameEngine.TurnStep.SETTLE_HEAT
	var react := turn_step == HeatGameEngine.TurnStep.REACT
	var def := CardCatalog.get_def(card.def_id)
	for s in def.symbols:
		out[int(s.kind)] = _state_for_kind(p, card.id, s.kind, settle, react)
	return out


static func _state_for_kind(
	p: PlayerState,
	card_id: String,
	kind: CardSymbol.Kind,
	settle: bool,
	react: bool,
) -> String:
	match kind:
		CardSymbol.Kind.HEAT:
			if not _has_pending(p, card_id, kind):
				return CardSymbolIcon.STATE_RESOLVED
			if (settle or react) and p.engine_heat() >= _heat_cost(p, card_id):
				return CardSymbolIcon.STATE_CLICKABLE
			return CardSymbolIcon.STATE_INERT
		CardSymbol.Kind.SCRAP, CardSymbol.Kind.ADJUST_SPEED_LIMIT, CardSymbol.Kind.COOLDOWN:
			return CardSymbolIcon.STATE_RESOLVED
		CardSymbol.Kind.PLUS:
			if card_id in p.plus_resolved_card_ids:
				return CardSymbolIcon.STATE_RESOLVED
			return CardSymbolIcon.STATE_INERT
		CardSymbol.Kind.DIRECT_PLAY:
			return CardSymbolIcon.STATE_INERT
		_:
			if not _has_pending(p, card_id, kind):
				return CardSymbolIcon.STATE_RESOLVED
			if react:
				return CardSymbolIcon.STATE_CLICKABLE
			return CardSymbolIcon.STATE_INERT


static func _heat_cost(p: PlayerState, card_id: String) -> int:
	for debt in p.pending_heat_debts:
		if str(debt.get("card_id", "")) == card_id:
			return int(debt.get("count", 0))
	return 0
