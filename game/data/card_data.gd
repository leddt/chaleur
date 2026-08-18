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


static func upgrade_heat() -> CardData:
	var c := CardData.new()
	c.kind = Kind.UPGRADE
	c.value = 0
	c.center_text = "H"
	c.title = "AMÉLIORATION"
	c.symbol = "flame"
	return c


static func stress() -> CardData:
	var c := CardData.new()
	c.kind = Kind.STRESS
	c.value = 0
	c.title = "STRESS"
	c.effect = "Revele des cartes jusqu'a une vitesse."
	return c
