class_name GSIWebSocketServer
extends GSIBaseClient

var _tcp_server: TCPServer
var _peers: Dictionary[int, GSIWebsocketConnection] = {}
var _next_peer_id: int = 1

var _tls_options: TLSOptions
var _use_ssl: bool = false

var _pending_connections: Dictionary[int, GSIWebsocketConnection] = {}
var _pending_id_counter: int = 0


func _init(p_config: GSIConfig) -> void:
	super(p_config)

	if OS.has_feature("web"):
		GSILogger.log_gsi(
			(
				"WSServer(%s): WebSocketServer is not supported in HTML5 exports."
				+ " This endpoint will not function." % config.id
			),
			GSILogger.LogLevel.ERROR
		)
		return

	_tcp_server = TCPServer.new()

	if not config.tls_certificate_path.is_empty() or not config.tls_key_path.is_empty():
		var cert := X509Certificate.new()
		var key := CryptoKey.new()

		var cert_load_err: Error = cert.load(config.tls_certificate_path)
		if cert_load_err != OK:
			GSILogger.log_gsi(
				(
					"WSServer(%s): Failed to load TLS certificate from %s: %s"
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
					"WSServer(%s): Failed to load TLS key from %s: %s"
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
				"WSServer(%s): Loaded TLS certificate and key for WSS."
				+ " Will attempt TLS handshake for new connections." % config.id
			),
			GSILogger.LogLevel.INFO
		)
	elif not config.tls_certificate_path.is_empty() or not config.tls_key_path.is_empty():
		GSILogger.log_gsi(
			(
				"WSServer(%s): Incomplete TLS configuration."
				+ "Both certificate and key paths must be provided for WSS."
				+ " Starting as ws://." % config.id
			),
			GSILogger.LogLevel.WARN
		)

	var error: Error = _tcp_server.listen(config.port)
	if error != OK:
		GSILogger.log_gsi(
			(
				"WSServer(%s): Failed to start listening on port %d: %s"
				% [config.id, config.port, error_string(error)]
			),
			GSILogger.LogLevel.ERROR
		)
		_tcp_server = null
		return

	var protocol_prefix: String = "wss://" if _use_ssl else "ws://"
	GSILogger.log_gsi(
		"WSServer(%s): Listening on %s0.0.0.0:%d" % [config.id, protocol_prefix, config.port],
		GSILogger.LogLevel.INFO
	)


func _physics_process(_delta: float) -> void:
	if _tcp_server == null or not _tcp_server.is_listening():
		return

	while _tcp_server.is_connection_available():
		var client_stream: StreamPeerTCP = _tcp_server.take_connection()
		if client_stream == null:
			continue

		_pending_id_counter += 1
		var current_pending_id: int = _pending_id_counter

		if _use_ssl:
			var tls_stream := StreamPeerTLS.new()
			var tls_error: Error = tls_stream.accept_stream(client_stream, _tls_options)
			if tls_error != OK:
				GSILogger.log_gsi(
					(
						"WSServer(%s): Failed to accept TLS stream for new connection: %s"
						% [config.id, error_string(tls_error)]
					),
					GSILogger.LogLevel.ERROR
				)
				client_stream.disconnect_from_host()
				continue
			var connection := GSIWebsocketConnection.new(
				current_pending_id,
				tls_stream,
				GSIWebsocketConnection.ConnectionState.PENDING_TLS_HANDSHAKE,
				Time.get_ticks_msec()
			)
			_pending_connections[current_pending_id] = connection
			GSILogger.log_gsi(
				(
					"WSServer(%s): Initiated TLS handshake for new connection (Pending ID: %d)."
					% [config.id, current_pending_id]
				),
				GSILogger.LogLevel.DEBUG
			)
		else:
			var connection := GSIWebsocketConnection.new(
				current_pending_id,
				client_stream,
				GSIWebsocketConnection.ConnectionState.PENDING_TCP,
				Time.get_ticks_msec()
			)
			_pending_connections[current_pending_id] = connection
			(
				GSILogger
				. log_gsi(
					(
						"WSServer(%s): New non-SSL connection ready for WebSocket upgrade (Pending ID: %d)."
						% [config.id, current_pending_id]
					),
					GSILogger.LogLevel.DEBUG
				)
			)

	for pending_id: int in _pending_connections.keys().duplicate():
		var connection: GSIWebsocketConnection = _pending_connections[pending_id]
		var stream: StreamPeer = connection.stream

		stream.poll()

		if (Time.get_ticks_msec() - connection.handshake_start_time) > config.timeout:
			GSILogger.log_gsi(
				(
					"WSServer(%s): Handshake/Upgrade timed out for Pending ID: %d."
					% [config.id, pending_id]
				),
				GSILogger.LogLevel.ERROR
			)
			connection.cleanup()
			_pending_connections.erase(pending_id)
			continue

		var stream_status: int
		if connection.state == GSIWebsocketConnection.ConnectionState.PENDING_TLS_HANDSHAKE:
			stream_status = (stream as StreamPeerTLS).get_status()
			if stream_status == StreamPeerTLS.STATUS_HANDSHAKING:
				continue
		else:
			stream_status = (stream as StreamPeerTCP).get_status()

		if (
			stream_status == StreamPeerTLS.STATUS_ERROR
			or stream_status == StreamPeerTCP.STATUS_ERROR
			or stream_status == StreamPeerTLS.STATUS_DISCONNECTED
			or stream_status == StreamPeerTCP.STATUS_NONE
		):
			GSILogger.log_gsi(
				(
					"WSServer(%s): Pending connection (ID: %d)"
					+ " stream failed or disconnected during handshake/upgrade."
					+ " Status: %d" % [config.id, pending_id, stream_status]
				),
				GSILogger.LogLevel.ERROR
			)
			connection.cleanup()
			_pending_connections.erase(pending_id)
			continue

		if (
			(
				connection.state == GSIWebsocketConnection.ConnectionState.PENDING_TLS_HANDSHAKE
				and stream_status == StreamPeerTLS.STATUS_CONNECTED
			)
			or (
				connection.state == GSIWebsocketConnection.ConnectionState.PENDING_TCP
				and stream_status == StreamPeerTCP.STATUS_CONNECTED
			)
		):
			var ws_peer := WebSocketPeer.new()
			var ws_accept_error: Error = ws_peer.accept_stream(stream)

			if ws_accept_error != OK:
				GSILogger.log_gsi(
					(
						"WSServer(%s): Failed to accept WebSocket stream for Pending ID %d: %s"
						% [config.id, pending_id, error_string(ws_accept_error)]
					),
					GSILogger.LogLevel.ERROR
				)
				connection.cleanup()
				_pending_connections.erase(pending_id)
				continue

			connection.set_websocket_peer(ws_peer)
			_next_peer_id += 1
			connection.id = _next_peer_id
			_peers[_next_peer_id] = connection
			GSILogger.log_gsi(
				(
					"WSServer(%s): Client connected: ID %d (from Pending ID: %d). Total clients: %d"
					% [config.id, _next_peer_id, pending_id, _peers.size()]
				),
				GSILogger.LogLevel.INFO
			)

			if not queued_payload.is_empty():
				_perform_send_to_single_peer(_next_peer_id, queued_payload)

			_pending_connections.erase(pending_id)

	for peer_id: int in _peers.keys().duplicate():
		var connection: GSIWebsocketConnection = _peers[peer_id]
		var peer: WebSocketPeer = connection.ws_peer

		if peer != null:
			_peers.erase(peer_id)
			continue

		peer.poll()

		var peer_state: WebSocketPeer.State = peer.get_ready_state()
		if peer_state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count():
				var packet: PackedByteArray = peer.get_packet()
				# We don't care about received data, but handle it anyway...
		elif peer_state == WebSocketPeer.STATE_CLOSED or peer_state == WebSocketPeer.STATE_CLOSING:
			_peers.erase(peer_id)
			var code: int = peer.get_close_code()
			var reason: String = peer.get_close_reason()
			(
				GSILogger
				. log_gsi(
					(
						"WSServer(%s): Client disconnected: ID %d, Code: %d, Reason: '%s'. Total clients: %d"
						% [config.id, peer_id, code, reason, _peers.size()]
					),
					GSILogger.LogLevel.INFO
				)
			)


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
		var connection: GSIWebsocketConnection = _peers.get(peer_id)
		var peer: WebSocketPeer = connection.ws_peer

		if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			# Ignore, should be removed in _physics_process()
			continue

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
	var connection: GSIWebsocketConnection = _peers.get(peer_id)
	if connection == null:
		# Ignore, should be removed in _physics_process()
		return

	var peer: WebSocketPeer = connection.ws_peer
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		# Ignore, should be removed in _process()
		return

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
		if _tcp_server != null:
			_tcp_server.stop()
			_tcp_server = null

		for pending_id: int in _pending_connections.keys():
			_pending_connections[pending_id].cleanup()
		_pending_connections.clear()

		for peer_id: int in _peers.keys():
			var connection: GSIWebsocketConnection = _peers[peer_id]
			var peer: WebSocketPeer = connection.ws_peer
			if peer != null:
				peer.close()
				peer.queue_free()
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
