class_name HeatCard
extends RefCounted

## Alias — CardDefinition.Kind is the single source of truth.
const Kind = CardDefinition.Kind

var id: String
var def_id: String


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
		return _def().speed_value


func is_speed_card() -> bool:
	return kind == Kind.SPEED


func is_playable() -> bool:
	return kind != Kind.HEAT


func can_discard() -> bool:
	return _def().discardable


func contributes_speed_when_played() -> bool:
	return _def().contributes_speed


func duplicate_card() -> HeatCard:
	return HeatCard.new(id, def_id)
