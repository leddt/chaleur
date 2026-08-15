extends GutTest


func test_normalize_known_and_fallback() -> void:
	assert_eq(TrackDecor.normalize("tree"), TrackDecor.TYPE_TREE)
	assert_eq(TrackDecor.normalize("ROCK"), TrackDecor.TYPE_ROCK)
	assert_eq(TrackDecor.normalize("bleachers"), TrackDecor.TYPE_BLEACHERS)
	assert_eq(TrackDecor.normalize(""), TrackDecor.DEFAULT_TYPE)
	assert_eq(TrackDecor.normalize("bush"), TrackDecor.DEFAULT_TYPE)
	assert_eq(TrackDecor.normalize_brush("select"), TrackDecor.TOOL_SELECT)
	assert_eq(TrackDecor.normalize_brush("tree"), TrackDecor.TYPE_TREE)
	assert_eq(TrackDecor.normalize_brush("bleachers"), TrackDecor.TYPE_BLEACHERS)
	assert_eq(TrackDecor.normalize_brush("nope"), TrackDecor.TOOL_SELECT)
	assert_true(TrackDecor.is_place_brush(TrackDecor.TYPE_ROCK))
	assert_true(TrackDecor.is_place_brush(TrackDecor.TYPE_BLEACHERS))
	assert_false(TrackDecor.is_place_brush(TrackDecor.TOOL_SELECT))
	assert_true(TrackDecor.uses_free_size(TrackDecor.TYPE_BLEACHERS))
	assert_false(TrackDecor.uses_free_size(TrackDecor.TYPE_TREE))


func test_make_and_parse_item() -> void:
	var item := TrackDecor.make_item(TrackDecor.TYPE_ROCK, Vector2(10, 20), 42)
	assert_eq(item.type, TrackDecor.TYPE_ROCK)
	assert_eq(item.position, Vector2(10, 20))
	assert_eq(item.seed, 42)
	var roundtrip := TrackDecor.parse_item({
		"type": "tree",
		"position": [3.5, -1.25],
		"seed": 7,
	})
	assert_eq(roundtrip.type, TrackDecor.TYPE_TREE)
	assert_eq(roundtrip.position, Vector2(3.5, -1.25))
	assert_eq(roundtrip.seed, 7)


func test_bleachers_size_and_tiers() -> void:
	var item := TrackDecor.make_item(TrackDecor.TYPE_BLEACHERS, Vector2(1, 2), 5)
	assert_eq(item.type, TrackDecor.TYPE_BLEACHERS)
	assert_eq(item.size, TrackDecor.BLEACHER_DEFAULT_SIZE)
	assert_eq(TrackDecor.bleacher_tier_count(item.size), 3)
	item.size = TrackDecor.clamp_bleacher_size(Vector2(100, 100))
	assert_eq(TrackDecor.bleacher_tier_count(item.size), 14)
	assert_almost_eq(float(item.size.y), 14.0 * TrackDecor.BLEACHER_TIER_DEPTH, 0.001)
	var extents := TrackDecor.selection_extents(item)
	assert_gt(extents.x, extents.y * 0.5)
	assert_ne(extents.x, extents.y)


func test_document_roundtrip() -> void:
	var items := [
		TrackDecor.make_item(TrackDecor.TYPE_TREE, Vector2(1, 2), 11),
		TrackDecor.make_item(TrackDecor.TYPE_ROCK, Vector2(8, 9), 22),
		TrackDecor.make_item(TrackDecor.TYPE_BLEACHERS, Vector2(4, 5), 33),
	]
	items[0].rotation = 0.5
	items[0].scale = 1.5
	items[2].size = TrackDecor.clamp_bleacher_size(Vector2(120, 42))
	items[2].rotation = 0.25
	var doc := {"decorations": TrackDecor.to_document(items)}
	var loaded := TrackDecor.from_document(doc)
	assert_eq(loaded.size(), 3)
	assert_eq(loaded[0].type, TrackDecor.TYPE_TREE)
	assert_eq(loaded[0].position, Vector2(1, 2))
	assert_eq(loaded[0].seed, 11)
	assert_almost_eq(float(loaded[0].rotation), 0.5, 0.0001)
	assert_almost_eq(float(loaded[0].scale), 1.5, 0.0001)
	assert_eq(loaded[1].type, TrackDecor.TYPE_ROCK)
	assert_eq(loaded[2].type, TrackDecor.TYPE_BLEACHERS)
	assert_almost_eq(float(loaded[2].size.x), 120.0, 0.0001)
	assert_almost_eq(float(loaded[2].size.y), 42.0, 0.0001)
	assert_almost_eq(float(loaded[2].rotation), 0.25, 0.0001)
	## Trees must not serialize a size field.
	var raw_doc: Array = doc.decorations
	assert_false(raw_doc[0].has("size"))
	assert_true(raw_doc[2].has("size"))
	assert_eq(TrackDecor.from_document({}).size(), 0)


func test_params_are_seed_stable() -> void:
	var a := TrackDecor.make_item(TrackDecor.TYPE_TREE, Vector2.ZERO, 99)
	var b := TrackDecor.make_item(TrackDecor.TYPE_TREE, Vector2.ZERO, 99)
	var pa := TrackDecor.params_for(a)
	var pb := TrackDecor.params_for(b)
	assert_eq(pa.hit_radius, pb.hit_radius)
	assert_eq(pa.blobs.size(), pb.blobs.size())
	var different := TrackDecor.params_for(TrackDecor.make_item(TrackDecor.TYPE_TREE, Vector2.ZERO, 100))
	assert_ne(float(pa.hi_ang), float(different.hi_ang))
	var ba := TrackDecor.make_item(TrackDecor.TYPE_BLEACHERS, Vector2.ZERO, 7)
	var bb := TrackDecor.make_item(TrackDecor.TYPE_BLEACHERS, Vector2.ZERO, 7)
	assert_eq(TrackDecor.params_for(ba).spectators.size(), TrackDecor.params_for(bb).spectators.size())
	assert_gt(TrackDecor.params_for(ba).spectators.size(), 0)
	assert_true(TrackDecor.has_bleachers([ba]))
	assert_false(TrackDecor.has_bleachers([a]))
	var spec: Dictionary = TrackDecor.params_for(ba).spectators[0]
	assert_true(spec.has("phase"))
	assert_true(spec.has("bob"))


func test_hit_index_topmost() -> void:
	var items := [
		TrackDecor.make_item(TrackDecor.TYPE_ROCK, Vector2(0, 0), 1),
		TrackDecor.make_item(TrackDecor.TYPE_TREE, Vector2(2, 0), 2),
	]
	assert_eq(TrackDecor.hit_index(items, Vector2(2, 0)), 1)
	assert_eq(TrackDecor.hit_index(items, Vector2(500, 500)), -1)


func test_hit_respects_scale() -> void:
	var item := TrackDecor.make_item(TrackDecor.TYPE_ROCK, Vector2(0, 0), 1)
	item.scale = 0.3
	var half := TrackDecor.selection_half(item) * float(item.scale)
	# Far in local unscaled space; should miss when scaled down.
	assert_eq(TrackDecor.hit_index([item], Vector2(half + 2.0, 0)), -1)
	item.scale = 2.5
	assert_eq(TrackDecor.hit_index([item], Vector2.ZERO), 0)


func test_bleachers_hit_uses_rect() -> void:
	var item := TrackDecor.make_item(TrackDecor.TYPE_BLEACHERS, Vector2(0, 0), 1)
	item.size = TrackDecor.clamp_bleacher_size(Vector2(60, 24))
	assert_eq(TrackDecor.hit_index([item], Vector2.ZERO), 0)
	assert_eq(TrackDecor.hit_index([item], Vector2(200, 0)), -1)
	assert_eq(TrackDecor.hit_index([item], Vector2(0, 200)), -1)


func test_preview_texture_non_empty() -> void:
	var tex := TrackDecor.preview_texture(TrackDecor.TYPE_TREE, 32, 5)
	assert_ne(tex, null)
	assert_eq(tex.get_width(), 32)
	assert_eq(tex.get_height(), 32)
	var rock := TrackDecor.preview_texture(TrackDecor.TYPE_ROCK, 32, 5)
	assert_ne(rock, null)
	var stands := TrackDecor.preview_texture(TrackDecor.TYPE_BLEACHERS, 32, 5)
	assert_ne(stands, null)
	assert_eq(stands.get_width(), 32)
	var cursor := TrackDecor.preview_texture(TrackDecor.TOOL_SELECT, 32)
	assert_ne(cursor, null)
	assert_eq(cursor, TrackDecor.SELECT_ICON)
