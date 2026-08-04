class_name PlayerPalette
extends RefCounted

## Shared seat colors for HUD, cars, and legends.

const COLORS: Array[Color] = [
	Color(0.9, 0.25, 0.25),
	Color(0.25, 0.55, 0.95),
	Color(0.25, 0.8, 0.4),
	Color(0.95, 0.8, 0.2),
	Color(0.95, 0.55, 0.15),
	Color(0.7, 0.35, 0.9),
]


static func color_for(player_id: int) -> Color:
	return COLORS[player_id % COLORS.size()]
