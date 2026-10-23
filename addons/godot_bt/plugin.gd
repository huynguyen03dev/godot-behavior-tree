@tool
extends EditorPlugin
## Godot Behavior Tree Editor Plugin.
## Registers the visual Behavior Tree editor dock in the bottom panel.

const VIEWER_SCENE := preload("res://addons/godot_bt/editor/bt_viewer.tscn")
const DOCK_TITLE := "Behavior Tree"

var _viewer_instance: Control = null

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	_viewer_instance = VIEWER_SCENE.instantiate()
	add_control_to_bottom_panel(_viewer_instance, DOCK_TITLE)

	# Configure project setting for custom BT provider if not already set
	if not ProjectSettings.has_setting("behavior_tree/custom_source_provider"):
		ProjectSettings.set_setting("behavior_tree/custom_source_provider", "")
		ProjectSettings.set_initial_value("behavior_tree/custom_source_provider", "")

func _exit_tree() -> void:
	if _viewer_instance != null:
		remove_control_from_bottom_panel(_viewer_instance)
		_viewer_instance.free()
		_viewer_instance = null

## Godot 4.4+ asks plugins for unsaved state before the editor closes.
## Returns a non-empty message while the viewer holds unsaved changes.
func _get_unsaved_status(for_scene: String) -> String:
	if _viewer_instance == null:
		return ""
	if not _viewer_instance.has_method("_has_unsaved_changes"):
		return ""
	if not _viewer_instance._has_unsaved_changes():
		return ""
	if for_scene.is_empty():
		return "The Behavior Tree editor has unsaved changes. Save them before closing."
	return "The Behavior Tree editor has unsaved changes. Save them before closing %s." % for_scene.get_file()

## Called when the editor saves the project or closes. Writes the open
## behavior tree back to its source.
func _save_external_data() -> void:
	if _viewer_instance == null:
		return
	if _viewer_instance.has_method("auto_save_external_data"):
		_viewer_instance.auto_save_external_data()
	elif _viewer_instance.has_method("can_auto_save") and not _viewer_instance.can_auto_save():
		return
	elif _viewer_instance.has_method("save_current_tree"):
		_viewer_instance.save_current_tree()

