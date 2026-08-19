class_name CardSymbolTooltip
extends RefCounted

## Builds a styled RichTextLabel for symbol tooltips.


static func make_control(bbcode: String) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = bbcode
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(280, 0)
	rtl.add_theme_constant_override("line_separation", 4)
	return rtl
