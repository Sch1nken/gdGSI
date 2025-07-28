class_name GSIWebSocketClient
extends GSIBaseClient

const RECONNECT_DELAY_SEC = 5.0

var ws_peer: WebSocketPeer
var reconnect_timer: Timer

var _last_peer_state: int = WebSocketPeer.STATE_CLOSED


func _init(p_config: GSIConfig) -> void:
	super(p_config)
	ws_peer = WebSocketPeer.new()


func _get_display_name() -> String:
	return "WSClient(%s)" % config.id


func _perform_send(payload: Dictionary) -> void:
	var current_state: int = ws_peer.get_ready_state()
	print("STATE %s" % str(current_state))

	if current_state == WebSocketPeer.STATE_CLOSED or current_state == WebSocketPeer.STATE_CLOSING:
		GSILogger.log_gsi(
			(
				"WSClient(%s): Not connected (state: %d). Attempting to connect to %s..."
				% [config.id, current_state, config.uri]
			)
		)
		var error: Error = ws_peer.connect_to_url(
			config.uri, null if config.tls_verification_enabled else TLSOptions.client_unsafe()
		)

		if error != OK:
			GSILogger.log_gsi(
				(
					"WSClient(%s): Failed to initiate connection to %s: %s"
					% [config.id, config.uri, error_string(error)]
				),
				GSILogger.LogLevel.ERROR
			)
			_handle_send_result(false, payload)
			return

		GSILogger.log_gsi(
			"WSClient(%s): Connection initiated. Waiting for connection to open..." % config.id
		)
		_handle_send_result(false, payload)
		return

	if current_state == WebSocketPeer.STATE_CONNECTING:
		GSILogger.log_gsi(
			"WSClient(%s): Still connecting. Skipping send attempt." % config.id,
			GSILogger.LogLevel.DEBUG
		)
		_handle_send_result(false, payload)
		return

	var json_string: String = JSON.stringify(payload)
	var send_error: Error = ws_peer.send_text(json_string)

	if send_error == OK:
		_handle_send_result(true, payload)
	else:
		GSILogger.log_gsi(
			"WSClient(%s): Failed to send data: %s" % [config.id, error_string(send_error)],
			GSILogger.LogLevel.WARN
		)
		_handle_send_result(false, payload)


func _start_reconnect_timer() -> void:
	reconnect_timer.stop()
	reconnect_timer.start(RECONNECT_DELAY_SEC)
	GSILogger.log_gsi(
		(
			"WSClient(%s): Will attempt to reconnect/resend in %d seconds."
			% [config.id, RECONNECT_DELAY_SEC]
		),
		GSILogger.LogLevel.DEBUG
	)


func _stop_reconnect_timer() -> void:
	if is_instance_valid(reconnect_timer) and not reconnect_timer.is_stopped():
		reconnect_timer.stop()
		GSILogger.log_gsi(
			"WSClient(%s): Reconnect timer stopped." % config.id, GSILogger.LogLevel.DEBUG
		)


func _physics_process(_delta: float) -> void:
	if ws_peer == null:
		return

	ws_peer.poll()
	var current_peer_state: int = ws_peer.get_ready_state()

	if current_peer_state == _last_peer_state:
		if current_peer_state == WebSocketPeer.STATE_OPEN:
			while ws_peer.get_available_packet_count() > 0:
				@warning_ignore("unused_variable")
				var packet: PackedByteArray = ws_peer.get_packet()
				# We don't really care about data that is sent to us... just do work as usual
		return

	match current_peer_state:
		WebSocketPeer.STATE_OPEN:
			GSILogger.log_gsi(
				"WSClient(%s): Connection state changed to OPEN." % config.id,
				GSILogger.LogLevel.DEBUG
			)
			_stop_reconnect_timer()
		WebSocketPeer.STATE_CONNECTING:
			GSILogger.log_gsi(
				"WSClient(%s): Connection state changed to CONNECTING." % config.id,
				GSILogger.LogLevel.DEBUG
			)
		WebSocketPeer.STATE_CLOSING:
			GSILogger.log_gsi(
				"WSClient(%s): Connection state changed to CLOSING." % config.id,
				GSILogger.LogLevel.DEBUG
			)
		WebSocketPeer.STATE_CLOSED:
			var code: int = ws_peer.get_close_code()
			var reason: String = ws_peer.get_close_reason()
			GSILogger.log_gsi(
				(
					"WSClient(%s): Connection state changed to CLOSED. Code: %d, Reason: '%s'"
					% [config.id, code, reason]
				),
				GSILogger.LogLevel.DEBUG
			)
		_:
			pass  # No specific action for other states

	_last_peer_state = current_peer_state


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_PREDELETE:
		_stop_reconnect_timer()
		if ws_peer != null:
			ws_peer.close()
			ws_peer.queue_free()


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
