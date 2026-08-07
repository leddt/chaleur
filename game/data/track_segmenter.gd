class_name TrackSegmenter
extends RefCounted

## Builds closed-track space frontiers (2 spots: inner race line + outer)
## from a TrackSpline, with interchangeable segmentation algorithms.

enum Algorithm {
	CENTER_UNIFORM, ## Equal arc length on the centerline.
	INNER_UNIFORM, ## Equal arc length on the inner (race line) offset.
	ADAPTIVE_INNER, ## Local step so inner arc stays ≥ car_length.
}

const ALGO_NAMES := {
	Algorithm.CENTER_UNIFORM: "Centre uniforme",
	Algorithm.INNER_UNIFORM: "Intérieur uniforme",
	Algorithm.ADAPTIVE_INNER: "Adaptatif (intérieur)",
}


class Params:
	extends RefCounted

	var algorithm: int = Algorithm.INNER_UNIFORM
	var road_half_width: float = 28.0
	## Minimum inner arc length per space (car footprint along the race line).
	var car_length: float = 36.0
	## Spot distance from centerline as a fraction of road_half_width.
	var spot_inset: float = 0.45
	var bake_interval: float = 4.0
	## If > 0, preferred centerline step for CENTER_UNIFORM (else car_length).
	var target_space_len: float = 0.0
	## If > 0, force exactly this many spaces (clamped to min/max); length params ignored for count.
	var forced_space_count: int = 0
	var min_spaces: int = 8
	var max_spaces: int = 180


class Frontier:
	extends RefCounted

	var center: Vector2 = Vector2.ZERO
	var tangent: Vector2 = Vector2.RIGHT
	## Unit normal pointing toward the inside of the loop (race line side).
	var inside_normal: Vector2 = Vector2.UP
	var spot_inner: Vector2 = Vector2.ZERO ## Spot 0 — race line.
	var spot_outer: Vector2 = Vector2.ZERO ## Spot 1 — outside.
	var offset: float = 0.0 ## Arc length along centerline.


class Result:
	extends RefCounted

	var frontiers: Array = [] ## Array[Frontier]
	var total_length: float = 0.0
	var algorithm: int = Algorithm.INNER_UNIFORM
	## Dense centerline samples used for ribbons / hit-tests (includes closing duplicate).
	var samples: Array = []

	func space_count() -> int:
		return frontiers.size()


	## Asphalt ribbon polygon for one space (follows the curve — OK in tight corners).
	## May be concave / self-intersecting in S-bends; prefer `space_fill_quads` for fills.
	func space_ribbon(space_index: int, half_width: float) -> PackedVector2Array:
		var pts := _space_centerline_samples(space_index)
		if pts.size() < 2:
			return PackedVector2Array()
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		left.resize(pts.size())
		right.resize(pts.size())
		var prev_inside := Vector2.ZERO
		for i in pts.size():
			var s: Dictionary = pts[i]
			var pos: Vector2 = s.pos
			var inside: Vector2 = s.inside
			if inside.length_squared() > 0.0001:
				inside = inside.normalized()
			if i > 0 and inside.dot(prev_inside) < 0.0:
				inside = -inside
			prev_inside = inside
			left[i] = pos + inside * half_width
			right[i] = pos - inside * half_width
		var poly := PackedVector2Array()
		poly.resize(pts.size() * 2)
		for i in pts.size():
			poly[i] = left[i]
		for i in pts.size():
			poly[pts.size() + i] = right[pts.size() - 1 - i]
		return poly


	## Consecutive convex quads covering a space band. Densified so S-bends stay fillable.
	func space_fill_quads(space_index: int, half_width: float) -> Array:
		var raw := _space_centerline_samples(space_index)
		if raw.size() < 2:
			return []
		var path_len := 0.0
		for i in raw.size() - 1:
			path_len += (raw[i].pos as Vector2).distance_to(raw[i + 1].pos as Vector2)
		var steps := maxi(1, int(ceil(path_len / 4.0)))
		var pts: Array = []
		pts.resize(steps + 1)
		for i in steps + 1:
			pts[i] = _interpolate_along_path(raw, float(i) / float(steps))
		var insides: Array[Vector2] = []
		insides.resize(pts.size())
		var prev_inside := Vector2.ZERO
		for i in pts.size():
			var inside: Vector2 = pts[i].inside
			if inside.length_squared() > 0.0001:
				inside = inside.normalized()
			else:
				inside = Vector2.UP
			if i > 0 and inside.dot(prev_inside) < 0.0:
				inside = -inside
			prev_inside = inside
			insides[i] = inside
		var quads: Array = []
		for i in pts.size() - 1:
			var a: Vector2 = pts[i].pos
			var b: Vector2 = pts[i + 1].pos
			var ia: Vector2 = insides[i]
			var ib: Vector2 = insides[i + 1]
			quads.append(PackedVector2Array([
				a + ia * half_width,
				b + ib * half_width,
				b - ib * half_width,
				a - ia * half_width,
			]))
		return quads


	## Centerline points for one space (entry → samples → exit), for stroke-style fills.
	func space_centerline_points(space_index: int) -> PackedVector2Array:
		var pts := _space_centerline_samples(space_index)
		var out := PackedVector2Array()
		out.resize(pts.size())
		for i in pts.size():
			out[i] = pts[i].pos as Vector2
		return out


	## Space index under `world_pos`, or -1 if outside the asphalt band.
	func space_at_world(world_pos: Vector2, half_width: float) -> int:
		if frontiers.is_empty() or samples.is_empty() or total_length <= 0.0:
			return -1
		var best_i := 0
		var best_d := INF
		# Ignore closing duplicate when searching.
		var n_samp := maxi(samples.size() - 1, 1)
		for i in n_samp:
			var d: float = world_pos.distance_squared_to(samples[i].pos as Vector2)
			if d < best_d:
				best_d = d
				best_i = i
		if sqrt(best_d) > half_width + 2.0:
			return -1
		var offset := float(samples[best_i].cum)
		return space_index_at_offset(offset)


	func space_index_at_offset(offset: float) -> int:
		var n := frontiers.size()
		if n == 0 or total_length <= 0.0:
			return -1
		var o := fposmod(offset, total_length)
		for i in n:
			var a := float((frontiers[i] as Frontier).offset)
			var b := float((frontiers[(i + 1) % n] as Frontier).offset)
			if a <= b:
				if o >= a and o < b:
					return i
			else:
				# Wrap across the finish.
				if o >= a or o < b:
					return i
		return n - 1


	func _space_centerline_samples(space_index: int) -> Array:
		var n := frontiers.size()
		if n < 2 or samples.is_empty():
			return []
		var i0 := posmod(space_index, n)
		var a: Frontier = frontiers[i0]
		var b: Frontier = frontiers[(i0 + 1) % n]
		var o0 := float(a.offset)
		var o1 := float(b.offset)
		var out: Array = []
		out.append({
			"pos": a.center,
			"inside": a.inside_normal,
			"tangent": a.tangent,
			"cum": o0,
		})
		var n_samp := maxi(samples.size() - 1, 0)
		if o0 <= o1:
			for i in n_samp:
				var c := float(samples[i].cum)
				if c > o0 and c < o1:
					out.append(samples[i])
		else:
			for i in n_samp:
				var c := float(samples[i].cum)
				if c > o0:
					out.append(samples[i])
			for i in n_samp:
				var c := float(samples[i].cum)
				if c < o1:
					out.append(samples[i])
		out.append({
			"pos": b.center,
			"inside": b.inside_normal,
			"tangent": b.tangent,
			"cum": o1 if o1 > o0 else o1 + total_length,
		})
		return out


	## Spot poses at mid-arc of the space (same ribbon logic — not a chord lerp).
	func space_slot_poses(space_index: int, road_half_width: float, spot_inset: float) -> Array:
		var n := frontiers.size()
		if n < 2:
			return []
		var pts := _space_centerline_samples(space_index)
		if pts.size() < 2:
			return []
		var mid := _interpolate_along_path(pts, 0.5)
		var inside: Vector2 = mid.inside
		if inside.length_squared() < 0.0001:
			inside = (frontiers[posmod(space_index, n)] as Frontier).inside_normal
		else:
			inside = inside.normalized()
		# Keep side coherent with the space entry frontier (avoids mid-lerp flip).
		var entry_inside: Vector2 = (frontiers[posmod(space_index, n)] as Frontier).inside_normal
		if inside.dot(entry_inside) < 0.0:
			inside = -inside
		var heading: Vector2 = mid.tangent
		if heading.length_squared() < 0.0001:
			heading = (frontiers[posmod(space_index, n)] as Frontier).tangent
		else:
			heading = heading.normalized()
		var lateral := road_half_width * spot_inset
		var center: Vector2 = mid.pos
		return [
			{"pos": center + inside * lateral, "heading": heading},
			{"pos": center - inside * lateral, "heading": heading},
		]


	func _interpolate_along_path(pts: Array, fraction: float) -> Dictionary:
		var seglens: PackedFloat32Array = PackedFloat32Array()
		seglens.resize(pts.size() - 1)
		var total := 0.0
		for i in pts.size() - 1:
			var d: float = (pts[i].pos as Vector2).distance_to(pts[i + 1].pos as Vector2)
			seglens[i] = d
			total += d
		if total < 0.0001:
			return pts[0]
		var target := clampf(fraction, 0.0, 1.0) * total
		var acc := 0.0
		for i in seglens.size():
			var seg: float = seglens[i]
			if acc + seg >= target - 0.00001:
				var u := 0.0 if seg < 0.0001 else (target - acc) / seg
				return _lerp_sample(pts[i], pts[i + 1], u)
			acc += seg
		return pts[pts.size() - 1]


	func _lerp_sample(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
		var ia: Vector2 = a.inside
		var ib: Vector2 = b.inside
		if ia.length_squared() > 0.0001:
			ia = ia.normalized()
		if ib.length_squared() > 0.0001:
			ib = ib.normalized()
		if ia.dot(ib) < 0.0:
			ib = -ib
		var ta: Vector2 = a.get("tangent", Vector2.RIGHT)
		var tb: Vector2 = b.get("tangent", ta)
		if ta.length_squared() > 0.0001:
			ta = ta.normalized()
		if tb.length_squared() > 0.0001:
			tb = tb.normalized()
		if ta.dot(tb) < 0.0:
			tb = -tb
		var inside := ia.lerp(ib, u)
		if inside.length_squared() > 0.0001:
			inside = inside.normalized()
		var tangent := ta.lerp(tb, u)
		if tangent.length_squared() > 0.0001:
			tangent = tangent.normalized()
		return {
			"pos": (a.pos as Vector2).lerp(b.pos as Vector2, u),
			"inside": inside,
			"tangent": tangent,
			"cum": lerpf(float(a.cum), float(b.cum), u),
		}


static func algorithm_name(algo: int) -> String:
	return str(ALGO_NAMES.get(algo, "?"))


static func segment(spline: TrackSpline, params: Params = null) -> Result:
	var p := params if params != null else Params.new()
	var result := Result.new()
	result.algorithm = p.algorithm
	if spline == null or spline.point_count() < 3:
		return result

	var samples := _build_samples(spline, p)
	if samples.size() < 3:
		return result
	result.total_length = float(samples[samples.size() - 1].get("cum", 0.0))
	if result.total_length < 1.0:
		return result

	var offsets: PackedFloat32Array
	match p.algorithm:
		Algorithm.CENTER_UNIFORM:
			offsets = _offsets_center_uniform(result.total_length, p)
		Algorithm.INNER_UNIFORM:
			offsets = _offsets_inner_uniform(samples, result.total_length, p)
		Algorithm.ADAPTIVE_INNER:
			offsets = _offsets_adaptive_inner(samples, result.total_length, p)
		_:
			offsets = _offsets_inner_uniform(samples, result.total_length, p)

	for i in offsets.size():
		result.frontiers.append(_frontier_at(samples, float(offsets[i]), p))
	result.samples = samples
	return result


## Dense centerline samples with cumulative length, tangent, inside normal.
static func _build_samples(spline: TrackSpline, p: Params) -> Array:
	var baked := spline.baked_points(p.bake_interval)
	var pts := _unique_loop(baked)
	var n := pts.size()
	if n < 3:
		return []

	# Winding decides "inside" once for the whole loop. Centroid.dot(left) flips mid-track
	# on elongated / concave shapes (race-line kerb would jump sides inside a sector).
	# Godot Y-down: positive shoelace ≈ clockwise. Traversing clockwise, interior is
	# to the left of the forward tangent (same as math CCW / left-hand rule on screen).
	var shoelace := 0.0
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		shoelace += a.x * b.y - b.x * a.y
	var inside_from_left := 1.0 if shoelace > 0.0 else -1.0

	var samples: Array = []
	var cum := 0.0
	for i in n:
		var prev: Vector2 = pts[(i - 1 + n) % n]
		var curr: Vector2 = pts[i]
		var next: Vector2 = pts[(i + 1) % n]
		if i > 0:
			cum += curr.distance_to(pts[i - 1])
		var tangent := (next - prev)
		if tangent.length_squared() < 0.0001:
			tangent = next - curr
		if tangent.length_squared() < 0.0001:
			tangent = Vector2.RIGHT
		else:
			tangent = tangent.normalized()
		var left := Vector2(-tangent.y, tangent.x)
		var inside := (left * inside_from_left).normalized()
		# Keep continuity if a cusp reverses left momentarily.
		if i > 0 and inside.dot(samples[i - 1].inside as Vector2) < 0.0:
			inside = -inside
		samples.append({
			"pos": curr,
			"tangent": tangent,
			"inside": inside,
			"cum": cum,
		})
	# Close length: add last→first distance onto a virtual end sample for interpolation.
	var close_len := pts[0].distance_to(pts[n - 1])
	samples.append({
		"pos": pts[0],
		"tangent": samples[0].tangent,
		"inside": samples[0].inside,
		"cum": cum + close_len,
	})
	return samples


static func _unique_loop(baked: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if baked.is_empty():
		return pts
	pts.append(baked[0])
	for i in range(1, baked.size()):
		if baked[i].distance_squared_to(pts[pts.size() - 1]) > 0.25:
			pts.append(baked[i])
	if pts.size() >= 2 and pts[0].distance_squared_to(pts[pts.size() - 1]) <= 0.25:
		pts.resize(pts.size() - 1)
	return pts


static func _space_count_for_length(total: float, step: float, p: Params) -> int:
	if p.forced_space_count > 0:
		return clampi(p.forced_space_count, p.min_spaces, p.max_spaces)
	var raw := int(round(total / maxf(step, 1.0)))
	return clampi(raw, p.min_spaces, p.max_spaces)


static func _offsets_center_uniform(total: float, p: Params) -> PackedFloat32Array:
	var step := p.target_space_len if p.target_space_len > 0.0 else p.car_length
	var count := _space_count_for_length(total, step, p)
	var actual := total / float(count)
	var offsets := PackedFloat32Array()
	offsets.resize(count)
	for i in count:
		offsets[i] = actual * float(i)
	return offsets


static func _offsets_inner_uniform(samples: Array, total: float, p: Params) -> PackedFloat32Array:
	var inset := p.road_half_width * p.spot_inset
	# Cumulative length along the inner offset polyline ( excluding final duplicate ).
	var inner_cum := PackedFloat32Array()
	var n := samples.size() - 1
	inner_cum.resize(n + 1)
	inner_cum[0] = 0.0
	for i in range(1, n + 1):
		var a: Vector2 = samples[i - 1].pos + samples[i - 1].inside * inset
		var b: Vector2 = samples[i].pos + samples[i].inside * inset
		inner_cum[i] = inner_cum[i - 1] + a.distance_to(b)
	var inner_total := float(inner_cum[n])
	if inner_total < 1.0:
		return _offsets_center_uniform(total, p)

	var count := _space_count_for_length(inner_total, p.car_length, p)
	var inner_step := inner_total / float(count)
	var offsets := PackedFloat32Array()
	offsets.resize(count)
	for i in count:
		var target_inner := inner_step * float(i)
		offsets[i] = _center_offset_for_inner(samples, inner_cum, target_inner, total)
	return offsets


static func _center_offset_for_inner(
	samples: Array,
	inner_cum: PackedFloat32Array,
	target_inner: float,
	center_total: float
) -> float:
	var n := inner_cum.size() - 1
	var t := fposmod(target_inner, float(inner_cum[n]))
	# Find segment on inner path.
	var seg := 0
	while seg < n - 1 and inner_cum[seg + 1] < t:
		seg += 1
	var seg_len := float(inner_cum[seg + 1] - inner_cum[seg])
	var u := 0.0 if seg_len < 0.0001 else (t - float(inner_cum[seg])) / seg_len
	var c0 := float(samples[seg].cum)
	var c1 := float(samples[seg + 1].cum)
	return clampf(lerpf(c0, c1, u), 0.0, center_total - 0.0001)


static func _offsets_adaptive_inner(samples: Array, total: float, p: Params) -> PackedFloat32Array:
	var forced_count := (
		clampi(p.forced_space_count, p.min_spaces, p.max_spaces) if p.forced_space_count > 0 else 0
	)
	var offsets: Array[float] = [0.0]
	var s := 0.0
	var guard := 0
	while guard < p.max_spaces * 2:
		guard += 1
		if forced_count > 0 and offsets.size() >= forced_count:
			break
		var step := _adaptive_step_at(samples, s, total, p)
		if forced_count <= 0 and s + step >= total - p.car_length * 0.35:
			break
		s += step
		if s >= total - 0.001:
			break
		offsets.append(s)
		if forced_count <= 0 and offsets.size() >= p.max_spaces:
			break
	# Ensure enough spaces; if too few, fall back to inner uniform.
	if offsets.size() < p.min_spaces:
		return _offsets_inner_uniform(samples, total, p)
	var last := offsets[offsets.size() - 1]
	if last <= 0.0001:
		return _offsets_inner_uniform(samples, total, p)
	# Normalize adaptive sample to unit shape, optionally resample for a fixed count.
	var shape: Array[float] = []
	shape.resize(offsets.size())
	for i in offsets.size():
		shape[i] = float(offsets[i]) / last
	var count := forced_count if forced_count > 0 else offsets.size()
	var densified: Array[float] = []
	densified.resize(count)
	if count == shape.size():
		for i in count:
			densified[i] = shape[i]
	else:
		for i in count:
			# Sample count frontiers on [0,1) of the adaptive shape before close.
			var t := float(i) / float(count) * float(shape.size() - 1)
			var i0 := int(floor(t))
			var i1 := mini(i0 + 1, shape.size() - 1)
			var u := t - float(i0)
			densified[i] = lerpf(shape[i0], shape[i1], u)
	var ring_step := total / float(count)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var rel := densified[i]
		var adaptive_pos := rel * (total - ring_step)
		var uniform_pos := ring_step * float(i)
		out[i] = lerpf(uniform_pos, adaptive_pos, 0.65)
	return out


static func _adaptive_step_at(samples: Array, s: float, total: float, p: Params) -> float:
	var fr: Dictionary = _sample_at(samples, s)
	var tangent: Vector2 = fr.tangent
	# Look ahead a bit to estimate curvature.
	var ahead_s := minf(s + maxf(p.car_length, 8.0), total - 0.001)
	var ahead: Dictionary = _sample_at(samples, ahead_s)
	var t2: Vector2 = ahead.tangent
	var ds := maxf(ahead_s - s, 0.001)
	var turn := absf(tangent.angle_to(t2))
	var kappa := turn / ds
	var R := 1.0 / maxf(kappa, 0.00005)
	var inset := p.road_half_width * p.spot_inset
	var R_in := maxf(R - inset, inset * 0.5)
	var need := p.car_length * (R / R_in)
	# Also never go below a short floor on straightaways.
	var straight := p.target_space_len if p.target_space_len > 0.0 else p.car_length
	return clampf(need, straight * 0.75, straight * 3.5)


static func _frontier_at(samples: Array, offset: float, p: Params) -> Frontier:
	var s: Dictionary = _sample_at(samples, offset)
	var fr := Frontier.new()
	fr.center = s.pos
	fr.tangent = s.tangent
	fr.inside_normal = s.inside
	fr.offset = offset
	var lateral := p.road_half_width * p.spot_inset
	fr.spot_inner = fr.center + fr.inside_normal * lateral
	fr.spot_outer = fr.center - fr.inside_normal * lateral
	return fr


static func _sample_at(samples: Array, offset: float) -> Dictionary:
	var total := float(samples[samples.size() - 1].cum)
	var o := fposmod(offset, total)
	var lo := 0
	var hi := samples.size() - 1
	while lo + 1 < hi:
		var mid := (lo + hi) >> 1
		if float(samples[mid].cum) <= o:
			lo = mid
		else:
			hi = mid
	var c0 := float(samples[lo].cum)
	var c1 := float(samples[hi].cum)
	var u := 0.0 if c1 - c0 < 0.0001 else (o - c0) / (c1 - c0)
	var t0: Vector2 = samples[lo].tangent
	var t1: Vector2 = samples[hi].tangent
	var i0: Vector2 = samples[lo].inside
	var i1: Vector2 = samples[hi].inside
	if i0.dot(i1) < 0.0:
		i1 = -i1
	var tangent := (t0.lerp(t1, u))
	if tangent.length_squared() < 0.0001:
		tangent = t0
	else:
		tangent = tangent.normalized()
	var inside := (i0.lerp(i1, u))
	if inside.length_squared() < 0.0001:
		inside = i0
	else:
		inside = inside.normalized()
	return {
		"pos": (samples[lo].pos as Vector2).lerp(samples[hi].pos as Vector2, u),
		"tangent": tangent,
		"inside": inside,
		"cum": o,
	}
