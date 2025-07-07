class_name GSIHTTPClient
extends GSIBaseClient

var http_request: HTTPRequest


func _init(p_config: GSIConfig) -> void:
	super(p_config)
	http_request = HTTPRequest.new()
	http_request.name = "GSIHttpRequest_%s" % config.id.validate_node_name()
	add_child(http_request)
	http_request.set_use_threads(true)
	http_request.request_completed.connect(Callable(self, "_on_http_request_completed"))


func _get_display_name() -> String:
	return "HTTPClient(%s)" % config.id


func _perform_send(payload: Dictionary) -> void:
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body: String = JSON.stringify(payload)

	http_request.timeout = config.timeout

	if not config.tls_verification_enabled:
		http_request.set_tls_options(TLSOptions.client_unsafe())

	var error: int = http_request.request(config.uri, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		GSILogger.log_gsi(
			"HTTPClient(%s): Failed to send HTTP request: %s" % [config.id, error_string(error)],
			GSILogger.LogLevel.ERROR
		)
		_handle_send_result(false, payload)


func _on_http_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	var success: bool = false
	match result:
		HTTPRequest.RESULT_SUCCESS:
			if response_code >= 200 and response_code < 300:
				success = true
				GSILogger.log_gsi(
					(
						"HTTPClient(%s): GSI payload sent successfully. HTTP Status: %d"
						% [config.id, response_code]
					),
					GSILogger.LogLevel.DEBUG
				)
			else:
				var error_body: String = body.get_string_from_utf8()
				GSILogger.log_gsi(
					(
						"HTTPClient(%s): GSI send failed: HTTP %d - %s"
						% [config.id, response_code, error_body]
					),
					GSILogger.LogLevel.ERROR
				)
		HTTPRequest.RESULT_TIMEOUT:
			GSILogger.log_gsi(
				(
					"HTTPClient(%s): GSI send timed out after %.2f s. No response from receiver."
					% [config.id, config.timeout]
				),
				GSILogger.LogLevel.ERROR
			)
		_:
			GSILogger.log_gsi(
				(
					"HTTPClient(%s): GSI send failed (network/other error): %s"
					% [config.id, error_string(result)]
				),
				GSILogger.LogLevel.ERROR
			)

	_handle_send_result(success, queued_payload)


func error_string(error_code: int) -> String:
	match error_code:
		OK:
			return "OK"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "ERR_CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "ERR_CANT_RESOLVE"
		HTTPRequest.RESULT_TIMEOUT:
			return "ERR_TIMEOUT"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "ERR_REQUEST_FAILED"
		_:
			return "UNKNOWN_ERROR (%d)" % error_code
