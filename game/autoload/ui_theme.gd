extends Node

## Applies the Heat-inspired UI kit theme to the whole game.
##
## Autoloads run before the main scene is instantiated, so setting the theme on
## the root here covers every screen without touching individual scenes.
##
## Set ENABLED to false to fall back to Godot's default look.

const ENABLED := true


func _ready() -> void:
	if not ENABLED:
		return
	get_tree().root.theme = ThemeBuilder.build()
