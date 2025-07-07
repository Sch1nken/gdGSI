extends Node

const GSI_CONFIG_FOLDER: StringName = "gamestate_integration/"
const GSI_CONFIG_PATTERN: StringName = "^gamestate_integration_.*\\.json$"

var gsi_enabled: bool = false
var _gsi_dir: StringName = "res://addons/gsi/"

var _game_state: Dictionary = {
	"provider":
	{
		"name": ProjectSettings.get_setting("application/config/name", "???"),
		"version": ProjectSettings.get_setting("application/config/version"),
		"timestamp": 0
	},
	"auth": {"token": ""}
}

var _endpoints: Dictionary[StringName, GSIBaseClient] = {}


func _update_game_state_and_queue_send() -> void:
	_game_state.provider.timestamp = Time.get_unix_time_from_system()

	for endpoint_id: StringName in _endpoints:
		var client: GSIBaseClient = _endpoints[endpoint_id]
		var config: GSIConfig = client.config

		var current_filtered_state: Dictionary = {}
		current_filtered_state.provider = clone_value(_game_state.provider)
		current_filtered_state.auth = {"token": config.auth_token}

		for section_name: StringName in config.data_sections:
			if config.data_sections.get(section_name, false) and _game_state.has(section_name):
				current_filtered_state[section_name] = clone_value(_game_state[section_name])

		var payload_to_send: Dictionary = clone_value(current_filtered_state)
		var previously: Dictionary = {}
		var added: Dictionary = {}

		if not client.last_sent_game_state.is_empty():
			for key: StringName in current_filtered_state:
				if client.last_sent_game_state.has(key):
					if (
						JSON.stringify(current_filtered_state[key])
						!= JSON.stringify(client.last_sent_game_state[key])
					):
						previously[key] = clone_value(client.last_sent_game_state[key])
				else:
					added[key] = clone_value(current_filtered_state[key])

		if not previously.is_empty():
			payload_to_send.previously = previously
		if not added.is_empty():
			payload_to_send.added = added

		client.queue_send(payload_to_send)


func set_section_data(section_name: String, data_to_merge: Dictionary) -> void:
	if not _game_state.has(section_name) or typeof(_game_state[section_name]) != TYPE_DICTIONARY:
		_game_state[section_name] = {}
	_game_state[section_name].merge(data_to_merge, true)
	GSILogger.log_gsi(
		(
			"[GSI] Central state: Section '%s' updated: %s"
			% [section_name, JSON.stringify(data_to_merge)]
		),
		GSILogger.LogLevel.DEBUG
	)
	_update_game_state_and_queue_send()


func set_provider_info(provider_data: Dictionary) -> void:
	_game_state.provider.merge(provider_data, true)
	GSILogger.log_gsi(
		"[GSI] Central state: Provider info updated: %s" % JSON.stringify(provider_data)
	)
	_update_game_state_and_queue_send()


func set_custom_data(key: String, value: Variant) -> void:
	_game_state[key] = value
	GSILogger.log_gsi(
		"[GSI] Central state: Custom data '%s' updated: %s" % [key, JSON.stringify(value)],
		GSILogger.LogLevel.DEBUG
	)
	_update_game_state_and_queue_send()


func remove_custom_data(key: String) -> void:
	if not _game_state.has(key):
		GSILogger.log_gsi(
			"[GSI] Central state: Attempted to remove non-existent custom data '%s'." % key,
			GSILogger.LogLevel.WARN
		)
		return
	_game_state.erase(key)
	GSILogger.log_gsi(
		"[GSI] Central state: Custom data '%s' removed." % key, GSILogger.LogLevel.DEBUG
	)
	_update_game_state_and_queue_send()


func add_endpoint(config_instance: GSIConfig) -> void:
	var endpoint_id: StringName = config_instance.id
	var client_instance: GSIBaseClient = null

	if _endpoints.has(endpoint_id):
		GSILogger.log_gsi(
			"[GSI] Endpoint '%s' already exists. Replacing existing endpoint." % endpoint_id,
			GSILogger.LogLevel.WARN
		)
		remove_endpoint(endpoint_id)

	match config_instance.type:
		"http":
			client_instance = GSIHTTPClient.new(config_instance)
		"websocket_server":
			if OS.has_feature("web"):
				GSILogger.log_gsi(
					(
						"[GSI] Endpoint '%s' (type 'websocket_server') skipped: "
						+ "WebSocketServer is not supported in HTML5 exports." % endpoint_id
					),
					GSILogger.LogLevel.ERROR
				)
				return
			client_instance = GSIWebSocketServer.new(config_instance)
		"websocket_client":
			client_instance = GSIWebSocketClient.new(config_instance)
		_:
			GSILogger.log_gsi(
				(
					"[GSI] Unknown endpoint type '%s' for ID '%s'. Skipping."
					% [config_instance.type, endpoint_id]
				),
				GSILogger.LogLevel.ERROR
			)
			return

	if not is_instance_valid(client_instance):
		GSILogger.log_gsi(
			(
				"Client instance for endpoint type '%s' for ID '%s' could not be created "
				+ "(this should not happen). Skipping." % [config_instance.type, endpoint_id]
			),
			GSILogger.LogLevel.ERROR
		)
		return

	add_child(client_instance)
	_endpoints[endpoint_id] = client_instance
	GSILogger.log_gsi(
		(
			"[GSI] Endpoint '%s' added (Type: %s): %s"
			% [endpoint_id, config_instance.type, config_instance]
		)
	)

	var initial_filtered_state: Dictionary = {}
	initial_filtered_state.provider = clone_value(_game_state.provider)
	initial_filtered_state.auth = {"token": config_instance.auth_token}

	for section_name: StringName in config_instance.data_sections:
		if config_instance.data_sections.get(section_name, false) and _game_state.has(section_name):
			initial_filtered_state[section_name] = clone_value(_game_state[section_name])

	var initial_payload_to_send: Dictionary = clone_value(initial_filtered_state)
	initial_payload_to_send.added = clone_value(initial_filtered_state)

	client_instance.queue_send(initial_payload_to_send)
	client_instance._reset_heartbeat_timer()


func remove_endpoint(endpoint_id: String) -> void:
	if not _endpoints.has(endpoint_id):
		GSILogger.log_gsi(
			"[GSI] Attempted to remove non-existent endpoint '%s'." % endpoint_id,
			GSILogger.LogLevel.WARN
		)
		return

	var client: GSIBaseClient = _endpoints[endpoint_id]
	if not is_instance_valid(client):
		(
			GSILogger
			. log_gsi(
				(
					"[GSI] Endpoint '%s' found in _endpoints, but client instance is invalid. Removing entry."
					% endpoint_id
				),
				GSILogger.LogLevel.ERROR
			)
		)
		_endpoints.erase(endpoint_id)
		return

	client.queue_free()
	_endpoints.erase(endpoint_id)
	GSILogger.log_gsi("[GSI] Endpoint '%s' removed." % endpoint_id)


func initialize_endpoints(endpoint_configs: Array[GSIConfig]) -> void:
	if not _endpoints.is_empty():
		(
			GSILogger
			. log_gsi(
				"[GSI] GSI Sender already initialized. Clearing existing endpoints for re-initialization.",
				GSILogger.LogLevel.WARN
			)
		)
		for endpoint_id: StringName in _endpoints.keys():
			remove_endpoint(endpoint_id)
		_endpoints.clear()

	if endpoint_configs.is_empty():
		GSILogger.log_gsi(
			"[GSI] No valid GSI endpoint configurations provided. Plugin will not send data.",
			GSILogger.LogLevel.WARN
		)
		return

	for config_instance: GSIConfig in endpoint_configs:
		add_endpoint(config_instance)

	GSILogger.log_gsi(
		"[GSI] GSI Sender plugin ready with %d endpoints." % _endpoints.size(),
		GSILogger.LogLevel.INFO
	)


func clone_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
		return value.duplicate(true)
	return value


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var args: PackedStringArray = OS.get_cmdline_args()
	gsi_enabled = args.has("--gamestateintegration")

	if not gsi_enabled:
		return

	GSILogger.log_gsi(
		"[GSI] GSI Sender plugin _ready. Loading configs from file paths...",
		GSILogger.LogLevel.INFO
	)

	if not OS.has_feature("editor"):
		_gsi_dir = StringName(OS.get_executable_path().get_base_dir())

	var full_folder_path: String = _gsi_dir.path_join(GSI_CONFIG_FOLDER)
	var dir_access: DirAccess = DirAccess.open(full_folder_path)

	if dir_access == null:
		gsi_enabled = false
		GSILogger.log_gsi(
			"[GSI] Folder '%s' not found, aborting GSI startup" % full_folder_path,
			GSILogger.LogLevel.ERROR
		)
		return

	var regex: RegEx = RegEx.new()
	var compile_error: Error = regex.compile(GSI_CONFIG_PATTERN, true)

	if compile_error != OK:
		gsi_enabled = false
		GSILogger.log_gsi(
			"[GSI] Failed to compile regex: %d, aborting GSI startup" % compile_error,
			GSILogger.LogLevel.ERROR
		)
		return

	var found_config_files: Array[String] = []

	GSILogger.log_gsi(
		(
			"[GSI] Searching for filenames matching pattern: '%s' in '%s'"
			% [GSI_CONFIG_PATTERN, full_folder_path]
		),
		GSILogger.LogLevel.DEBUG
	)
	dir_access.list_dir_begin()
	var file_name: String = dir_access.get_next()
	while file_name != "":
		if dir_access.current_is_dir():
			file_name = dir_access.get_next()
			continue

		var is_match: RegExMatch = regex.search(file_name)
		if is_match:
			found_config_files.push_back(full_folder_path.path_join(file_name))

		file_name = dir_access.get_next()
	dir_access.list_dir_end()

	var loaded_configs: Array[GSIConfig] = []

	GSILogger.log_gsi(
		"[GSI] Found %d config files matching criteria" % found_config_files.size(),
		GSILogger.LogLevel.INFO
	)
	for config_path: String in found_config_files:
		GSILogger.log_gsi("-> %s" % config_path, GSILogger.LogLevel.DEBUG)
		var cfg: GSIConfig = GSIConfig.from_file(config_path)
		if cfg != null and cfg.is_valid():
			loaded_configs.push_back(cfg)

	initialize_endpoints(loaded_configs)

	#GSILogger.log_gsi("--- Starting simulated game events (for demonstration) ---")
	#await get_tree().create_timer(2.0).timeout
	#set_section_data("player", {"name": "GodotPlayer", "health": 90, "money": 100})
	#await get_tree().create_timer(1.0).timeout
	#set_section_data("player", {"health": 80})
	#await get_tree().create_timer(3.0).timeout
	#set_custom_data("player_rank", "Gold Nova")
	#await get_tree().create_timer(2.0).timeout
	#set_section_data("inventory", {"weapon": "pistol", "ammo": 12})
	#await get_tree().create_timer(2.0).timeout
	#set_section_data("inventory", {"ammo": 8, "grenades": 2})
	#await get_tree().create_timer(2.0).timeout
	#set_custom_data("player_rank", "Master Guardian")
	#await get_tree().create_timer(2.0).timeout
	#remove_custom_data("player_rank")
	#await get_tree().create_timer(5.0).timeout
	#set_section_data("map", {"name": "godot_level_1", "phase": "live"})
	#set_section_data("map_round", {"number": 2, "phase": "freezetime"})
	#await get_tree().create_timer(5.0).timeout
	#set_section_data("map_round", {"phase": "playing"})
	#await get_tree().create_timer(15.0).timeout
	#set_section_data("player", {"health": 0, "activity": "dead"})
	#set_section_data("map", {"phase": "gameover"})
	#
	#GSILogger.log_gsi("--- Demonstrating runtime endpoint management ---")
	#await get_tree().create_timer(5.0).timeout
	#
	#var new_config_dict: Dictionary = {
	#"id": "dynamic_overlay",
	#"description": "Dynamically added HTTP endpoint for a special overlay",
	#"type": "http",
	#"config": {
	#"uri": "http://127.0.0.1:5001/dynamic_gsi",
	#"timeout": 3.0,
	#"buffer": 1.0,
	#"throttle": 1.0,
	#"heartbeat": 20.0,
	#"data": {
	#"player": 1,
	#"abilities": 1
	#},
	#"auth": {
	#"token": "dynamic_token_123"
	#},
	#"tls_verification_enabled": false
	#}
	#}
	#var dynamic_gsi_config: GSIConfig = GSIConfig.from_dictionary(new_config_dict)
	#if dynamic_gsi_config:
	#add_endpoint(dynamic_gsi_config)
	#set_section_data("abilities", {"ability_a": "ready", "ability_b": "cooldown"})
	#
	#await get_tree().create_timer(10.0).timeout
	#
	#remove_endpoint("main_display_endpoint")
	#GSILogger.log_gsi("Removed 'main_display_endpoint'.")
	#
	#await get_tree().create_timer(5.0).timeout
	#
	#GSILogger.log_gsi("--- Demonstrating throttling with rapid updates ---")
	#var throttle_test_config_dict: Dictionary = {
	#"id": "throttle_test_endpoint",
	#"description": "Endpoint for testing throttling",
	#"type": "http",
	#"config": {
	#"uri": "http://127.0.0.1:5003/throttle_test",
	#"timeout": 3.0,
	#"buffer": 0.05,
	#"throttle": 0.5,
	#"heartbeat": 10.0,
	#"data": {
	#"player": 1
	#},
	#"auth": {
	#"token": "throttle_token"
	#}
	#}
	#}
	#var throttle_gsi_config: GSIConfig = GSIConfig.from_dictionary(throttle_test_config_dict)
	#if throttle_gsi_config:
	#add_endpoint(throttle_gsi_config)
	#
	#for i in range(10):
	#set_section_data("player", {"health": 100 - (i * 5)})
	#await get_tree().create_timer(0.01).timeout
	#
	#GSILogger.log_gsi("Finished rapid updates. Observe throttle_test_endpoint behavior.")
	#await get_tree().create_timer(5.0).timeout
	#remove_endpoint("throttle_test_endpoint")
	#GSILogger.log_gsi("Removed 'throttle_test_endpoint'.")
	#
	#await get_tree().create_timer(5.0).timeout
	#GSILogger.log_gsi("--- Simulated game events finished ---")
