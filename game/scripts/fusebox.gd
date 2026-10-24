class_name FuseBox
extends StaticBody3D

signal fuse_inserted

@export var is_powered: bool = false
@export var hallway_light_path: NodePath = NodePath("../HallwayDimLight")

var _hallway_light: Light3D = null

func _ready() -> void:
	add_to_group("Interactable")
	add_to_group("FuseBox")
	collision_layer = 1 | 8
	collision_mask = 0

	_resolve_light()
	_update_power()

func _resolve_light() -> void:
	if has_node(hallway_light_path):
		_hallway_light = get_node(hallway_light_path) as Light3D
	elif get_tree() and get_tree().current_scene:
		_hallway_light = get_tree().current_scene.find_child("HallwayDimLight", true, false) as Light3D

func _update_power() -> void:
	if not _hallway_light:
		_resolve_light()
	if _hallway_light:
		_hallway_light.light_energy = 0.8 if is_powered else 0.0

func get_interaction_text(player: Node = null) -> String:
	if is_powered:
		return "Fuse Box (Operational - Hallway Powered)"
	if player and player.get("fuse_count") != null and player.fuse_count > 0:
		return "Press [E] to insert Fuse"
	return "Fuse Box (Requires Fuse - Hallway Power Offline)"

func interact(player: Node) -> bool:
	if is_powered:
		return false

	if player and player.get("fuse_count") != null and player.fuse_count > 0:
		player.fuse_count -= 1
		is_powered = true
		_update_power()
		emit_signal("fuse_inserted")
		print("[FuseBox] Fuse installed successfully! Hallway lights powered on.")
		return true

	print("[FuseBox] Requires an electrical Fuse!")
	return false
