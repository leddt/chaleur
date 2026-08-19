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
	PLUS, ## Mandatory: flip until Speed when the card is revealed.
}

@export var kind: Kind = Kind.HEAT
## Magnitude: Heat paid, cards scrapped, limit delta (may be negative), etc.
@export var count: int = 1


static func is_mandatory(p_kind: Kind) -> bool:
	return (
		p_kind == Kind.HEAT
		or p_kind == Kind.SCRAP
		or p_kind == Kind.ADJUST_SPEED_LIMIT
		or p_kind == Kind.PLUS
	)


static func make(p_kind: Kind, p_count: int = 1) -> CardSymbol:
	var s := CardSymbol.new()
	s.kind = p_kind
	s.count = p_count
	return s


func label() -> String:
	return display_name()


static func shows_count(p_kind: Kind) -> bool:
	return (
		p_kind == Kind.HEAT
		or p_kind == Kind.SCRAP
		or p_kind == Kind.ADJUST_SPEED_LIMIT
		or p_kind == Kind.SALVAGE
		or p_kind == Kind.COOLDOWN
		or p_kind == Kind.SLIPSTREAM_BOOST
		or p_kind == Kind.REDUCE_STRESS
		or p_kind == Kind.PLUS
	)


func display_name() -> String:
	match kind:
		Kind.HEAT:
			return "Heat %d" % count
		Kind.SCRAP:
			return "Scrap %d" % count
		Kind.ADJUST_SPEED_LIMIT:
			if count >= 0:
				return "Adjust Speed Limit +%d" % count
			return "Adjust Speed Limit %d" % count
		Kind.SALVAGE:
			return "Salvage %d" % count
		Kind.COOLDOWN:
			return "Cooldown %d" % count
		Kind.SLIPSTREAM_BOOST:
			return "Slipstream boost %d" % count
		Kind.REDUCE_STRESS:
			return "Reduce stress %d" % count
		Kind.REFRESH:
			return "Refresh"
		Kind.DIRECT_PLAY:
			return "Direct play"
		Kind.ACCELERATE:
			return "Accelerate"
		Kind.PLUS:
			return "Plus ×%d" % count
	return "?"


func tooltip_bbcode(extra: Dictionary = {}) -> String:
	var body := _tooltip_body(extra)
	var title := display_name()
	if is_mandatory(kind):
		title += " (obligatoire)"
	return "[b]%s[/b]\n%s" % [title, body]


func _tooltip_body(extra: Dictionary = {}) -> String:
	match kind:
		Kind.HEAT:
			if count == 1:
				return "Payez 1 Heat du moteur pour jouer cette carte."
			return "Payez %d Heat du moteur pour jouer cette carte." % count
		Kind.SCRAP:
			if count == 1:
				return "1 carte est défaussée du dessus de la pioche."
			return "%d cartes sont défaussées du dessus de la pioche." % count
		Kind.ADJUST_SPEED_LIMIT:
			if count >= 0:
				return (
					"Les limites de vitesse des virages ce tour-ci sont augmentées de %d."
					% count
				)
			return (
				"Les limites de vitesse des virages ce tour-ci sont diminuées de %d."
				% absi(count)
			)
		Kind.COOLDOWN:
			if count == 1:
				return "Vous pouvez remettre 1 Heat supplémentaire en cooldown ce tour-ci."
			return (
				"Vous pouvez remettre %d Heat supplémentaires en cooldown ce tour-ci." % count
			)
		Kind.SLIPSTREAM_BOOST:
			if count == 1:
				return (
					"Si vous utilisez le Slipstream ce tour-ci, "
					+ "le déplacement est augmenté de 1 case."
				)
			return (
				"Si vous utilisez le Slipstream ce tour-ci, "
				+ "le déplacement est augmenté de %d cases." % count
			)
		Kind.REDUCE_STRESS:
			if count == 1:
				return "Défaussez 1 carte Stress de votre main."
			return "Défaussez %d cartes Stress de votre main." % count
		Kind.REFRESH:
			return "Cette carte retourne en haut de la pioche au lieu d'aller à la défausse."
		Kind.SALVAGE:
			if count == 1:
				return (
					"Choisissez jusqu'à 1 carte dans la défausse : elle rejoint la pioche, "
					+ "qui est ensuite mélangée."
				)
			return (
				"Choisissez jusqu'à %d cartes dans la défausse : elles rejoignent la pioche, "
				+ "qui est ensuite mélangée."
			) % count
		Kind.DIRECT_PLAY:
			return "Jouez cette carte depuis la main pendant la phase Réaction."
		Kind.ACCELERATE:
			var bonus := int(extra.get("plus_used", 0))
			if bonus <= 0:
				return "Avancez du nombre de symboles + utilisés ce tour-ci."
			if bonus == 1:
				return "Avancez de 1 case (symboles + utilisés ce tour-ci)."
			return "Avancez de %d cases (symboles + utilisés ce tour-ci)." % bonus
		Kind.PLUS:
			return "Retournez des cartes jusqu'à obtenir une carte Vitesse 1–4."
	return ""
