extends Node

## Presentation-layer sound effects (not part of the rules engine).

const _STREAMS := {
	"engine": preload("res://assets/sfx/engine.mp3"),
	"fail": preload("res://assets/sfx/fail.mp3"),
	"finish_line": preload("res://assets/sfx/finish-line.mp3"),
	"podium": preload("res://assets/sfx/podium.mp3"),
	"spinout": preload("res://assets/sfx/spinout.mp3"),
	"button": preload("res://assets/sfx/button.mp3"),
	"boost": preload("res://assets/sfx/boost.mp3"),
	"slipstream": preload("res://assets/sfx/slipstream.mp3"),
	"lever": preload("res://assets/sfx/lever.mp3"),
}

var _players: Dictionary = {} # id -> AudioStreamPlayer


func _ready() -> void:
	for id in _STREAMS.keys():
		var player := AudioStreamPlayer.new()
		player.name = "Sfx_%s" % id
		player.stream = _STREAMS[id]
		add_child(player)
		_players[id] = player
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_hook_existing_buttons")


func play(id: String) -> void:
	var player: AudioStreamPlayer = _players.get(id) as AudioStreamPlayer
	if player == null or player.stream == null:
		return
	player.play()


## Map authoritative event_log lines to SFX (used when the UI journal advances).
func play_for_log_line(line: String) -> void:
	if "reveals speed" in line and "moves" in line:
		play("engine")
	elif "boosts for" in line or "uses adrenaline" in line:
		play("boost")
	elif "slipstreams" in line:
		play("slipstream")
	elif "All gears locked" in line:
		play("lever")
	elif "cluttered — no move" in line:
		play("fail")
	elif "crossed the finish line" in line:
		play("finish_line")
	elif "spins out at" in line:
		play("spinout")


func _hook_existing_buttons() -> void:
	_hook_tree(get_tree().root)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node as BaseButton)


func _hook_tree(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node as BaseButton)
	for child in node.get_children():
		_hook_tree(child)


func _hook_button(button: BaseButton) -> void:
	if button.get_meta("_sfx_button_hooked", false):
		return
	button.set_meta("_sfx_button_hooked", true)
	button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play("button")
