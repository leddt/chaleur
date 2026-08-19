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
	resized.connect(_fit_height)
	visibility_changed.connect(_fit_height)
	call_deferred("_fit_height")


func _fit_height() -> void:
	var vp := get_viewport()
	if vp == null or not is_inside_tree() or _rtl == null:
		return
	var vr := vp.get_visible_rect()
	var pad := 8.0
	var max_h := maxf(64.0, vr.size.y - pad * 2.0)
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
