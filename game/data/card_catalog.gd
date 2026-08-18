class_name CardCatalog
extends RefCounted

const CARDS_DIR := "res://data/cards"

static var _by_id: Dictionary = {}


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
			return CardData.heat()
		CardDefinition.Kind.STRESS:
			return CardData.stress()
		CardDefinition.Kind.UPGRADE:
			return CardData.upgrade(def.speed_value)
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
	var dir := DirAccess.open(CARDS_DIR)
	if dir == null:
		push_error("CardCatalog: cannot open %s" % CARDS_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var def := load("%s/%s" % [CARDS_DIR, file_name]) as CardDefinition
			if def != null and not def.id.is_empty():
				_by_id[def.id] = def
		file_name = dir.get_next()
	dir.list_dir_end()


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
