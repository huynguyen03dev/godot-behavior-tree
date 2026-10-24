class_name RitualBook
extends Area3D

signal picked_up(by_who: Node)
signal dropped(pos: Vector3)
signal placed_on_altar

@export var book_name: String = "Ritual Book of Banishment"

var is_placed_on_altar: bool = false
var is_held_by_player: bool = false
var is_held_by_ghost: bool = false

var _bob_timer: float = 0.0

@onready var mesh_node: Node3D = $Mesh
@onready var glow_light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	add_to_group("RitualBook")
	add_to_group("Interactable")
	collision_layer = 8 # Layer 4 (Interactable)
	collision_mask = 0

func _process(delta: float) -> void:
	if not is_placed_on_altar and not is_held_by_player and not is_held_by_ghost:
		_bob_timer += delta * 1.5
		if mesh_node:
			mesh_node.position.y = sin(_bob_timer) * 0.04
			mesh_node.rotate_y(delta * 0.5)

func get_interaction_text() -> String:
	if is_placed_on_altar:
		return "Ritual Book is resting on the Altar"
	if is_held_by_player:
		return ""
	return "Press [E] to pick up " + book_name

func interact(player: Node) -> bool:
	if is_placed_on_altar:
		return false
	if is_held_by_player or is_held_by_ghost:
		return false
	if player.has_method("carry_ritual_book"):
		if player.carry_ritual_book(self):
			is_held_by_player = true
			collision_layer = 0 # Temporarily disable collision while carried
			emit_signal("picked_up", player)
			return true
	return false

func on_placed_on_altar(altar_node: Node3D, mount_transform: Transform3D) -> void:
	is_placed_on_altar = true
	is_held_by_player = false
	is_held_by_ghost = false
	collision_layer = 0
	get_parent().remove_child(self)
	altar_node.add_child(self)
	transform = mount_transform
	if mesh_node:
		mesh_node.position = Vector3.ZERO
		mesh_node.rotation = Vector3.ZERO
	emit_signal("placed_on_altar")

func drop_to_ground(world_pos: Vector3) -> void:
	is_held_by_player = false
	is_held_by_ghost = false
	is_placed_on_altar = false
	collision_layer = 8
	var root = get_tree().current_scene
	if get_parent() != root:
		get_parent().remove_child(self)
		root.add_child(self)
	global_position = world_pos
	if mesh_node:
		mesh_node.position = Vector3.ZERO
		mesh_node.rotation = Vector3.ZERO
	emit_signal("dropped", world_pos)
