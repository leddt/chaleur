extends Node

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 6

signal host_started(port: int)
signal join_started(address: String, port: int)
signal left
signal lobby_changed
signal race_started
signal state_updated
signal net_error(message: String)
signal peer_gone(peer_id: int)
signal return_to_lobby_requested

## peer_id -> {name: String, ready: bool, seat: int}
var lobby: Dictionary = {}
var local_display_name: String = "Player"
var race_laps: int = 1
var race_track_id: String = "track1"
var _port: int = DEFAULT_PORT
var upnp_status: String = ""
var upnp_external_ip: String = ""
var public_ip: String = ""
var lan_ips: PackedStringArray = []
var _upnp: UPNP
var _http: HTTPRequest
var _public_ip_http_fallback: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_http = HTTPRequest.new()
	_http.timeout = 5.0
	add_child(_http)
	_http.request_completed.connect(_on_public_ip_response)


func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func has_peer() -> bool:
	return multiplayer.multiplayer_peer != null


func my_peer_id() -> int:
	if not has_peer():
		return 0
	return multiplayer.get_unique_id()


func my_seat() -> int:
	var entry: Variant = lobby.get(my_peer_id(), null)
	if entry == null:
		return -1
	return int(entry.get("seat", -1))


## Prefer web public IP, then UPnP external.
func external_ip() -> String:
	if not public_ip.is_empty():
		return public_ip
	return upnp_external_ip


func join_address_hint() -> String:
	var ext := external_ip()
	if not ext.is_empty():
		return "%s:%d" % [ext, _port]
	if not lan_ips.is_empty():
		return "%s:%d" % [lan_ips[0], _port]
	return "?:%d" % _port


## Host-facing multi-line share text: external first, then LAN.
func host_share_text() -> String:
	var lines: PackedStringArray = ["Hôte — port UDP %d" % _port]
	var ext := external_ip()
	if not ext.is_empty():
		lines.append("Internet: %s:%d" % [ext, _port])
	else:
		lines.append("Internet: recherche de l'IP publique…")
	if lan_ips.is_empty():
		refresh_lan_ips()
	if not lan_ips.is_empty():
		var parts: PackedStringArray = []
		for ip in lan_ips:
			parts.append("%s:%d" % [ip, _port])
		lines.append("LAN: %s" % ", ".join(parts))
	else:
		lines.append("LAN: aucune IPv4 locale trouvée")
	return "\n".join(lines)


func refresh_lan_ips() -> void:
	var found: Array[String] = []
	for addr in IP.get_local_addresses():
		if _is_usable_ipv4(str(addr)):
			found.append(str(addr))
	found.sort_custom(func(a: String, b: String) -> bool:
		return _lan_priority(a) < _lan_priority(b)
	)
	lan_ips = PackedStringArray(found)


func _lan_priority(ip: String) -> int:
	if ip.begins_with("192.168."):
		return 0
	if ip.begins_with("10."):
		return 1
	if ip.begins_with("172."):
		var second := int(ip.get_slice(".", 1)) if ip.get_slice_count(".") > 1 else 0
		if second >= 16 and second <= 31:
			return 2
	return 3


func host(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		net_error.emit(
			"Impossible d'héberger sur le port %d (%s). Port déjà pris ?" % [port, error_string(err)]
		)
		return err
	multiplayer.multiplayer_peer = peer
	_port = port
	Game.set_mode(Game.Mode.HOST)
	lobby.clear()
	lobby[1] = {"name": local_display_name, "ready": false, "seat": 0}
	refresh_lan_ips()
	_fetch_public_ip()
	_try_upnp(port)
	host_started.emit(port)
	_broadcast_lobby()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		net_error.emit(
			"Impossible de rejoindre %s:%d (%s)" % [address, port, error_string(err)]
		)
		return err
	multiplayer.multiplayer_peer = peer
	_port = port
	Game.set_mode(Game.Mode.CLIENT)
	lobby.clear()
	upnp_status = ""
	upnp_external_ip = ""
	public_ip = ""
	lan_ips.clear()
	join_started.emit(address, port)
	return OK


func leave() -> void:
	_clear_upnp()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	lobby.clear()
	if Game.mode == Game.Mode.HOST or Game.mode == Game.Mode.CLIENT:
		Game.set_mode(Game.Mode.NONE)
	left.emit()
	lobby_changed.emit()


func set_ready(is_ready: bool) -> void:
	if not has_peer():
		return
	if is_server():
		_set_ready_local(my_peer_id(), is_ready)
		_broadcast_lobby()
	else:
		rpc_set_ready.rpc_id(1, is_ready)


func set_race_settings(track_id: String, laps: int) -> void:
	if not is_server():
		return
	race_track_id = track_id if not track_id.is_empty() else "track1"
	race_laps = maxi(1, laps)
	_broadcast_lobby()


func start_race(laps: int = 1, track_id: String = "track1") -> void:
	if not is_server():
		net_error.emit("Seul l'hôte peut démarrer")
		return
	if lobby.size() < 2:
		net_error.emit("Il faut au moins 2 joueurs")
		return
	for peer_id in lobby:
		if not bool(lobby[peer_id].get("ready", false)):
			net_error.emit("Tous les joueurs doivent être prêts")
			return
	_assign_seats()
	var names: Array[String] = []
	for peer_id in _peers_by_seat():
		names.append(str(lobby[peer_id]["name"]))
	var seed := int(Time.get_unix_time_from_system())
	race_laps = maxi(1, laps)
	race_track_id = track_id if not track_id.is_empty() else "track1"
	Game.engine = HeatGameEngine.new()
	Game.engine.setup(names, HeatTrack.from_id(race_track_id, race_laps), seed)
	Game.local_player_id = my_seat()
	_broadcast_lobby()
	for peer_id in lobby:
		var seat := int(lobby[peer_id]["seat"])
		var snap := StateCodec.encode(Game.engine, seat)
		if int(peer_id) == my_peer_id():
			continue
		rpc_start_with_snapshot.rpc_id(peer_id, snap)
	race_started.emit()
	state_updated.emit()


func submit_action(action: String, payload: Dictionary) -> void:
	if Game.engine == null:
		return
	if Game.mode == Game.Mode.HOST:
		var result := _apply_action(my_seat(), action, payload)
		if not result.ok:
			net_error.emit(result.error)
			return
		_broadcast_snapshots()
		state_updated.emit()
	elif Game.mode == Game.Mode.CLIENT:
		rpc_request_action.rpc_id(1, action, payload)


func request_rematch(laps: int = -1, track_id: String = "") -> void:
	if is_server():
		# Keep ready flags so rematch can start immediately.
		var use_laps := race_laps if laps < 1 else laps
		var use_track := race_track_id if track_id.is_empty() else track_id
		start_race(use_laps, use_track)
	else:
		net_error.emit("Seul l'hôte peut lancer le rematch")


func request_return_to_lobby() -> void:
	if not has_peer():
		return
	if is_server():
		_apply_return_to_lobby()
	else:
		rpc_request_return_to_lobby.rpc_id(1)


# --- RPCs ------------------------------------------------------------------

@rpc("any_peer", "reliable")
func rpc_register(player_name: String) -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if lobby.size() >= MAX_CLIENTS:
		rpc_action_rejected.rpc_id(peer_id, "Lobby plein (%d joueurs max)" % MAX_CLIENTS)
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	if Game.engine != null and not Game.engine.is_race_over():
		rpc_action_rejected.rpc_id(peer_id, "Une course est déjà en cours")
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	lobby[peer_id] = {"name": player_name, "ready": false, "seat": lobby.size()}
	_broadcast_lobby()


@rpc("any_peer", "reliable")
func rpc_set_ready(is_ready: bool) -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_set_ready_local(peer_id, is_ready)
	_broadcast_lobby()


@rpc("authority", "reliable")
func rpc_lobby_sync(lobby_data: Dictionary, track_id: String = "track1", laps: int = 1) -> void:
	lobby = lobby_data
	race_track_id = track_id if not track_id.is_empty() else "track1"
	race_laps = maxi(1, laps)
	if Game.mode == Game.Mode.CLIENT:
		Game.local_player_id = my_seat()
	lobby_changed.emit()


@rpc("authority", "reliable")
func rpc_start_with_snapshot(data: Dictionary) -> void:
	Game.engine = StateCodec.decode(data)
	Game.local_player_id = my_seat()
	race_started.emit()
	state_updated.emit()


@rpc("authority", "reliable")
func rpc_apply_snapshot(data: Dictionary) -> void:
	if is_server():
		return
	Game.engine = StateCodec.decode(data)
	Game.local_player_id = my_seat()
	state_updated.emit()


@rpc("any_peer", "reliable")
func rpc_request_action(action: String, payload: Dictionary) -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not lobby.has(peer_id):
		return
	var seat := int(lobby[peer_id]["seat"])
	var result := _apply_action(seat, action, payload)
	if not result.ok:
		rpc_action_rejected.rpc_id(peer_id, result.error)
		return
	_broadcast_snapshots()
	state_updated.emit()


@rpc("authority", "reliable")
func rpc_action_rejected(message: String) -> void:
	net_error.emit(message)


@rpc("authority", "reliable")
func rpc_race_aborted(reason: String) -> void:
	net_error.emit(reason)
	Game.engine = null
	state_updated.emit()


@rpc("any_peer", "reliable")
func rpc_request_return_to_lobby() -> void:
	if not is_server():
		return
	_apply_return_to_lobby()


@rpc("authority", "call_local", "reliable")
func rpc_goto_lobby() -> void:
	Game.engine = null
	return_to_lobby_requested.emit()


# --- Internals -------------------------------------------------------------

func _apply_return_to_lobby() -> void:
	Game.engine = null
	for peer_id in lobby:
		lobby[peer_id]["ready"] = false
	_broadcast_lobby()
	rpc_goto_lobby.rpc()


func _on_peer_connected(_peer_id: int) -> void:
	if is_server():
		_broadcast_lobby()


func _on_peer_disconnected(peer_id: int) -> void:
	peer_gone.emit(peer_id)
	if is_server():
		lobby.erase(peer_id)
		_broadcast_lobby()
		if Game.engine != null and not Game.engine.is_race_over():
			Game.engine = null
			rpc_race_aborted.rpc("Un joueur s'est déconnecté — partie terminée")
			state_updated.emit()


func _on_connected_to_server() -> void:
	rpc_register.rpc_id(1, local_display_name)


func _on_connection_failed() -> void:
	net_error.emit(
		"Connexion échouée — vérifie l'IP, le port UDP %d, le firewall et que l'hôte est lancé" % _port
	)
	leave()


func _on_server_disconnected() -> void:
	net_error.emit("L'hôte a quitté la partie")
	Game.engine = null
	leave()


func _set_ready_local(peer_id: int, is_ready: bool) -> void:
	if lobby.has(peer_id):
		lobby[peer_id]["ready"] = is_ready


func _assign_seats() -> void:
	var peers: Array = lobby.keys()
	peers.sort()
	var seat := 0
	for peer_id in peers:
		lobby[peer_id]["seat"] = seat
		seat += 1


func _peers_by_seat() -> Array:
	var items: Array = []
	for peer_id in lobby:
		items.append([int(lobby[peer_id]["seat"]), peer_id])
	items.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for item in items:
		out.append(item[1])
	return out


func _broadcast_lobby() -> void:
	rpc_lobby_sync.rpc(lobby.duplicate(true), race_track_id, race_laps)
	lobby_changed.emit()


func _broadcast_snapshots() -> void:
	if Game.engine == null or not is_server():
		return
	for peer_id in lobby:
		if int(peer_id) == my_peer_id():
			continue
		var seat := int(lobby[peer_id]["seat"])
		rpc_apply_snapshot.rpc_id(peer_id, StateCodec.encode(Game.engine, seat))


func _apply_action(player_id: int, action: String, payload: Dictionary) -> ActionResult:
	if Game.engine == null:
		return ActionResult.fail("No race")
	var pending := Game.engine.pending_actor_ids()
	if player_id not in pending:
		return ActionResult.fail("Not your turn to act")
	match action:
		"shift_gear":
			return Game.engine.shift_gear(player_id, int(payload.get("gear", 1)))
		"play_cards":
			var ids: Array[String] = []
			for id in payload.get("card_ids", []):
				ids.append(str(id))
			return Game.engine.play_cards(player_id, ids)
		"react":
			return Game.engine.react(
				player_id,
				int(payload.get("cooldown", 0)),
				bool(payload.get("boost", false)),
				bool(payload.get("adrenaline", false))
			)
		"slipstream":
			return Game.engine.slipstream(player_id, bool(payload.get("use", false)))
		"discard":
			var dids: Array[String] = []
			for id in payload.get("card_ids", []):
				dids.append(str(id))
			return Game.engine.discard_cards(player_id, dids)
		_:
			return ActionResult.fail("Unknown action")


func _try_upnp(port: int) -> void:
	upnp_external_ip = ""
	upnp_status = "UPnP: recherche de la box…"
	# Discover blocks ~2s — run off the main thread.
	WorkerThreadPool.add_task(_upnp_worker.bind(port))


func _upnp_worker(port: int) -> void:
	var upnp := UPNP.new()
	var err := upnp.discover(2000, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS:
		err = upnp.discover(2000, 2)
	if err != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_upnp_finished", port, upnp, "UPnP indisponible — ouvre le port UDP %d (firewall + box)" % port, "")
		return
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		call_deferred(
			"_upnp_finished",
			port,
			upnp,
			"UPnP: aucune passerelle — ouvre le port UDP %d manuellement" % port,
			""
		)
		return
	var map_err := gateway.add_port_mapping(port, port, "Chaleur", "UDP")
	if map_err != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred(
			"_upnp_finished",
			port,
			upnp,
			"UPnP: échec mapping UDP %d — configure la box à la main" % port,
			""
		)
		return
	var external := upnp.query_external_address()
	var status: String
	if external.is_empty():
		status = "UPnP: port %d ouvert — IP externe inconnue (demande à ta box)" % port
	else:
		status = "UPnP OK — les amis rejoignent: %s:%d" % [external, port]
	call_deferred("_upnp_finished", port, upnp, status, external)


func _upnp_finished(port: int, upnp: UPNP, status: String, external: String) -> void:
	if not is_server() or _port != port:
		return
	_upnp = upnp
	upnp_status = status
	upnp_external_ip = external
	lobby_changed.emit()


func _clear_upnp() -> void:
	if _upnp != null:
		var gateway := _upnp.get_gateway()
		if gateway != null and gateway.is_valid_gateway():
			gateway.delete_port_mapping(_port, "UDP")
	_upnp = null
	upnp_status = ""
	upnp_external_ip = ""
	public_ip = ""
	lan_ips.clear()
	if _http != null:
		_http.cancel_request()


func _is_usable_ipv4(addr: String) -> bool:
	if addr.is_empty() or addr.contains(":"):
		return false
	if addr.begins_with("127."):
		return false
	var parts := addr.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not str(part).is_valid_int():
			return false
		var n := int(part)
		if n < 0 or n > 255:
			return false
	return true


func _fetch_public_ip() -> void:
	public_ip = ""
	_public_ip_http_fallback = false
	if _http == null:
		return
	_http.cancel_request()
	var err := _http.request("https://api.ipify.org")
	if err != OK:
		_public_ip_http_fallback = true
		_http.request("http://api.ipify.org")


func _on_public_ip_response(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if not is_server():
		return
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	if not ok:
		if not _public_ip_http_fallback:
			_public_ip_http_fallback = true
			_http.request("http://api.ipify.org")
			return
		lobby_changed.emit()
		return
	var ip := body.get_string_from_utf8().strip_edges()
	if _is_usable_ipv4(ip):
		public_ip = ip
	lobby_changed.emit()
