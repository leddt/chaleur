extends Node2D


func _draw() -> void:
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 28, Color(1, 1, 1, 0.9), 1.8, true)
