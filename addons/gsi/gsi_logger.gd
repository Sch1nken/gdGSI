class_name GSILogger
extends RefCounted

enum LogLevel { NONE, ERROR, WARN, INFO, DEBUG }

const LOG_PREFIX: Dictionary[LogLevel, String] = {
	LogLevel.NONE: "",
	LogLevel.ERROR: "[ERROR]",
	LogLevel.WARN: "[WARN]",
	LogLevel.INFO: "[INFO]",
	LogLevel.DEBUG: "[DEBUG]"
}

static var _log_level: LogLevel = LogLevel.DEBUG


static func set_log_level(level: LogLevel) -> void:
	_log_level = level


static func log_gsi(message: String, log_level: LogLevel = LogLevel.INFO) -> void:
	if log_level > _log_level:
		return

	var prefix: String = LOG_PREFIX.get(log_level, "")
	var timestamp: Dictionary = Time.get_datetime_dict_from_unix_time(
		Time.get_unix_time_from_system()
	)
	var time_str: String = "%02d:%02d:%02d" % [timestamp.hour, timestamp.minute, timestamp.second]
	print("GSI - %s [%s] %s" % [prefix, time_str, message])
