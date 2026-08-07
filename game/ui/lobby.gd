extends Control

enum Step { CHOICE, HOST_SETUP, JOIN_SETUP, SESSION }

const SETTINGS_PATH := "user://chaleur_settings.cfg"

@onready var _status: Label = %StatusLabel
@onready var _name: LineEdit = %NameEdit
@onready var _noray_host: LineEdit = %NorayHostEdit
@onready var _host_port: LineEdit = %HostPortEdit
@onready var _host_internet: Button = %HostInternetButton
@onready var _host_direct: Button = %HostDirectButton
@onready var _host_hint: Label = %HostHint
@onready var _game_id: LineEdit = %GameIdEdit
@onready var _address: LineEdit = %AddressEdit
@onready var _join_port: LineEdit = %JoinPortEdit
@onready var _join_internet: Button = %JoinInternetButton
@onready var _join_direct: Button = %JoinDirectButton
@onready var _join_hint: Label = %JoinHint
@onready var _players: ItemList = %PlayersList
@onready var _upnp: Label = %UpnpLabel
@onready var _share_row: HBoxContainer = %ShareRow
@onready var _share_code: LineEdit = %ShareCodeEdit
@onready var _copy_share: Button = %CopyShareButton
@onready var _choice_panel: VBoxContainer = %ChoicePanel
@onready var _host_panel: VBoxContainer = %HostPanel
@onready var _join_panel: VBoxContainer = %JoinPanel
@onready var _session_panel: VBoxContainer = %SessionPanel
@onready var _race_panel: VBoxContainer = %RacePanel
@onready var _track_option: OptionButton = %TrackOption
@onready var _track_preview: SplineTrackPreview = %TrackPreview
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
var _busy: bool = false
var _host_mode_group: ButtonGroup
var _join_mode_group: ButtonGroup


func _ready() -> void:
	_setup_mode_toggles()
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
	_copy_share.pressed.connect(_on_copy_share)
	_name.text_changed.connect(_on_name_changed)
	_noray_host.text_changed.connect(_on_noray_host_changed)
	_host_port.text_changed.connect(_on_ports_changed)
	_join_port.text_changed.connect(_on_ports_changed)
	_address.text_changed.connect(_on_address_changed)
	_game_id.text_changed.connect(_on_game_id_changed)
	_host_mode_group.pressed.connect(_on_host_mode_changed)
	_join_mode_group.pressed.connect(_on_join_mode_changed)
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


func _setup_mode_toggles() -> void:
	_host_mode_group = ButtonGroup.new()
	_host_internet.button_group = _host_mode_group
	_host_direct.button_group = _host_mode_group
	_join_mode_group = ButtonGroup.new()
	_join_internet.button_group = _join_mode_group
	_join_direct.button_group = _join_mode_group


func _setup_track_options() -> void:
	_track_option.clear()
	_track_ids.clear()
	for entry in HeatTrack.catalog():
		var track_id := str(entry.get("id", ""))
		var track_name := str(entry.get("name", track_id))
		if bool(entry.get("builtin", false)):
			track_name = "%s · intégrée" % track_name
		_track_ids.append(track_id)
		_track_option.add_item(track_name)
		_track_option.set_item_metadata(_track_option.item_count - 1, track_id)
	if _track_option.item_count > 0:
		_track_option.select(0)
	_refresh_track_preview()


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
		_refresh_share_row()
	elif step == Step.HOST_SETUP:
		_apply_host_mode_visibility()
	elif step == Step.JOIN_SETUP:
		_game_id.text = ""
		_apply_join_mode_visibility()
	else:
		_share_row.visible = false


func _host_internet_mode() -> bool:
	return _host_internet.button_pressed


func _join_internet_mode() -> bool:
	return _join_internet.button_pressed


func _apply_host_mode_visibility() -> void:
	var internet := _host_internet_mode()
	_noray_host.visible = internet
	_host_port.visible = not internet
	_host_hint.text = (
		"Adresse du serveur relay"
		if internet
		else "Port UDP à ouvrir / utiliser (LAN ou UPnP)"
	)


func _apply_join_mode_visibility() -> void:
	var internet := _join_internet_mode()
	_game_id.visible = internet
	_address.visible = not internet
	_join_port.visible = not internet
	_join_hint.text = (
		"Colle le Game ID (serveur:code)"
		if internet
		else "Adresse et port de l'hôte"
	)


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
	var saved_noray := str(cfg.get_value("net", "noray_host", "")).strip_edges()
	_noray_host.text = saved_noray
	_game_id.text = ""
	var prefer_direct := bool(cfg.get_value("net", "lan_direct", false))
	_host_internet.button_pressed = not prefer_direct
	_host_direct.button_pressed = prefer_direct
	_join_internet.button_pressed = not prefer_direct
	_join_direct.button_pressed = prefer_direct
	var saved_track := str(cfg.get_value("race", "track_id", ""))
	_select_track_id(saved_track)
	var saved_laps := int(cfg.get_value("race", "laps", 1))
	_laps_spin.value = clampf(float(saved_laps), _laps_spin.min_value, _laps_spin.max_value)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("player", "name", _name.text.strip_edges())
	var port_text := _host_port.text.strip_edges()
	if port_text.is_empty():
		port_text = _join_port.text.strip_edges()
	if port_text.is_empty():
		port_text = str(Net.DEFAULT_PORT)
	cfg.set_value("net", "port", port_text)
	cfg.set_value("net", "address", _address.text.strip_edges())
	cfg.set_value("net", "noray_host", _noray_host.text.strip_edges())
	# Drop legacy persisted Game ID keys if present.
	if cfg.has_section_key("net", "share_code"):
		cfg.erase_section_key("net", "share_code")
	if cfg.has_section_key("net", "game_id"):
		cfg.erase_section_key("net", "game_id")
	cfg.set_value("net", "lan_direct", not _host_internet_mode())
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
		return ""
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
	var name := _track_display_name(track_id)
	if name.is_empty() and not Net.race_track_document.is_empty():
		name = str(Net.race_track_document.get("name", "Piste"))
	if name.is_empty():
		name = "Piste"
	_race_summary.text = "%s — %s" % [name, _laps_phrase(laps)]


func _refresh_track_preview_for(track_id: String) -> void:
	if not Net.race_track_document.is_empty() and (
		track_id.is_empty() or track_id == Net.race_track_id
	):
		_track_preview.set_from_document(Net.race_track_document)
		return
	if track_id.is_empty():
		_track_preview.clear_track()
		return
	_track_preview.set_from_path(track_id)


func _publish_race_settings() -> void:
	if Game.mode != Game.Mode.HOST:
		return
	Net.set_race_settings(_selected_track_id(), int(_laps_spin.value))


func _refresh_track_preview() -> void:
	_refresh_track_preview_for(_selected_track_id())


func _refresh_share_row() -> void:
	var show_share := Game.mode == Game.Mode.HOST and Net.using_noray
	_share_row.visible = show_share
	if show_share:
		_share_code.text = Net.share_code()


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


func _on_noray_host_changed(_new_text: String) -> void:
	_save_settings()


func _on_game_id_changed(_new_text: String) -> void:
	pass


func _on_host_mode_changed(_button: BaseButton) -> void:
	_apply_host_mode_visibility()
	_save_settings()


func _on_join_mode_changed(_button: BaseButton) -> void:
	_apply_join_mode_visibility()
	_save_settings()


func _on_ports_changed(_new_text: String) -> void:
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
			_upnp.text = ""
		Game.Mode.HOST:
			if Net.using_noray:
				_status.text = ""
				_upnp.text = Net.connection_status
			else:
				_status.text = Net.host_share_text()
				_upnp.text = Net.upnp_status if not Net.upnp_status.is_empty() else "UPnP en cours…"
			_refresh_share_row()
		Game.Mode.CLIENT:
			_share_row.visible = false
			if Net.using_noray:
				_status.text = "En lobby — %s" % Net.share_code()
				_upnp.text = Net.connection_status
			else:
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
	if _busy:
		return
	if _track_ids.is_empty():
		_status.text = "Aucune piste enregistrée — crée-en une d’abord."
		return
	_apply_display_name("Host")
	Net.race_track_id = _selected_track_id()
	Net.race_laps = int(_laps_spin.value)
	Net.race_track_document = SplineTrackFile.load_document(Net.race_track_id)
	_busy = true
	if not _host_internet_mode():
		var err := Net.host(_port_from(_host_port))
		_busy = false
		if err != OK:
			_status.text = "Échec host — port peut-être déjà utilisé"
			return
		_save_settings()
		return

	var server := _noray_host.text.strip_edges()
	if server.is_empty():
		_busy = false
		_status.text = "Indique l'adresse du serveur relay"
		return
	_status.text = "Connexion au relay…"
	var nerr: Error = await Net.host_noray(server, Net.DEFAULT_NORAY_PORT)
	_busy = false
	if nerr != OK:
		_refresh_status()
		return
	_save_settings()


func _on_join_confirm() -> void:
	if _busy:
		return
	_apply_display_name("Client")
	_busy = true
	if not _join_internet_mode():
		var address := _address.text.strip_edges()
		if address.is_empty():
			address = "127.0.0.1"
		var port := _port_from(_join_port)
		var err := Net.join(address, port)
		_busy = false
		if err != OK:
			_status.text = "Échec join"
			return
		_status.text = "Connexion à %s:%d…" % [address, port]
		_save_settings()
		return

	var parsed := Net.parse_share_code(_game_id.text)
	if parsed.is_empty():
		_busy = false
		_status.text = "Game ID invalide — format attendu: serveur:code"
		return
	var relay_host := str(parsed["host"])
	_maybe_remember_relay_host(relay_host)
	_status.text = "Connexion via relay…"
	var nerr: Error = await Net.join_noray(
		relay_host,
		str(parsed["oid"]),
		Net.DEFAULT_NORAY_PORT
	)
	_busy = false
	if nerr != OK:
		_refresh_status()
		return
	_save_settings()


## Persist relay host from a pasted Game ID only if none is saved yet.
func _maybe_remember_relay_host(host: String) -> void:
	host = host.strip_edges()
	if host.is_empty():
		return
	if not _noray_host.text.strip_edges().is_empty():
		return
	_noray_host.text = host
	_save_settings()


func _on_copy_share() -> void:
	var code := Net.share_code()
	if code.is_empty():
		code = _share_code.text.strip_edges()
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	_upnp.text = "Game ID copié"


func _on_ready_pressed() -> void:
	Net.set_ready(not _local_ready())
	_refresh_ready_button()


func _on_start_pressed() -> void:
	if _track_ids.is_empty():
		_status.text = "Aucune piste enregistrée — crée-en une d’abord."
		return
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
	_busy = false
	if _step == Step.SESSION:
		_set_step(Step.CHOICE)
	_refresh_status()
	_refresh_players()


func _on_lobby_changed() -> void:
	_refresh_players()
	_refresh_status()
	if _step == Step.SESSION:
		_refresh_race_display()
		_refresh_share_row()


func _on_race_started() -> void:
	get_tree().change_scene_to_file("res://view/board.tscn")


func _on_net_error(message: String) -> void:
	_busy = false
	_status.text = message
