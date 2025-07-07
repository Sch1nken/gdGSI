# 🎮 gdGSI - Godot Game State Integration
---
## 🚨 The current state, while seemingly working, has not been tested thoroughly. Please report any issues you might find so they can be fixed 🚨
---
## Table of Contents

*   [Core Functionality](#core-functionality)
    
    *   [Protocol Compatibility](#protocol-compatibility)
        
    *   [Efficient Data Management](#efficient-data-management)
        
    *   [Connection Resilience](#connection-resilience)
        
    *   [Configurability](#configurability)
        
    *   [Developer Experience](#developer-experience)
        
*   [Feature Matrix](#-feature-matrix)
    
*   [Installation Guide](#-installation-guide)
    
*   [Configuration](#-configuration)
    
    *   [Example Configuration Files](#example-configuration-files)
        
    *   [Parameter Definitions](#parameter-definitions)
        
*   [Usage Guidelines](#ℹ-usage-guidelines)
    
    *   [Example Code Snippet (`showcase_gsi.gd`)](#-example-code-snippet)
        
    *   [Primary API Functions](#-primary-api-functions)

*   [Endpoint Examples](#-endpoint-examples)
        
*   [Plugin File Structure](#-plugin-file-structure)
    
*   [Critical Considerations ⚠️](#critical-considerations-)
    
*   [Contributing](#-contributing)
    
*   [Development Roadmap 🗺️](#development-roadmap-)
    
---

This document outlines a robust and flexible Godot 4 plugin designed to facilitate the real-time transmission of Game State Integration (GSI) data to various external endpoints. Drawing inspiration from [Valve's GSI specification](https://developer.valvesoftware.com/wiki/Counter-Strike:_Global_Offensive_Game_State_Integration), notably utilized in titles such as Dota 2 and CS:GO (and probably CS2?), this plugin empowers Godot-based applications to disseminate dynamic state updates to external interfaces, including but not limited to overlays, analytical tools, and custom hardware solutions like RGB LEDs.

## Core Functionality

 * ###  **Protocol Compatibility:**
    
    *   🌐 **HTTP Client:** This component enables the transmission of data via standard HTTP POST requests to designated web servers.
        
    *   🔌 **WebSocket Client:** The plugin supports establishing connections with and transmitting data to external WebSocket servers, ensuring compatibility across all platforms, including HTML5 environments.
        
    *   📡 **WebSocket Server:** A local WebSocket server can be hosted to broadcast game state data to multiple connected clients. It should be noted that this server functionality is restricted to desktop and mobile platforms, with no support for HTML5 builds.
        
*  ### **Efficient Data Management:**
    
    *   ⚡ **Delta Updates:** The system automatically computes `previously` and `added` sections within the JSON payload, thereby transmitting only modified or newly introduced data to minimize bandwidth consumption.
        
    *   ⚙️ **Configurable Filtering:** Users can precisely specify which top-level game state sections (e.g., `player`, `map`, `inventory`) each individual endpoint is authorized to receive. Given that you (the developer) provides data to these top-level sections of course :)
        
* ###  **Connection Resilience:**
    
    *   ⏱️ **Independent Timers:** Each configured endpoint operates with its own distinct `buffer`, `throttle`, `timeout`, and `heartbeat` intervals, allowing for granular control over data transmission.
        
    *   🔄 **Automatic Reconnection:** In the event of a WebSocket connection disruption, the client automatically attempts to re-establish the connection.
        
    *   🩹 **Error Resilience:** Upon encountering network errors or timeouts, the endpoint's state (e.g., `previously` data) is reset, ensuring that upon reconnection a complete payload is sent.
        
*  ### **Configurability:**
    
    *   📝 **External JSON Configuration:** All endpoint settings are defined within external JSON files, facilitating straightforward management and updates without requiring modifications to the core game code.
        
    *   🚀 **Runtime Endpoint Management:** The plugin supports the dynamic addition or removal of GSI endpoints during runtime. This is mostly interesting for HTML5 builds but can be interesting for other platforms as well.
        
    *   🔒 **HTTPS/WSS Support:** Secure connections can be established using HTTPS/WSS protocols. An option to disable TLS verification is available.
        
* ### **Developer Experience:**
    
    *   🌳 **Clean SceneTree Integration:** Dynamically generated network nodes are instantiated as child nodes of the GSI plugin, polluting the SCeneTree as little as possible.
        
    *   🏷️ **Godot Node Naming Safety:** Endpoint identifiers are automatically converted into valid Godot node names, preventing potential issues.
        

## 📊 Feature Matrix

| Feature / Endpoint Type | HTTP Client | WebSocket Client | WebSocket Server |
| --- | --- | --- | --- |
| **TLS/SSL Support** | ✅ HTTPS | ✅ WSS | ✅ WSS |
| **TLS Configurability** | ✅ Yes | ✅ Yes | ✅ Yes |
| **HTML5 Export Compatibility** | ✅ Yes | ✅ Yes | ❌ No |
| **Buffer/Throttle/Heartbeat** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Delta Updates (`previously`/`added`)** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Authentication Token Support** | ✅ Yes | ✅ Yes | ✅ Yes |

## 🚀 Installation Guide

Just grab the latest release and unpack into your project. In case there is no release yet, clone or download this repository as zip and copy over the `res://addons/gsi/` into your project. This plugin might also be available through the Godot Asset Library at a later time. 

Then you just need to enable plugin, no further initialization necessary, the plugin only activates when the game gets started with the `--gamestateintegration` flag. When not enabled the plugin still exists in-game but doesn't really do anything resulting in hopefully minimal performance impact.

For development purposes the `--gamestateintegration` flag can be added under `Debug -> Customize Run Instances -> Main Run Args`. 

## ⚙️ Configuration

The plugin is designed to load endpoint configurations from JSON files. By default, `gsi.gd` searches for files adhering to the pattern `gamestate_integration_*.cfg` within the `gamestate_integration/` directory. This directory is relative to the executable path in deployed builds and `res://addons/gsi/` within the editor environment. There are example config files provided, though by default they reside in the `res://addons/gsi/gamestate_integration/disabled` directory. To enable them just move them up a folder (into `gamestate_integration/`). These will only be loaded when using the editor and will be ignore in exported builds.

### Example Configuration Files

**1\. HTTP Client Endpoint (`gamestate_integration/gamestate_integration_http.cfg`)**

```
{
    "id": "dev_http",
    "description": "HTTP endpoint for testing",
    "type": "http",
    "config": {
        "uri": "http://127.0.0.1:5000",
        "timeout": 5.0,
        "buffer": 0.1,
        "throttle": 0.25,
        "heartbeat": 10.0,
        "data": {
            "provider": true,
            "units": true,
        },
        "auth": {
            "token": "abcdefghijklmopqrstuvxyz123456789"
        },
        "tls_verification_enabled": false
    }
}
```
**2\. WebSocket Client Endpoint (`gamestate_integration/gamestate_integration_wsclient.cfg`)**

```
{
    "id": "dev_wsclient",
    "description": "WebSocket Client for testing",
    "type": "websocket_client",
    "config": {
        "uri": "ws://127.0.0.1:9001",
        "timeout": 5.0,
        "buffer": 0.1,
        "throttle": 0.25,
        "heartbeat": 10.0,
        "data": {
            "player": true,
            "units": true
        },
        "auth": {
            "token": "abcdefghijklmopqrstuvxyz123456789"
        },
        "tls_verification_enabled": false
    }
}
```

**3\. WebSocket Server Endpoint (`gamestate_integration/gamestate_integration_wsserver.cfg`)** 
⚠️ WebSocket Server is **NOT** supported on HTML5 exports!

```
{
    "id": "dev_wsserver",
    "description": "WebSocket Server for testing",
    "type": "websocket_server",
    "config": {
        "port": 9000,
        "buffer": 0.1,
        "throttle": 0.25,
        "heartbeat": 10.0,
        "data": {
            "provider": true,
            "units": true
        },
        "auth": {
            "token": "abcdefghijklmopqrstuvxyz123456789"
        },
        "tls_certificate_path": "",
        "tls_key_path": ""
    }
}
```

⚠️ To enable secure WebSocket Server (WSS), it is necessary to generate SSL certificates (e.g., utilizing OpenSSL) and subsequently provide their respective paths in the `tls_certificate_path` and `tls_key_path` fields. If either is left empty, the WebSocket Server will run in non-TLS mode (`ws://`)

### Parameter Definitions:

| Parameter   | Type   | Required | Description                                                                                         |
| ----------- | ------ | -------- | --------------------------------------------------------------------------------------------------- |
| id          | String | Yes      | A unique identifier for the endpoint.                                                               |
| description | String | No       | A human-readable text describing the endpoint's purpose.                                            |
| type        | String | Yes      | Specifies the communication protocol. Valid values: "http", "websocket_client", "websocket_server". |
| config      | Object | Yes      | An object containing endpoint-specific configuration settings. (See Config Parameters table below)  |


**config** section:
| Parameter                | Type    | Required For    | Default Value | Description                                                                                                                                   |
| ------------------------ | ------- | --------------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| uri                      | String  | HTTP, WS Client | None          | The target Uniform Resource Identifier for data transmission.                                                                                 |
| port                     | Integer | WS Server       | None          | The network port on which the WebSocket server listens for incoming connections.                                                              |
| timeout                  | Float   | Optional        | 5.0      | The maximum duration, in seconds, to await a response or connection establishment.                                                            |
| buffer                   | Float   | Optional        | 0.1      | The time interval, in seconds, during which state changes are aggregated before a consolidated transmission.                                  |
| throttle                 | Float   | Optional        | 0.25     | The minimum interval, in seconds, between successful data transmissions to prevent excessive network traffic.                                 |
| heartbeat                | Float   | Optional        | 10.0      | The periodic interval, in seconds, at which a full payload is transmitted to confirm connection liveness.                                     |
| data                     | Object  | Optional        | {}            | A dictionary specifying top-level game state sections (e.g., "player": 1) to be included in transmissions for this endpoint.                  |
| auth                     | Object  | Yes             | None          | Contains the authentication token required for endpoint access. The endpoint can choose wether to ignore an incorrect auth parameter. This is basically used to have a fail-safe on the endpoints to know they're connected to the right instance.                                                                              |
| tls_verification_enabled | Boolean | HTTP, WS Client | true          | A flag indicating whether SSL/TLS certificate verification should be performed. Disabling this is generally recommended only for development. |
| tls_certificate_path     | String  | Optional       | None          | File path to the TLS certificate used in WebSocket Server. Omitting either this or `tls_key_path` starts the WebSocket Server in non-TLS mode (`ws://`).                                                             |
| tls_key_path             | String  | Optional       | None          | File path to the private key used in WebSocket Server. Omitting either this or `tls_certificate_path` starts the WebSocket Server in non-TLS mode (`ws://`).                                                             |

## ℹ️ Usage Guidelines

Upon the `gsi.gd` script being configured as an Autoload (e.g., under the global name `GSI`), game state updates can be initiated from any script within the project. The plugin autonomously manages data filtering, timing, and transmission to all configured endpoints.

### 📜 Example Code Snippet 
## (`showcase_gsi.gd`)

```
extends Node

func _ready():
    # The GSI (the autoloaded plugin instance) will automatically
    # load configurations and initialize endpoints during its _ready() lifecycle event.

    GSI.set_provider_info({
        "game_name": "MyAwesomeGame",
        "game_version": "1.0.0",
        "map_loaded": true
    })

    GSI.set_section_data("player", {
        "name": "PlayerOne",
        "health": 100,
        "score": 0
    })

    GSI.set_section_data("map", {
        "current_map_name": "Level1",
        "game_phase": "playing"
    })

    GSILogger.log_gsi("Initial game state data has been transmitted to GSI_Manager.")

func _on_player_damaged(damage_amount: int):
    var current_health = GSI._game_state.player.get("health", 0)
    GSI.set_section_data("player", {"health": current_health - damage_amount})
    GSILogger.log_gsi("Player health has been updated.")

func _on_score_changed(points: int):
    var current_score = GSI._game_state.player.get("score", 0)
    GSI.set_section_data("player", {"score": current_score + points})
    GSILogger.log_gsi("Player score has been updated.")

func _on_game_over():
    GSI.set_section_data("map", {"game_phase": "gameover"})
    GSILogger.log_gsi("Game over state has been transmitted.")

func _on_add_custom_debug_info(message: String):
    GSI.set_custom_data("debug_message", message)
    GSILogger.log_gsi("Custom debug information has been added.")

func _on_remove_debug_info():
    GSI.remove_custom_data("debug_message")
    GSILogger.log_gsi("Custom debug information has been removed.")

func _input(event: InputEvent):
    if event.is_action_pressed("ui_accept"):
        _on_player_damaged(10)
    if event.is_action_pressed("ui_cancel"):
        _on_score_changed(50)
    if event.is_action_pressed("ui_text_submit"):
        _on_game_over()
```

### 🔌 Primary API Functions:

*   `GSI.set_section_data(section_name: String, data_to_merge: Dictionary)`: This function facilitates the update of a specific top-level section within the game state (e.g., "player", "map"). If the designated section does not exist, it will be instantiated. Existing keys within the section will be merged or overwritten as specified by `data_to_merge`.
    
*   `GSI.set_provider_info(provider_data: Dictionary)`: This method is utilized to update the mandatory `provider` section of the game state. ℹ️ By default doesn't have to be set explicitly. It is read from the ProjectSettings (game name + version). But can be overriden using this function ℹ️
    
*   `GSI.set_custom_data(key: String, value: Variant)`: This function adds or updates a custom key-value pair directly at the top level of the game state.
    
*   `GSI.remove_custom_data(key: String)`: This method removes a specified custom top-level key and its associated value from the game state. It is particularly useful for clearing sections that are no longer relevant (e.g., map-specific data upon level transition).
    
*   `GSI.add_endpoint(config_instance: GSIConfig)`: This function enables the dynamic addition of a new GSI endpoint during runtime. If an endpoint with an identical ID already exists, the existing configuration will be superseded.
    
*   `GSI.remove_endpoint(endpoint_id: String)`: This method facilitates the removal of an active GSI endpoint by its unique identifier.

## 📡 Endpoint Examples

See the [Example Repository](https://github.com/Sch1nken/gdGSI-endpoint-examples) for some example endpoint implementations.

## 📂 Plugin File Structure

```
you_godot_project/
├── addons
│   └── gsi
│       ├── autoload
│       │   └── gsi.gd                                      # The main/autoload script handling endpoints and state
│       ├── clients
│       │   ├── gsi_http_client.gd                          # HTTP Client implementation
│       │   ├── gsi_websocket_client.gd                     # WebSocket Client implementation
│       │   └── gsi_websocket_server.gd                     # WebSocket Server implementation
│       ├── gamestate_integration
│       │   └── disabled
│       │       ├── gamestate_integration_http.cfg          # Example dev config for HTTP Client
│       │       ├── gamestate_integration_wsclient.cfg      # Example dev config for WebSocket Client
│       │       └── gamestate_integration_wsserver.cfg      # Example dev config for WebSocket Server
│       ├── gsi_base_client.gd                              # Base-class for client implementations
│       ├── gsi_config.gd                                   # GSI Config specification and parser
│       ├── gsi_logger.gd                                   # Simple logger for the plugin
│       ├── gsi_plugin.gd                                   # Plugin file to be loaded by Godot
│       ├── gsi_websocket_connection.gd                     # Minimal class to simplify WebSocket Connections inside WebSocket Server
│       └── plugin.cfg                                      # Godot plugin.cfg
```
## Critical Considerations ⚠️

*   **TLS/SSL Security Protocols:** Disabling `tls_verification_enabled` is advisable solely within controlled development environments (e.g., when utilizing self-signed certificates for local testing). For production deployments, it is recommended to use a properly signed SSL/TLS certificates and maintain TLS verification as enabled to ensure secure communication. 
    
*   **Performance Implications:** While the plugin incorporates optimizations for delta updates and data filtering, it is prudent to monitor the frequency of updates to large segments of your game state. High-frequency transmissions of extensive datasets may potentially impact application performance or network resource utilization. Additionally the state-merging logic could cause performance issues when (larger) sections are updated very frequently. It might be wise to accumulate state-changes over a game-tick instead of sending every state-change directly to the GSI plugin. (i.e. instead of iterating over every enemy and calling `GSI.set_section_data()` for that particular enemy data, create a dictionary after the every enemy ticked, and use `GSI.set_section_data` only once. This reduces possible expensive merge calculation).
    
*   **Receiver Dependency:** This plugin functions as the data _sender_. Consequently, a corresponding GSI _receiver_ application is required (e.g., a Python Flask server, Node.js server, or a specialized overlay application). This receiver must be configured to listen for HTTP POST requests or WebSocket connections at the specified URIs/ports and process the incoming JSON payloads. Some small example endpoint implementations will be provided soon(tm).
    

## 🤝 Contributing

Contributions to this project are highly encouraged and welcome. Should you identify areas for improvement, discover defects, or wish to propose new functionalities, feel free to open an issue or PR.

To contribute effectively, please adhere to the following guidelines:

1.  **Defect Reporting:** In the event of an identified bug, please submit a detailed issue report via the GitHub repository. Such reports should ideally include reproducible steps, the anticipated behavior, and the observed outcome.
    
2.  **Feature Proposals:** For new feature concepts, please initiate a discussion by opening an issue. Clearly articulate the proposed functionality and its potential benefits.
    
3.  **Pull Requests:** When submitting code modifications, please ensure the following:
    
    *   Adherence to the established Godot GDScript [style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).
        
    *   Focus on a single, well-defined feature or defect resolution per pull request.
        
    *   Provision of clear and concise commit messages.
        
    *   Inclusion of explanatory comments for complex logic, while avoiding redundant annotations for self-evident code. _(Even comment-only PRs would be nice in case something is unclear for people unfamiliar with my code)_

## Development Roadmap 🗺️

| Feature | Status |
| --- | --- |
| Core GSI Sending (HTTP) | ✅ Completed |
| Configurable Buffer, Throttle, Heartbeat | ✅ Completed |
| External JSON Configuration | ✅ Completed |
| `previously` and `added` Delta Calculation | ✅ Completed |
| Data Filtering per Endpoint | ✅ Completed |
| HTTPS Support (Client) | ✅ Completed |
| WebSocket Client Support | ✅ Completed |
| WebSocket Server Support | ✅ Completed |
| Improved Error Logging | ✅ Completed |
| Receiver Application Examples (Multi-Language) | ✅ Completed |
| **Better Godot Project Example Project** | ⬜ Planned |
| **Integrated Editor Configuration Interface** | ⬜ Planned |
| **Performance Optimization** | ⬜ Planned |
| **Allow Removal Of Keys From Sections** | ⬜ Planned |
