class_name CardData
extends Resource

## Les donnees d'une carte. Aucune image ici : la carte est dessinee a partir
## de ces valeurs. Tu peux creer un .tres par carte dans l'editeur, ou generer
## le paquet en code (voir deck.gd).

enum Kind {
	SPEED,   # carte de vitesse normale (1-4)
	HEAT,    # carte chaleur, encombre la main
	STRESS,  # carte stress, valeur revelee au hasard
	UPGRADE, # amelioration
	SPONSOR, # parrainage
}

@export var kind: Kind = Kind.SPEED
@export var value: int = 1
@export var title: String = ""
## When set, overrides big_text() (e.g. upgrade Heat shows "H").
@export var center_text: String = ""
@export_multiline var effect: String = ""
## Symbole optionnel : "flame", "gear", "chevron", "" (aucun)
@export var symbol: String = ""
@export var symbols: PackedStringArray = PackedStringArray()
@export var speed_options: PackedInt32Array = PackedInt32Array()
@export var is_advanced: bool = false


func accent() -> Color:
	match kind:
		Kind.HEAT:
			return Palette.RACE_RED
		Kind.STRESS:
			return Palette.MUSTARD
		Kind.UPGRADE:
			return Palette.FUEL_BLUE
		Kind.SPONSOR:
			return Palette.SMOKE
		_:
			return Palette.INK


func face() -> Color:
	return Palette.RACE_RED if kind == Kind.HEAT else Palette.CARDBOARD


func ink() -> Color:
	return Palette.CARDBOARD if kind == Kind.HEAT else Palette.INK


## Ce qui s'affiche en gros au centre.
func big_text() -> String:
	if not center_text.is_empty():
		return center_text
	match kind:
		Kind.HEAT:
			return "H"
		Kind.STRESS:
			return "?"
		Kind.SPEED, Kind.UPGRADE:
			if speed_options.size() > 1:
				var parts: PackedStringArray = PackedStringArray()
				for v in speed_options:
					parts.append(str(v))
				return "/".join(parts)
			return str(value)
		_:
			return ""


static func speed(v: int) -> CardData:
	var c := CardData.new()
	c.kind = Kind.SPEED
	c.value = v
	c.title = "VITESSE"
	return c


static func heat() -> CardData:
	var c := CardData.new()
	c.kind = Kind.HEAT
	c.value = 0
	c.title = "CHALEUR"
	c.effect = "Se defausse en refroidissant."
	c.symbol = "flame"
	return c


static func upgrade(v: int) -> CardData:
	var c := CardData.new()
	c.kind = Kind.UPGRADE
	c.value = v
	c.title = "AMÉLIORATION"
	c.symbol = "gear"
	return c


static func upgrade_from_def(def: CardDefinition, advanced: bool) -> CardData:
	var c := CardData.new()
	c.kind = Kind.UPGRADE
	c.value = def.speed_value
	c.title = def.title if not def.title.is_empty() else "AMÉLIORATION"
	c.symbol = "gear"
	c.speed_options = def.resolved_speed_options()
	c.is_advanced = advanced
	var bits: PackedStringArray = PackedStringArray()
	for s in def.symbols:
		bits.append(s.label())
	c.effect = " · ".join(bits)
	var icons: PackedStringArray = PackedStringArray()
	for s in def.symbols:
		icons.append(_symbol_icon(s.kind))
	c.symbols = icons
	return c


static func _symbol_icon(kind: CardSymbol.Kind) -> String:
	match kind:
		CardSymbol.Kind.HEAT:
			return "flame"
		CardSymbol.Kind.PLUS:
			return "plus"
		CardSymbol.Kind.COOLDOWN:
			return "snow"
		CardSymbol.Kind.SLIPSTREAM_BOOST:
			return "chevron"
		CardSymbol.Kind.REFRESH:
			return "refresh"
		CardSymbol.Kind.DIRECT_PLAY:
			return "play"
		CardSymbol.Kind.ACCELERATE:
			return "accel"
		CardSymbol.Kind.SCRAP:
			return "scrap"
		CardSymbol.Kind.ADJUST_SPEED_LIMIT:
			return "corner"
		CardSymbol.Kind.SALVAGE:
			return "salvage"
		CardSymbol.Kind.REDUCE_STRESS:
			return "stress"
		_:
			return "gear"


static func upgrade_heat() -> CardData:
	return upgrade_heat_named("AMÉLIORATION")


static func upgrade_heat_named(title: String) -> CardData:
	var c := CardData.new()
	c.kind = Kind.UPGRADE
	c.value = 0
	c.center_text = "H"
	c.title = title if not title.is_empty() else "AMÉLIORATION"
	c.symbol = "flame"
	c.effect = "Heat dans le deck."
	return c


static func stress() -> CardData:
	var c := CardData.new()
	c.kind = Kind.STRESS
	c.value = 0
	c.title = "STRESS"
	c.effect = "Revele des cartes jusqu'a une vitesse."
	return c
