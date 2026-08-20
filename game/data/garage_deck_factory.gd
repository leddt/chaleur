class_name GarageDeckFactory
extends RefCounted

const BASIC_PATH := "res://data/garage_deck_basic.tres"
const ADVANCED_PATH := "res://data/garage_deck_advanced.tres"


static func build_pool(include_basic: bool, include_advanced: bool) -> Array[HeatCard]:
	var cards: Array[HeatCard] = []
	var n := 0
	if include_basic:
		n = _append_manifest(cards, load(BASIC_PATH) as GarageDeckManifest, n)
	if include_advanced:
		n = _append_manifest(cards, load(ADVANCED_PATH) as GarageDeckManifest, n)
	return cards


static func deal_random(
	pool: Array[HeatCard], rng: RandomNumberGenerator, count: int
) -> Array[HeatCard]:
	var remaining: Array[HeatCard] = pool.duplicate()
	for i in range(remaining.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := remaining[i]
		remaining[i] = remaining[j]
		remaining[j] = tmp
	var out: Array[HeatCard] = []
	var n := mini(count, remaining.size())
	for i in n:
		out.append(remaining[i])
	return out


static func _append_manifest(
	cards: Array[HeatCard], manifest: GarageDeckManifest, start_n: int
) -> int:
	if manifest == null:
		return start_n
	var n := start_n
	for entry in manifest.entries:
		if entry == null or entry.card == null:
			continue
		var def_id := entry.def_id()
		for _c in entry.copies():
			n += 1
			cards.append(CardCatalog.make_card("garage_%s_%d" % [def_id, n], def_id))
	return n
