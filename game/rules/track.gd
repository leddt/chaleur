class_name HeatTrack
extends RefCounted

var id: String = ""
var space_count: int = 0
## Number of spots on each space (index = space). Spot 0 = closest to race line.
var spots: Array[int] = []
var corners: Array[HeatCorner] = []
var laps: int = 1
var start_heat: int = 6
var start_stress: int = 3
## If true, cars start behind the finish/start line on the last spaces (progress -1, -2, …).
var start_behind_finish_line: bool = false
## Max cars sharing one space on the starting grid (and typically the whole track).
var start_max_per_space: int = 2
## Spline runtime for painting / car poses. Required for playable races.
var spline_bind: SplineTrackBind = null


func display_name() -> String:
	if spline_bind != null:
		return spline_bind.display_name()
	if id.is_empty():
		return "Tracé"
	return id.get_file().get_basename()


func spot_count(space: int) -> int:
	if space < 0 or space >= spots.size():
		return 1
	return spots[space]


func space_of_progress(progress: int) -> int:
	if space_count <= 0:
		return 0
	return posmod(progress, space_count)


func lap_of_progress(progress: int) -> int:
	if space_count <= 0:
		return 0
	return int(progress / float(space_count))


func finish_progress() -> int:
	return laps * space_count


func corner_after(space: int) -> HeatCorner:
	for corner in corners:
		if corner.from_space == space:
			return corner
	return null


## Spaces until standing on the next corner's approach space (`from_space`).
## Returns -1 if the track has no corners.
func distance_to_next_corner(progress: int) -> int:
	if corners.is_empty() or space_count <= 0:
		return -1
	var space := space_of_progress(progress)
	var best := space_count
	for corner in corners:
		var d := posmod(corner.from_space - space, space_count)
		if d < best:
			best = d
	return best


## Remaining spaces to finish line (`finish_progress()`). Negative if already past.
func distance_to_finish(progress: int) -> int:
	return finish_progress() - progress


func next_corner(progress: int) -> HeatCorner:
	if corners.is_empty() or space_count <= 0:
		return null
	var space := space_of_progress(progress)
	var best := space_count
	var found: HeatCorner = null
	for corner in corners:
		var d := posmod(corner.from_space - space, space_count)
		if d < best:
			best = d
			found = corner
	return found


func next_landmark(progress: int) -> Dictionary:
	var to_finish := distance_to_finish(progress)
	if to_finish < 0:
		return {"kind": "none", "distance": -1}
	var to_corner := distance_to_next_corner(progress)
	if to_corner < 0 or to_corner >= to_finish:
		return {"kind": "finish", "distance": to_finish}
	return {"kind": "corner", "distance": to_corner}


## Built-in (`res://tracks`) and user-saved (`user://tracks`) spline tracks.
static func catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in SplineTrackFile.list_entries():
		if not entry is Dictionary:
			continue
		var track_name := str(entry.get("name", ""))
		var builtin := bool(entry.get("builtin", false))
		out.append({
			"id": str(entry.get("path", "")),
			"name": track_name,
			"builtin": builtin,
		})
	return out


static func from_id(track_id: String, p_laps: int = 1) -> HeatTrack:
	if track_id.is_empty():
		return null
	var bind := SplineTrackBind.from_path(track_id)
	if bind == null:
		push_warning("HeatTrack: cannot load spline track '%s'" % track_id)
		return null
	return bind.to_heat_track(p_laps)


static func from_document(data: Dictionary, p_laps: int = 1, path: String = "") -> HeatTrack:
	var bind := SplineTrackBind.from_document(data, path)
	if bind == null:
		return null
	return bind.to_heat_track(p_laps)


static func default_track(p_laps: int = 1) -> HeatTrack:
	var entries := catalog()
	if entries.is_empty():
		return null
	return from_id(str(entries[0].get("id", "")), p_laps)


## Abstract oval for unit tests only (no spline bind / board painting).
static func for_tests(p_laps: int = 1) -> HeatTrack:
	var track := HeatTrack.new()
	track.id = "test_oval"
	track.space_count = 24
	track.laps = p_laps
	track.start_heat = 6
	track.start_stress = 3
	track.start_behind_finish_line = true
	track.start_max_per_space = 2
	track.spots = []
	for i in track.space_count:
		if i == 8 or i == 15:
			track.spots.append(1)
		else:
			track.spots.append(2)
	track.corners = [
		HeatCorner.new(5, 4, "test_c1"),
		HeatCorner.new(11, 5, "test_c2"),
		HeatCorner.new(17, 3, "test_c3"),
		HeatCorner.new(21, 6, "test_c4"),
	]
	return track
