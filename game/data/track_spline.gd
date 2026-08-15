class_name TrackSpline
extends RefCounted

## Closed path defined by control points with a cubic Bezier backbone.
## Per-point types share the same Bezier representation; only how tangents
## are authored changes (auto / tension / free).

enum PointType {
	AUTO_SMOOTH, ## Tangents fully automatic (Catmull-Rom-equivalent).
	TENSION, ## Symmetric tangents; `tension` scales handle length.
	FREE, ## Independent in/out handles.
}

const DEFAULT_TENSION := 1.0
const MIN_TENSION := 0.05
const MAX_TENSION := 3.0
const MIN_POINTS := 3
## Maps tension=1 to Catmull-Rom-equivalent handle length fraction of chord.
const TENSION_TO_HANDLE := 1.0 / 6.0

const TYPE_NAMES := {
	PointType.AUTO_SMOOTH: "Auto",
	PointType.TENSION: "Tension",
	PointType.FREE: "Libre",
}


class ControlPoint:
	extends RefCounted

	var position: Vector2 = Vector2.ZERO
	var type: int = PointType.AUTO_SMOOTH
	## Amplitude scaler for TENSION (1 = natural). Ignored by AUTO_SMOOTH / FREE.
	var tension: float = DEFAULT_TENSION
	## Relative handles for FREE mode.
	var in_handle: Vector2 = Vector2.ZERO
	var out_handle: Vector2 = Vector2.ZERO

	func duplicate_point() -> ControlPoint:
		var copy := ControlPoint.new()
		copy.position = position
		copy.type = type
		copy.tension = tension
		copy.in_handle = in_handle
		copy.out_handle = out_handle
		return copy


var points: Array = [] ## Array[ControlPoint]


static func make_default_triangle(center: Vector2 = Vector2(640, 360), radius: float = 180.0) -> TrackSpline:
	var spline := TrackSpline.new()
	# Equilateral layout so a closed tension curve reads as a smooth oval-ish loop.
	for i in 3:
		var angle := -PI * 0.5 + TAU * float(i) / 3.0
		var p := ControlPoint.new()
		p.position = center + Vector2(cos(angle), sin(angle)) * radius
		p.type = PointType.AUTO_SMOOTH
		p.tension = DEFAULT_TENSION
		spline.points.append(p)
	return spline


## Cardinal auto-smooth points; closed Catmull-style handles read as a stadium oval.
static func make_default_oval(
	center: Vector2 = Vector2.ZERO,
	radii: Vector2 = Vector2(420, 260)
) -> TrackSpline:
	var spline := TrackSpline.new()
	var offsets := [
		Vector2(0.0, -radii.y),
		Vector2(radii.x, 0.0),
		Vector2(0.0, radii.y),
		Vector2(-radii.x, 0.0),
	]
	for offset in offsets:
		var p := ControlPoint.new()
		p.position = center + offset
		p.type = PointType.AUTO_SMOOTH
		p.tension = DEFAULT_TENSION
		spline.points.append(p)
	return spline


static func type_name(type: int) -> String:
	return str(TYPE_NAMES.get(type, "?"))


func point_count() -> int:
	return points.size()


func get_point(index: int) -> ControlPoint:
	return points[posmod(index, points.size())] as ControlPoint


func set_point_position(index: int, pos: Vector2) -> void:
	get_point(index).position = pos


func set_point_tension(index: int, tension: float) -> void:
	var cp := get_point(index)
	if cp.type != PointType.TENSION:
		return
	cp.tension = clampf(tension, MIN_TENSION, MAX_TENSION)


## Switch point type, baking / recovering handles so the curve shape stays close.
func set_point_type(index: int, new_type: int) -> void:
	var cp := get_point(index)
	if cp.type == new_type:
		return
	var resolved: Dictionary = _resolved_handles(index)
	match new_type:
		PointType.FREE:
			cp.in_handle = resolved.in
			cp.out_handle = resolved.out
		PointType.TENSION:
			var out_len: float = (resolved.out as Vector2).length()
			cp.tension = _tension_from_handle_length(index, out_len)
		PointType.AUTO_SMOOTH:
			pass
	cp.type = new_type


func set_out_handle_world(index: int, world_pos: Vector2) -> void:
	var cp := get_point(index)
	if cp.type != PointType.FREE:
		return
	cp.out_handle = world_pos - cp.position


func set_in_handle_world(index: int, world_pos: Vector2) -> void:
	var cp := get_point(index)
	if cp.type != PointType.FREE:
		return
	cp.in_handle = world_pos - cp.position


## Inserts a tension point on the closest curve location to `world_pos`.
## Returns the new point index, or -1 if the curve is empty.
func insert_point_near(world_pos: Vector2) -> int:
	if points.is_empty():
		return -1
	var curve := to_curve2d()
	var on_curve := curve.get_closest_point(world_pos)
	var offset := curve.get_closest_offset(world_pos)
	var insert_after := _segment_index_at_offset(curve, offset)
	var cp := ControlPoint.new()
	cp.position = on_curve
	cp.type = PointType.AUTO_SMOOTH
	cp.tension = DEFAULT_TENSION
	var new_index := insert_after + 1
	if new_index >= points.size():
		points.append(cp)
		new_index = points.size() - 1
	else:
		points.insert(new_index, cp)
	return new_index


## Removes a control point. Fails (returns false) below MIN_POINTS.
func remove_point(index: int) -> bool:
	if points.size() <= MIN_POINTS:
		return false
	points.remove_at(posmod(index, points.size()))
	return true


## Closest point on the closed curve to `world_pos`, plus distance.
func closest_on_curve(world_pos: Vector2) -> Dictionary:
	if points.is_empty():
		return {"point": world_pos, "distance": INF}
	var curve := to_curve2d()
	var on_curve := curve.get_closest_point(world_pos)
	return {"point": on_curve, "distance": world_pos.distance_to(on_curve)}


## World-space outgoing handle tip for the given point (for editor gizmos).
func out_handle_world(index: int) -> Vector2:
	var cp := get_point(index)
	var handles := _resolved_handles(index)
	return cp.position + handles.out


## World-space incoming handle tip.
func in_handle_world(index: int) -> Vector2:
	var cp := get_point(index)
	var handles := _resolved_handles(index)
	return cp.position + handles.in


## Tension implied by dragging a handle tip to `world_pos` (TENSION mode).
func tension_from_out_handle(index: int, world_pos: Vector2) -> float:
	var cp := get_point(index)
	var chord := _neighbor_chord(index)
	var chord_len := chord.length()
	if chord_len < 0.001:
		return cp.tension
	var dir := chord / chord_len
	var offset := world_pos - cp.position
	var handle_len := absf(offset.dot(dir))
	return _tension_from_handle_length(index, handle_len)


## Builds a Curve2D; Godot 4.7 has no Curve2D.closed, so the first point is
## appended again to close the path for baking / Path2D consumers.
func to_curve2d() -> Curve2D:
	var curve := Curve2D.new()
	if points.is_empty():
		return curve
	for i in points.size():
		var cp := get_point(i)
		var handles := _resolved_handles(i)
		curve.add_point(cp.position, handles.in, handles.out)
	var first := get_point(0)
	var first_handles := _resolved_handles(0)
	curve.add_point(first.position, first_handles.in, Vector2.ZERO)
	return curve


## Sample the closed path as polyline points (for drawing / future space baking).
func baked_points(bake_interval: float = 8.0) -> PackedVector2Array:
	var curve := to_curve2d()
	curve.bake_interval = bake_interval
	return curve.get_baked_points()


func to_dict() -> Dictionary:
	var points_data: Array = []
	for i in points.size():
		var cp := get_point(i)
		points_data.append({
			"x": cp.position.x,
			"y": cp.position.y,
			"type": int(cp.type),
			"tension": cp.tension,
			"in": [cp.in_handle.x, cp.in_handle.y],
			"out": [cp.out_handle.x, cp.out_handle.y],
		})
	return {"points": points_data}


static func from_dict(data: Dictionary) -> TrackSpline:
	var spline := TrackSpline.new()
	var points_data: Variant = data.get("points", [])
	if points_data is Array:
		for item in points_data:
			if not item is Dictionary:
				continue
			var entry: Dictionary = item
			var cp := ControlPoint.new()
			cp.position = Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
			cp.type = int(entry.get("type", PointType.AUTO_SMOOTH))
			cp.tension = float(entry.get("tension", DEFAULT_TENSION))
			var hin: Variant = entry.get("in", [0.0, 0.0])
			var hout: Variant = entry.get("out", [0.0, 0.0])
			if hin is Array and hin.size() >= 2:
				cp.in_handle = Vector2(float(hin[0]), float(hin[1]))
			if hout is Array and hout.size() >= 2:
				cp.out_handle = Vector2(float(hout[0]), float(hout[1]))
			spline.points.append(cp)
	return spline


func _tension_from_handle_length(index: int, handle_len: float) -> float:
	var natural := _neighbor_chord(index).length() * TENSION_TO_HANDLE
	if natural < 0.001:
		return DEFAULT_TENSION
	return clampf(handle_len / natural, MIN_TENSION, MAX_TENSION)


func _resolved_handles(index: int) -> Dictionary:
	var cp := get_point(index)
	match cp.type:
		PointType.FREE:
			return {"in": cp.in_handle, "out": cp.out_handle}
		PointType.AUTO_SMOOTH:
			return _tension_handles(index, DEFAULT_TENSION)
		_:
			return _tension_handles(index, cp.tension)


func _tension_handles(index: int, tension: float) -> Dictionary:
	var chord := _neighbor_chord(index)
	var out_vec := chord * (TENSION_TO_HANDLE * tension)
	return {"in": -out_vec, "out": out_vec}


func _neighbor_chord(index: int) -> Vector2:
	var prev_p := get_point(index - 1).position
	var next_p := get_point(index + 1).position
	return next_p - prev_p


## Which open segment [i → i+1] (wrapping) contains baked `offset`.
func _segment_index_at_offset(curve: Curve2D, offset: float) -> int:
	var n := points.size()
	if n <= 1:
		return 0
	var baked_len := curve.get_baked_length()
	var clamped := clampf(offset, 0.0, baked_len)
	var starts: PackedFloat32Array = PackedFloat32Array()
	starts.resize(n)
	for i in n:
		if i == 0:
			starts[i] = 0.0
		else:
			starts[i] = curve.get_closest_offset(get_point(i).position)
	for i in n:
		var o_start: float = starts[i]
		var o_end: float = baked_len if i == n - 1 else starts[i + 1]
		if clamped >= o_start and clamped <= o_end:
			return i
	return n - 1
