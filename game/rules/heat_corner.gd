class_name HeatCorner
extends RefCounted

## Corner crossed when leaving `from_space` toward the next space.
var from_space: int = 0
var speed_limit: int = 0
var id: String = ""


func _init(p_from: int = 0, p_limit: int = 0, p_id: String = "") -> void:
	from_space = p_from
	speed_limit = p_limit
	id = p_id
