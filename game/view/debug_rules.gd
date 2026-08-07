extends Control

var _engine: HeatGameEngine

@onready var _log: TextEdit = %Log


func _ready() -> void:
	$Margin/VBox/Buttons/SetupButton.pressed.connect(_on_setup)
	$Margin/VBox/Buttons/DumpButton.pressed.connect(_on_dump)
	$Margin/VBox/Buttons/BackButton.pressed.connect(_on_back)


func _on_setup() -> void:
	_engine = HeatGameEngine.new()
	_engine.setup(["Alice", "Bob"], HeatTrack.for_tests(1), 42)
	_append(_engine.dump_state())
	_append("--- log ---")
	for line in _engine.event_log:
		_append(line)


func _on_dump() -> void:
	if _engine == null:
		_append("No engine. Click Setup 2P.")
		return
	_append(_engine.dump_state())


func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _append(text: String) -> void:
	_log.text += text + "\n"
