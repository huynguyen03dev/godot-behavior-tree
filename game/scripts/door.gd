class_name FarmhouseDoor
extends AnimatableBody3D

signal door_opened
signal door_closed

@export var is_locked: bool = false
@export var key_id: String = ""
@export var door_name: String = "Door"

var is_open: bool = false
var _target_yaw: float = 0.0
var _open_angle: float = deg_to_rad(90.0)

@onready var mesh_root: Node3D = $MeshRoot
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("Door")
	add_to_group("Interactable")
	# Collision Layer 1 (World) | Layer 4 (Interactable bit 8)
	collision_layer = 1 | 8
	collision_mask = 0
	_target_yaw = 0.0

	if mesh_root and mesh_root.get_node_or_null("DoorModel") == null:
		if ResourceLoader.exists("res://game/assets/models/door.glb"):
			var door_scene = load("res://game/assets/models/door.glb")
			if door_scene:
				var inst = door_scene.instantiate()
				inst.name = "DoorModel"
				mesh_root.add_child(inst)

func _physics_process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _target_yaw, delta * 6.0)

func get_interaction_text() -> String:
	if is_locked:
		return "Press [E] to unlock " + door_name + " (Locked)"
	if is_open:
		return "Press [E] to close " + door_name
	return "Press [E] to open " + door_name

func interact(player: Node) -> bool:
	if is_locked:
		if player.has_method("has_key") and player.has_key(key_id):
			is_locked = false
			player.consume_key(key_id)
			print("[Door] %s unlocked using key: %s" % [door_name, key_id])
			_toggle_door()
			return true
		else:
			print("[Door] %s is locked! Requires key: %s" % [door_name, key_id])
			return false

	_toggle_door()
	return true

func _toggle_door() -> void:
	is_open = not is_open
	_target_yaw = _open_angle if is_open else 0.0
	if is_open:
		emit_signal("door_opened")
	else:
		emit_signal("door_closed")
