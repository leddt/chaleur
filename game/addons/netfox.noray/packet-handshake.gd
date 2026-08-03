extends Node
class_name _PacketHandshake

class HandshakeStatus:
	var did_read: bool = false
	var did_write: bool = false
	var did_handshake: bool = false

	func _to_string() -> String:
		return "$" + \
			("r" if did_read else "-") + \
			("w" if did_write else "-") + \
			("x" if did_handshake else "-")

	static func from_string(text: String) -> HandshakeStatus:
		var result = HandshakeStatus.new()
		result.did_read = text.contains("r")
		result.did_write = text.contains("w")
		result.did_handshake = text.contains("x")
		return result


func over_packet_peer(peer: PacketPeer, timeout: float = 8.0, frequency: float = 0.1) -> Error:
	var result = ERR_TIMEOUT
	var status = HandshakeStatus.new()
	status.did_write = true

	while timeout >= 0:
		while peer.get_available_packet_count() > 0:
			var packet = peer.get_packet()
			var incoming_status = HandshakeStatus.from_string(packet.get_string_from_ascii())
			status.did_read = true
			if incoming_status.did_read:
				status.did_handshake = true
			if incoming_status.did_handshake and status.did_handshake:
				result = OK
				timeout = 0
		peer.put_packet(status.to_string().to_ascii_buffer())
		await get_tree().create_timer(frequency).timeout
		timeout -= frequency

	if status.did_read and status.did_write and not status.did_handshake:
		result = ERR_BUSY
	return result


func over_enet(
	connection: ENetConnection,
	address: String,
	port: int,
	timeout: float = 8.0,
	frequency: float = 0.1
) -> Error:
	var status = HandshakeStatus.new()
	status.did_write = true
	status.did_read = true
	status.did_handshake = true
	while timeout >= 0:
		connection.socket_send(address, port, status.to_string().to_ascii_buffer())
		await get_tree().create_timer(frequency).timeout
		timeout -= frequency
	return OK


func over_enet_peer(
	peer: ENetMultiplayerPeer,
	address: String,
	port: int,
	timeout: float = 8.0,
	frequency: float = 0.1
) -> Error:
	var status = HandshakeStatus.new()
	status.did_write = true
	status.did_read = true
	status.did_handshake = true
	while timeout >= 0:
		if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return ERR_CONNECTION_ERROR
		peer.host.socket_send(address, port, status.to_string().to_ascii_buffer())
		await get_tree().create_timer(frequency).timeout
		timeout -= frequency
	return OK
