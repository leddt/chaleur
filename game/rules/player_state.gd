class_name PlayerState
extends RefCounted

var id: int = 0
var display_name: String = ""
var gear: int = 1
## Spaces advanced from the start line. Finish at track.finish_progress().
var progress: int = 0
var spot: int = 0
var finished: bool = false
var finish_rank: int = -1

var draw_pile: CardPile = CardPile.new()
var hand: CardPile = CardPile.new()
var play_area: CardPile = CardPile.new()
var discard: CardPile = CardPile.new()
var engine: CardPile = CardPile.new()

# Per-round / per-turn working data
var gear_locked: bool = false
## Chosen gear before simultaneous reveal (-1 = none).
var pending_gear: int = -1
var cards_locked: bool = false
var skipped_move: bool = false
var round_speed: int = 0
var corners_crossed: Array[String] = []
var has_adrenaline: bool = false
var boost_used: bool = false
var adrenaline_speed_used: bool = false
var cooldown_used: int = 0
var cooldown_bonus: int = 0
var turn_complete: bool = false
var speed_limit_adjust: int = 0
var slipstream_bonus: int = 0
var plus_symbols_used: int = 0
## Cards whose mandatory Plus has already been flipped (idempotent).
var plus_resolved_card_ids: Array[String] = []
var refresh_card_ids: Array[String] = []
var accelerate_used: bool = false
var pending_symbols: Array[Dictionary] = []
## Mandatory Heat still owed for cards in play ({card_id, count, uid}).
var pending_heat_debts: Array[Dictionary] = []
var garage_upgrades: CardPile = CardPile.new()


func reset_round_flags() -> void:
	gear_locked = false
	pending_gear = -1
	cards_locked = false
	skipped_move = false
	round_speed = 0
	corners_crossed.clear()
	has_adrenaline = false
	boost_used = false
	adrenaline_speed_used = false
	cooldown_used = 0
	cooldown_bonus = 0
	turn_complete = false
	speed_limit_adjust = 0
	slipstream_bonus = 0
	plus_symbols_used = 0
	plus_resolved_card_ids.clear()
	refresh_card_ids.clear()
	accelerate_used = false
	pending_symbols.clear()
	pending_heat_debts.clear()


func engine_heat() -> int:
	return engine.count_kind(HeatCard.Kind.HEAT)


func playable_in_hand() -> Array[HeatCard]:
	var out: Array[HeatCard] = []
	for card in hand.cards:
		if card.is_playable():
			out.append(card)
	return out


func cooldown_from_gear() -> int:
	return cooldown_for_gear(gear)


static func cooldown_for_gear(gear: int) -> int:
	match gear:
		1:
			return 3
		2:
			return 1
		_:
			return 0


func max_cooldown() -> int:
	var n := cooldown_from_gear() + cooldown_bonus
	if has_adrenaline:
		n += 1
	return n


func cooldown_remaining() -> int:
	return maxi(0, max_cooldown() - cooldown_used)


func can_use_boost() -> bool:
	return not boost_used and engine_heat() >= 1


func can_use_adrenaline() -> bool:
	return has_adrenaline and not adrenaline_speed_used


func can_use_cooldown() -> bool:
	return cooldown_remaining() > 0 and hand.count_kind(HeatCard.Kind.HEAT) >= 1


func has_pending_heat_debts() -> bool:
	return not pending_heat_debts.is_empty()


func can_pay_any_heat_debt() -> bool:
	for debt in pending_heat_debts:
		if engine_heat() >= int(debt.get("count", 0)):
			return true
	return false


func has_pending_react_options() -> bool:
	if has_unresolved_speeds():
		return true
	if has_pending_heat_debts() and can_pay_any_heat_debt():
		return true
	if can_use_boost() or can_use_adrenaline() or can_use_cooldown():
		return true
	return not pending_symbols.is_empty()


func has_unresolved_speeds() -> bool:
	for card in play_area.cards:
		if card.needs_speed_choice():
			return true
	return false
