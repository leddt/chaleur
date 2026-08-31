class_name DynamicMusicSong
extends Resource

## Configurable collection of synchronized stems and context-specific mixes.

@export var id: StringName
@export var default_context: StringName = &"menu"
@export_range(0.0, 10.0, 0.05, "suffix:s") var default_transition_seconds: float = 0.8
@export var stems: Array[DynamicMusicStem] = []
@export var mixes: Array[DynamicMusicMix] = []


func find_mix(context: StringName) -> DynamicMusicMix:
	for mix in mixes:
		if mix != null and mix.context == context:
			return mix
	return null


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("song id is empty")
	if stems.is_empty():
		errors.append("song has no stems")
	if stems.size() > AudioStreamSynchronized.MAX_STREAMS:
		errors.append("song has more than %d stems" % AudioStreamSynchronized.MAX_STREAMS)

	var stem_ids: Dictionary = {}
	var shortest_length := INF
	for stem in stems:
		if stem == null:
			errors.append("song contains a null stem")
			continue
		if stem.id.is_empty():
			errors.append("song contains a stem with an empty id")
		elif stem_ids.has(stem.id):
			errors.append("duplicate stem id: %s" % stem.id)
		else:
			stem_ids[stem.id] = true
		if stem.stream == null:
			errors.append("stem %s has no stream" % stem.id)
		else:
			shortest_length = minf(shortest_length, stem.stream.get_length())

	var contexts: Dictionary = {}
	for mix in mixes:
		if mix == null:
			errors.append("song contains a null mix")
			continue
		if mix.context.is_empty():
			errors.append("song contains a mix with an empty context")
		elif contexts.has(mix.context):
			errors.append("duplicate mix context: %s" % mix.context)
		else:
			contexts[mix.context] = true
		for stem_id in mix.levels:
			if not stem_ids.has(stem_id):
				errors.append("mix %s references unknown stem %s" % [mix.context, stem_id])
		for stem_id in stem_ids:
			if not mix.levels.has(stem_id):
				errors.append("mix %s has no level for stem %s" % [mix.context, stem_id])
	if find_mix(default_context) == null:
		errors.append("default context %s does not exist" % default_context)

	# Loops may have different lengths, but each one must cover an integer
	# multiple of the shortest musical cycle or it will drift over time.
	if shortest_length < INF and shortest_length > 0.0:
		for stem in stems:
			if stem == null or stem.stream == null:
				continue
			var ratio := stem.stream.get_length() / shortest_length
			if absf(ratio - roundf(ratio)) > 0.002:
				errors.append("stem %s has an incompatible loop length" % stem.id)
	return errors
