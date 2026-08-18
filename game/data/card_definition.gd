class_name CardDefinition
extends Resource

## Static card template (core game). Instances reference this via HeatCard.def_id.

enum Kind { SPEED, HEAT, STRESS, UPGRADE }

@export var id: String = ""
@export var kind: Kind = Kind.SPEED
@export var speed_value: int = 0
@export var contributes_speed: bool = false
@export var discardable: bool = true
