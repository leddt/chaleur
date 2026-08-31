class_name DynamicMusicStem
extends Resource

## One continuously playing layer of a dynamic song.

@export var id: StringName
@export var stream: AudioStream
@export_range(-24.0, 24.0, 0.1, "suffix:dB") var trim_db: float = 0.0
