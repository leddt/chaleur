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
@export var symbol_entries: Array[CardSymbol] = []
@export var speed_options: PackedInt32Array = PackedInt32Array()
@export var is_advanced: bool = false


func accent() -> Color:
	if shows_heat_center():
		return Palette.RACE_RED
	if kind == Kind.STRESS:
		return Palette.MUSTARD
	match kind:
		Kind.UPGRADE:
			return Palette.FUEL_BLUE
		Kind.SPONSOR:
			return Palette.SMOKE
		_:
			return Palette.INK


func face() -> Color:
	if shows_heat_center():
		return Palette.RACE_RED
	if kind == Kind.STRESS:
		return Palette.MUSTARD
	return Palette.CARDBOARD


func ink() -> Color:
	if shows_heat_center():
		return Palette.CARDBOARD
	return Palette.INK


## Gros pictogramme feu à la place du « H ».
func shows_heat_center() -> bool:
	return kind == Kind.HEAT or center_text == "H"


## Gros symbole Plus à la place du « ? ».
func shows_plus_center() -> bool:
	return kind == Kind.STRESS


func tooltip_bbcode() -> String:
	if kind != Kind.STRESS:
		return ""
	return (
		"[b]Stress[/b]\n"
		+ "À la révélation, retournez des cartes de la pioche jusqu'à obtenir "
		+ "une carte Vitesse 1–4. Compte comme un symbole + pour Accélérer."
	)


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
				return "|".join(parts)
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
	return c


static func upgrade(v: int) -> CardData:
	var c := CardData.new()
	c.kind = Kind.UPGRADE
	c.value = v
	c.title = "AMÉLIORATION"
	return c


static func upgrade_from_def(def: CardDefinition, advanced: bool) -> CardData:
	var c := CardData.new()
	c.kind = Kind.UPGRADE
	c.value = def.speed_value
	c.title = def.title if not def.title.is_empty() else "AMÉLIORATION"
	c.speed_options = def.resolved_speed_options()
	c.is_advanced = advanced
	for s in def.symbols:
		var copy := CardSymbol.new()
		copy.kind = s.kind
		copy.count = s.count
		c.symbol_entries.append(copy)
	return c


static func upgrade_heat() -> CardData:
	return upgrade_heat_named("AMÉLIORATION")


static func upgrade_heat_named(title: String) -> CardData:
	var c := CardData.new()
	c.kind = Kind.UPGRADE
	c.value = 0
	c.center_text = "H"
	c.title = title if not title.is_empty() else "AMÉLIORATION"
	return c


static func stress() -> CardData:
	var c := CardData.new()
	c.kind = Kind.STRESS
	c.value = 0
	c.title = "STRESS"
	return c
