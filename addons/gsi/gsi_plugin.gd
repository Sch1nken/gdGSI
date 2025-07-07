@tool
extends EditorPlugin

const AUTOLOAD_NAME: String = "GSI"
const AUTOLOAD_PATH: String = "res://addons/gsi/autoload/gsi.gd"


func _enter_tree() -> void:
	add_autoload()


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func add_autoload() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		return

	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
