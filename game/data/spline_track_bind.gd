class_name SplineTrackBind
extends RefCounted

## Runtime for a saved spline track: rules conversion + world poses for the board.

var path: String = ""
var document: Dictionary = {}
var spline: TrackSpline
var seg: TrackSegmenter.Result
var seg_params: TrackSegmenter.Params = TrackSegmenter.Params.new()
## Geometric index of the start/finish frontier (playable space 0 starts here).
var start_space: int = 0
## Geometric space_index -> {speed_limit, outside, offset}
var corners: Dictionary = {}
## Geometric space_index -> {inside: bool, outside: bool}
var kerbs: Dictionary = {}
## flip_key -> true
var sector_flip_race_line: Dictionary = {}
var half_width: float = SplineTrackPainter.HALF_WIDTH
var spot_inset: float = 0.45


static func from_path(track_path: String) -> SplineTrackBind:
	var data := SplineTrackFile.load_document(track_path)
	if data.is_empty():
		return null
	return from_document(data, track_path)


static func from_document(data: Dictionary, track_path: String = "") -> SplineTrackBind:
	if not SplineTrackFile.is_valid_document(data):
		return null
	var spline_data: Variant = data.get("spline", {})
	if not spline_data is Dictionary:
		return null
	var bind := SplineTrackBind.new()
	bind.path = track_path
	bind.document = data.duplicate(true)
	bind.spline = TrackSpline.from_dict(spline_data)
	if bind.spline.point_count() < TrackSpline.MIN_POINTS:
		return null
	bind.seg_params = TrackSegmenter.Params.new()
	bind.seg_params.road_half_width = SplineTrackPainter.HALF_WIDTH
	var seg_data: Variant = data.get("segmentation", {})
	if seg_data is Dictionary:
		bind.seg_params.algorithm = int(seg_data.get("algorithm", TrackSegmenter.Algorithm.INNER_UNIFORM))
		bind.seg_params.car_length = float(seg_data.get("car_length", 36.0))
		bind.seg_params.target_space_len = float(
			seg_data.get("target_space_len", bind.seg_params.car_length)
		)
		bind.seg_params.forced_space_count = int(seg_data.get("forced_space_count", 0))
	bind.half_width = bind.seg_params.road_half_width
	bind.spot_inset = bind.seg_params.spot_inset
	bind.seg = TrackSegmenter.segment(bind.spline, bind.seg_params)
	if bind.seg == null or bind.seg.space_count() < 2:
		return null
	var n := bind.seg.space_count()
	bind.start_space = posmod(int(data.get("start_space", 0)), n)
	bind.corners.clear()
	var corners_data: Variant = data.get("corners", [])
	if corners_data is Array:
		for item in corners_data:
			if not item is Dictionary:
				continue
			var entry: Dictionary = item
			var space := int(entry.get("space", -1))
			if space < 0 or space >= n:
				continue
			var offset := Vector2.ZERO
			var off_v: Variant = entry.get("offset", [0.0, 0.0])
			if off_v is Array and off_v.size() >= 2:
				offset = Vector2(float(off_v[0]), float(off_v[1]))
			elif off_v is Vector2:
				offset = off_v
			bind.corners[space] = {
				"speed_limit": int(entry.get("speed_limit", 0)),
				"outside": bool(entry.get("outside", true)),
				"offset": offset,
			}
	bind.kerbs.clear()
	var kerbs_data: Variant = data.get("kerbs", [])
	if kerbs_data is Array:
		for k_item in kerbs_data:
			if not k_item is Dictionary:
				continue
			var k_entry: Dictionary = k_item
			var k_space := int(k_entry.get("space", -1))
			if k_space < 0 or k_space >= n:
				continue
			var want_in := bool(k_entry.get("inside", false))
			var want_out := bool(k_entry.get("outside", false))
			if not want_in and not want_out:
				continue
			bind.kerbs[k_space] = {"inside": want_in, "outside": want_out}
	bind.sector_flip_race_line.clear()
	var flips_data: Variant = data.get("sector_flip_race_line", [])
	if flips_data is Array:
		for item2 in flips_data:
			if item2 is Dictionary:
				bind.sector_flip_race_line[int(item2.get("key", -1))] = true
			elif item2 != null:
				bind.sector_flip_race_line[int(item2)] = true
	return bind


func display_name() -> String:
	var name := str(document.get("name", "")).strip_edges()
	if not name.is_empty():
		return name
	if not path.is_empty():
		return path.get_file().get_basename()
	return "Piste"


func space_count() -> int:
	return 0 if seg == null else seg.space_count()


func play_to_geom(play_space: int) -> int:
	var n := space_count()
	if n <= 0:
		return 0
	return posmod(play_space + start_space, n)


func geom_to_play(geom_space: int) -> int:
	var n := space_count()
	if n <= 0:
		return 0
	return posmod(geom_space - start_space, n)


func to_heat_track(laps: int = 1) -> HeatTrack:
	var track := HeatTrack.new()
	track.id = path if not path.is_empty() else "spline:%s" % display_name()
	track.laps = maxi(1, laps)
	track.space_count = space_count()
	track.spots.clear()
	for _i in track.space_count:
		track.spots.append(2)
	track.corners.clear()
	var corner_spaces: Array[int] = []
	for key in corners.keys():
		corner_spaces.append(int(key))
	corner_spaces.sort()
	for geom in corner_spaces:
		var entry: Variant = corners[geom]
		var speed := 0
		if entry is Dictionary:
			speed = int(entry.get("speed_limit", 0))
		else:
			speed = int(entry)
		var play_from := geom_to_play(geom)
		track.corners.append(HeatCorner.new(play_from, speed, "c%d" % play_from))
	track.start_heat = int(document.get("start_heat", 6))
	track.start_stress = int(document.get("start_stress", 3))
	track.start_behind_finish_line = true
	track.start_max_per_space = 2
	track.spline_bind = self
	return track


## World-space mid-space poses for playable space (spot 0 = race line).
func space_slot_poses(play_space: int) -> Array:
	if seg == null or space_count() < 2:
		return []
	var geom := play_to_geom(play_space)
	var poses := seg.space_slot_poses(geom, half_width, spot_inset)
	if poses.size() < 2:
		return poses
	var race: Dictionary = (poses[0] as Dictionary).duplicate()
	var outer: Dictionary = (poses[1] as Dictionary).duplicate()
	if space_race_line_flipped_geom(geom):
		var tmp_pos: Vector2 = race.pos
		race["pos"] = outer.pos
		outer["pos"] = tmp_pos
	var heading: Vector2 = outer.heading
	if heading.length_squared() > 0.0001:
		outer["pos"] = (outer.pos as Vector2) - heading.normalized() * SplineTrackPainter.OUTER_SPOT_ALONG_OFFSET
	return [race, outer]


func sample_at(progress: float, spot: float) -> Dictionary:
	var n := space_count()
	if n < 2:
		return {"pos": Vector2.ZERO, "heading": Vector2.RIGHT}
	var spot0 := int(floor(spot))
	if is_equal_approx(spot, float(spot0)):
		return _sample_at_spot(progress, spot0)
	var a := _sample_at_spot(progress, spot0)
	var b := _sample_at_spot(progress, spot0 + 1)
	var u := spot - float(spot0)
	return {
		"pos": (a.pos as Vector2).lerp(b.pos as Vector2, u),
		"heading": _slerp_heading(a.heading, b.heading, u),
	}


func paint_context(font: Font = null) -> SplineTrackPainter.Context:
	var ctx := SplineTrackPainter.Context.new()
	ctx.half_width = half_width
	ctx.spot_inset = spot_inset
	ctx.seg = seg
	ctx.start_space = start_space
	ctx.corners = corners
	ctx.kerbs = kerbs
	ctx.race_line_flipped = space_race_line_flipped_geom
	ctx.font = font if font != null else ThemeDB.fallback_font
	return ctx


func baked_points() -> PackedVector2Array:
	return SplineTrackPainter.bake_spline(spline)


func space_race_line_flipped_geom(geom_space: int) -> bool:
	if corners.is_empty():
		return bool(sector_flip_race_line.get(-1, false))
	var n := space_count()
	if n == 0:
		return false
	var ordered: Array[int] = []
	for key in corners.keys():
		ordered.append(int(key))
	ordered.sort()
	if ordered.is_empty():
		return false
	var flip_key := ordered[ordered.size() - 1]
	for i in ordered.size():
		var c := ordered[i]
		var next_c := ordered[(i + 1) % ordered.size()]
		var from := posmod(c + 1, n)
		var to := next_c
		if posmod(geom_space - from, n) <= posmod(to - from, n):
			flip_key = c
			break
	return bool(sector_flip_race_line.get(flip_key, false))


func _sample_at_spot(progress: float, spot: int) -> Dictionary:
	var n := space_count()
	var p0 := int(floor(progress))
	var frac := progress - float(p0)
	# Engine progress indexes the space the car occupies; lerp toward the next space.
	var s0 := posmod(p0, n)
	var s1 := posmod(p0 + 1, n)
	var a := _pose_for_play_space(s0, spot)
	var b := _pose_for_play_space(s1, spot)
	if is_equal_approx(frac, 0.0):
		return a
	return {
		"pos": (a.pos as Vector2).lerp(b.pos as Vector2, frac),
		"heading": _slerp_heading(a.heading, b.heading, frac),
	}


func _pose_for_play_space(play_space: int, spot: int) -> Dictionary:
	var poses := space_slot_poses(play_space)
	if poses.is_empty():
		return {"pos": Vector2.ZERO, "heading": Vector2.RIGHT}
	var idx := clampi(spot, 0, poses.size() - 1)
	var pose: Dictionary = poses[idx]
	return {
		"pos": pose.get("pos", Vector2.ZERO),
		"heading": pose.get("heading", Vector2.RIGHT),
	}


func _slerp_heading(a: Variant, b: Variant, u: float) -> Vector2:
	var ha: Vector2 = a if a is Vector2 else Vector2.RIGHT
	var hb: Vector2 = b if b is Vector2 else ha
	if ha.length_squared() < 0.0001:
		ha = Vector2.RIGHT
	else:
		ha = ha.normalized()
	if hb.length_squared() < 0.0001:
		hb = ha
	else:
		hb = hb.normalized()
	if ha.dot(hb) < 0.0:
		hb = -hb
	var mixed := ha.lerp(hb, u)
	if mixed.length_squared() < 0.0001:
		return ha
	return mixed.normalized()
