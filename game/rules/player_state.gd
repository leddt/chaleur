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
var turn_complete: bool = false


func reset_round_flags() -> void:
	gear_locked = false
	pending_gear = -1
	cards_locked = false
	skipped_move = false
	round_speed = 0
	corners_crossed.clear()
	has_adrenaline = false
	boost_used = false
	turn_complete = false


func engine_heat() -> int:
	return engine.count_kind(HeatCard.Kind.HEAT)


func playable_in_hand() -> Array[HeatCard]:
	var out: Array[HeatCard] = []
	for card in hand.cards:
		if card.is_playable():
			out.append(card)
	return out


func cooldown_from_gear() -> int:
	match gear:
		1:
			return 3
		2:
			return 1
		_:
			return 0


func can_boost_from_gear() -> bool:
	return gear >= 3
