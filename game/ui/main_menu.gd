extends Control


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/local_race_setup.tscn")


func _on_lobby_pressed() -> void:
	Game.set_mode(Game.Mode.LOCAL)
	get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _on_spline_track_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/spline_track_picker.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
