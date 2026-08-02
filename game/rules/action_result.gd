class_name ActionResult
extends RefCounted

var ok: bool = true
var error: String = ""
var log_lines: Array[String] = []


static func success(lines: Array[String] = []) -> ActionResult:
	var r := ActionResult.new()
	r.ok = true
	r.log_lines = lines
	return r


static func fail(message: String) -> ActionResult:
	var r := ActionResult.new()
	r.ok = false
	r.error = message
	return r


func with_log(line: String) -> ActionResult:
	log_lines.append(line)
	return self
