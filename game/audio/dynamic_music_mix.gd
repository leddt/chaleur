class_name DynamicMusicMix
extends Resource

## Per-stem linear levels for one semantic presentation context.

@export var context: StringName
@export var levels: Dictionary = {}
@export_range(-1.0, 10.0, 0.05, "suffix:s") var transition_seconds: float = -1.0


func level_for(stem_id: StringName) -> float:
	return clampf(float(levels.get(stem_id, 0.0)), 0.0, 1.0)
