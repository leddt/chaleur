class_name HeatCard
extends RefCounted

enum Kind { SPEED, HEAT, STRESS, UPGRADE }

var id: String
var kind: Kind
var speed_value: int = 0


func _init(p_id: String = "", p_kind: Kind = Kind.SPEED, p_speed: int = 0) -> void:
	id = p_id
	kind = p_kind
	speed_value = p_speed


func is_speed_card() -> bool:
	return kind == Kind.SPEED


func is_playable() -> bool:
	return kind != Kind.HEAT


func can_discard() -> bool:
	return kind != Kind.HEAT and kind != Kind.STRESS


func contributes_speed_when_played() -> bool:
	return kind == Kind.SPEED or kind == Kind.UPGRADE


func duplicate_card() -> HeatCard:
	return HeatCard.new(id, kind, speed_value)
