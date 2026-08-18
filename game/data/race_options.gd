class_name RaceOptions
extends RefCounted

var garage_enabled: bool = false
var garage_include_basic: bool = true
var garage_include_advanced: bool = false
var garage_quick_start: bool = false


func to_dict() -> Dictionary:
	return {
		"garage_enabled": garage_enabled,
		"garage_include_basic": garage_include_basic,
		"garage_include_advanced": garage_include_advanced,
		"garage_quick_start": garage_quick_start,
	}


static func from_dict(data: Dictionary) -> RaceOptions:
	var o := RaceOptions.new()
	o.garage_enabled = bool(data.get("garage_enabled", false))
	o.garage_include_basic = bool(data.get("garage_include_basic", true))
	o.garage_include_advanced = bool(data.get("garage_include_advanced", false))
	o.garage_quick_start = bool(data.get("garage_quick_start", false))
	return o


func duplicate_options() -> RaceOptions:
	return from_dict(to_dict())
