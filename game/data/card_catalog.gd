class_name CardCatalog
extends RefCounted

const CARDS_DIR := "res://data/cards"

static var _by_id: Dictionary = {}
static var _advanced_ids: Dictionary = {}


static func reload() -> void:
	_by_id.clear()
	_advanced_ids.clear()
	_ensure_loaded()


static func get_def(def_id: String) -> CardDefinition:
	_ensure_loaded()
	var def: Variant = _by_id.get(def_id)
	if def is CardDefinition:
		return def
	var dynamic := _dynamic_def(def_id)
	if dynamic != null:
		_by_id[def_id] = dynamic
		return dynamic
	push_error("CardCatalog: unknown def_id '%s'" % def_id)
	return _fallback(def_id)


static func has(def_id: String) -> bool:
	_ensure_loaded()
	return _by_id.has(def_id)


static func is_advanced(def_id: String) -> bool:
	_ensure_loaded()
	return _advanced_ids.has(def_id)


static func make_card(instance_id: String, def_id: String) -> HeatCard:
	return HeatCard.new(instance_id, def_id)


static func to_card_data(def_id: String) -> CardData:
	if def_id == "starter_heat":
		return CardData.upgrade_heat()
	var def := get_def(def_id)
	match def.kind:
		CardDefinition.Kind.SPEED:
			return CardData.speed(def.speed_value)
		CardDefinition.Kind.HEAT:
			if def_id.begins_with("upg_"):
				return CardData.upgrade_heat_named(def.title)
			return CardData.heat()
		CardDefinition.Kind.STRESS:
			return CardData.stress()
		CardDefinition.Kind.UPGRADE:
			return CardData.upgrade_from_def(def, is_advanced(def_id))
		_:
			return CardData.speed(1)


static func legacy_def_id(kind: CardDefinition.Kind, speed_value: int) -> String:
	match kind:
		CardDefinition.Kind.SPEED:
			return "speed_%d" % clampi(speed_value, 1, 4)
		CardDefinition.Kind.HEAT:
			return "heat"
		CardDefinition.Kind.STRESS:
			return "stress"
		CardDefinition.Kind.UPGRADE:
			match speed_value:
				0:
					return "starter_speed_0"
				5:
					return "starter_speed_5"
				_:
					return "starter_speed_0"
	return "speed_1"


static func _ensure_loaded() -> void:
	if not _by_id.is_empty():
		return
	_load_dir(CARDS_DIR)
	# Manifests are packed as dependencies; register them even if directory
	# listing misses .tres files in an exported PCK.
	_register_manifest(load(GarageDeckFactory.BASIC_PATH) as GarageDeckManifest, false)
	_register_manifest(load(GarageDeckFactory.ADVANCED_PATH) as GarageDeckManifest, true)


static func _register_manifest(manifest: GarageDeckManifest, advanced: bool) -> void:
	if manifest == null:
		return
	for entry in manifest.entries:
		if entry == null or entry.card == null or entry.card.id.is_empty():
			continue
		_by_id[entry.card.id] = entry.card
		if advanced:
			_advanced_ids[entry.card.id] = true


static func _load_dir(path: String) -> void:
	var listed := ResourceLoader.list_directory(path)
	if not listed.is_empty():
		for file_name in listed:
			if file_name.ends_with("/"):
				_load_dir("%s/%s" % [path, file_name.trim_suffix("/")])
				continue
			_try_load_def("%s/%s" % [path, file_name])
		return
	_load_dir_access(path)


static func _load_dir_access(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("CardCatalog: cannot open %s" % path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full := "%s/%s" % [path, file_name]
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		if dir.current_is_dir() or DirAccess.dir_exists_absolute(full):
			_load_dir(full)
		else:
			_try_load_def("%s/%s" % [path, file_name.trim_suffix(".remap")])
		file_name = dir.get_next()
	dir.list_dir_end()


static func _try_load_def(path: String) -> void:
	if not (path.ends_with(".tres") or path.ends_with(".res")):
		return
	var def := load(path) as CardDefinition
	if def != null and not def.id.is_empty():
		_by_id[def.id] = def


static func _dynamic_def(def_id: String) -> CardDefinition:
	if def_id.begins_with("speed_"):
		var tail := def_id.substr(6)
		if tail.is_valid_int():
			var speed := int(tail)
			if speed >= 0:
				var def := CardDefinition.new()
				def.id = def_id
				def.kind = CardDefinition.Kind.SPEED
				def.speed_value = speed
				def.contributes_speed = true
				def.discardable = true
				return def
	return null


static func _fallback(def_id: String) -> CardDefinition:
	var def := CardDefinition.new()
	def.id = def_id
	def.kind = CardDefinition.Kind.SPEED
	def.speed_value = 1
	def.contributes_speed = true
	return def
