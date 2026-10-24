class_name Talisman
extends Area3D

@export var talisman_name: String = "Cursed Talisman"
var _bob_offset: float = 0.0
var _base_y: float = 0.0

@onready var mesh_node: Node3D = $Mesh
@onready var light_node: OmniLight3D = $OmniLight3D

func _ready() -> void:
	add_to_group("Talisman")
	add_to_group("Interactable")
	collision_layer = 8 # Layer 4 (Interactable)
	collision_mask = 0
	_base_y = position.y
	_bob_offset = randf() * TAU

func _process(delta: float) -> void:
	# Subtle occult floating and rotation
	_bob_offset += delta * 2.0
	if mesh_node:
		mesh_node.position.y = sin(_bob_offset) * 0.08
		mesh_node.rotate_y(delta * 1.2)

func get_interaction_text() -> String:
	return "Press [E] to pick up " + talisman_name

func interact(player: Node) -> bool:
	if player.has_method("add_talisman"):
		if player.add_talisman():
			queue_free()
			return true
	return false
