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

	func space_count() -> int:
		return frontiers.size()


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
	return result


## Dense centerline samples with cumulative length, tangent, inside normal.
static func _build_samples(spline: TrackSpline, p: Params) -> Array:
	var baked := spline.baked_points(p.bake_interval)
	var pts := _unique_loop(baked)
	var n := pts.size()
	if n < 3:
		return []

	var centroid := Vector2.ZERO
	for i in n:
		centroid += pts[i]
	centroid /= float(n)

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
		var toward_inside := centroid - curr
		var inside := left if left.dot(toward_inside) >= 0.0 else -left
		samples.append({
			"pos": curr,
			"tangent": tangent,
			"inside": inside.normalized(),
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
	var offsets: Array[float] = [0.0]
	var s := 0.0
	var guard := 0
	while guard < p.max_spaces * 2:
		guard += 1
		var step := _adaptive_step_at(samples, s, total, p)
		if s + step >= total - p.car_length * 0.35:
			break
		s += step
		offsets.append(s)
	# Ensure enough spaces; if too few, fall back to inner uniform.
	if offsets.size() < p.min_spaces:
		return _offsets_inner_uniform(samples, total, p)
	# Redistribute slightly so the last gap closes evenly: scale offsets into [0, total).
	# Keep relative spacing, map max offset to leave one average gap at the end.
	var last := offsets[offsets.size() - 1]
	if last <= 0.0001:
		return _offsets_inner_uniform(samples, total, p)
	# Target: equalize remaining ring so average step matches.
	var count := offsets.size()
	var ring_step := total / float(count)
	# Blend original relative positions with a uniform ring for clean closure.
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var rel := float(offsets[i]) / last if i > 0 else 0.0
		# Map so frontier i sits at i * ring_step, weighted with adaptive shape.
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
