@tool
extends EditorPlugin
## Godot Behavior Tree Editor Plugin.
## Registers the visual Behavior Tree editor dock in the bottom panel.

const VIEWER_SCENE := preload("res://addons/godot_bt/editor/bt_viewer.tscn")
const DOCK_TITLE := "Behavior Tree"

var _viewer_instance: Control = null
var _dock_button: Button = null

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_viewer_instance = VIEWER_SCENE.instantiate()
	_dock_button = add_control_to_bottom_panel(_viewer_instance, DOCK_TITLE)

	# Configure project setting for custom BT provider if not already set
	if not ProjectSettings.has_setting("behavior_tree/custom_source_provider"):
		ProjectSettings.set_setting("behavior_tree/custom_source_provider", "")
		ProjectSettings.set_initial_value("behavior_tree/custom_source_provider", "")

func _exit_tree() -> void:
	if _viewer_instance != null:
		remove_control_from_bottom_panel(_viewer_instance)
		_viewer_instance.free()
		_viewer_instance = null
