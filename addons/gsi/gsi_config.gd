class_name GSIConfig
extends RefCounted

var id: String = ""
var description: String = ""
var type: String = "http"

var uri: String = ""
var port: int = 0
var timeout: float = 5.0
var buffer: float = 0.1
var throttle: float = 0.25
var heartbeat: float = 10.0

var auth_token: String = ""
var data_sections: Dictionary = {}

var tls_verification_enabled: bool = true
var tls_certificate_path: String = ""
var tls_key_path: String = ""

var websocket_protocols: PackedStringArray = []


static func from_file(file_path: String) -> GSIConfig:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		GSILogger.log_gsi(
			"[GSIConfig] Failed to open config file: %s" % file_path, GSILogger.LogLevel.ERROR
		)
		return null

	var content: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var error: Error = json.parse(content)

	if error != OK:
		GSILogger.log_gsi(
			(
				"[GSIConfig] Failed to parse JSON from config file %s: %s at line %d"
				% [file_path, json.get_error_message(), json.get_error_line]
			),
			GSILogger.LogLevel.ERROR
		)
		return null

	var root_data: Dictionary = json.data
	if typeof(root_data) != TYPE_DICTIONARY:
		GSILogger.log_gsi(
			"[GSIConfig] Config file %s: Root element is not a dictionary." % file_path,
			GSILogger.LogLevel.ERROR
		)
		return null

	return GSIConfig.from_dictionary(root_data)


static func from_dictionary(config_dict: Dictionary) -> GSIConfig:
	var new_config := GSIConfig.new()

	new_config.id = config_dict.get("id", "")
	if new_config.id.is_empty():
		GSILogger.log_gsi(
			"[GSIConfig] Config dictionary missing 'id' field at top level.",
			GSILogger.LogLevel.ERROR
		)
		return null

	new_config.description = config_dict.get("description", "Unnamed GSI Configuration")
	new_config.type = config_dict.get("type", "http")

	var raw_config: Dictionary = config_dict.get("config", {})
	if raw_config.is_empty():
		GSILogger.log_gsi(
			(
				"[GSIConfig] GSIConfig for ID '%s': 'config' section is missing or empty."
				% new_config.id
			),
			GSILogger.LogLevel.ERROR
		)
		return null

	new_config.timeout = float(raw_config.get("timeout", 5.0))
	new_config.buffer = float(raw_config.get("buffer", 0.1))
	new_config.throttle = float(raw_config.get("throttle", 0.25))
	new_config.heartbeat = float(raw_config.get("heartbeat", 10.0))
	new_config.auth_token = raw_config.get("auth", {}).get("token", "")
	new_config.data_sections = raw_config.get("data", {})

	match new_config.type:
		"http":
			new_config.uri = raw_config.get("uri", "")
			new_config.tls_verification_enabled = raw_config.get("tls_verification_enabled", true)
			if new_config.uri.is_empty():
				(
					GSILogger
					. log_gsi(
						(
							"[GSIConfig] GSIConfig for ID '%s' (type 'http'): 'uri' field is missing or empty."
							% new_config.id
						),
						GSILogger.LogLevel.ERROR
					)
				)
				return null
		"websocket_server":
			new_config.port = int(raw_config.get("port", 0))
			new_config.tls_certificate_path = raw_config.get("tls_certificate_path", "")
			new_config.tls_key_path = raw_config.get("tls_key_path", "")
			if new_config.port <= 1024 or new_config.port > 65535:
				GSILogger.log_gsi(
					(
						"[GSIConfig] GSIConfig for ID '%s' (type 'websocket_server'): "
						+ "'port' field is invalid (%s)." % [new_config.id, new_config.port]
					),
					GSILogger.LogLevel.ERROR
				)
				return null
			if (
				not new_config.tls_certificate_path.is_empty()
				and new_config.tls_key_path.is_empty()
			):
				GSILogger.log_gsi(
					(
						"[GSIConfig] GSIConfig for ID '%s' (type 'websocket_server'):"
						+ "'tls_certificate_path' provided without 'tls_key_path'." % new_config.id
					),
					GSILogger.LogLevel.ERROR
				)
				return null
			if (
				new_config.tls_key_path.is_empty()
				and not new_config.tls_certificate_path.is_empty()
			):
				GSILogger.log_gsi(
					(
						"[GSIConfig] GSIConfig for ID '%s' (type 'websocket_server'): "
						+ "'tls_key_path' provided without 'tls_certificate_path'." % new_config.id
					)
				)
				return null
		"websocket_client":
			new_config.uri = raw_config.get("uri", "")
			new_config.websocket_protocols = raw_config.get(
				"websocket_protocols", PackedStringArray()
			)
			new_config.tls_verification_enabled = raw_config.get("tls_verification_enabled", true)
			if new_config.uri.is_empty():
				GSILogger.log_gsi(
					(
						"[GSIConfig] GSIConfig for ID '%s' (type 'websocket_client'):"
						+ "'uri' field is missing or empty." % new_config.id
					),
					GSILogger.LogLevel.ERROR
				)
				return null
			if not (new_config.uri.begins_with("ws://") or new_config.uri.begins_with("wss://")):
				GSILogger.log_gsi(
					(
						"[GSIConfig] GSIConfig for ID '%s' (type 'websocket_client'):"
						+ " 'uri' must start with 'ws://' or 'wss://'." % new_config.id
					),
					GSILogger.LogLevel.ERROR
				)
				return null
		_:
			GSILogger.log_gsi(
				(
					"[GSIConfig] GSIConfig for ID '%s': Unknown endpoint type '%s'."
					% [new_config.id, new_config.type]
				),
				GSILogger.LogLevel.ERROR
			)
			return null

	return new_config


func is_valid() -> bool:
	if id.is_empty():
		return false

	match type:
		"http":
			return not uri.is_empty()
		"websocket_server":
			return port > 1024 and port <= 65535
		"websocket_client":
			return not uri.is_empty() and (uri.begins_with("ws://") or uri.begins_with("wss://"))
	return false


func _to_string() -> String:
	var s: String = "GSIConfig(ID: %s, Desc: '%s', Type: %s, " % [id, description, type]
	match type:
		"http":
			s += "URI: %s, TLS Verify: %s, " % [uri, str(tls_verification_enabled)]
		"websocket_server":
			s += "Port: %s, TLS Cert: %s, " % [str(port), not tls_certificate_path.is_empty()]
		"websocket_client":
			s += (
				"URI: %s, Protocols: %s, TLS Verify: %s, "
				% [uri, str(websocket_protocols), str(tls_verification_enabled)]
			)

	s += (
		"Timeout: %s, Buffer: %s, Throttle: %s, Heartbeat: %s"
		% [str(timeout), str(buffer), str(throttle), str(heartbeat)]
	)
	if not auth_token.is_empty():
		s += ", Auth: ***"
	if not data_sections.is_empty():
		s += ", Data Sections: %s" % JSON.stringify(data_sections)
	s += ")"
	return s
