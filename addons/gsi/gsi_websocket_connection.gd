class_name GSIWebsocketConnection
extends RefCounted

enum ConnectionState { PENDING_TCP, PENDING_TLS_HANDSHAKE, CONNECTED_WS }

var id: int
var stream: StreamPeer = null
var ws_peer: WebSocketPeer = null
var handshake_start_time: float = 0.0
var state: ConnectionState


func _init(
	p_id: int, p_stream: StreamPeer, p_state: ConnectionState, p_handshake_start_time: float
) -> void:
	id = p_id
	stream = p_stream
	state = p_state
	handshake_start_time = p_handshake_start_time


func set_websocket_peer(peer: WebSocketPeer) -> void:
	ws_peer = peer
	stream = null  # Stream is now managed by WebSocketPeer
	state = ConnectionState.CONNECTED_WS


func cleanup() -> void:
	if ws_peer != null:
		ws_peer.close()
		ws_peer.queue_free()
		ws_peer = null

	if stream != null:
		if stream is StreamPeerTCP:
			(stream as StreamPeerTCP).disconnect_from_host()
		stream.queue_free()
		stream = null
