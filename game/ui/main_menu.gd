extends Control


func _ready() -> void:
	%TrackEditorButton.visible = OS.is_debug_build()
	%SplineTrackEditorButton.visible = OS.is_debug_build()


func _on_play_pressed() -> void:
	Game.start_local_race()
	get_tree().change_scene_to_file("res://view/board.tscn")


func _on_lobby_pressed() -> void:
	Game.set_mode(Game.Mode.LOCAL)
	get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _on_track_editor_pressed() -> void:
	if not OS.is_debug_build():
		return
	get_tree().change_scene_to_file("res://view/track_editor.tscn")


func _on_spline_track_editor_pressed() -> void:
	if not OS.is_debug_build():
		return
	get_tree().change_scene_to_file("res://ui/spline_track_picker.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
