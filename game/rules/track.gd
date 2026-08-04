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


## HUD helper: prefer finish distance once the next corner would wrap past the finish
## (last sector of the race). Returns {"kind": "corner"|"finish"|"none", "distance": int}.
func next_landmark(progress: int) -> Dictionary:
	var to_finish := distance_to_finish(progress)
	if to_finish < 0:
		return {"kind": "none", "distance": -1}
	var to_corner := distance_to_next_corner(progress)
	if to_corner < 0 or to_corner >= to_finish:
		return {"kind": "finish", "distance": to_finish}
	return {"kind": "corner", "distance": to_corner}


## Hand-drawn track1.jpg layout (see res://data/track1_layout.json).
static func track1(p_laps: int = 1) -> HeatTrack:
	var layout := TrackLayout.for_track_id("track1")
	if layout == null or layout.space_count() <= 0:
		push_warning("track1 layout missing — falling back to usa_simplified")
		return usa_simplified(p_laps)
	return layout.to_heat_track(p_laps)


## Default playable track.
static func default_track(p_laps: int = 1) -> HeatTrack:
	return track1(p_laps)


## Build a track by id for lobby / net race setup.
static func from_id(track_id: String, p_laps: int = 1) -> HeatTrack:
	match track_id:
		"track1":
			return track1(p_laps)
		"usa_simplified":
			return usa_simplified(p_laps)
		_:
			push_warning("Unknown track id '%s' — using default" % track_id)
			return default_track(p_laps)


## Lobby catalog: id, display name, preview texture path.
static func catalog() -> Array[Dictionary]:
	return [
		{
			"id": "track1",
			"name": "Piste 1",
			"preview": "res://assets/track1.jpg",
		},
	]


## Build a simplified USA-like track for tests (abstract oval).
static func usa_simplified(p_laps: int = 1) -> HeatTrack:
	var track := HeatTrack.new()
	track.id = "usa_simplified"
	track.space_count = 24
	track.laps = p_laps
	track.start_heat = 6
	track.start_stress = 3
	track.spots = []
	for i in track.space_count:
		if i == 0:
			track.spots.append(6) # starting grid
		elif i == 8 or i == 15:
			track.spots.append(1) # chokepoints for block tests
		else:
			track.spots.append(2)
	track.corners = [
		HeatCorner.new(5, 4, "usa_c1"),
		HeatCorner.new(11, 5, "usa_c2"),
		HeatCorner.new(17, 3, "usa_c3"),
		HeatCorner.new(21, 6, "usa_c4"),
	]
	return track
