extends Node

## Instant tooltips that stay next to the cursor without covering it.

const OFFSET := Vector2(16, 18)
const PAD := 8.0

var _tip: Window


func _process(_delta: float) -> void:
	if _tip == null or not is_instance_valid(_tip) or not _tip.visible:
		_tip = _find_tooltip(get_tree().root)
	if _tip == null:
		return
	place_window(_tip, get_tree().root)


static func place_window(w: Window, viewport: Viewport) -> void:
	if w == null or not w.visible or viewport == null:
		return
	var sz := Vector2(w.size)
	if sz.x < 2.0 or sz.y < 2.0:
		sz = Vector2(w.get_contents_minimum_size())
	var mouse := viewport.get_mouse_position()
	var vr := viewport.get_visible_rect()
	w.position = Vector2i(_clamp_to_cursor(mouse, sz, vr).round())


static func _clamp_to_cursor(mouse: Vector2, sz: Vector2, vr: Rect2) -> Vector2:
	var pos := mouse + OFFSET
	if pos.x + sz.x > vr.end.x - PAD:
		pos.x = mouse.x - OFFSET.x - sz.x
	if pos.y + sz.y > vr.end.y - PAD:
		pos.y = mouse.y - OFFSET.y - sz.y
	var min_x := vr.position.x + PAD
	var min_y := vr.position.y + PAD
	var max_x := vr.end.x - PAD - sz.x
	var max_y := vr.end.y - PAD - sz.y
	if max_x >= min_x:
		pos.x = clampf(pos.x, min_x, max_x)
	else:
		pos.x = min_x
	if max_y >= min_y:
		pos.y = clampf(pos.y, min_y, max_y)
	else:
		pos.y = min_y
	return pos


func _find_tooltip(n: Node) -> Window:
	if n is Window:
		var w := n as Window
		if w.visible and w != get_tree().root and _is_tooltip_window(w):
			return w
	for i in n.get_child_count(true):
		var found := _find_tooltip(n.get_child(i, true))
		if found != null:
			return found
	return null


func _is_tooltip_window(w: Window) -> bool:
	if w.theme_type_variation == &"TooltipPanel":
		return true
	for i in w.get_child_count(true):
		var child := w.get_child(i, true)
		if child is Control:
			var c := child as Control
			if c.theme_type_variation == &"TooltipPanel" or str(c.name) == "TooltipPanel":
				return true
		if child is CardSymbolTooltip:
			return true
	return false
