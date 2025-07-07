class_name GSIBaseClient
extends Node

var config: GSIConfig
var last_successful_send_time: float = 0.0
var last_sent_game_state: Dictionary = {}
var is_sending: bool = false

var send_buffer_timer: Timer
var heartbeat_timer: Timer
var throttle_timer: Timer
var queued_payload: Dictionary = {}


func _init(p_config: GSIConfig) -> void:
	config = p_config
	name = config.id.validate_node_name()

	send_buffer_timer = create_timer("Send Buffer Timer")
	send_buffer_timer.timeout.connect(_attempt_send_game_state)

	throttle_timer = create_timer("Throttle Timer")
	throttle_timer.timeout.connect(_attempt_send_game_state)

	heartbeat_timer = create_timer("Heartbeat Timer")
	heartbeat_timer.timeout.connect(_attempt_send_game_state)


func create_timer(node_name: String) -> Timer:
	var timer := Timer.new()
	timer.name = node_name
	timer.one_shot = true
	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(timer)
	return timer


func _perform_send(_payload: Dictionary) -> void:
	push_error("GSIBaseClient: _perform_send must be implemented by subclasses.")


func _get_display_name() -> String:
	push_error("GSIBaseClient: _get_display_name must be implemented by subclasses.")
	return "UnnamedClient"


func queue_send(payload: Dictionary) -> void:
	queued_payload = payload

	if send_buffer_timer.is_stopped():
		send_buffer_timer.start(config.buffer)

	GSILogger.log_gsi(
		"[GSIBaseClient] %s: Queued send for %.2f s." % [_get_display_name(), config.buffer],
		GSILogger.LogLevel.DEBUG
	)


func _attempt_send_game_state() -> void:
	if is_sending:
		(
			GSILogger
			. log_gsi(
				(
					"[GSIBaseClient] %s: A send operation is already in progress, skipping this attempt."
					% _get_display_name()
				),
				GSILogger.LogLevel.DEBUG
			)
		)
		return

	if not throttle_timer.is_stopped():
		GSILogger.log_gsi(
			(
				"[GSIBaseClient] %s: is already throttled (remaining: %.2f), skipping this attempt."
				% [_get_display_name(), throttle_timer.time_left]
			),
			GSILogger.LogLevel.DEBUG
		)
		return

	var current_time: float = Time.get_ticks_msec() / 1000.0
	var time_since_last_successful_send: float = current_time - last_successful_send_time

	if time_since_last_successful_send < config.throttle:
		var remaining_throttle_time: float = config.throttle - time_since_last_successful_send
		GSILogger.log_gsi(
			(
				"[GSIBaseClient] %s: Throttled. Waiting %.2f s before next send. Re-queuing."
				% [_get_display_name(), remaining_throttle_time]
			),
			GSILogger.LogLevel.DEBUG
		)
		throttle_timer.start(remaining_throttle_time)
		return

	_send_game_state_now()


func _send_game_state_now() -> void:
	if is_sending:
		GSILogger.log_gsi(
			"[GSIBaseClient] %s: Already sending, cannot force send now." % _get_display_name(),
			GSILogger.LogLevel.DEBUG
		)
		return

	is_sending = true
	GSILogger.log_gsi(
		"[GSIBaseClient] %s: Triggering _perform_send with queued payload." % _get_display_name(),
		GSILogger.LogLevel.DEBUG
	)
	_perform_send(queued_payload)


func _handle_send_result(success: bool, sent_payload_base: Dictionary) -> void:
	is_sending = false
	if success:
		last_successful_send_time = Time.get_ticks_msec() / 1000.0
		last_sent_game_state = sent_payload_base
		GSILogger.log_gsi(
			"[GSIBaseClient] %s: Send successful. Heartbeat reset." % _get_display_name(),
			GSILogger.LogLevel.DEBUG
		)
	else:
		last_sent_game_state = {}
		GSILogger.log_gsi(
			(
				"[GSIBaseClient] %s: Send failed. Previously state reset. Heartbeat reset."
				% _get_display_name()
			),
			GSILogger.LogLevel.DEBUG
		)

	_reset_heartbeat_timer()


func _reset_heartbeat_timer() -> void:
	heartbeat_timer.start(config.heartbeat)
	GSILogger.log_gsi(
		(
			"[GSIBaseClient] %s: Heartbeat timer started for %.2f s."
			% [_get_display_name(), config.heartbeat]
		),
		GSILogger.LogLevel.DEBUG
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Should happen automatically but just be safe
		# Might remove at a later time if I am 100% sure this is not needed
		if is_instance_valid(send_buffer_timer):
			send_buffer_timer.queue_free()
		if is_instance_valid(heartbeat_timer):
			heartbeat_timer.queue_free()
		if is_instance_valid(throttle_timer):
			throttle_timer.queue_free()
