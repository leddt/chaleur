class_name RichTooltipButton
extends Button

## Button with a BBCode custom tooltip (title + description).

var tooltip_bbcode: String = ""


func _make_custom_tooltip(_tooltip: String) -> Object:
	return CardSymbolTooltip.make_control(tooltip_bbcode)
