class_name SplineTrackFile
extends RefCounted

## JSON documents for spline tracks under user://tracks/ (player) and
## res://tracks/ (built-in shipping tracks; writable in debug builds).

const VERSION := 1
const USER_DIR := "user://tracks"
const BUILTIN_DIR := "res://tracks"
const DEFAULT_LAPS := 2
const MIN_LAPS := 1
const MAX_LAPS := 6

## Path to open in the spline editor next scene change. Empty = new track.
static var editor_pending_path: String = ""


static func can_write_builtin() -> bool:
	return OS.is_debug_build()


static func is_builtin_path(path: String) -> bool:
	return path.begins_with(BUILTIN_DIR + "/") or path == BUILTIN_DIR


static func is_user_path(path: String) -> bool:
	return path.begins_with(USER_DIR + "/") or path == USER_DIR


static func ensure_dir(dir_path: String) -> Error:
	if DirAccess.dir_exists_absolute(dir_path):
		return OK
	if dir_path == BUILTIN_DIR and not can_write_builtin():
		return ERR_UNAUTHORIZED
	return DirAccess.make_dir_recursive_absolute(dir_path)


static func ensure_user_dir() -> Error:
	return ensure_dir(USER_DIR)


static func ensure_builtin_dir() -> Error:
	return ensure_dir(BUILTIN_DIR)


static func slugify(track_name: String) -> String:
	var raw := track_name.strip_edges().to_lower()
	var out := ""
	for i in raw.length():
		var ch := raw[i]
		var code := ch.unicode_at(0)
		var is_alnum := (
			(code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
		)
		if is_alnum:
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			if out.is_empty() or out[out.length() - 1] != "_":
				out += "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	if out.is_empty():
		out = "trace_%d" % int(Time.get_unix_time_from_system())
	return out


static func path_for_name(track_name: String, builtin: bool = false) -> String:
	var root := BUILTIN_DIR if builtin else USER_DIR
	return "%s/%s.json" % [root, slugify(track_name)]


static func save_document(path: String, data: Dictionary) -> Error:
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	if is_builtin_path(path) and not can_write_builtin():
		push_error("SplineTrackFile: built-in writes require a debug build (%s)" % path)
		return ERR_UNAUTHORIZED
	var dir_err := ensure_dir(path.get_base_dir())
	if dir_err != OK:
		push_error("SplineTrackFile: cannot create %s (%s)" % [path.get_base_dir(), dir_err])
		return dir_err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("SplineTrackFile: cannot write %s (%s)" % [path, err])
		return err
	file.store_string(JSON.stringify(data, "\t"))
	return OK


static func load_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SplineTrackFile: cannot read %s (%s)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("SplineTrackFile: invalid JSON in %s" % path)
	return {}


static func default_laps_from_document(data: Dictionary) -> int:
	return clampi(int(data.get("default_laps", DEFAULT_LAPS)), MIN_LAPS, MAX_LAPS)


static func default_laps_for_path(path: String) -> int:
	return default_laps_from_document(load_document(path))


static func delete_document(path: String) -> Error:
	if path.is_empty() or not FileAccess.file_exists(path):
		return OK
	if is_builtin_path(path) and not can_write_builtin():
		push_error("SplineTrackFile: cannot delete built-in %s outside debug" % path)
		return ERR_UNAUTHORIZED
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_error("SplineTrackFile: cannot delete %s (%s)" % [path, err])
	return err


## True for documents written by this editor (ignores other JSON leftover in dirs).
static func is_valid_document(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	if int(data.get("version", 0)) < 1:
		return false
	var spline: Variant = data.get("spline", null)
	if not spline is Dictionary:
		return false
	var points: Variant = spline.get("points", null)
	return points is Array and not points.is_empty()


## [{path, name, modified, builtin}] sorted by name (built-in before user on tie).
static func list_entries(include_user: bool = true, include_builtin: bool = true) -> Array:
	var entries: Array = []
	if include_builtin:
		_collect_dir_entries(BUILTIN_DIR, true, entries)
	if include_user:
		ensure_user_dir()
		_collect_dir_entries(USER_DIR, false, entries)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var an := str(a.get("name", "")).to_lower()
		var bn := str(b.get("name", "")).to_lower()
		if an == bn:
			return bool(a.get("builtin", false)) and not bool(b.get("builtin", false))
		return an < bn
	)
	return entries


static func _collect_dir_entries(dir_path: String, builtin: bool, out: Array) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var path := "%s/%s" % [dir_path, file_name]
			var data := load_document(path)
			if not is_valid_document(data):
				file_name = dir.get_next()
				continue
			var display_name := str(data.get("name", "")).strip_edges()
			if display_name.is_empty():
				display_name = file_name.get_basename()
			out.append({
				"path": path,
				"name": display_name,
				"modified": int(FileAccess.get_modified_time(path)),
				"builtin": builtin,
				"default_laps": default_laps_from_document(data),
			})
		file_name = dir.get_next()
	dir.list_dir_end()
