class_name CardDefinition
extends Resource

## Static card template. Instances reference this via HeatCard.def_id.

enum Kind { SPEED, HEAT, STRESS, UPGRADE }

@export var id: String = ""
@export var kind: Kind = Kind.SPEED
@export var speed_value: int = 0
@export var contributes_speed: bool = false
@export var discardable: bool = true
@export var title: String = ""
@export var category: String = ""
## If more than one value, the player chooses at play / Direct Play time.
@export var speed_options: PackedInt32Array = PackedInt32Array()
@export var symbols: Array[CardSymbol] = []


func resolved_speed_options() -> PackedInt32Array:
	if not speed_options.is_empty():
		return speed_options
	if contributes_speed or speed_value != 0:
		return PackedInt32Array([speed_value])
	return PackedInt32Array()


func has_symbol(kind_v: CardSymbol.Kind) -> bool:
	for s in symbols:
		if s.kind == kind_v:
			return true
	return false


func symbol_count(kind_v: CardSymbol.Kind) -> int:
	var n := 0
	for s in symbols:
		if s.kind == kind_v:
			n += s.count
	return n
