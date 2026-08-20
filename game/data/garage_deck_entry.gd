class_name GarageDeckEntry
extends Resource

## One upgrade in a garage pool, with how many copies to deal.

@export var card: CardDefinition
@export var count: int = 1


func def_id() -> String:
	if card == null:
		return ""
	return card.id


func copies() -> int:
	return maxi(1, count)
