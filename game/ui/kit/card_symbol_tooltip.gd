class_name CardSymbolTooltip
extends MarginContainer

## Tooltip body only. Godot already wraps `_make_custom_tooltip` in TooltipPanel;
## a PanelContainer here drew a second chrome (the inset top edge).


static func make_control(bbcode: String) -> Control:
	var panel := CardSymbolTooltip.new()
	panel._setup(bbcode)
	return panel


var _rtl: RichTextLabel


func _setup(bbcode: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = bbcode
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.custom_minimum_size = Vector2(280, 0)
	rtl.add_theme_constant_override("line_separation", 4)
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rtl = rtl
	add_child(rtl)


func _ready() -> void:
	resized.connect(_keep_in_viewport)
	visibility_changed.connect(_keep_in_viewport)
	call_deferred("_keep_in_viewport")
	# Popup places the tooltip after _ready; clamp again once it has a size.
	get_tree().create_timer(0.0).timeout.connect(_keep_in_viewport)


func _keep_in_viewport() -> void:
	var vp := get_viewport()
	if vp == null or not is_inside_tree():
		return
	var vr := vp.get_visible_rect()
	var pad := 8.0
	var max_h := maxf(64.0, vr.size.y - pad * 2.0)
	if _rtl != null:
		var content_h := float(_rtl.get_content_height())
		if content_h <= 0.0:
			content_h = _rtl.get_minimum_size().y
		if content_h > max_h:
			_rtl.scroll_active = true
			_rtl.custom_minimum_size.y = max_h
			_rtl.fit_content = false
		else:
			_rtl.scroll_active = false
			_rtl.fit_content = true
			_rtl.custom_minimum_size.y = 0
	var host := _tooltip_host()
	if host == null:
		return
	var rect := host.get_global_rect()
	var pos := rect.position
	if pos.x + rect.size.x > vr.end.x - pad:
		pos.x = vr.end.x - pad - rect.size.x
	if pos.x < vr.position.x + pad:
		pos.x = vr.position.x + pad
	if pos.y + rect.size.y > vr.end.y - pad:
		pos.y = vr.end.y - pad - rect.size.y
	if pos.y < vr.position.y + pad:
		pos.y = vr.position.y + pad
	host.global_position = pos


func _tooltip_host() -> Control:
	var node: Node = self
	var last: Control = self
	while node.get_parent() != null:
		node = node.get_parent()
		if node is Control:
			last = node
		if node is Popup or node is Window:
			return last
		if str(node.name) == "TooltipPanel":
			return last
	return last
