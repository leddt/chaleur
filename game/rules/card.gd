class_name HeatCard
extends RefCounted

## Alias — CardDefinition.Kind is the single source of truth.
const Kind = CardDefinition.Kind

var id: String
var def_id: String
## Chosen speed for cards with multiple speed_options. -1 = default.
var chosen_speed: int = -1


func _init(p_id: String = "", p_def_id: String = "speed_1") -> void:
	id = p_id
	def_id = p_def_id


func _def() -> CardDefinition:
	return CardCatalog.get_def(def_id)


var kind: Kind:
	get:
		return _def().kind


var speed_value: int:
	get:
		if chosen_speed >= 0:
			return chosen_speed
		var def := _def()
		var opts := def.resolved_speed_options()
		if opts.size() == 1:
			return opts[0]
		if opts.size() > 1:
			return 0
		return def.speed_value


func is_speed_card() -> bool:
	# Plus / Boost / Stress / heat-fallback keep only base Speed 1–4.
	# Starter 0/5, upgrades, Heat and Stress are discarded.
	if kind != Kind.SPEED:
		return false
	var v := _def().speed_value
	return v >= 1 and v <= 4


func needs_speed_choice() -> bool:
	return contributes_speed_when_played() and _def().resolved_speed_options().size() > 1 and chosen_speed < 0


func is_playable() -> bool:
	if kind == Kind.HEAT:
		return false
	# Direct Play (Gas Pedal, etc.) stays in hand until React.
	return not _def().has_symbol(CardSymbol.Kind.DIRECT_PLAY)


func can_discard() -> bool:
	return _def().discardable


func contributes_speed_when_played() -> bool:
	return _def().contributes_speed


func duplicate_card() -> HeatCard:
	var copy := HeatCard.new(id, def_id)
	copy.chosen_speed = chosen_speed
	return copy
