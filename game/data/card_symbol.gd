class_name CardSymbol
extends Resource

## One icon on an upgrade card. Mandatory vs optional is inherent to `kind`.

enum Kind {
	HEAT, ## Mandatory: pay this many Heat from the Engine.
	SCRAP, ## Mandatory: discard this many cards from the top of the draw pile.
	ADJUST_SPEED_LIMIT, ## Mandatory: modify this turn's corner limits by `count`.
	SALVAGE,
	COOLDOWN,
	SLIPSTREAM_BOOST,
	REDUCE_STRESS,
	REFRESH,
	DIRECT_PLAY,
	ACCELERATE,
	PLUS, ## Optional extra flip-until-speed (also used by Boost / Stress counting).
}

@export var kind: Kind = Kind.HEAT
## Magnitude: Heat paid, cards scrapped, limit delta (may be negative), etc.
@export var count: int = 1


static func is_mandatory(p_kind: Kind) -> bool:
	return (
		p_kind == Kind.HEAT
		or p_kind == Kind.SCRAP
		or p_kind == Kind.ADJUST_SPEED_LIMIT
	)


static func make(p_kind: Kind, p_count: int = 1) -> CardSymbol:
	var s := CardSymbol.new()
	s.kind = p_kind
	s.count = p_count
	return s


func label() -> String:
	match kind:
		Kind.HEAT:
			return "Heat %d" % count
		Kind.SCRAP:
			return "Scrap %d" % count
		Kind.ADJUST_SPEED_LIMIT:
			if count >= 0:
				return "Limite +%d" % count
			return "Limite %d" % count
		Kind.SALVAGE:
			return "Salvage %d" % count
		Kind.COOLDOWN:
			return "Cooldown %d" % count
		Kind.SLIPSTREAM_BOOST:
			return "Slipstream +%d" % count
		Kind.REDUCE_STRESS:
			return "Stress −%d" % count
		Kind.REFRESH:
			return "Refresh"
		Kind.DIRECT_PLAY:
			return "Direct Play"
		Kind.ACCELERATE:
			return "Accelerate"
		Kind.PLUS:
			return "+ ×%d" % count
	return "?"
