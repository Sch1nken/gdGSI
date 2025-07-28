extends Node

const GSI_CONFIG_FOLDER: StringName = "gamestate_integration/"
const GSI_CONFIG_PATTERN: StringName = "^gamestate_integration_.*\\.json$"
const RESERVED_KEYS: Array[String] = ["added", "removed", "previously", "provider", "auth", "data"]

var gsi_enabled: bool = false
# In editor, it defaults to `res://addons/gsi/`.
# In builds, it's overwritten to the executable's base directory.
var _gsi_dir: StringName = "res://addons/gsi/"

var _default_game_state: Dictionary = {
	"provider":
	{
		"name": ProjectSettings.get_setting("application/config/name", "???"),
		"version": ProjectSettings.get_setting("application/config/version"),
		"timestamp": 0
	},
	"auth": {"token": ""},
	"data": {}
}

var _game_state: Dictionary = _default_game_state.duplicate(true)
var _endpoints: Dictionary[StringName, GSIBaseClient] = {}

# NOTE: Currently unused, this will later be used to prevent
# set_custom_data to override keys created by set_section_data
# and vice versa... maybe there is a better way.
# Maybe custom_data should be nested under its own dictionary key
# "custom_data" or something.
# Will re-evualuate...
var _section_keys: Array[String] = []
var _custom_keys: Array[String] = []
# NOTE: using remove_nested_section_data requires an up to date state
# For this all pending updates are processed
# Structure: { "section_name": [{update1}, {update2}], ... }
var _pending_section_updates: Dictionary = {}
# Structure: { "custom_key": value, ... }
var _pending_custom_data_updates: Dictionary = {}
# Array to buffer top-level section removals
var _pending_removals_sections: Array[String] = []
# Array to buffer top-level custom data removals
var _pending_removals_custom: Array[String] = []

var _has_pending_updates: bool = false

var _is_paused: bool = false

#region Pause


# All internal timers (buffer, throttle, heartbeat) for all endpoints will be stopped.
# WebSocket connections will NOT be interrupted, but no data will be sent.
func pause_gsi() -> void:
	if _is_paused:
		GSILogger.log_gsi("GSI Sender is already paused.", GSILogger.LogLevel.INFO)
		return

	_is_paused = true
	for endpoint_id: StringName in _endpoints:
		var client: GSIBaseClient = _endpoints[endpoint_id]
		if is_instance_valid(client):
			client.pause_timers()

	GSILogger.log_gsi(
		"GSI Sender paused. No further updates will be sent until resumed.", GSILogger.LogLevel.INFO
	)


# Internal timers for all endpoints will be restarted.
func resume_gsi() -> void:
	if not _is_paused:
		GSILogger.log_gsi("GSI Sender is not paused.", GSILogger.LogLevel.INFO)
		return

	_is_paused = false
	for endpoint_id: StringName in _endpoints:
		var client: GSIBaseClient = _endpoints[endpoint_id]
		if is_instance_valid(client):
			client.resume_timers()

	# Might not be necessary, but also might prevent issues
	# _process_pending_updates()

	GSILogger.log_gsi("GSI Sender resumed. Updates will now be sent.", GSILogger.LogLevel.INFO)


func is_paused() -> bool:
	return _is_paused


#endregion

#region Data


func set_section_data(section_name: String, data_to_merge: Dictionary) -> void:
	if _pending_removals_sections.has(section_name):
		_pending_removals_sections.erase(section_name)
		(
			GSILogger
			. log_gsi(
				(
					"Central state: Cancelled pending removal for section '%s' due to new set operation."
					% section_name
				),
				GSILogger.LogLevel.DEBUG
			)
		)

	if not _pending_section_updates.has(section_name):
		_pending_section_updates[section_name] = []

	_pending_section_updates[section_name].push_back(data_to_merge)
	_has_pending_updates = true

	GSILogger.log_gsi(
		(
			"Central state: Section '%s' update buffered: %s"
			% [section_name, JSON.stringify(data_to_merge)]
		),
		GSILogger.LogLevel.DEBUG
	)


func remove_section_data(section_name: String, removal_pattern: Dictionary) -> void:
	if section_name.is_empty():
		GSILogger.log_gsi(
			"remove_section_data: Section name cannot be empty.", GSILogger.LogLevel.WARN
		)
		return

	if removal_pattern.is_empty():
		(
			GSILogger
			. log_gsi(
				"remove_nested_data_by_dictionary: Empty removal pattern provided. Use remove_section instead.",
				GSILogger.LogLevel.WARN
			)
		)
		return

	# Progress pending updates to prevent them being added later after we removed something
	_process_pending_updates()

	if not _game_state.data.has(section_name):
		GSILogger.log_gsi(
			(
				"remove_section_data: Section '%s' not found in game state. Skipping removal."
				% section_name
			),
			GSILogger.LogLevel.WARN
		)
		return

	var target_section: Variant = _game_state.data[section_name]
	if typeof(target_section) != TYPE_DICTIONARY:
		(
			GSILogger
			. log_gsi(
				(
					"remove_section_data: Section '%s' is not a dictionary. Cannot apply nested removal pattern."
					% section_name
				),
				GSILogger.LogLevel.WARN
			)
		)
		return

	# Start the recursive removal from the root of _game_state
	if _recursive_remove_by_pattern(target_section, removal_pattern, section_name):
		# Only update if something was actually removed
		_has_pending_updates = true
		_update_game_state_and_queue_send()


func remove_section(section_name: String) -> void:
	if _pending_section_updates.has(section_name):
		# If we remove the section anyways, all previously occuring updates will be
		# removed anyways :)
		_pending_section_updates.erase(section_name)
		GSILogger.log_gsi(
			(
				"Central state: Cleared pending updates for section '%s' due to removal request."
				% section_name
			),
			GSILogger.LogLevel.DEBUG
		)

	# Add pending removal
	if not _pending_removals_sections.has(section_name):
		_pending_removals_sections.push_back(section_name)
		_has_pending_updates = true
		GSILogger.log_gsi(
			"Central state: Section '%s' marked for removal (buffered)." % section_name,
			GSILogger.LogLevel.INFO
		)
	else:
		GSILogger.log_gsi(
			"Central state: Section '%s' already marked for removal." % section_name,
			GSILogger.LogLevel.WARN
		)


func set_custom_data(key: String, value: Variant) -> void:
	if key in RESERVED_KEYS:
		GSILogger.log_gsi("Tried to set reservered key '%s'. Skipping.", GSILogger.LogLevel.WARN)
		return

	if _pending_removals_custom.has(key):
		_pending_removals_custom.erase(key)
		(
			GSILogger
			. log_gsi(
				(
					"Central state: Cancelled pending removal for custom data '%s' due to new set operation."
					% key
				),
				GSILogger.LogLevel.DEBUG
			)
		)

	_pending_custom_data_updates[key] = value
	_has_pending_updates = true
	GSILogger.log_gsi(
		"Central state: Custom data '%s' update buffered: %s" % [key, JSON.stringify(value)],
		GSILogger.LogLevel.DEBUG
	)


func remove_custom_data(key: String) -> void:
	# Prevent removing reserved top-level keys or the 'data' container itself via custom data removal
	if key in RESERVED_KEYS:
		GSILogger.log_gsi(
			(
				"Central state: Attempted to remove reserved top-level key '%s'."
				+ (
					" Operation blocked. Use remove_section for sections or avoid reserved names."
					% key
				)
			),
			GSILogger.LogLevel.WARN
		)
		return

	# If there are pending updates for this custom key, clear them as the key will be removed
	if _pending_custom_data_updates.has(key):
		_pending_custom_data_updates.erase(key)
		(
			GSILogger
			. log_gsi(
				(
					"Central state: Cleared pending updates for custom data '%s' due to removal request."
					% key
				),
				GSILogger.LogLevel.DEBUG
			)
		)

	# Add to pending removals
	if not _pending_removals_custom.has(key):
		_pending_removals_custom.append(key)
		_has_pending_updates = true
		GSILogger.log_gsi(
			"Central state: Custom data '%s' marked for removal (buffered)." % key,
			GSILogger.LogLevel.INFO
		)
	else:
		GSILogger.log_gsi(
			"Central state: Custom data '%s' already marked for removal." % key,
			GSILogger.LogLevel.WARN
		)


func set_provider_info(provider_data: Dictionary) -> void:
	# We can use merge here since provider is flat
	# By default Godot's Dictionary.merge() does not work recursively
	_game_state.provider.merge(provider_data, true)
	GSILogger.log_gsi(
		"[GSI] Central state: Provider info updated: %s" % JSON.stringify(provider_data)
	)
	_update_game_state_and_queue_send()


#endregion

#region Endpoints


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
		if (
			config_instance.data_sections.get(section_name, false)
			and _game_state.data.has(section_name)
		):
			initial_filtered_state[section_name] = clone_value(_game_state.data[section_name])

	var initial_payload_to_send: Dictionary = clone_value(initial_filtered_state)
	initial_payload_to_send.added = clone_value(initial_filtered_state)

	client_instance.queue_send(initial_payload_to_send)

	if _is_paused:
		client_instance.pause_timers()
		# Pause timers when GSI is paused
	else:
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


#endregion

#region Helper


func clone_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
		return value.duplicate(true)
	return value


func _deep_merge_dictionaries(target: Dictionary, source: Dictionary) -> Dictionary:
	var result: Dictionary = target.duplicate(true)  # Start with a deep copy of the target
	for key: Variant in source:
		if (
			result.has(key)
			and typeof(result[key]) == TYPE_DICTIONARY
			and typeof(source[key]) == TYPE_DICTIONARY
		):
			result[key] = _deep_merge_dictionaries(result[key], source[key])
		else:
			result[key] = clone_value(source[key])

	return result


#endregion

#region Internal


func _physics_process(_delta: float) -> void:
	# We use call_deferred to be absolutely sure were late in the tick
	# We _could_ make use of process priority and the like, but oh well :)
	call_deferred("_process_pending_updates")
	#_process_pending_updates()


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


#endregion

#region Private


# This function calculates 'previously', 'added', and 'removed' fields for each endpoints payload.
func _update_game_state_and_queue_send() -> void:
	if _is_paused:
		GSILogger.log_gsi(
			"GSI Sender is paused. Skipping state update and send queue.", GSILogger.LogLevel.DEBUG
		)
		return

	_game_state.provider.timestamp = Time.get_unix_time_from_system()

	for endpoint_id: StringName in _endpoints:
		var client: GSIBaseClient = _endpoints[endpoint_id]
		var config: GSIConfig = client.config

		var current_filtered_state: Dictionary = {}
		current_filtered_state.provider = clone_value(_game_state.provider)
		current_filtered_state.auth = {"token": config.auth_token}

		# Populate current_filtered_state with relevant sections and custom data from _game_state.data
		for key_in_data_section: Variant in _game_state.data:
			# Only include keys explicitly enabled in the config's data_sections
			if config.data_sections.get(key_in_data_section, false):
				current_filtered_state[key_in_data_section] = clone_value(
					_game_state.data[key_in_data_section]
				)

		var payload_to_send: Dictionary = clone_value(current_filtered_state)
		var previously: Dictionary = {}
		var added: Dictionary = {}
		var removed: Dictionary = {}  # New: Dictionary for removed keys

		var simple_removal_state: Dictionary = client.last_sent_game_state.duplicate(true)
		simple_removal_state.erase("added")
		simple_removal_state.erase("previously")
		simple_removal_state.erase("removed")

		# Calculate 'previously', 'added', and 'removed' sections
		if not client.last_sent_game_state.is_empty():
			# Calculate 'previously' recursively for changed values
			if config.use_previously:
				_find_granular_previously_recursive(
					current_filtered_state, simple_removal_state, previously
				)

			# New: Calculate 'removed' for keys no longer present at any depth
			if config.use_removed:
				_find_granular_removed_recursive(
					current_filtered_state, simple_removal_state, removed
				)

		# Always handle added, since even for empty states everything is "added"
		if config.use_added:
			_find_granular_added_recursive(current_filtered_state, simple_removal_state, added)

		# Add 'previously', 'added', and 'removed' to the payload if they contain data
		if not previously.is_empty():
			payload_to_send.previously = previously
		if not added.is_empty():
			payload_to_send.added = added
		if not removed.is_empty():  # New: Add removed section
			payload_to_send.removed = removed

		client.queue_send(payload_to_send)


func _deep_equals(val1: Variant, val2: Variant) -> bool:
	if typeof(val1) != typeof(val2):
		return false

	if typeof(val1) == TYPE_DICTIONARY:
		var dict1: Dictionary = val1
		var dict2: Dictionary = val2
		if dict1.size() != dict2.size():
			return false
		for key: Variant in dict1:
			if not dict2.has(key) or not _deep_equals(dict1[key], dict2[key]):
				return false
		return true
	if typeof(val1) == TYPE_ARRAY:
		var arr1: Array = val1
		var arr2: Array = val2
		if arr1.size() != arr2.size():
			return false
		for i in range(arr1.size()):
			if not _deep_equals(arr1[i], arr2[i]):
				return false
		return true

	# For all other types (int, float, String, bool, Vector2, etc.), direct comparison is sufficient.
	# gdlint:ignore = max-returns
	return val1 == val2


# Clear the whole state. Useful for when leaving the game and going back to the
# main menu or similiar
# Additionally a "state" section could be set (afterwards) to show the current "screen"
# i.e. state = game, state = main menu (with not actual state data etc).
# TODO: Check if we want to immediately send data or also queue this like set_section_data does...
# Because this will surely lead to bugs with paused states and other things
func clear_gsi_state() -> void:
	_pending_section_updates.clear()
	_pending_custom_data_updates.clear()
	_pending_removals_sections.clear()
	_pending_removals_custom.clear()
	_has_pending_updates = false

	_game_state = _default_game_state.duplicate(true)
	GSILogger.log_gsi("Central state: Completely cleared.", GSILogger.LogLevel.INFO)

	# Trigger a send. This send will compare the now-empty _game_state
	# with each client's last_sent_game_state, correctly populating 'removed'.
	_update_game_state_and_queue_send()

	# After the 'removed' payload has been queued, reset each client's
	# last_sent_game_state to ensure the next update is treated as 'added'
	for endpoint_id: StringName in _endpoints:
		var client: GSIBaseClient = _endpoints[endpoint_id]
		if is_instance_valid(client):
			client.last_sent_game_state = {}
			# Reset heartbeat to send the new empty state if needed
			client._reset_heartbeat_timer()

	GSILogger.log_gsi(
		"All clients' last_sent_game_state reset after state clear.", GSILogger.LogLevel.DEBUG
	)


# recursively finds changed values in `current_data` compared to `previous_data`
# and populates `previously_output` with the *old* values of only those changed items.
func _find_granular_previously_recursive(
	current_data: Variant, previous_data: Variant, previously_output: Dictionary
) -> void:
	# Can't compare if previous_data is not a dictionary
	if typeof(previous_data) != TYPE_DICTIONARY:
		return

	# Iterate over keys that were present in the previous data
	for key: Variant in previous_data:
		var previous_value: Variant = previous_data[key]

		if not current_data.has(key):
			# Case 1: Key was in previous_data but is NOT in current_data -> removed
			previously_output[key] = clone_value(previous_value)
		else:
			var current_value: Variant = current_data[key]

			# Ensure both are dictionaries for recursive comparison
			if (
				typeof(previous_value) == TYPE_DICTIONARY
				and typeof(current_value) == TYPE_DICTIONARY
			):
				# Case 2: Both are dictionaries
				# recurse to find nested changes or removals within this sub-dictionary.
				var nested_previously: Dictionary = {}
				_find_granular_previously_recursive(
					current_value, previous_value, nested_previously
				)
				if not nested_previously.is_empty():
					previously_output[key] = nested_previously
			else:
				# Case 3: Not both dictionaries (primitive, array, or type mismatch).
				# If the value has changed, add the *old* value to 'previously'.
				if not _deep_equals(current_value, previous_value):
					previously_output[key] = clone_value(previous_value)


func _find_granular_added_recursive(
	current_data: Variant, previous_data: Variant, added_output: Dictionary
) -> void:
	if typeof(current_data) == TYPE_DICTIONARY or typeof(previous_data) == TYPE_DICTIONARY:
		for key: Variant in current_data:
			if not previous_data.has(key):
				# Key is new in current_data, add its value (deep clone)
				added_output[key] = clone_value(current_data[key])
			elif (
				typeof(current_data[key]) == TYPE_DICTIONARY
				and typeof(previous_data[key]) == TYPE_DICTIONARY
			):
				# Both are dictionaries, recurse
				# I wonder if we could cheese it by doing string manipulation stuff on
				# two JSON representations? Basically a string "diff"
				var nested_added: Dictionary = {}
				_find_granular_added_recursive(current_data[key], previous_data[key], nested_added)
				if not nested_added.is_empty():
					added_output[key] = nested_added

		# If current_data is a dictionary, but previous_data is not,
		# or if types don't match, the whole current_data is considered 'new' for this key
		# (but this scenario is handled by the top-level loop for 'added' if the key itself is new)


func _find_granular_removed_recursive(
	current_data: Variant, previous_data: Variant, removed_output: Dictionary
) -> void:
	if typeof(current_data) == TYPE_DICTIONARY and typeof(previous_data) == TYPE_DICTIONARY:
		for key: Variant in previous_data:
			if not current_data.has(key):
				# Key was in previous_data but not in current_data, so it's removed
				removed_output[key] = clone_value(previous_data[key])
			elif (
				typeof(current_data[key]) == TYPE_DICTIONARY
				and typeof(previous_data[key]) == TYPE_DICTIONARY
			):
				# Both are dictionaries, recurse
				var nested_removed: Dictionary = {}
				_find_granular_removed_recursive(
					current_data[key], previous_data[key], nested_removed
				)
				if not nested_removed.is_empty():
					removed_output[key] = nested_removed
		# Similar logic for type mismatches as in _find_granular_added_recursive,
		# where if a type changes from dict to non-dict, the whole key might be considered 'removed'
		# from its previous dict structure.


func _recursive_remove_by_pattern(
	current_state_node: Dictionary, pattern_to_apply: Dictionary, current_full_path: String
) -> bool:
	var removed_any_data: bool = false

	for key: Variant in pattern_to_apply.keys():
		var next_path_segment: String = current_full_path.path_join(key)

		if not current_state_node.has(key):
			GSILogger.log_gsi(
				"Key '%s' not found at path '%s'. Skipping removal." % [key, next_path_segment],
				GSILogger.LogLevel.WARN
			)
			continue

		var value_in_pattern: Variant = pattern_to_apply[key]
		var value_in_state: Variant = current_state_node[key]

		if typeof(value_in_pattern) == TYPE_DICTIONARY and not value_in_pattern.is_empty():
			# If the pattern has a non-empty dictionary, recurse
			if typeof(value_in_state) == TYPE_DICTIONARY:
				if _recursive_remove_by_pattern(
					value_in_state, value_in_pattern, next_path_segment
				):
					removed_any_data = true
			else:
				(
					GSILogger
					. log_gsi(
						(
							"Mismatch: Pattern expects dictionary at '%s', but state has %s. Skipping sub-removal."
							% [next_path_segment, typeof(value_in_state)]
						),
						GSILogger.LogLevel.WARN
					)
				)
		else:
			# This is a leaf node in the pattern
			# (empty dict or primitive value), meaning remove the key itself
			current_state_node.erase(key)
			GSILogger.log_gsi(
				"Central state: Removed data at '%s'." % next_path_segment, GSILogger.LogLevel.INFO
			)
			removed_any_data = true

	return removed_any_data


func _process_pending_updates() -> void:
	if not _has_pending_updates:
		return  # No updates to process

	var changes_applied: bool = false

	# 1. Apply buffered section updates
	# Duplicate keys to allow modification during iteration
	for section_name: Variant in _pending_section_updates.keys().duplicate():
		var changes_array: Array = _pending_section_updates[section_name]
		if changes_array.is_empty():
			continue

		# Ensure the section exists in the main game state's 'data' sub-dictionary
		if (
			not _game_state.data.has(section_name)
			or typeof(_game_state.data[section_name]) != TYPE_DICTIONARY
		):
			_game_state.data[section_name] = {}

		# Merge all accumulated changes for this section
		for data_to_merge: Dictionary in changes_array:
			_game_state.data[section_name] = _deep_merge_dictionaries(
				_game_state.data[section_name], data_to_merge
			)
			changes_applied = true

		GSILogger.log_gsi(
			"Central state: Section '%s' processed buffered updates." % section_name,
			GSILogger.LogLevel.DEBUG
		)
	_pending_section_updates.clear()  # Clear the buffer after processing

	# 2. Apply buffered custom data updates
	for key: Variant in _pending_custom_data_updates.keys().duplicate():
		# Apply to _game_state.data
		_game_state.data[key] = _pending_custom_data_updates[key]
		changes_applied = true
		GSILogger.log_gsi(
			"Central state: Custom data '%s' processed buffered update." % key,
			GSILogger.LogLevel.INFO
		)
	_pending_custom_data_updates.clear()

	# 3. Process top-level section removals
	for section_name: String in _pending_removals_sections.duplicate():
		if _game_state.data.has(section_name):  # Remove from _game_state.data
			_game_state.data.erase(section_name)
			changes_applied = true
			GSILogger.log_gsi(
				"Central state: Section '%s' removed from state." % section_name,
				GSILogger.LogLevel.INFO
			)
	_pending_removals_sections.clear()

	# 4. Process top-level custom data removals
	for key: String in _pending_removals_custom.duplicate():
		if _game_state.data.has(key):  # Remove from _game_state.data
			_game_state.data.erase(key)
			changes_applied = true
			GSILogger.log_gsi(
				"Central state: Custom data '%s' removed from state." % key, GSILogger.LogLevel.INFO
			)
	_pending_removals_custom.clear()

	_has_pending_updates = false

	if changes_applied:
		# Only trigger a GSI send if actual changes were merged into _game_state
		_update_game_state_and_queue_send()


#endregion

#region Testing


func _add_test_endpoint_for_mocking(
	config_instance: GSIConfig, mock_client_instance: GSIBaseClient
) -> void:
	var endpoint_id: StringName = config_instance.id

	if _endpoints.has(endpoint_id):
		GSILogger.log_gsi(
			(
				"Test helper: Endpoint '%s' already exists. Replacing existing endpoint with mock."
				% endpoint_id
			),
			GSILogger.LogLevel.WARN
		)
		remove_endpoint(endpoint_id)

	add_child(mock_client_instance)
	_endpoints[endpoint_id] = mock_client_instance
	GSILogger.log_gsi(
		"Test helper: Mock endpoint '%s' added for testing." % endpoint_id, GSILogger.LogLevel.DEBUG
	)

	# Perform initial send logic for the mock client as add_endpoint would
	var initial_filtered_state: Dictionary = {}
	initial_filtered_state.provider = clone_value(_game_state.provider)
	initial_filtered_state.auth = {"token": config_instance.auth_token}

	for section_name: StringName in config_instance.data_sections:
		if (
			config_instance.data_sections.get(section_name, false)
			and _game_state.data.has(section_name)
		):
			initial_filtered_state[section_name] = clone_value(_game_state.data[section_name])

	var initial_payload_to_send: Dictionary = clone_value(initial_filtered_state)
	initial_payload_to_send.added = clone_value(initial_filtered_state)

	mock_client_instance.queue_send(initial_payload_to_send)

	if _is_paused:
		mock_client_instance.pause_timers()
	else:
		mock_client_instance._reset_heartbeat_timer()

#endregion
