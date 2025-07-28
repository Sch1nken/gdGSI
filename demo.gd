extends Node


func _ready() -> void:
	GSILogger.log_gsi("--- Starting simulated game events (for demonstration) ---")
	await get_tree().create_timer(2.0).timeout
	GSI.set_section_data("player", {"name": "GodotPlayer", "health": 90, "money": 100})
	await get_tree().create_timer(1.0).timeout
	GSI.set_section_data("player", {"health": 80})
	await get_tree().create_timer(2.0).timeout
	GSI.set_section_data("inventory", {"weapon": "pistol", "ammo": 12})
	await get_tree().create_timer(2.0).timeout
	GSI.set_section_data("inventory", {"ammo": 8, "grenades": 2})
	await get_tree().create_timer(5.0).timeout
	GSI.set_section_data("map", {"name": "godot_level_1", "phase": "live"})
	GSI.set_section_data("map_round", {"number": 2, "phase": "freezetime"})
	await get_tree().create_timer(5.0).timeout
	GSI.set_section_data("map_round", {"phase": "playing"})
	await get_tree().create_timer(15.0).timeout
	GSI.set_section_data("player", {"health": 0, "state": "dead"})
	GSI.set_section_data("map", {"phase": "gameover"})

	add_endpoint_at_runtime()


func add_endpoint_at_runtime() -> void:
	GSILogger.log_gsi("--- Demonstrating runtime endpoint management ---")
	await get_tree().create_timer(5.0).timeout

	var new_config_dict: Dictionary = {
		"id": "dynamic_overlay",
		"description": "Dynamically added HTTP endpoint",
		"type": "http",
		"config":
		{
			"uri": "http://127.0.0.1:5001",
			"timeout": 3.0,
			"buffer": 1.0,
			"throttle": 1.0,
			"heartbeat": 20.0,
			"data": {"player": true, "abilities": true},
			"auth": {"token": "dynamic_token_123"},
			"tls_verification_enabled": false
		}
	}
	var dynamic_gsi_config: GSIConfig = GSIConfig.from_dictionary(new_config_dict)
	if dynamic_gsi_config:
		GSI.add_endpoint(dynamic_gsi_config)

	GSI.set_section_data("abilities", {"ability_a": "ready", "ability_b": "cooldown"})

	await get_tree().create_timer(10.0).timeout

	GSI.remove_endpoint("main_display_endpoint")
	GSILogger.log_gsi("Removed 'main_display_endpoint'.")

	await get_tree().create_timer(5.0).timeout

	GSILogger.log_gsi("--- Demonstrating throttling with rapid updates ---")
	var throttle_test_config_dict: Dictionary = {
		"id": "throttle_test_endpoint",
		"description": "Endpoint for testing throttling",
		"type": "http",
		"config":
		{
			"uri": "http://127.0.0.1:5003/throttle_test",
			"timeout": 3.0,
			"buffer": 0.05,
			"throttle": 0.5,
			"heartbeat": 10.0,
			"data": {"player": true},
			"auth": {"token": "throttle_token"}
		}
	}
	var throttle_gsi_config: GSIConfig = GSIConfig.from_dictionary(throttle_test_config_dict)
	if throttle_gsi_config:
		GSI.add_endpoint(throttle_gsi_config)

	for i: int in 10:
		GSI.set_section_data("player", {"health": 100 - (i * 5)})
		await get_tree().create_timer(0.01).timeout

	GSILogger.log_gsi("Finished rapid updates. Observe throttle_test_endpoint behavior.")
	await get_tree().create_timer(5.0).timeout
	GSI.remove_endpoint("throttle_test_endpoint")
	GSILogger.log_gsi("Removed 'throttle_test_endpoint'.")

	await get_tree().create_timer(5.0).timeout
	GSILogger.log_gsi("--- Simulated game events finished ---")
