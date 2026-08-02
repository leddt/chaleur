extends Control

enum Step { CHOICE, HOST_SETUP, JOIN_SETUP, SESSION }

const SETTINGS_PATH := "user://chaleur_settings.cfg"

@onready var _status: Label = %StatusLabel
@onready var _name: LineEdit = %NameEdit
@onready var _host_port: LineEdit = %HostPortEdit
@onready var _address: LineEdit = %AddressEdit
@onready var _join_port: LineEdit = %JoinPortEdit
@onready var _players: ItemList = %PlayersList
@onready var _upnp: Label = %UpnpLabel
@onready var _choice_panel: VBoxContainer = %ChoicePanel
@onready var _host_panel: VBoxContainer = %HostPanel
@onready var _join_panel: VBoxContainer = %JoinPanel
@onready var _session_panel: VBoxContainer = %SessionPanel
@onready var _race_panel: VBoxContainer = %RacePanel
@onready var _track_option: OptionButton = %TrackOption
@onready var _track_preview: TextureRect = %TrackPreview
@onready var _laps_spin: SpinBox = %LapsSpin
@onready var _laps_label: Label = %LapsLabel
@onready var _race_summary: Label = %RaceSummary
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton
@onready var _hint: Label = %Hint

var _step: Step = Step.CHOICE
var _track_ids: Array[String] = []
var _syncing_race_ui: bool = false


func _ready() -> void:
	_setup_track_options()
	_load_settings()
	%HostButton.pressed.connect(_on_choose_host)
	%JoinButton.pressed.connect(_on_choose_join)
	%HostConfirmButton.pressed.connect(_on_host_confirm)
	%HostCancelButton.pressed.connect(_on_setup_cancel)
	%JoinConfirmButton.pressed.connect(_on_join_confirm)
	%JoinCancelButton.pressed.connect(_on_setup_cancel)
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	%LeaveButton.pressed.connect(_on_leave_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_name.text_changed.connect(_on_name_changed)
	_host_port.text_changed.connect(_on_ports_changed)
	_join_port.text_changed.connect(_on_ports_changed)
	_address.text_changed.connect(_on_address_changed)
	_track_option.item_selected.connect(_on_track_selected)
	_laps_spin.value_changed.connect(_on_laps_changed)

	Net.host_started.connect(_on_host_started)
	Net.join_started.connect(_on_join_started)
	Net.left.connect(_on_left)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.race_started.connect(_on_race_started)
	Net.net_error.connect(_on_net_error)

	if Game.mode == Game.Mode.HOST or Game.mode == Game.Mode.CLIENT:
		_set_step(Step.SESSION)
	else:
		_set_step(Step.CHOICE)
	_refresh_status()
	_refresh_players()
	_refresh_ready_button()
	_refresh_track_preview()


func _setup_track_options() -> void:
	_track_option.clear()
	_track_ids.clear()
	for entry in HeatTrack.catalog():
		var track_id := str(entry.get("id", ""))
		var track_name := str(entry.get("name", track_id))
		_track_ids.append(track_id)
		_track_option.add_item(track_name)
		_track_option.set_item_metadata(_track_option.item_count - 1, track_id)
	if _track_option.item_count > 0:
		_track_option.select(0)


func _set_step(step: Step) -> void:
	_step = step
	_choice_panel.visible = step == Step.CHOICE
	_host_panel.visible = step == Step.HOST_SETUP
	_join_panel.visible = step == Step.JOIN_SETUP
	_session_panel.visible = step == Step.SESSION
	_back_button.visible = step != Step.SESSION
	_hint.visible = step != Step.SESSION
	if step == Step.SESSION:
		var is_host := Game.mode == Game.Mode.HOST
		_start_button.visible = is_host
		_race_panel.visible = true
		_apply_race_controls_editable(is_host)
		_refresh_ready_button()
		_refresh_race_display()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var saved_name := str(cfg.get_value("player", "name", "")).strip_edges()
	if not saved_name.is_empty():
		_name.text = saved_name
	var saved_port := str(cfg.get_value("net", "port", Net.DEFAULT_PORT))
	_host_port.text = saved_port
	_join_port.text = saved_port
	var saved_address := str(cfg.get_value("net", "address", "127.0.0.1")).strip_edges()
	if not saved_address.is_empty():
		_address.text = saved_address
	var saved_track := str(cfg.get_value("race", "track_id", "track1"))
	_select_track_id(saved_track)
	var saved_laps := int(cfg.get_value("race", "laps", 1))
	_laps_spin.value = clampf(float(saved_laps), _laps_spin.min_value, _laps_spin.max_value)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # ignore missing file
	var name_text := _name.text.strip_edges()
	cfg.set_value("player", "name", name_text)
	var port_text := _host_port.text.strip_edges()
	if port_text.is_empty():
		port_text = _join_port.text.strip_edges()
	if port_text.is_empty():
		port_text = str(Net.DEFAULT_PORT)
	cfg.set_value("net", "port", port_text)
	cfg.set_value("net", "address", _address.text.strip_edges())
	cfg.set_value("race", "track_id", _selected_track_id())
	cfg.set_value("race", "laps", int(_laps_spin.value))
	cfg.save(SETTINGS_PATH)


func _select_track_id(track_id: String) -> void:
	for i in _track_ids.size():
		if _track_ids[i] == track_id:
			_track_option.select(i)
			return
	if _track_option.item_count > 0:
		_track_option.select(0)


func _selected_track_id() -> String:
	var idx := _track_option.selected
	if idx < 0 or idx >= _track_ids.size():
		return "track1"
	return _track_ids[idx]


func _apply_race_controls_editable(is_host: bool) -> void:
	_track_option.visible = is_host
	_laps_spin.visible = is_host
	_laps_label.visible = is_host
	_race_summary.visible = not is_host
	_track_option.disabled = not is_host
	_laps_spin.editable = is_host


func _track_display_name(track_id: String) -> String:
	for entry in HeatTrack.catalog():
		if str(entry.get("id", "")) == track_id:
			return str(entry.get("name", track_id))
	return track_id


func _laps_phrase(laps: int) -> String:
	if laps <= 1:
		return "1 tour"
	return "%d tours" % laps


func _refresh_race_display() -> void:
	var track_id := Net.race_track_id if Game.mode != Game.Mode.NONE else _selected_track_id()
	var laps := Net.race_laps if Game.mode != Game.Mode.NONE else int(_laps_spin.value)
	if Game.mode == Game.Mode.HOST:
		track_id = _selected_track_id()
		laps = int(_laps_spin.value)
	_syncing_race_ui = true
	_select_track_id(track_id)
	_laps_spin.value = clampf(float(laps), _laps_spin.min_value, _laps_spin.max_value)
	_syncing_race_ui = false
	_refresh_track_preview_for(track_id)
	_race_summary.text = "%s — %s" % [_track_display_name(track_id), _laps_phrase(laps)]


func _refresh_track_preview_for(track_id: String) -> void:
	var preview_path := ""
	for entry in HeatTrack.catalog():
		if str(entry.get("id", "")) == track_id:
			preview_path = str(entry.get("preview", ""))
			break
	if preview_path.is_empty() or not ResourceLoader.exists(preview_path):
		_track_preview.texture = null
		return
	_track_preview.texture = load(preview_path) as Texture2D


func _publish_race_settings() -> void:
	if Game.mode != Game.Mode.HOST:
		return
	Net.set_race_settings(_selected_track_id(), int(_laps_spin.value))


func _refresh_track_preview() -> void:
	_refresh_track_preview_for(_selected_track_id())


func _on_track_selected(_index: int) -> void:
	if _syncing_race_ui:
		return
	_refresh_track_preview()
	_save_settings()
	_publish_race_settings()
	_refresh_race_display()


func _on_laps_changed(_value: float) -> void:
	if _syncing_race_ui:
		return
	_save_settings()
	_publish_race_settings()
	_refresh_race_display()


func _on_name_changed(_new_text: String) -> void:
	_save_settings()


func _on_ports_changed(_new_text: String) -> void:
	# Keep host/join port fields mirrored for convenience.
	if _step == Step.HOST_SETUP:
		_join_port.text = _host_port.text
	elif _step == Step.JOIN_SETUP:
		_host_port.text = _join_port.text
	_save_settings()


func _on_address_changed(_new_text: String) -> void:
	_save_settings()


func _refresh_status() -> void:
	match Game.mode:
		Game.Mode.NONE:
			match _step:
				Step.HOST_SETUP:
					_status.text = "Configurer l'hébergement"
				Step.JOIN_SETUP:
					_status.text = "Configurer la connexion"
				_:
					_status.text = "Hors ligne — héberge ou rejoins une partie"
		Game.Mode.HOST:
			_status.text = Net.host_share_text()
			_upnp.text = Net.upnp_status if not Net.upnp_status.is_empty() else "UPnP en cours…"
		Game.Mode.CLIENT:
			_status.text = "En lobby — en attente que l'hôte démarre"
			_upnp.text = ""
		_:
			_status.text = "Mode: %s" % str(Game.mode)


func _refresh_players() -> void:
	_players.clear()
	var items: Array = []
	for peer_id in Net.lobby:
		items.append([int(Net.lobby[peer_id].get("seat", 0)), peer_id])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for item in items:
		var peer_id: int = item[1]
		var info: Dictionary = Net.lobby[peer_id]
		var ready_txt := "PRÊT" if bool(info.get("ready", false)) else "pas prêt"
		var you := " ★" if peer_id == Net.my_peer_id() else ""
		_players.add_item("%s — %s — siège %d%s" % [
			str(info.get("name", "?")),
			ready_txt,
			int(info.get("seat", -1)),
			you,
		])
	if Game.mode == Game.Mode.HOST and not Net.upnp_status.is_empty():
		_upnp.text = Net.upnp_status
	_refresh_ready_button()


func _refresh_ready_button() -> void:
	var is_ready := _local_ready()
	_ready_button.text = "Pas prêt" if is_ready else "Prêt"


func _local_ready() -> bool:
	var entry: Variant = Net.lobby.get(Net.my_peer_id(), null)
	if entry == null:
		return false
	return bool(entry.get("ready", false))


func _port_from(edit: LineEdit) -> int:
	var p := edit.text.strip_edges()
	if p.is_empty():
		return Net.DEFAULT_PORT
	return int(p)


func _apply_display_name(fallback: String) -> void:
	Net.local_display_name = _name.text.strip_edges()
	if Net.local_display_name.is_empty():
		Net.local_display_name = fallback
	_save_settings()


func _on_choose_host() -> void:
	_set_step(Step.HOST_SETUP)
	_refresh_status()


func _on_choose_join() -> void:
	_set_step(Step.JOIN_SETUP)
	_refresh_status()


func _on_setup_cancel() -> void:
	_set_step(Step.CHOICE)
	_refresh_status()


func _on_host_confirm() -> void:
	_apply_display_name("Host")
	Net.race_track_id = _selected_track_id()
	Net.race_laps = int(_laps_spin.value)
	var err := Net.host(_port_from(_host_port))
	if err != OK:
		_status.text = "Échec host — port peut-être déjà utilisé"
		return
	_save_settings()


func _on_join_confirm() -> void:
	_apply_display_name("Client")
	var address := _address.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var port := _port_from(_join_port)
	var err := Net.join(address, port)
	if err != OK:
		_status.text = "Échec join"
		return
	_status.text = "Connexion à %s:%d…" % [address, port]
	_save_settings()


func _on_ready_pressed() -> void:
	Net.set_ready(not _local_ready())
	_refresh_ready_button()


func _on_start_pressed() -> void:
	_save_settings()
	Net.start_race(int(_laps_spin.value), _selected_track_id())


func _on_leave_pressed() -> void:
	Net.leave()
	_set_step(Step.CHOICE)
	_refresh_status()
	_refresh_players()


func _on_back_pressed() -> void:
	if _step == Step.HOST_SETUP or _step == Step.JOIN_SETUP:
		_on_setup_cancel()
		return
	Net.leave()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_host_started(_port: int) -> void:
	_set_step(Step.SESSION)
	_refresh_status()
	_refresh_players()


func _on_join_started(_address: String, _port: int) -> void:
	_set_step(Step.SESSION)
	_refresh_status()


func _on_left() -> void:
	if _step == Step.SESSION:
		_set_step(Step.CHOICE)
	_refresh_status()
	_refresh_players()


func _on_lobby_changed() -> void:
	_refresh_players()
	_refresh_status()
	if _step == Step.SESSION:
		_refresh_race_display()


func _on_race_started() -> void:
	get_tree().change_scene_to_file("res://view/board.tscn")


func _on_net_error(message: String) -> void:
	_status.text = message
