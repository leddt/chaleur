class_name GarageDeckManifest
extends Resource

## Garage pool: which upgrades, and how many copies of each.

@export var entries: Array[GarageDeckEntry] = []


func count_for(def_id: String) -> int:
	for entry in entries:
		if entry != null and entry.def_id() == def_id:
			return entry.copies()
	return 0
