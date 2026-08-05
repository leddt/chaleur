class_name PlayerPalette
extends RefCounted

## Shared seat colors for HUD, cars, and legends.
##
## The colors themselves live in Palette.team() so that cars, HUD chips and cards
## cannot drift apart. This stays as the seat-facing name for that lookup.


static func color_for(player_id: int) -> Color:
	return Palette.team(player_id)
