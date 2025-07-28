class_name GSIWebSocketServer
extends GSIBaseClient

var _tcp_server: TCPServer
var _peers: Dictionary[int, GSIWebSocketConnection] = {}
var _next_peer_id: int = 1

var _tls_options: TLSOptions = null
var _use_ssl: bool = false

var _pending_connections: Dictionary[int, GSIWebSocketConnection] = {}
var _pending_id_counter: int = 0  # Start from 0, increment before first use


func _init(p_config: GSIConfig) -> void:
	super(p_config)

	if OS.has_feature("web"):
		GSILogger.log_gsi(
			(
				"WebSocketServer(%s): WebSocketServer is not supported in HTML5 exports."
				+ " This endpoint will not function." % config.id
			),
			GSILogger.LogLevel.ERROR
		)
		_tcp_server = null
		return

	_tcp_server = TCPServer.new()
	_configure_tls()
	_start_listening()


func _configure_tls() -> void:
	var cert_path_empty: bool = config.tls_certificate_path.is_empty()
	var key_path_empty: bool = config.tls_key_path.is_empty()

	if cert_path_empty and key_path_empty:
		_use_ssl = false
		return

	if cert_path_empty or key_path_empty:
		GSILogger.log_gsi(
			(
				"WebSocketServer(%s): Incomplete TLS configuration. "
				+ (
					"Both certificate and key paths must be provided for WSS. Starting as ws://."
					% config.id
				)
			),
			GSILogger.LogLevel.WARN
		)
		_use_ssl = false
		return

	var cert: X509Certificate = X509Certificate.new()
	var key: CryptoKey = CryptoKey.new()

	var cert_load_err: Error = cert.load(config.tls_certificate_path)
	if cert_load_err != OK:
		GSILogger.log_gsi(
			(
				"WebSocketServer(%s): Failed to load TLS certificate from %s: %s"
				% [config.id, config.tls_certificate_path, error_string(cert_load_err)]
			),
			GSILogger.LogLevel.ERROR
		)
		_tcp_server = null
		return

	var key_load_err: Error = key.load(config.tls_key_path)
	if key_load_err != OK:
		GSILogger.log_gsi(
			(
				"WebSocketServer(%s): Failed to load TLS key from %s: %s"
				% [config.id, config.tls_key_path, error_string(key_load_err)]
			),
			GSILogger.LogLevel.ERROR
		)
		_tcp_server = null
		return

	_tls_options = TLSOptions.server(key, cert)
	_use_ssl = true
	GSILogger.log_gsi(
		(
			"WebSocketServer(%s): Loaded TLS certificate and key for WSS. "
			+ "Will attempt TLS handshake for new connections." % config.id
		),
		GSILogger.LogLevel.INFO
	)


func _start_listening() -> void:
	if _tcp_server == null:
		return  # TLS configuration failed

	var error: Error = _tcp_server.listen(config.port)
	if error == OK:
		var protocol_prefix: String = "wss://" if _use_ssl else "ws://"
		GSILogger.log_gsi(
			(
				"WebSocketServer(%s): Listening on %s0.0.0.0:%d"
				% [config.id, protocol_prefix, config.port]
			),
			GSILogger.LogLevel.INFO
		)
	else:
		GSILogger.log_gsi(
			(
				"WebSocketServer(%s): Failed to start listening on port %d: %s"
				% [config.id, config.port, error_string(error)]
			),
			GSILogger.LogLevel.ERROR
		)
		_tcp_server = null


func _physics_process(_delta: float) -> void:
	if _tcp_server == null or not _tcp_server.is_listening():
		return

	_handle_new_connections()
	_process_pending_connections()
	_process_established_connections()


func _handle_new_connections() -> void:
	while _tcp_server.is_connection_available():
		var client_stream: StreamPeerTCP = _tcp_server.take_connection()
		if client_stream == null:
			continue

		_pending_id_counter += 1
		var current_pending_id: int = _pending_id_counter

		if _use_ssl:
			_initiate_tls_handshake(client_stream, current_pending_id)
		else:
			_add_pending_tcp_connection(client_stream, current_pending_id)


func _initiate_tls_handshake(client_stream: StreamPeerTCP, pending_id: int) -> void:
	var tls_stream: StreamPeerTLS = StreamPeerTLS.new()
	var tls_error: Error = tls_stream.accept_stream(client_stream, _tls_options)
	if tls_error != OK:
		GSILogger.log_gsi(
			(
				"WSServer(%s): Failed to initiate TLS handshake for new connection: %s"
				% [config.id, error_string(tls_error)]
			),
			GSILogger.LogLevel.ERROR
		)
		client_stream.disconnect_from_host()
		return

	var connection: GSIWebSocketConnection = GSIWebSocketConnection.new(
		pending_id,
		tls_stream,
		GSIWebSocketConnection.ConnectionState.PENDING_TLS_HANDSHAKE,
		Time.get_ticks_msec()
	)
	_pending_connections[pending_id] = connection
	GSILogger.log_gsi(
		(
			"WSServer(%s): Initiated TLS handshake for new connection (Pending ID: %d)."
			% [config.id, pending_id]
		),
		GSILogger.LogLevel.DEBUG
	)


func _add_pending_tcp_connection(client_stream: StreamPeerTCP, pending_id: int) -> void:
	var connection: GSIWebSocketConnection = GSIWebSocketConnection.new(
		pending_id,
		client_stream,
		GSIWebSocketConnection.ConnectionState.PENDING_TCP,
		Time.get_ticks_msec()
	)
	_pending_connections[pending_id] = connection
	GSILogger.log_gsi(
		(
			"WSServer(%s): New non-SSL connection ready for WebSocket upgrade (Pending ID: %d)."
			% [config.id, pending_id]
		),
		GSILogger.LogLevel.DEBUG
	)


func _process_pending_connections() -> void:
	for pending_id: int in _pending_connections.keys().duplicate():
		var connection: GSIWebSocketConnection = _pending_connections[pending_id]

		if not _is_valid_and_poll(connection, pending_id):
			continue

		if _check_handshake_timeout(connection, pending_id):
			continue

		_check_and_accept_websocket(connection, pending_id)


func _is_valid_and_poll(connection: GSIWebSocketConnection, pending_id: int) -> bool:
	if connection == null or connection.stream == null:
		GSILogger.log_gsi(
			(
				"WSServer(%s): Invalid pending connection or stream (ID: %d). Removing."
				% [config.id, pending_id]
			),
			GSILogger.LogLevel.WARN
		)
		_cleanup_pending_connection(pending_id, connection)
		return false

	connection.stream.poll()
	return true


func _check_handshake_timeout(connection: GSIWebSocketConnection, pending_id: int) -> bool:
	if (Time.get_ticks_msec() - connection.handshake_start_time) > config.timeout:
		GSILogger.log_gsi(
			(
				"WSServer(%s): Handshake/Upgrade timed out for Pending ID: %d."
				% [config.id, pending_id]
			),
			GSILogger.LogLevel.ERROR
		)
		_cleanup_pending_connection(pending_id, connection)
		return true
	return false


func _check_and_accept_websocket(connection: GSIWebSocketConnection, pending_id: int) -> void:
	var stream_status: int = _get_stream_status(connection)

	# Early exit if still handshaking
	if (
		connection.state == GSIWebSocketConnection.ConnectionState.PENDING_TLS_HANDSHAKE
		and stream_status == StreamPeerTLS.STATUS_HANDSHAKING
	):
		return

	# Check for connected state
	var connected: bool = (
		(
			connection.state == GSIWebSocketConnection.ConnectionState.PENDING_TLS_HANDSHAKE
			and stream_status == StreamPeerTLS.STATUS_CONNECTED
		)
		or (
			connection.state == GSIWebSocketConnection.ConnectionState.PENDING_TCP
			and stream_status == StreamPeerTCP.STATUS_CONNECTED
		)
	)

	if connected:
		_accept_websocket_connection(connection, pending_id)
		return

	# Handle errors or unexpected disconnections
	if (
		stream_status == StreamPeerTLS.STATUS_ERROR
		or stream_status == StreamPeerTCP.STATUS_ERROR
		or stream_status == StreamPeerTLS.STATUS_DISCONNECTED
		or stream_status == StreamPeerTCP.STATUS_NONE
	):
		GSILogger.log_gsi(
			(
				"WSServer(%s): Pending connection (ID: %d) "
				+ (
					"stream failed or disconnected during handshake/upgrade. Status: %d"
					% [config.id, pending_id, stream_status]
				)
			),
			GSILogger.LogLevel.ERROR
		)
		_cleanup_pending_connection(pending_id, connection)


func _get_stream_status(connection: GSIWebSocketConnection) -> int:
	if connection.state == GSIWebSocketConnection.ConnectionState.PENDING_TLS_HANDSHAKE:
		return (connection.stream as StreamPeerTLS).get_status()

	return (connection.stream as StreamPeerTCP).get_status()


func _accept_websocket_connection(connection: GSIWebSocketConnection, pending_id: int) -> void:
	var ws_peer: WebSocketPeer = WebSocketPeer.new()
	var ws_accept_error: Error = ws_peer.accept_stream(connection.stream)

	if ws_accept_error != OK:
		GSILogger.log_gsi(
			(
				"WSServer(%s): Failed to accept WebSocket stream for Pending ID %d: %s"
				% [config.id, pending_id, error_string(ws_accept_error)]
			),
			GSILogger.LogLevel.ERROR
		)
		_cleanup_pending_connection(pending_id, connection)
		return

	_next_peer_id += 1
	connection.id = _next_peer_id
	connection.set_websocket_peer(ws_peer)
	_peers[_next_peer_id] = connection
	_pending_connections.erase(pending_id)

	GSILogger.log_gsi(
		(
			"WSServer(%s): Client connected: ID %d (from Pending ID: %d). Total clients: %d"
			% [config.id, _next_peer_id, pending_id, _peers.size()]
		),
		GSILogger.LogLevel.INFO
	)

	if not queued_payload.is_empty():
		_perform_send_to_single_peer(_next_peer_id, queued_payload)


func _cleanup_pending_connection(pending_id: int, connection: GSIWebSocketConnection) -> void:
	if connection != null:
		connection.cleanup()
	_pending_connections.erase(pending_id)


func _process_established_connections() -> void:
	for peer_id: int in _peers.keys().duplicate():
		var connection: GSIWebSocketConnection = _peers.get(peer_id)

		if connection == null or connection.ws_peer == null:
			GSILogger.log_gsi(
				(
					"WSServer(%s): Invalid peer connection or WebSocketPeer for ID %d. Removing."
					% [config.id, peer_id]
				),
				GSILogger.LogLevel.WARN
			)
			_cleanup_established_connection(peer_id, connection)
			continue

		var peer: WebSocketPeer = connection.ws_peer
		peer.poll()

		var peer_state: int = peer.get_ready_state()
		match peer_state:
			WebSocketPeer.STATE_OPEN:
				_handle_open_peer(peer_id, peer)
			WebSocketPeer.STATE_CLOSED, WebSocketPeer.STATE_CLOSING:
				_log_and_cleanup_disconnected_peer(peer_id, peer, connection)


func _handle_open_peer(peer_id: int, peer: WebSocketPeer) -> void:
	while peer.get_available_packet_count():
		var packet: PackedByteArray = peer.get_packet()
		if peer.was_string_packet():
			var text_packet: String = packet.get_string_from_utf8()
			GSILogger.log_gsi(
				(
					"WSServer(%s): Data received from client %d: %s"
					% [config.id, peer_id, text_packet]
				),
				GSILogger.LogLevel.INFO
			)
		else:
			GSILogger.log_gsi(
				(
					"WSServer(%s): Binary data received from client %d (size: %d)"
					% [config.id, peer_id, packet.size()]
				),
				GSILogger.LogLevel.INFO
			)


func _log_and_cleanup_disconnected_peer(
	peer_id: int, peer: WebSocketPeer, connection: GSIWebSocketConnection
) -> void:
	GSILogger.log_gsi(
		(
			"WSServer(%s): Client disconnected: ID %d, Code: %d, Reason: '%s'. Total clients: %d"
			% [config.id, peer_id, peer.get_close_code(), peer.get_close_reason(), _peers.size()]
		),
		GSILogger.LogLevel.INFO
	)
	_cleanup_established_connection(peer_id, connection)


func _cleanup_established_connection(peer_id: int, connection: GSIWebSocketConnection) -> void:
	if connection != null:
		connection.cleanup()
	_peers.erase(peer_id)


func _get_display_name() -> String:
	return "WSServer(%s)" % config.id


func _perform_send(payload: Dictionary) -> void:
	if _tcp_server == null or not _tcp_server.is_listening():
		_handle_send_result(false, payload)
		return

	if _peers.is_empty():
		_handle_send_result(true, payload)
		return

	var json_string: String = JSON.stringify(payload)
	var success_count: int = 0
	var failure_count: int = 0

	for peer_id: int in _peers.keys().duplicate():
		var connection: GSIWebSocketConnection = _peers.get(peer_id)
		if connection == null or connection.ws_peer == null:
			# This peer is already invalid or cleaned up,
			# it will be removed by _process_established_connections
			continue

		var peer: WebSocketPeer = connection.ws_peer
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			var send_error: Error = peer.send_text(json_string)
			if send_error == OK:
				success_count += 1
			else:
				failure_count += 1
				GSILogger.log_gsi(
					(
						"WSServer(%s): Failed to send data to peer %d: %s"
						% [config.id, peer_id, error_string(send_error)]
					),
					GSILogger.LogLevel.ERROR
				)
		else:
			# Peer not in open state, will be handled by _process_established_connections
			pass

	_handle_send_result(success_count > 0 or _peers.is_empty(), payload)
	if success_count > 0:
		GSILogger.log_gsi(
			(
				"WSServer(%s): Broadcasted to %d clients (failed: %d)."
				% [config.id, success_count, failure_count]
			),
			GSILogger.LogLevel.INFO
		)


func _perform_send_to_single_peer(peer_id: int, payload: Dictionary) -> void:
	var connection: GSIWebSocketConnection = _peers.get(peer_id)
	if connection == null or connection.ws_peer == null:
		return

	var peer: WebSocketPeer = connection.ws_peer
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var json_string: String = JSON.stringify(payload)
		var send_error: Error = peer.send_text(json_string)
		if send_error != OK:
			GSILogger.log_gsi(
				(
					"WSServer(%s): Failed to send initial data to new peer %d: %s"
					% [config.id, peer_id, error_string(send_error)]
				),
				GSILogger.LogLevel.ERROR
			)


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_PREDELETE:
		_cleanup_server()


func _cleanup_server() -> void:
	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null

	for pending_id: int in _pending_connections.keys():
		_cleanup_pending_connection(pending_id, _pending_connections[pending_id])
	_pending_connections.clear()

	for peer_id: int in _peers.keys():
		_cleanup_established_connection(peer_id, _peers[peer_id])
	_peers.clear()


func error_string(error_code: int) -> String:
	match error_code:
		OK:
			return "OK"
		ERR_UNAVAILABLE:
			return "ERR_UNAVAILABLE"
		ERR_CANT_CONNECT:
			return "ERR_CANT_CONNECT"
		ERR_CANT_RESOLVE:
			return "ERR_CANT_RESOLVE"
		ERR_TIMEOUT:
			return "ERR_TIMEOUT"
		ERR_INVALID_DATA:
			return "ERR_INVALID_DATA"
		ERR_INVALID_PARAMETER:
			return "ERR_INVALID_PARAMETER"
		ERR_CANT_OPEN:
			return "ERR_CANT_OPEN"
		_:
			# gdlint:ignore = max-returns
			return "UNKNOWN_ERROR (%d)" % error_code
